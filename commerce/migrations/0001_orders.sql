CREATE TABLE orders (
  session_id TEXT PRIMARY KEY NOT NULL,
  payment_intent_id TEXT NOT NULL,
  email TEXT NOT NULL,
  email_hash TEXT NOT NULL,
  license TEXT NOT NULL,
  livemode INTEGER NOT NULL CHECK (livemode IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  blocked INTEGER NOT NULL DEFAULT 0 CHECK (blocked IN (0,1))
);
CREATE INDEX orders_email_hash ON orders(email_hash);
CREATE INDEX orders_payment_intent ON orders(payment_intent_id);
CREATE TABLE deliveries (
  id TEXT PRIMARY KEY NOT NULL,
  session_id TEXT NOT NULL REFERENCES orders(session_id),
  state TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','sending','sent','blocked')),
  attempts INTEGER NOT NULL DEFAULT 0,
  lease_until TEXT,
  next_attempt_at TEXT NOT NULL DEFAULT (datetime('now')),
  provider_id TEXT,
  sent_at TEXT,
  last_error TEXT
);
CREATE TABLE recovery_limits (
  key TEXT PRIMARY KEY NOT NULL,
  window_start TEXT NOT NULL DEFAULT (datetime('now')),
  attempts INTEGER NOT NULL DEFAULT 1
);
