import Stripe from 'stripe';
import { configuration } from './lib/config.js';
import { signingKey } from './lib/license.js';
import { D1Store } from './lib/d1-store.js';
import { Commerce } from './lib/service.js';
import { ResendMailer } from './lib/mail.js';
import { handler } from './lib/handler.js';

function application(env) {
  if(!env.ORDERS) throw new Error('Missing order database binding');
  const config=configuration(env,{database:'d1'});
  const stripe=new Stripe(config.stripeKey,{httpClient:Stripe.createFetchHttpClient(),maxNetworkRetries:1,timeout:10000});
  const commerce=new Commerce({config,stripe,store:new D1Store(env.ORDERS),
    mailer:new ResendMailer(config),key:signingKey(config.privateKey,config.publicKey)});
  return {commerce,serve:handler(commerce,{...config,clientIPHeader:'cf-connecting-ip'},stripe)};
}
export default {
  async fetch(request,env) {
    try { return await application(env).serve(request); }
    catch { return new Response('Purchase service temporarily unavailable. Your existing Mac licence continues to work.',{status:503,headers:{'cache-control':'no-store'}}); }
  },
  async scheduled(_controller,env,context) {
    context.waitUntil(application(env).commerce.retry());
  },
};
