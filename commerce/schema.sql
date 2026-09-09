CREATE TABLE IF NOT EXISTS orders (
  session_id TEXT PRIMARY KEY,
  payment_intent_id TEXT NOT NULL,
  email TEXT NOT NULL,
  email_hash TEXT NOT NULL,
  license TEXT NOT NULL,
  livemode BOOLEAN NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  blocked BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS orders_email_hash ON orders(email_hash);
CREATE INDEX IF NOT EXISTS orders_payment_intent ON orders(payment_intent_id);
CREATE TABLE IF NOT EXISTS deliveries (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES orders(session_id),
  state TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','sending','sent','blocked')),
  attempts INTEGER NOT NULL DEFAULT 0,
  lease_until TIMESTAMPTZ,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  provider_id TEXT,
  sent_at TIMESTAMPTZ,
  last_error TEXT
);
CREATE TABLE IF NOT EXISTS recovery_limits (
  key TEXT PRIMARY KEY,
  window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
  attempts INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS deliveries_ready ON deliveries(next_attempt_at) WHERE state IN ('pending','sending');
CREATE INDEX IF NOT EXISTS deliveries_session ON deliveries(session_id);
CREATE INDEX IF NOT EXISTS recovery_limits_window ON recovery_limits(window_start);
