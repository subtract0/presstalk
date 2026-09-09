# Production purchase service — 2026-09-09

> Historical preparation snapshot. The [public release record](2026-09-09-public-release.md)
> contains the completed publication and current cutover verification.

The production licence Worker is deployed and its live-mode health endpoint
passes. The existing Stripe checkout remains active. The new PressTalk webhook
is staged and the service's new-sales switch remains off until the matching Mac
release and website cutover. This is deployed infrastructure and verified
automatic fulfilment behavior, not a completed public launch or a live sale.

## Customer behavior and recovery

Receipt downloads no longer wait for email. Recovery requests queue the original
licence without contacting Stripe or email providers before returning; this
also removes the pronounced response-time difference between existing buyers
and unknown email addresses. Signed payment webhooks send purchase receipts,
and cron handles both purchase retries and recovery receipts.

The outbox now uses an index over active deliveries rather than scanning all
historical customers. A second index covers refund lookups. Every-minute runs
process up to 50 jobs, paced at 250 ms, and stop starting jobs after 20 seconds.
An already-started provider request can finish after that budget. Failures back
off from one minute to one hour, respecting provider Retry-After up to 24 hours.
Expired recovery limits are pruned in bounded batches, with current abuse limits
preserved. D1 health rejects a missing capacity migration.

The existing atomic claims, original licence, payment verification and provider
idempotency remain intact. The monitor's `failed` flag reports failure of the
scheduled run itself; per-job retries remain visible in attempted/sent counters
and the durable outbox. A successful cron invocation is not proof of delivery.

## Evidence

- PostgreSQL and workerd/D1 contracts pass for payment scope, invalid signatures,
  duplicate events, concurrent delivery, refunds, recovery, unavailable email,
  persistent backoff, bounded processing and rate-limit cleanup. The added live
  mode contract passes in both stores with a fixture key; it is not a live charge.
- The actual compiled Worker passes signed webhook → D1 licence → HTTP mail
  adapter → receipt tests in workerd. A service-binding spy verifies that the
  actual request path emits only approved observation fields. Removing the
  production monitoring call fails that behavioral assertion.
- With 500,000 fixture orders and deliveries in local workerd/D1, selecting 20
  jobs from a 37-job active backlog read 20 rows. Removing the production index
  made the same query read 500,037 rows. This is a queue-query/storage check,
  not a measurement of simultaneous purchases or provider throughput.
- Both remote databases have `0002_delivery_capacity.sql`. The live readiness
  check verifies the real Stripe product, app verification key, database schema
  and indexes, verified sender domain and disabled email tracking.
- Production health returns live mode, sales disabled and key `commerce-2026`.
  Invalid webhook input is rejected with HTTP 400; an unknown route returns 404.
- The owner's real paid sandbox order was used for an automatic recovery test.
  The isolated acceptance service temporarily received an invalid email key;
  the recovery form returned 202 in about 328 ms and queued a zero-attempt job.
  An actual scheduled run retained the failed send. Working configuration was
  restored in `finally`; the next successful scheduled attempt sent the original
  licence, and Resend reported `delivered`. No `/api/retry` call, new payment or
  owner action was used. The licence download still matches the owner's file.
  The initial harness attempt stopped while parsing Wrangler's `--file` output
  and restored configuration; it is not counted as a successful recovery test.
- The installed Mac's Settings focus check passed through synthetic Fn events,
  actual capture and a no-speech completion, with TextEdit in front throughout.
  That check covers window focus, not spoken-content accuracy. TextEdit's
  AppleEvent close timed out; the temporary document was closed through native
  Accessibility and the prior browser foreground was restored.

## Deployment and private monitoring

Production: `presstalk-licenses.presstalk.workers.dev`, version
`1d4137eb-05ca-4e35-aea4-7f5e9960463e`. Its deployed bundle and restored acceptance
bundle are byte-identical to the compiled-runtime test artifact:
`b255fd0e3db70600e8c8707c86fdbe810cd50d3b441382e0a0b4bea39ba81550`.

The new Stripe endpoint is `we_1UDXmRJpvh3XLeRlsS4Tuv0K`, restricted to completed
and settled checkout sessions, refunds and disputes. It is disabled for staging;
the existing Payment Link and unrelated endpoints were preserved. Production
uses the persistent restricted live key and separate recovery/retry secrets,
while retaining the already-trusted licence signing key.

The private `presstalk-commerce-monitor` service has no public route. The
purchase Worker sends only approved route labels, status codes, timings and
retry counters through a service binding. The monitor enables structured logs
and sampled traces. Automatic logs and traces remain disabled on the purchase
Worker itself because receipt and Stripe request URLs contain bearer IDs.
This applies Cloudflare's observability guidance without storing raw purchase
requests. See [Workers Logs](https://developers.cloudflare.com/workers/observability/logs/workers-logs/)
and [service bindings](https://developers.cloudflare.com/workers/runtime-apis/bindings/service-bindings/rpc/).

A live marker in an unknown request path/query and invalid webhook body was
absent from the monitor's entire observed event output. The expected health,
404 and 400 records arrived over the real binding. No customer identity,
licence, request body or credential is an allowed observation field.

Private receipts, source/artifact hashes and logs are under `.local/commerce/`:
`production-readiness.log`, `production-deploy.log`, `production-secrets.json`,
`production-webhook-staged.json`, `order-capacity-500000.json`,
`monitor-canary.jsonl`, `automatic-recovery.json` and `focus-check-result.json`.
The secret files and paid receipt URLs must never enter a public artifact.

## Still required for the full goal

Investigate the first AirPods timestamp discontinuity without weakening capture
integrity. Publish the audited Mac artifact, update both website languages and
support information, enable the new webhook and live sales, set the verified
receipt redirect and check the public flow. Verify customer support forwarding
and operational provider quotas. Provider capacity is separate from the local
500,000-order check: [Resend's free quotas](https://resend.com/docs/knowledge-base/account-quotas-and-limits)
are 100 emails/day and 3,000/month. Billing capacity must be handled before that
volume; the current work does not claim 500,000 concurrent purchases. Installed
paid Macs work offline without periodic licence-server calls.
