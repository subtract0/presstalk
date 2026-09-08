import { readFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import Stripe from 'stripe';
import pg from 'pg';
import { configuration } from '../lib/config.js';
import { signingKey } from '../lib/license.js';

// A real configuration/readiness check. Missing services, permissions, public
// key wiring or DNS make it fail; fixtures and screenshots cannot satisfy it.
let pool;
try {
  const cloudflare=process.argv.includes('--cloudflare');
  const config=configuration(process.env,{database:cloudflare?'d1':'postgres'});
  signingKey(config.privateKey,config.publicKey);
  const app=await readFile(new URL('../../Sources/JarvisTap/ProductUI.swift',import.meta.url),'utf8');
  if(!app.includes(`"${config.keyID}": "${config.publicKey}"`)) throw new Error('App does not trust the configured issuing key');
  const stripe=new Stripe(config.stripeKey,{maxNetworkRetries:0,timeout:10000});
  const link=await stripe.paymentLinks.retrieve(config.paymentLinkID);
  if(link.livemode!==config.liveMode) throw new Error('Checkout mode mismatch');
  const items=await stripe.paymentLinks.listLineItems(config.paymentLinkID,{limit:2});
  if(items.has_more || items.data.length!==1 || items.data[0].quantity!==1 || items.data[0].price.id!==config.priceID) throw new Error('Checkout product mismatch');
  const price=await stripe.prices.retrieve(config.priceID,{expand:['currency_options']});
  if(!config.currencies.every(currency=>price.currency_options?.[currency]?.unit_amount>0)) throw new Error('Checkout currencies are not configured');
  if(cloudflare) {
    const sql='SELECT o.session_id,o.license,o.blocked,d.id,d.state,d.lease_until,d.provider_id,r.key,r.window_start,r.attempts FROM orders o,deliveries d,recovery_limits r LIMIT 0';
    try {
      const output=execFileSync('npx',['wrangler','d1','execute','ORDERS','--remote','--json','--command',sql],
        {cwd:new URL('..',import.meta.url),encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:30000,
          env:{...process.env,WRANGLER_SEND_METRICS:'false'}});
      const result=JSON.parse(output);
      if(!Array.isArray(result)||!result.length||result.some(x=>x.success!==true)) throw new Error('Remote D1 schema did not verify');
    } catch {throw new Error('Cannot verify deployed Cloudflare database');}
  } else {
    pool=new pg.Pool({connectionString:config.databaseURL,max:1,connectionTimeoutMillis:5000});
    await pool.query('SELECT session_id,license,blocked FROM orders LIMIT 0');
    await pool.query('SELECT id,state,lease_until,provider_id FROM deliveries LIMIT 0');
    await pool.query('SELECT key,window_start,attempts FROM recovery_limits LIMIT 0');
  }
  const res=await fetch('https://api.resend.com/domains',{headers:{authorization:`Bearer ${config.resendKey}`},signal:AbortSignal.timeout(10000)});
  if(!res.ok) throw new Error('Cannot verify email sender domain');
  const domains=await res.json();
  const domain=domains.data?.find(x=>x.name==='presstalk.app');
  if(!domain || domain.status!=='verified') throw new Error('presstalk.app email DNS is not verified');
  const detail=await fetch(`https://api.resend.com/domains/${domain.id}`,{headers:{authorization:`Bearer ${config.resendKey}`},signal:AbortSignal.timeout(10000)});
  if(!detail.ok) throw new Error('Cannot verify email tracking configuration');
  const settings=await detail.json();
  if(settings.open_tracking || settings.click_tracking) throw new Error('Receipt tracking must be disabled');
  console.log('PASS: real service credentials, product, database schema, app public key and email DNS.');
  console.log('Payment-to-email-to-app acceptance must still pass before opening sales.');
} catch(error) {
  // Configuration messages are authored locally. Never print provider objects
  // because those can contain keys, customer data or signed receipt URLs.
  const safe=/^(Missing |Invalid |Explicit |HTTPS |Stripe key|Recovery and|App does not|Checkout |Cannot verify|presstalk.app |Receipt tracking|Licence key)/.test(error.message);
  console.error('NOT READY: '+(safe?error.message:'A required service check failed; inspect its account configuration.'));
  process.exitCode=1;
} finally {await pool?.end();}
