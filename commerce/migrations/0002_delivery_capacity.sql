-- Keep retry work proportional to the active backlog, not all past customers.
CREATE INDEX deliveries_ready ON deliveries(next_attempt_at) WHERE state IN ('pending','sending');
CREATE INDEX deliveries_session ON deliveries(session_id);
CREATE INDEX recovery_limits_window ON recovery_limits(window_start);
