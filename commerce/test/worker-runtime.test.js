import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {Miniflare,convertV4MiniflareOptions} from 'miniflare';
import Stripe from 'stripe';

test('compiled Worker receives a signed payment, issues the Mac-compatible key and sends the real receipt payload through its HTTP adapter',async()=>{
  const id='cs_test_0123456789abcdef';
  const fixture=JSON.parse(await readFile(new URL('../../Tests/PressTalkCoreTests/Fixtures/commerce-license.json',import.meta.url),'utf8'));
  const session={id,created:1788820000,livemode:false,mode:'payment',payment_link:'plink_test',status:'complete',client_reference_id:'acceptance-fixture-'.repeat(3),
    payment_status:'paid',currency:'eur',amount_total:2000,customer_details:{email:'buyer@example.test'},
    payment_intent:{id:'pi_test',status:'succeeded',latest_charge:{id:'ch_test',refunded:false,disputed:false,amount_refunded:0}}};
  const outgoing=[],traffic=[];
  const primary={name:'commerce',modules:true,serviceBindings:{MONITOR:'monitor-spy'},
    // Load the exact compiled bytes. Miniflare 5's V4 path converter failed
    // before module evaluation for this bundle; inline module loading does not.
    script:await readFile(process.env.PRESSTALK_WORKER_TEST_BUNDLE || new URL('../../.local/commerce/worker-bundle/worker.js',import.meta.url),'utf8'),
    compatibilityDate:'2026-09-08',compatibilityFlags:['nodejs_compat'],d1Databases:['ORDERS'],
    bindings:{STRIPE_SECRET_KEY:'sk_test_fixture',STRIPE_WEBHOOK_SECRET:'whsec_fixture',STRIPE_LIVE_MODE:'false',
      STRIPE_TEST_REFERENCE:session.client_reference_id,
      STRIPE_PAYMENT_LINK_ID:'plink_test',STRIPE_PRICE_ID:'price_test',STRIPE_CURRENCIES:'eur,usd,cad',
      LICENSE_KEY_ID:'test-only',LICENSE_PRIVATE_KEY:Buffer.alloc(32,7).toString('base64'),LICENSE_PUBLIC_KEY:fixture.publicKey,
      RESEND_API_KEY:'test-only',MAIL_FROM:'PressTalk <licenses@presstalk.app>',MAIL_REPLY_TO:'help@presstalk.app',
      PUBLIC_ORIGIN:'https://licenses.example.test',RECOVERY_PEPPER:'test'.repeat(16),CRON_SECRET:'cron'.repeat(16),SALES_ENABLED:'false'},
    outboundService:async request=>{
      const url=new URL(request.url);
      traffic.push(url.hostname+url.pathname);
      if(url.hostname==='api.stripe.com' && url.pathname===`/v1/checkout/sessions/${id}`) return Response.json(session);
      if(url.hostname==='api.stripe.com' && url.pathname==='/v1/checkout/sessions/cs_test_unlistedpayment123') return Response.json({...session,id:'cs_test_unlistedpayment123',client_reference_id:'unrelated-test-checkout'});
      if(url.hostname==='api.stripe.com' && url.pathname===`/v1/checkout/sessions/${id}/line_items`) return Response.json({has_more:false,data:[{price:{id:'price_test'},quantity:1}]});
      if(url.hostname==='api.resend.com' && url.pathname==='/emails'){
        outgoing.push(await request.json());return Response.json({id:'email_runtime_1'});
      }
      throw new Error('Unexpected outgoing request in isolated runtime test');
    },
  };
  const runtime=new Miniflare(convertV4MiniflareOptions({workers:[primary,{
    name:'monitor-spy',modules:true,compatibilityDate:'2026-09-08',d1Databases:['OBSERVATIONS'],
    script:`import {WorkerEntrypoint} from 'cloudflare:workers';
      export default class extends WorkerEntrypoint {
        async record(value) {await this.env.OBSERVATIONS.prepare('INSERT INTO observations (value) VALUES (?)').bind(JSON.stringify(value)).run();}
      }`,
  }]}));
  try {
    const db=await runtime.getD1Database('ORDERS','commerce');
    const observations=await runtime.getD1Database('OBSERVATIONS','monitor-spy');
    await observations.prepare('CREATE TABLE observations(value TEXT)').run();
    for(const name of (await readdir(new URL('../migrations/',import.meta.url))).filter(x=>x.endsWith('.sql')).sort()) {
      const schema=await readFile(new URL('../migrations/'+name,import.meta.url),'utf8');
      for(const sql of schema.split(';').filter(x=>x.trim()))await db.prepare(sql).run();
    }
    const body=JSON.stringify({livemode:false,type:'checkout.session.completed',data:{object:session}});
    const sdk=new Stripe('sk_test_fixture');
    const signature=sdk.webhooks.generateTestHeaderString({payload:body,secret:'whsec_fixture'});
    const response=await runtime.dispatchFetch('https://licenses.example.test/api/stripe-webhook',{
      method:'POST',headers:{'stripe-signature':signature},body,
    });
    const bodyText=await response.text();
    assert.equal(response.status,200,JSON.stringify({traffic,response:bodyText.slice(0,100),orders:(await db.prepare('SELECT COUNT(*) AS n FROM orders').first()).n}));
    const order=await db.prepare('SELECT * FROM orders WHERE session_id=?').bind(id).first();
    assert.equal(order?.license,fixture.license);
    assert.equal(outgoing.length,1);
    assert.equal(Buffer.from(outgoing[0].attachments[0].content,'base64').toString().trim(),fixture.license);
    const page=await runtime.dispatchFetch('https://licenses.example.test/thanks?session_id='+id);
    assert.equal(page.status,200);assert((await page.text()).includes('PressTalk is yours.'));
    assert.equal(outgoing.length,1,'landing page sent a duplicate receipt');
    const unlisted=await runtime.dispatchFetch('https://licenses.example.test/thanks?session_id=cs_test_unlistedpayment123');
    assert.equal(unlisted.status,404);
    assert.equal(outgoing.length,1,'an unlisted sandbox order sent a receipt');
    assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM orders').first()).n,1,'an unrelated sandbox order issued a licence');
    const invalid=await runtime.dispatchFetch('https://licenses.example.test/api/stripe-webhook',{
      method:'POST',headers:{'stripe-signature':'bad'},body,
    });
    assert.equal(invalid.status,400);assert.equal(outgoing.length,1);
    const sentinel='PRESSTALK_PRIVATE_SENTINEL';
    await runtime.dispatchFetch('https://licenses.example.test/'+sentinel+'?session_id='+sentinel,{
      headers:{authorization:sentinel},
    });
    let recorded=[];
    const deadline=Date.now()+2000;
    do {
      recorded=(await observations.prepare('SELECT value FROM observations').all()).results.map(x=>JSON.parse(x.value));
      if(recorded.length>=5)break;
      await new Promise(resolve=>setTimeout(resolve,10));
    }while(Date.now()<deadline);
    assert.equal(recorded.length,5,'the actual Worker did not send its observations through the service binding');
    assert(recorded.some(x=>x.route==='receipt'&&x.status===200));
    assert(recorded.some(x=>x.route==='stripe_webhook'&&x.status===400));
    assert(recorded.some(x=>x.route==='other'&&x.status===404));
    const logged=JSON.stringify(recorded);
    for(const privateValue of [sentinel,id,fixture.license,session.customer_details.email])assert(!logged.includes(privateValue));
  }finally{await runtime.dispose();}
});
