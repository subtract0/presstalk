import assert from 'node:assert/strict';
import { readFile,readdir } from 'node:fs/promises';
import { Miniflare,convertV4MiniflareOptions } from 'miniflare';
import { D1Store } from '../lib/d1-store.js';

// Local workerd/D1 data only. No Stripe, email, customer data or remote binding.
const rows=Number(process.argv[2]||500000);
assert(Number.isInteger(rows)&&rows>=1000&&rows<=500000);
const runtime=new Miniflare(convertV4MiniflareOptions({modules:true,
  script:'export default {fetch(){return new Response("local capacity fixture")}}',d1Databases:['ORDERS']}));
try {
  const db=await runtime.getD1Database('ORDERS');
  for(const name of (await readdir(new URL('../migrations/',import.meta.url))).filter(x=>x.endsWith('.sql')).sort()) {
    const sql=await readFile(new URL('../migrations/'+name,import.meta.url),'utf8');
    for(const statement of sql.split(';').filter(x=>x.trim()))await db.prepare(statement).run();
  }
  const fixture=JSON.parse(await readFile(new URL('../../Tests/PressTalkCoreTests/Fixtures/commerce-license.json',import.meta.url),'utf8'));
  const started=performance.now();
  for(let first=1;first<=rows;first+=5000) {
    const last=Math.min(first+4999,rows);
    await db.prepare(`WITH RECURSIVE batch(n) AS (VALUES (?) UNION ALL SELECT n+1 FROM batch WHERE n<?)
      INSERT INTO orders (session_id,payment_intent_id,email,email_hash,license,livemode)
      SELECT 'cs_test_capacity_'||n,'pi_capacity_'||n,'capacity@example.test','capacity-hash',?,0 FROM batch`)
      .bind(first,last,fixture.license).run();
    await db.prepare(`INSERT INTO deliveries (id,session_id,state)
      SELECT 'purchase/'||session_id,session_id,'sent' FROM orders WHERE rowid>=? AND rowid<=?`).bind(first,last).run();
  }
  await db.prepare("UPDATE deliveries SET state='pending' WHERE rowid>?").bind(rows-37).run();
  let measurement;
  const store=new D1Store({prepare(sql) {
    const statement=db.prepare(sql);
    return {bind(...args) {
      const bound=statement.bind(...args);
      return {async all() {
        const start=performance.now(),result=await bound.all();
        measurement={sql,args,meta:result.meta,milliseconds:performance.now()-start};
        return result;
      }};
    }};
  }});
  const jobs=await store.pending(20);
  assert.equal(jobs.length,20);
  assert(jobs.every(x=>Number(x.id.split('_').at(-1))>rows-37));
  const indexed={...measurement};
  const plan=await db.prepare('EXPLAIN QUERY PLAN '+indexed.sql).bind(...indexed.args).all();
  assert(plan.results.some(x=>x.detail.includes('USING INDEX deliveries_ready')),
    'the real retry query scans historical purchases');
  assert(indexed.meta.rows_read<500,'the indexed retry read too much history');
  // Prove this measurement rejects the actual absent-index defect.
  await db.prepare('DROP INDEX deliveries_ready').run();
  await store.pending(20);
  const unindexed={...measurement};
  assert(unindexed.meta.rows_read>=rows,'negative control did not expose the full scan');
  console.log(JSON.stringify({orders:rows,deliveries:rows,activeBacklog:37,selected:jobs.length,
    indexedRowsRead:indexed.meta.rows_read,withoutIndexRowsRead:unindexed.meta.rows_read,
    indexedMilliseconds:indexed.milliseconds,withoutIndexMilliseconds:unindexed.milliseconds,
    totalSeconds:(performance.now()-started)/1000,indexRemovalRejected:true,
    scope:'local workerd D1 queue selection; not an HTTP throughput or email delivery benchmark'},null,2));
} finally {await runtime.dispose();}
