import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {Miniflare,convertV4MiniflareOptions} from 'miniflare';
import {AccessGrants} from '../lib/access-grants.js';
import {signingKey,issueAccessLicense} from '../lib/license.js';

const origin='https://licenses.example.test',day=86400000;
const fixture=JSON.parse(await readFile(new URL('../../Tests/PressTalkCoreTests/Fixtures/access-license.json',import.meta.url),'utf8'));
const key=signingKey(Buffer.alloc(32,7).toString('base64'),fixture.publicKey);
const adminToken='operator-test-secret-'.repeat(4);
async function setup(t) {
  const runtime=new Miniflare(convertV4MiniflareOptions({modules:true,
    script:await readFile(new URL('../../.local/commerce/worker-bundle/worker.js',import.meta.url),'utf8'),
    compatibilityDate:'2026-09-08',compatibilityFlags:['nodejs_compat'],d1Databases:['ORDERS'],
    bindings:{STRIPE_SECRET_KEY:'sk_test_fixture',STRIPE_WEBHOOK_SECRET:'whsec_fixture',STRIPE_LIVE_MODE:'false',
      STRIPE_TEST_REFERENCE:'acceptance-fixture-'.repeat(3),STRIPE_PAYMENT_LINK_ID:'plink_test',STRIPE_PRICE_ID:'price_test',STRIPE_CURRENCIES:'eur',
      LICENSE_KEY_ID:'test-only',LICENSE_PRIVATE_KEY:Buffer.alloc(32,7).toString('base64'),LICENSE_PUBLIC_KEY:fixture.publicKey,
      RESEND_API_KEY:'test-only',MAIL_FROM:'PressTalk <licenses@presstalk.app>',MAIL_REPLY_TO:'help@presstalk.app',PUBLIC_ORIGIN:origin,
      RECOVERY_PEPPER:'test'.repeat(16),CRON_SECRET:'cron'.repeat(16),SALES_ENABLED:'false',ADMIN_TOKEN:adminToken},
    outboundService:async()=>{throw new Error('Grant attempted an external request');},
  }));
  t.after(()=>runtime.dispose());
  const db=await runtime.getD1Database('ORDERS');
  for(const name of (await readdir(new URL('../migrations/',import.meta.url))).filter(x=>x.endsWith('.sql')).sort()) {
    for(const sql of (await readFile(new URL('../migrations/'+name,import.meta.url),'utf8')).split(';').filter(x=>x.trim()))await db.prepare(sql).run();
  }
  let clock=1800000000000;
  const grants=new AccessGrants({db,key,config:{origin,keyID:'test-only',adminToken},now:()=>clock});
  const fetch=(path,options={})=>runtime.dispatchFetch(origin+path,{redirect:'manual',...options});
  const post=(path,data,headers={})=>fetch(path,{method:'POST',headers:{origin,'content-type':'application/x-www-form-urlencoded',...headers},body:new URLSearchParams(data).toString()});
  return {db,grants,fetch,post,advance:days=>{clock+=days*day;}};
}

