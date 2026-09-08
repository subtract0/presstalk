import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile,readdir } from 'node:fs/promises';
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
const storedTime=value=>value instanceof Date?value.getTime():Date.parse(value.replace(' ','T')+'Z');
async function fixture() {
  let db,makeStore;
  if(process.env.TEST_STORE==='d1') {
    const runtime=new Miniflare(convertV4MiniflareOptions({modules:true,script:'export default { fetch() { return new Response("test fixture"); } }',d1Databases:['ORDERS']}));
    const binding=await runtime.getD1Database('ORDERS');
    for(const name of (await readdir(new URL('../migrations/',import.meta.url))).filter(x=>x.endsWith('.sql')).sort()) {
      const schema=await readFile(new URL('../migrations/'+name,import.meta.url),'utf8');
      for(const sql of schema.split(';').filter(x=>x.trim())) await binding.prepare(sql).run();
    }
    db={...d1Adapter(binding),close:()=>runtime.dispose()};
    makeStore=()=>new D1Store(binding);
  } else {
    db=new PGlite();
    await db.exec(await readFile(new URL('../schema.sql',import.meta.url),'utf8'));
    makeStore=()=>new Store(db);
  }
  const config={liveMode:false,testReference:'acceptance-fixture-'.repeat(3),paymentLinkID:'plink_test',priceID:'price_test',currencies:['eur','usd','cad'],
    keyID:'test-only',recoveryPepper:'test-pepper',origin:'https://licenses.example.test',
    mailFrom:'PressTalk <license@example.test>',mailReplyTo:'help@example.test',
    webhookSecret:'whsec_fixture',cronSecret:'cron_fixture',salesEnabled:false};
  const session={id:sessionID,created:1788820000,livemode:false,mode:'payment',payment_link:'plink_test',client_reference_id:config.testReference,
    status:'complete',payment_status:'paid',currency:'eur',amount_total:2000,
    customer_details:{email:'buyer@example.test'},
    payment_intent:{id:'pi_test',status:'succeeded',latest_charge:{id:'ch_test',refunded:false,disputed:false,amount_refunded:0}}};
  const items={has_more:false,data:[{price:{id:'price_test'},quantity:1}]};
  const stripe={checkout:{sessions:{retrieve:async()=>structuredClone(session),listLineItems:async()=>structuredClone(items)}},
    paymentLinks:{retrieve:async()=>({active:true,livemode:false,url:'https://buy.stripe.com/test'})},webhooks:stripeSDK.webhooks};
  const sends=[];
  const mailer={send:async(order,id)=>{sends.push({order,id});return 'email_1';}};
  const store=makeStore(),commerce=new Commerce({stripe,store,mailer,config,key,pause:async()=>{}});
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
test('live mode fulfils the exact paid product without an acceptance capability',async()=>{
  const f=await fixture();try {
    f.config.liveMode=true;delete f.config.testReference;
    f.session.id='cs_live_0123456789abcdef';f.session.livemode=true;
    delete f.session.client_reference_id;
    await f.commerce.event({livemode:true,type:'checkout.session.completed',data:{object:f.session}});
    const state=await counts(f.db);
    assert.equal(state.orders.length,1);assert.equal(state.orders[0].session_id,f.session.id);
    assert.equal(Boolean(state.orders[0].livemode),true);assert.equal(f.sends.length,1);
    assert.equal(state.deliveries[0].state,'sent');
    await assert.rejects(f.commerce.event({livemode:false,type:'checkout.session.completed',data:{object:f.session}}),Unavailable);
    assert.equal(f.sends.length,1);
  }finally{await f.db.close();}
});
test('a paid sandbox order without the private acceptance reference cannot issue or send a licence',async()=>{
  const f=await fixture();try {
    let lookedUp=false;
    f.stripe.checkout.sessions.retrieve=async()=>{lookedUp=true;return structuredClone(f.session);};
    f.session.client_reference_id='unrelated-test-checkout';
    await assert.rejects(f.commerce.fulfill(sessionID),Unavailable);
    assert.equal(lookedUp,true);
    assert.equal((await counts(f.db)).orders.length,0);
    assert.equal(f.sends.length,0);
    delete f.config.testReference;
    lookedUp=false;
    await assert.rejects(f.commerce.fulfill(sessionID),Unavailable);
    assert.equal(lookedUp,false);
  }finally{await f.db.close();}
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
    assert.equal(f.sends.length,0,'recovery must not wait on mail before returning');
    // The original purchase and the recovery job are separate receipts.
    await f.db.query("UPDATE deliveries SET state='sent' WHERE id=$1",['purchase/'+sessionID]);
    await f.commerce.retry();
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
    let attemptedMail=false;
    f.mailer.send=async()=>{attemptedMail=true;throw new Error('outage');};
    const response=await f.serve(new Request(f.config.origin+'/thanks?session_id='+sessionID));
    assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'no-store, private');
    assert.equal(response.headers.get('referrer-policy'),'no-referrer');
    const html=await response.text();assert(html.includes('presstalk://activate?license=PRESSTALK-1.'));
    assert(!html.includes('buyer@example.test'));assert(html.includes('Download your licence file'));
    const file=await f.serve(new Request(f.config.origin+'/api/license?session_id='+sessionID));
    assert.equal(file.status,200);assert((await file.text()).startsWith('PRESSTALK-1.'));
    assert.equal(attemptedMail,false,'licence access must not wait for the mail provider');
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

test('provider Retry-After and repeated failures delay durable retries without changing the licence',async()=>{
  const f=await fixture();try {
    const {order,deliveryID}=await f.commerce.fulfill(sessionID);
    f.commerce.mailer=new ResendMailer(f.config,async()=>new Response('',{status:429,headers:{'retry-after':'900'}}));
    await assert.rejects(f.commerce.deliver(deliveryID));
    const row=(await counts(f.db)).deliveries[0];
    const due=storedTime(row.next_attempt_at);
    assert(due-Date.now()>890000,'the provider delay was ignored');
    assert.equal(row.state,'pending');assert.equal(row.attempts,1);
    assert.equal((await f.store.pending()).length,0);
    assert.equal((await f.store.order(sessionID)).license,order.license);
    await f.db.query(`UPDATE deliveries SET attempts=6,next_attempt_at=${process.env.TEST_STORE==='d1'?"datetime('now','-1 minute')":"now()-interval '1 minute'"}`);
    f.commerce.mailer={send:async()=>{throw new Error('still unavailable');}};
    await assert.rejects(f.commerce.deliver(deliveryID));
    const later=(await counts(f.db)).deliveries[0];
    assert.equal(later.attempts,7);
    assert(storedTime(later.next_attempt_at)-Date.now()>3590000,'repeated failures must back off');
    assert.equal((await f.store.pending()).length,0);
  }finally{await f.db.close();}
});

test('recovery form queues a receipt without contacting the mail provider',async()=>{
  const f=await fixture();try {
    await f.commerce.fulfill(sessionID);
    f.mailer.send=async()=>assert.fail('public recovery waited for an external provider');
    const response=await f.serve(new Request(f.config.origin+'/api/recover',{method:'POST',
      headers:{origin:f.config.origin,'content-type':'application/x-www-form-urlencoded'},body:'email=buyer%40example.test'}));
    assert.equal(response.status,202);
    const jobs=(await counts(f.db)).deliveries;
    assert.equal(jobs.filter(x=>x.id.startsWith('recovery/')).length,1);
    assert(jobs.every(x=>x.state==='pending'&&x.attempts===0));
  }finally{await f.db.close();}
});

test('backlog retries are paced, bounded and leave unfinished jobs durable',async()=>{
  const f=await fixture();try {
    await f.commerce.fulfill(sessionID);
    for(let i=0;i<70;i++) await f.store.queue('backlog/'+i,sessionID);
    let time=0;const pauses=[];
    f.commerce.now=()=>time;
    f.commerce.pause=async ms=>{pauses.push(ms);time+=ms;};
    assert.deepEqual(await f.commerce.retry(),{attempted:50,sent:50});
    assert.equal(pauses.length,50);assert(pauses.every(ms=>ms>=250));
    assert.equal((await f.store.pending(100)).length,21);
    f.mailer.send=async()=>{time+=2500;return 'slow-mail';};
    const next=await f.commerce.retry();
    assert(next.attempted>0&&next.attempted<21,'slow providers escaped the run budget');
    assert.equal(next.sent,next.attempted);
    assert.equal((await f.store.pending(100)).length,21-next.sent);
  }finally{await f.db.close();}
});

test('old recovery limits are pruned without resetting active abuse limits',async()=>{
  const f=await fixture();try {
    assert.equal(await f.store.allowRecovery('active',1),true);
    await f.store.allowRecovery('expired',1);
    await f.db.query(`UPDATE recovery_limits SET window_start=${process.env.TEST_STORE==='d1'?"datetime('now','-2 days')":"now()-interval '2 days'"} WHERE key='expired'`);
    await f.store.pruneRecoveryLimits();
    const rows=(await f.db.query('SELECT key FROM recovery_limits')).rows;
    assert.deepEqual(rows.map(x=>x.key),['active']);
    assert.equal(await f.store.allowRecovery('active',1),false);
  }finally{await f.db.close();}
});

test('D1 checkout health rejects a missing delivery-capacity migration',{skip:process.env.TEST_STORE!=='d1'},async()=>{
  const f=await fixture();try {
    await f.store.health();
    await f.db.query('DROP INDEX deliveries_ready');
    await assert.rejects(f.store.health(),/Missing delivery capacity migration/);
    f.config.salesEnabled=true;
    assert.equal((await f.serve(new Request(f.config.origin+'/buy'))).status,503);
  }finally{await f.db.close();}
});
