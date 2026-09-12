import { timingSafeEqual } from 'node:crypto';
import { Unavailable } from './service.js';
import * as pages from './pages.js';
import {grantHandler} from './grant-handler.js';

const response=(body,status=200,extra={})=>new Response(body,{status,headers:{...pages.headers,...extra}});
const json=(data,status=200)=>response(JSON.stringify(data),status,{'content-type':'application/json'});
function secretMatches(value,expected) {
  const a=Buffer.from(value||''),b=Buffer.from(expected||'');
  return b.length>0 && a.length===b.length && timingSafeEqual(a,b);
}
async function limitedBody(request,max=65536) {
  if (Number(request.headers.get('content-length')||0)>max) throw new Unavailable('too_large');
  const reader=request.body?.getReader();
  if (!reader) return '';
  const chunks=[];let length=0;
  for (;;) {
    const {done,value}=await reader.read();if(done)break;
    length+=value.length;
    if(length>max){await reader.cancel();throw new Unavailable('too_large');}
    chunks.push(Buffer.from(value));
  }
  return Buffer.concat(chunks).toString('utf8');
}

export function handler(commerce,config,stripe,grants=null) {
  return async request => {
    const url=new URL(request.url),path=url.pathname;
    try {
      if(grants) {const result=await grantHandler(request,grants,config);if(result)return result;}
      if (path==='/api/stripe-webhook' && request.method==='POST') {
        let event;
        try {
          const raw=await limitedBody(request);
          event=await stripe.webhooks.constructEventAsync(raw,request.headers.get('stripe-signature'),config.webhookSecret);
        } catch { return json({error:'Invalid webhook'},400); }
        await commerce.event(event);
        return json({received:true});
      }
      if (path==='/api/retry' && request.method==='GET') {
        if (!secretMatches(request.headers.get('authorization'),`Bearer ${config.cronSecret}`)) return json({error:'Unauthorized'},401);
        return json(await commerce.retry());
      }
      if (path==='/api/health' && request.method==='GET') {
        await commerce.store.health();
        return json({ok:true,mode:config.liveMode?'live':'test',salesEnabled:config.salesEnabled,keyID:config.keyID});
      }
      if (path==='/buy' && request.method==='GET') {
        if (!config.salesEnabled) return response(pages.paused(),503);
        // A missing database prevents accepting new sales; receipt access and
        // paid-order webhooks continue independently of the sales switch.
        await commerce.store.health();
        const link=await stripe.paymentLinks.retrieve(config.paymentLinkID);
        if (!link.active || link.livemode!==config.liveMode) return response(pages.paused(),503);
        return response('',303,{location:link.url});
      }
      // Browser form POSTs need Origin for CSRF checks. Private receipt pages
      // retain no-referrer; this form has no bearer credential in its URL.
      if (path==='/recover' && request.method==='GET') return response(pages.recovery(),200,{'referrer-policy':'same-origin'});
      if (path==='/api/recover' && request.method==='POST') {
        // Same-origin form only. Do not permit a third-party site to trigger
        // receipt email, and never reveal whether an address bought the app.
        if (request.headers.get('origin')!==config.origin) return response(pages.recovery(true),202);
        if (!request.headers.get('content-type')?.startsWith('application/x-www-form-urlencoded')) return response(pages.recovery(true),202);
        const form=new URLSearchParams(await limitedBody(request,1024));
        const ipHeader=config.clientIPHeader || 'x-vercel-forwarded-for';
        await commerce.recover(form.get('email'),request.headers.get(ipHeader)?.split(',')[0]?.trim() || 'unknown');
        return response(pages.recovery(true),202);
      }
      if (['/thanks','/api/license'].includes(path) && request.method==='GET') {
        const id=url.searchParams.get('session_id')||'';
        let result;
        try { result=await commerce.fulfill(id); }
        catch(error) {
          if(error instanceof Unavailable) return response(error.message==='payment_pending'?pages.pending():pages.unavailable(),error.message==='payment_pending'?202:404);
          throw error;
        }
        // The signed webhook and cron deliver email. The buyer can obtain
        // their already-issued licence immediately even if mail is slow.
        if(path==='/api/license') return response(result.order.license+'\n',200,{
          'content-type':'application/octet-stream','content-disposition':'attachment; filename="PressTalk.presstalk-license"',
        });
        return response(pages.thanks(result.order));
      }
      return response(pages.unavailable(),404);
    } catch(error) {
      // Avoid logging Stripe objects, addresses, licence keys or request URLs.
      console.error('commerce_request_failed',error?.constructor?.name || 'UnknownError');
      return response(pages.pending(),503);
    }
  };
}
