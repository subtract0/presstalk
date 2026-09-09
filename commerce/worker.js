import Stripe from 'stripe';
import { configuration } from './lib/config.js';
import { signingKey } from './lib/license.js';
import { D1Store } from './lib/d1-store.js';
import { Commerce } from './lib/service.js';
import { ResendMailer } from './lib/mail.js';
import { handler } from './lib/handler.js';
import { requestObservation,sanitizeObservation } from './lib/observability.js';

const environment=env=>env.STRIPE_LIVE_MODE==='true'?'live':'test';
async function observe(env,value) {
  // An observability outage must not prevent a paid buyer receiving a licence.
  try { if(env.MONITOR) await env.MONITOR.record(sanitizeObservation(value)); } catch {}
}

function application(env) {
  if(!env.ORDERS) throw new Error('Missing order database binding');
  const config=configuration(env,{database:'d1'});
  const stripe=new Stripe(config.stripeKey,{httpClient:Stripe.createFetchHttpClient(),maxNetworkRetries:1,timeout:10000});
  const commerce=new Commerce({config,stripe,store:new D1Store(env.ORDERS),
    mailer:new ResendMailer(config),key:signingKey(config.privateKey,config.publicKey)});
  return {commerce,serve:handler(commerce,{...config,clientIPHeader:'cf-connecting-ip'},stripe)};
}
export default {
  async fetch(request,env,context) {
    const start=performance.now();let response;
    try { response=await application(env).serve(request); }
    catch { response=new Response('Purchase service temporarily unavailable. Your existing Mac licence continues to work.',{status:503,headers:{'cache-control':'no-store'}}); }
    context.waitUntil(observe(env,requestObservation(request,response.status,performance.now()-start,environment(env))));
    return response;
  },
  async scheduled(_controller,env,context) {
    context.waitUntil((async()=>{
      const start=performance.now();let result={attempted:0,sent:0},failed=false;
      try {result=await application(env).commerce.retry();}
      catch {failed=true;}
      await observe(env,{kind:'delivery_run',environment:environment(env),...result,failed,milliseconds:performance.now()-start});
      if(failed) throw new Error('commerce_retry_failed');
    })());
  },
};
