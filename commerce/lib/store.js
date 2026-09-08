export class Store {
  constructor(db,clock={now:'now()',lease:"now()+interval '90 seconds'",retry:"now()+interval '60 seconds'",hourAgo:"now()-interval '1 hour'"}) { this.db = db;this.clock=clock; }
  async putOrder(order) {
    const { rows } = await this.db.query(`INSERT INTO orders
      (session_id,payment_intent_id,email,email_hash,license,livemode)
      VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (session_id) DO UPDATE
      SET session_id = orders.session_id RETURNING *`,
    [order.session_id,order.payment_intent_id,order.email,order.email_hash,order.license,order.livemode]);
    return rows[0];
  }
  async order(id) {
    return (await this.db.query('SELECT * FROM orders WHERE session_id=$1',[id])).rows[0];
  }
  async ordersForEmail(hash) {
    return (await this.db.query('SELECT * FROM orders WHERE email_hash=$1 AND NOT blocked ORDER BY created_at DESC LIMIT 5',[hash])).rows;
  }
  async queue(id, sessionID) {
    await this.db.query('INSERT INTO deliveries (id,session_id) VALUES ($1,$2) ON CONFLICT DO NOTHING',[id,sessionID]);
  }
  async claim(id) {
    const { rows } = await this.db.query(`UPDATE deliveries SET state='sending',
      lease_until=${this.clock.lease},attempts=attempts+1
      WHERE id=$1 AND next_attempt_at <= ${this.clock.now}
      AND (state='pending' OR (state='sending' AND lease_until < ${this.clock.now}))
      RETURNING *`,[id]);
    return rows[0];
  }
  async sent(id, attempt, providerID) {
    await this.db.query(`UPDATE deliveries SET state='sent',provider_id=$3,sent_at=${this.clock.now},
      lease_until=NULL,last_error=NULL WHERE id=$1 AND attempts=$2 AND state='sending'`,[id,attempt,providerID]);
  }
  async failed(id, attempt, code) {
    await this.db.query(`UPDATE deliveries SET state='pending',lease_until=NULL,last_error=$3,
      next_attempt_at=${this.clock.retry} WHERE id=$1 AND attempts=$2 AND state='sending'`,[id,attempt,code]);
  }
  async pending(limit=20) {
    return (await this.db.query(`SELECT id FROM deliveries WHERE next_attempt_at<=${this.clock.now}
      AND (state='pending' OR (state='sending' AND lease_until<${this.clock.now})) ORDER BY next_attempt_at LIMIT $1`,[limit])).rows;
  }
  async block(paymentIntentID) {
    await this.db.query('UPDATE orders SET blocked=true WHERE payment_intent_id=$1',[paymentIntentID]);
    await this.db.query(`UPDATE deliveries SET state='blocked' WHERE session_id IN
      (SELECT session_id FROM orders WHERE payment_intent_id=$1) AND state != 'sent'`,[paymentIntentID]);
  }
  async allowRecovery(key, maximum) {
    const { rows } = await this.db.query(`INSERT INTO recovery_limits (key) VALUES ($1)
      ON CONFLICT (key) DO UPDATE SET
      attempts=CASE WHEN recovery_limits.window_start<${this.clock.hourAgo} THEN 1 ELSE recovery_limits.attempts+1 END,
      window_start=CASE WHEN recovery_limits.window_start<${this.clock.hourAgo} THEN ${this.clock.now} ELSE recovery_limits.window_start END
      RETURNING attempts`,[key]);
    return rows[0].attempts<=maximum;
  }
  async health() {
    await this.db.query('SELECT session_id,license,blocked FROM orders LIMIT 0');
    await this.db.query('SELECT id,state,lease_until,provider_id FROM deliveries LIMIT 0');
    await this.db.query('SELECT key,window_start,attempts FROM recovery_limits LIMIT 0');
  }
}
