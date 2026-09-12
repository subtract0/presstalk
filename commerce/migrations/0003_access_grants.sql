CREATE TABLE access_grants (
  id TEXT PRIMARY KEY NOT NULL,
  token TEXT UNIQUE NOT NULL,
  label TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('extension','gift')),
  days INTEGER NOT NULL CHECK (days >= 0 AND days <= 3650),
  created_at INTEGER NOT NULL,
  claimed_at INTEGER,
  expires_at INTEGER,
  license TEXT,
  revoked INTEGER NOT NULL DEFAULT 0 CHECK (revoked IN (0,1)),
  revision INTEGER NOT NULL DEFAULT 0,
  last_action TEXT NOT NULL
);
CREATE INDEX access_grants_created ON access_grants(created_at DESC, id);
CREATE TABLE operator_logins (
  token_hash TEXT PRIMARY KEY NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE TABLE operator_sessions (
  token_hash TEXT PRIMARY KEY NOT NULL,
  expires_at INTEGER NOT NULL
);
