import { createHmac, timingSafeEqual } from 'node:crypto';
import { issueLicense } from './license.js';
import { MailDeliveryError } from './mail.js';

export class Unavailable extends Error {}
const idOf = value => typeof value === 'string' ? value : value?.id;
const sameReference=(actual,expected)=>{
  if(typeof actual!=='string'||typeof expected!=='string'||!expected) return false;
  const a=Buffer.from(actual),b=Buffer.from(expected);
  return a.length===b.length && timingSafeEqual(a,b);
};

export class Commerce {
  constructor({ stripe, store, mailer, config, key,
    now=()=>performance.now(),pause=ms=>new Promise(resolve=>setTimeout(resolve,ms)) }) {
    Object.assign(this,{ stripe,store,mailer,config,key,now,pause });
  }
  emailHash(email) {
    return createHmac('sha256',this.config.recoveryPepper).update(email.trim().toLowerCase()).digest('hex');
  }
  async paidSession(id) {
    if (!/^cs_(test|live)_[A-Za-z0-9]{8,240}$/.test(id)) throw new Unavailable('invalid_order');
    if (!this.config.liveMode && !this.config.testReference) throw new Unavailable('wrong_order');
    const session = await this.stripe.checkout.sessions.retrieve(id,{expand:['payment_intent.latest_charge']});
    if (!this.config.liveMode && !sameReference(session.client_reference_id,this.config.testReference)) throw new Unavailable('wrong_order');
    if (session.livemode !== this.config.liveMode || session.mode !== 'payment' ||
        idOf(session.payment_link) !== this.config.paymentLinkID) throw new Unavailable('wrong_order');
    if (session.status !== 'complete' || session.payment_status !== 'paid') throw new Unavailable('payment_pending');
    const intent=session.payment_intent, charge=intent?.latest_charge;
    if (!intent?.id || !charge?.id || intent.status !== 'succeeded') throw new Unavailable('payment_pending');
    if (charge.refunded || charge.disputed || charge.amount_refunded > 0) {
      await this.store.block(intent.id);
      throw new Unavailable('payment_reversed');
    }
    const items = await this.stripe.checkout.sessions.listLineItems(id,{limit:2});
    if (items.has_more || items.data.length !== 1 || items.data[0].quantity !== 1 ||
        idOf(items.data[0].price) !== this.config.priceID ||
        !this.config.currencies.includes(session.currency) || !(session.amount_total > 0)) {
      throw new Unavailable('wrong_product');
    }
    const email=session.customer_details?.email;
    if (!email || email.length>254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Unavailable('missing_email');
    return session;
  }
  async fulfill(id) {
    const session=await this.paidSession(id);
    const email=session.customer_details.email;
    const order=await this.store.putOrder({
      session_id:session.id,payment_intent_id:session.payment_intent.id,email,
      email_hash:this.emailHash(email),livemode:session.livemode,
      license:issueLicense({session,key:this.key,keyID:this.config.keyID}),
    });
    if (order.blocked) throw new Unavailable('payment_reversed');
    const deliveryID=`purchase/${id}`;
    await this.store.queue(deliveryID,id);
    return { order,deliveryID };
  }
  async deliver(id) {
    const job=await this.store.claim(id);
    if (!job) return false;
    try {
      const order=await this.store.order(job.session_id);
      // Read Stripe again before every send, including recovery and old retries.
      // A refund can arrive before the original payment webhook.
      await this.paidSession(order.session_id);
      if (order.blocked) throw new Unavailable('payment_reversed');
      const providerID=await this.mailer.send(order,id);
      await this.store.sent(id,job.attempts,providerID);
      return true;
    } catch(error) {
      const backoff=Math.min(3600,60*2**Math.min(job.attempts-1,6));
      const retrySeconds=Math.max(backoff,error instanceof MailDeliveryError?error.retryAfterSeconds:0);
      await this.store.failed(id,job.attempts,error instanceof Unavailable ? error.message : 'delivery_retry',retrySeconds);
      throw error;
    }
  }
  async event(event) {
    if (event.livemode !== this.config.liveMode) throw new Unavailable('wrong_mode');
    if (['checkout.session.completed','checkout.session.async_payment_succeeded'].includes(event.type)) {
      if (idOf(event.data.object.payment_link) !== this.config.paymentLinkID) return;
      try {
        const {deliveryID}=await this.fulfill(event.data.object.id);
        await this.deliver(deliveryID);
      } catch(error) {
        // Delayed payments get another event when they settle. Permanent scope
        // mismatches are not retried; network/storage/mail failures are.
        if (!(error instanceof Unavailable)) throw error;
      }
    } else if (['charge.refunded','charge.dispute.created'].includes(event.type)) {
      let intent=idOf(event.data.object.payment_intent);
      if (!intent && event.type==='charge.dispute.created') {
        const charge=await this.stripe.charges.retrieve(idOf(event.data.object.charge));
        intent=idOf(charge.payment_intent);
      }
      if (intent) await this.store.block(intent);
    }
  }
  async recover(email,ip) {
    if (typeof email !== 'string' || email.length>254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return;
    const hash=this.emailHash(email);
    if (!await this.store.allowRecovery(`ip/${this.emailHash(ip)}`,10)) return;
    if (!await this.store.allowRecovery(`email/${hash}`,2)) return;
    const orders=await this.store.ordersForEmail(hash);
    for (const order of orders) {
      const id=`recovery/${order.session_id}/${Math.floor(Date.now()/3600000)}`;
      await this.store.queue(id,order.session_id);
      // The cron sends this durable job. Waiting on Stripe and email here
      // would disclose matching buyers through response time and hold the form
      // open during a provider outage.
    }
  }
  async retry() {
    await this.store.pruneRecoveryLimits();
    const jobs=await this.store.pending(50);
    const deadline=this.now()+20000;
    let sent=0;
    let attempted=0;
    for (const {id} of jobs) {
      if(this.now()>=deadline) break;
      attempted++;
      try { if (await this.deliver(id)) sent++; } catch {}
      // Pace backlog recovery below the provider's default five requests/sec.
      // Live webhooks share that quota; any 429 remains durably queued.
      await this.pause(250);
    }
    return {attempted,sent};
  }
}
