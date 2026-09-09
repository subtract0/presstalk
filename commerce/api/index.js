import Stripe from 'stripe';
import pg from 'pg';
import { configuration } from '../lib/config.js';
import { signingKey } from '../lib/license.js';
import { Store } from '../lib/store.js';
import { Commerce } from '../lib/service.js';
import { ResendMailer } from '../lib/mail.js';
import { handler } from '../lib/handler.js';

let serve;
export default {
  async fetch(request) {
    try {
      if (!serve) {
        const config=configuration();
        const stripe=new Stripe(config.stripeKey,{maxNetworkRetries:1,timeout:10000});
        const pool=new pg.Pool({connectionString:config.databaseURL,max:3,idleTimeoutMillis:20000,connectionTimeoutMillis:5000});
        pool.on('error',()=>console.error('commerce_database_connection_failed'));
        const commerce=new Commerce({config,stripe,store:new Store(pool),mailer:new ResendMailer(config),key:signingKey(config.privateKey,config.publicKey)});
        serve=handler(commerce,config,stripe);
      }
      return await serve(request);
    } catch {
      console.error('commerce_configuration_failed');
      return new Response('Purchase service temporarily unavailable. Your existing Mac licence continues to work.',{status:503,headers:{'cache-control':'no-store','content-type':'text/plain'}});
    }
  },
};
