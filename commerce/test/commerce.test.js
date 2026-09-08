import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createPublicKey,verify } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import Stripe from 'stripe';
import { Store } from '../lib/store.js';
import { D1Store,d1Adapter } from '../lib/d1-store.js';
import { Miniflare,convertV4MiniflareOptions } from 'miniflare';
import { Commerce,Unavailable } from '../lib/service.js';
import { signingKey } from '../lib/license.js';
import { handler } from '../lib/handler.js';
import { receipt,ResendMailer } from '../lib/mail.js';

const seed=Buffer.alloc(32,7);
const publicKey='6kpsY+KcUgq+9VB7Ey7F+ZVHdq6+vnuSQh7qaRRG0iw=';
const key=signingKey(seed.toString('base64'),publicKey);
const stripeSDK=new Stripe('sk_test_fixture');
const sessionID='cs_test_0123456789abcdef';
async function fixture() {
  let db,makeStore;
  if(process.env.TEST_STORE==='d1') {
    const runtime=new Miniflare(convertV4MiniflareOptions({modules:true,script:'export default { fetch() { return new Response("test fixture"); } }',d1Databases:['ORDERS']}));
    const binding=await runtime.getD1Database('ORDERS');
    const schema=await readFile(new URL('../migrations/0001_orders.sql',import.meta.url),'utf8');
    for(const sql of schema.split(';').filter(x=>x.trim())) await binding.prepare(sql).run();
    db={...d1Adapter(binding),close:()=>runtime.dispose()};
    makeStore=()=>new D1Store(binding);
  } else {
    db=new PGlite();
    await db.exec(await readFile(new URL('../schema.sql',import.meta.url),'utf8'));
    makeStore=()=>new Store(db);
  }
  const config={liveMode:false,paymentLinkID:'plink_test',priceID:'price_test',currencies:['eur','usd','cad'],
    keyID:'test-only',recoveryPepper:'test-pepper',origin:'https://licenses.example.test',
    mailFrom:'PressTalk <license@example.test>',mailReplyTo:'help@example.test',
    webhookSecret:'whsec_fixture',cronSecret:'cron_fixture',salesEnabled:false};
  const session={id:sessionID,created:1788820000,livemode:false,mode:'payment',payment_link:'plink_test',
    status:'complete',payment_status:'paid',currency:'eur',amount_total:2000,
    customer_details:{email:'buyer@example.test'},
    payment_intent:{id:'pi_test',status:'succeeded',latest_charge:{id:'ch_test',refunded:false,disputed:false,amount_refunded:0}}};
  const items={has_more:false,data:[{price:{id:'price_test'},quantity:1}]};
  const stripe={checkout:{sessions:{retrieve:async()=>structuredClone(session),listLineItems:async()=>structuredClone(items)}},
    paymentLinks:{retrieve:async()=>({active:true,livemode:false,url:'https://buy.stripe.com/test'})},webhooks:stripeSDK.webhooks};
  const sends=[];
  const mailer={send:async(order,id)=>{sends.push({order,id});return 'email_1';}};
  const store=makeStore(),commerce=new Commerce({stripe,store,mailer,config,key});
  return {db,config,session,items,stripe,store,makeStore,commerce,mailer,sends,serve:handler(commerce,config,stripe)};
}
const counts=async db=>{
  const orders=(await db.query('SELECT * FROM orders')).rows;
  const deliveries=(await db.query('SELECT * FROM deliveries')).rows;
  return {orders,deliveries};
};
test('a verified paid order produces an offline signature and durable sent receipt',async()=>{
  const f=await fixture();try {
    const {order,deliveryID}=await f.commerce.fulfill(sessionID);
    await f.commerce.deliver(deliveryID);
    const [prefix,kid,payload,signature]=order.license.split('.');
    assert.equal(prefix,'PRESSTALK-1');
    assert(verify(null,Buffer.from(`PressTalk-license-v1\n${kid}.${payload}`),createPublicKey(key),Buffer.from(signature,'base64url')));
    const data=JSON.parse(Buffer.from(payload,'base64url'));
    const macFixture=JSON.parse(await readFile(new URL('../../Tests/PressTalkCoreTests/Fixtures/commerce-license.json',import.meta.url),'utf8'));
    assert.equal(order.license,macFixture.license,'Swift interoperability fixture drifted from the actual issuer');
    assert.equal(data.maxMajorVersion,0);assert.equal(data.productID,'com.am.presstalk');
    assert(!JSON.stringify(data).includes('buyer'));assert(!('expiresAt' in data));
    const state=await counts(f.db);
    assert.equal(state.orders.length,1);assert.equal(state.deliveries[0].state,'sent');assert.equal(f.sends.length,1);
  } finally {await f.db.close();}
});
test('all three existing checkout currencies are accepted without changing prices',async()=>{
  for(const currency of ['eur','usd','cad']){
    const f=await fixture();try{
      f.session.currency=currency;
      const {order}=await f.commerce.fulfill(sessionID);
      assert(order.license.startsWith('PRESSTALK-1.'));
    }finally{await f.db.close();}
  }
});
test('concurrent landing pages and duplicate webhooks issue and email once',async()=>{
  const f=await fixture();try {
    await Promise.all(Array.from({length:12},async()=>{
      const {deliveryID}=await f.commerce.fulfill(sessionID);await f.commerce.deliver(deliveryID);
    }));
    const state=await counts(f.db);
    assert.equal(state.orders.length,1);assert.equal(state.deliveries.length,1);assert.equal(f.sends.length,1);
  } finally {await f.db.close();}
});
test('unpaid, other product, wrong mode, wrong link, mixed carts and reversed payments never issue',async()=>{
  const cases=[f=>f.session.payment_status='unpaid',f=>f.session.livemode=true,
    f=>f.session.payment_link='plink_other',f=>f.items.data[0].price.id='price_other',
    f=>f.items.data[0].quantity=2,f=>f.items.has_more=true,f=>f.session.amount_total=0,
    f=>f.session.currency='xyz',f=>f.session.payment_intent.latest_charge.refunded=true,
    f=>f.session.payment_intent.latest_charge.disputed=true];
  for(const change of cases){const f=await fixture();try{
    change(f);await assert.rejects(f.commerce.fulfill(sessionID),Unavailable);
    assert.equal((await counts(f.db)).orders.length,0);assert.equal(f.sends.length,0);
  }finally{await f.db.close();}}
});
test('a delayed payment is fulfilled only by the settled event',async()=>{
  const f=await fixture();try{
    const event={livemode:false,type:'checkout.session.completed',data:{object:f.session}};
    f.session.payment_status='unpaid';await f.commerce.event(event);
    assert.equal((await counts(f.db)).orders.length,0);
    f.session.payment_status='paid';event.type='checkout.session.async_payment_succeeded';
    await f.commerce.event(event);assert.equal(f.sends.length,1);
  }finally{await f.db.close();}
});
test('email failure keeps a usable licence and durable retry that survives a new service instance',async()=>{
  const f=await fixture();try{
    f.mailer.send=async()=>{throw new Error('provider unavailable');};
    const result=await f.commerce.fulfill(sessionID);
    await assert.rejects(f.commerce.deliver(result.deliveryID));
    const state=await counts(f.db);assert.equal(state.deliveries[0].state,'pending');
    assert.equal(state.orders[0].license,result.order.license);
    await f.db.query(`UPDATE deliveries SET next_attempt_at=${process.env.TEST_STORE==='d1'?"datetime('now','-1 minute')":"now()-interval '1 minute'"}`);
    const restarted=new Commerce({stripe:f.stripe,store:f.makeStore(),config:f.config,key,
      mailer:{send:async()=> 'email_after_restart'}});
    assert.deepEqual(await restarted.retry(),{attempted:1,sent:1});
    assert.equal((await counts(f.db)).deliveries[0].provider_id,'email_after_restart');
  }finally{await f.db.close();}
});
test('an incomplete database blocks new checkout instead of passing a connection-only health check',async()=>{
  const f=await fixture();try{
    f.config.salesEnabled=true;
    await f.db.query('DROP TABLE recovery_limits');
    await assert.rejects(f.store.health());
    assert.equal((await f.serve(new Request(f.config.origin+'/buy'))).status,503);
    assert.equal(f.sends.length,0);
  }finally{await f.db.close();}
});
test('refund arriving before a delivery retry blocks issuance and recovery',async()=>{
  const f=await fixture();try{
    await f.commerce.fulfill(sessionID);
    f.session.payment_intent.latest_charge.refunded=true;
    await f.commerce.event({livemode:false,type:'charge.refunded',data:{object:{payment_intent:'pi_test'}}});
    await f.commerce.recover('buyer@example.test','127.0.0.1');await f.commerce.retry();
    await assert.rejects(f.commerce.fulfill(sessionID),Unavailable);
    assert.equal(f.sends.length,0);assert.equal((await counts(f.db)).deliveries[0].state,'blocked');
  }finally{await f.db.close();}
});
test('recovery sends the original licence only to its stored buyer and is limited',async()=>{
  const f=await fixture();try{
    const {order}=await f.commerce.fulfill(sessionID);
    await f.commerce.recover('nobody@example.test','127.0.0.1');assert.equal(f.sends.length,0);
    await f.commerce.recover('BUYER@example.test','127.0.0.1');
    await f.commerce.recover('buyer@example.test','127.0.0.1');
    await f.commerce.recover('buyer@example.test','127.0.0.1');
    assert.equal(f.sends.length,1);assert.equal(f.sends[0].order.email,'buyer@example.test');
    assert.equal(f.sends[0].order.license,order.license);
  }finally{await f.db.close();}
});
test('invalid webhook signature, altered body and stale timestamp cause no fulfilment',async()=>{
  const f=await fixture();try{
    const body=JSON.stringify({livemode:false,type:'checkout.session.completed',data:{object:f.session}});
    const valid=stripeSDK.webhooks.generateTestHeaderString({payload:body,secret:f.config.webhookSecret});
    const old=stripeSDK.webhooks.generateTestHeaderString({payload:body,secret:f.config.webhookSecret,timestamp:1});
    for(const [payload,signature] of [[body,'invalid'],[body+' ',valid],[body,old]]){
      const response=await f.serve(new Request(f.config.origin+'/api/stripe-webhook',{method:'POST',headers:{'stripe-signature':signature},body:payload}));
      assert.equal(response.status,400);
    }
    assert.equal((await counts(f.db)).orders.length,0);
    const response=await f.serve(new Request(f.config.origin+'/api/stripe-webhook',{method:'POST',headers:{'stripe-signature':valid},body}));
    assert.equal(response.status,200);assert.equal(f.sends.length,1);
  }finally{await f.db.close();}
});
test('receipt never caches licences and remains available while mail is down',async()=>{
  const f=await fixture();try{
    f.mailer.send=async()=>{throw new Error('outage');};
    const response=await f.serve(new Request(f.config.origin+'/thanks?session_id='+sessionID));
    assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'no-store, private');
    assert.equal(response.headers.get('referrer-policy'),'no-referrer');
    const html=await response.text();assert(html.includes('presstalk://activate?license=PRESSTALK-1.'));
    assert(!html.includes('buyer@example.test'));assert(html.includes('Download your licence file'));
    const file=await f.serve(new Request(f.config.origin+'/api/license?session_id='+sessionID));
    assert.equal(file.status,200);assert((await file.text()).startsWith('PRESSTALK-1.'));
  }finally{await f.db.close();}
});
test('anonymous cron and cross-origin recovery cannot send mail; sales can be paused independently',async()=>{
  const f=await fixture();try{
    await f.commerce.fulfill(sessionID);
    assert.equal((await f.serve(new Request(f.config.origin+'/api/retry'))).status,401);
    const req=new Request(f.config.origin+'/api/recover',{method:'POST',headers:{origin:'https://attacker.test','content-type':'application/x-www-form-urlencoded'},body:'email=buyer%40example.test'});
    assert.equal((await f.serve(req)).status,202);assert.equal(f.sends.length,0);
    assert.equal((await f.serve(new Request(f.config.origin+'/buy'))).status,503);
    f.config.salesEnabled=true;assert.equal((await f.serve(new Request(f.config.origin+'/buy'))).status,303);
  }finally{await f.db.close();}
});
test('recovery uses the selected hosting platform client-IP header',async()=>{
  const f=await fixture();try{
    f.config.clientIPHeader='cf-connecting-ip';let received;
    f.commerce.recover=async(email,ip)=>{received={email,ip};};
    const result=await f.serve(new Request(f.config.origin+'/api/recover',{method:'POST',
      headers:{origin:f.config.origin,'content-type':'application/x-www-form-urlencoded',
        'cf-connecting-ip':'192.0.2.5','x-vercel-forwarded-for':'spoofed'},body:'email=buyer%40example.test'}));
    assert.equal(result.status,202);assert.deepEqual(received,{email:'buyer@example.test',ip:'192.0.2.5'});
  }finally{await f.db.close();}
});
test('the actual mail adapter sends the saved licence attachment with stable retry identity',async()=>{
  const f=await fixture();try{
    const {order}=await f.commerce.fulfill(sessionID);let call;
    const adapter=new ResendMailer({...f.config,resendKey:'test-only'},async(url,options)=>{call={url,options};return Response.json({id:'message_123'});});
    assert.equal(await adapter.send(order,'purchase/test'),'message_123');
    assert.equal(call.options.headers['Idempotency-Key'],'purchase/test');
    const mail=JSON.parse(call.options.body);
    assert.equal(Buffer.from(mail.attachments[0].content,'base64').toString().trim(),order.license);
    assert.deepEqual(mail.to,['buyer@example.test']);assert.equal(mail.reply_to,'help@example.test');
    assert(receipt(order,f.config).text.includes('No account or subscription'));
  }finally{await f.db.close();}
});