test('compiled Worker authenticates the operator, rejects replay and CSRF, and delivers a signed invitation without payments or email',async t=>{
  const {db,fetch,post}=await setup(t);
  assert.equal((await fetch('/admin')).status,401);
  assert.equal((await post('/admin/create',{id:'creation-'.repeat(4),label:'Someone',choice:'gift'})).status,401);
  assert.equal((await post('/admin/link',{}, {authorization:'Bearer wrong'})).status,401);
  const link=await post('/admin/link',{}, {authorization:'Bearer '+adminToken});
  assert.equal(link.status,200);
  const code=new URL((await link.json()).url).hash.slice(1);
  assert.equal((await post('/admin/login',{code},{origin:'https://attacker.test'})).status,403);
  const login=await post('/admin/login',{code});assert.equal(login.status,303);
  const cookie=login.headers.get('set-cookie').split(';')[0];
  assert.match(login.headers.get('set-cookie'),/HttpOnly; Secure; SameSite=Strict/);
  assert.equal((await post('/admin/login',{code})).status,401,'one-use login was replayed');
  const headers={cookie},id='creation-'.repeat(4),label='<img src=x onerror=alert(1)>';
  assert.equal((await post('/admin/create',{id,label,choice:'7'},{cookie,origin:'https://attacker.test'})).status,403);
  assert.equal((await fetch('/admin/create',{headers})).status,405);
  const created=await post('/admin/create',{id,label,choice:'7'},headers);assert.equal(created.status,303);
  assert.equal((await post('/admin/create',{id,label,choice:'7'},headers)).status,303);
  assert.equal((await db.prepare('SELECT COUNT(*) n FROM access_grants').first()).n,1,'duplicate click issued twice');
  const dashboard=await fetch(created.headers.get('location'),{headers});
  const html=await dashboard.text();assert(!html.includes(label));assert(html.includes('&lt;img'));
  const grant=await db.prepare('SELECT * FROM access_grants WHERE id=?').bind(id).first();
  const path='/gift/'+grant.token;
  const unclaimed=await fetch(path);assert.equal(unclaimed.status,200);assert((await unclaimed.text()).includes('Start my extra time'));
  assert.equal((await db.prepare('SELECT claimed_at FROM access_grants WHERE id=?').bind(id).first()).claimed_at,null,'GET/prefetch started trial');
  assert.equal((await fetch(path+'/license')).status,409);
  assert.equal((await fetch(path+'/claim')).status,405);
  assert.equal((await post(path+'/claim',{}, {origin:'https://attacker.test'})).status,403);
  const claims=await Promise.all([post(path+'/claim',{}),post(path+'/claim',{})]);assert(claims.every(r=>r.status===303));
  const saved=await db.prepare('SELECT * FROM access_grants WHERE id=?').bind(id).first();
  assert.equal(saved.expires_at-saved.claimed_at,7*day);
  const licence=await fetch(path+'/license');assert.equal((await licence.text()).trim(),saved.license);
  const payload=JSON.parse(Buffer.from(saved.license.split('.')[2],'base64url'));assert.equal(payload.schemaVersion,2);assert.equal(payload.entitlement,'trial_extension');assert(!JSON.stringify(payload).includes(label));
  assert.equal((await db.prepare('SELECT COUNT(*) n FROM orders').first()).n,0);
  const disable=await post('/admin/change',{id,revision:saved.revision,operation:'disable-'.repeat(4),action:'disable'},headers);assert.equal(disable.status,303);
  assert.equal((await fetch(path)).status,404);assert.equal((await fetch(path+'/license')).status,404);assert.equal((await post(path+'/claim',{})).status,404);
  assert.equal((await post('/admin/logout',{},headers)).status,303);assert.equal((await fetch('/admin',{headers})).status,401);
});

test('extra time begins at claim, extensions resume after expiry, action retries are idempotent, and gifts remain permanent',async t=>{
  const {grants,advance,db}=await setup(t),id='extension-'.repeat(4);
  let g=await grants.create({id,label:'Private tester',choice:'7'});
  advance(10);g=await grants.change({id,revision:g.revision,operation:'extend-before-'.repeat(3),action:'7'});
  assert.equal(g.claimed_at,null);assert.equal(g.days,14);
  g=await grants.claim(g.token);assert.equal(g.expires_at-g.claimed_at,14*day);
  const first=g.license;
  advance(2);const operation='extend-after-'.repeat(3),revision=g.revision;
  g=await grants.change({id,revision,operation,action:'30'});
  assert.equal(g.expires_at-g.claimed_at,44*day);assert.notEqual(g.license,first);
  assert.equal((await grants.change({id,revision,operation,action:'30'})).expires_at,g.expires_at);
  await assert.rejects(grants.change({id,revision,operation:'different-'.repeat(4),action:'7'}),/changed/);
  advance(90);const now=grants.now();g=await grants.change({id,revision:g.revision,operation:'renew-expired-'.repeat(3),action:'7'});assert.equal(g.expires_at,now+7*day);
  g=await grants.change({id,revision:g.revision,operation:'make-permanent-'.repeat(3),action:'gift'});
  const payload=JSON.parse(Buffer.from(g.license.split('.')[2],'base64url'));assert.equal(payload.schemaVersion,1);assert.equal(payload.expiresAt,undefined);
  advance(10000);assert.equal((await grants.claim(g.token)).license,g.license);
  assert.equal((await db.prepare('SELECT COUNT(*) n FROM orders').first()).n,0);
});

test('JavaScript signing fixture is the exact expiring schema verified by Swift',()=>{
  assert.equal(issueAccessLicense({grant:{id:'fixture-access-2026',kind:'extension',expires_at:1800604800000},key,keyID:'test-only',now:1800000000000}),fixture.license);
});

test('operator login expires and absent master credentials fail closed',async t=>{
  const {grants,advance}=await setup(t);
  const code=new URL(await grants.loginLink()).hash.slice(1);advance(1);
  await assert.rejects(grants.login(code),/expired/);
  grants.config.adminToken=undefined;assert.equal(grants.masterAuthorized('Bearer undefined'),false);
});
