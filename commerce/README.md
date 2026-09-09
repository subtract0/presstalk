# PressTalk purchase service

Buy once, activate on the Mac, continue offline. This service handles purchases
and receipts only. It never sees microphone audio or dictated text.

Stripe Managed Payments remains the checkout. Its verified paid Checkout Session
is checked against the exact configured Payment Link and Price, quantity one,
allowed currencies, and current charge/refund status. The webhook and receipt
page converge on a unique database order and stable Ed25519 licence. The original
`founder-2026` verification key stays in the app; the separate `commerce-2026`
key adds automatic issuance without accessing the original signing directory.

After paying, the buyer can open `presstalk://activate`, download a
`.presstalk-license` file, or paste the licence. Email contains the same key and
file. Recovery emails the stored licence only to the original purchase address,
with a generic response and database-backed hourly limits. No account, machine
binding, periodic activation check or remote licence revocation is added.

## Runtime

- Cloudflare Workers with D1 is the selected production host. `wrangler.jsonc`
  pins the authorized account and existing EU `presstalk-orders` database.
  Migrations `0001_orders.sql` and `0002_delivery_capacity.sql` are applied and
  the remote schema and required indexes were verified. The production Worker
  is deployed with new sales disabled and its new Stripe webhook staged.
  The isolated acceptance Worker uses a separate EU database. The owner has
  completed test Checkout, received the licence, and dictated with the whole
  Mac app offline. Final public release and checkout cutover remain outstanding.
- The Node 24/PostgreSQL adapter remains an alternative runtime. The prepared
  Vercel Hobby project is unused; no hosting plan upgrade is needed for the
  selected Cloudflare route.
- Resend for purchase receipts, with open/click tracking disabled. Its accepted
  send response is not proof that a person received the email.
- Signature-checked Stripe webhooks retry transient failures. The durable outbox
  also has a fallback cron (every minute on Cloudflare, daily on the
  prepared Vercel configuration) and can be processed through the authorized
  `/api/retry` endpoint. Receipt downloads and recovery forms never wait for an
  email send. The signed payment webhook sends the purchase receipt; cron also
  handles purchase retries and queued recovery receipts.
- `SALES_ENABLED=false` pauses `/buy` while preserving all existing receipt and
  recovery routes. Older app versions contain the direct Stripe Payment Link
  and bypass this switch. The owner explicitly requested that the existing
  Stripe link remain active during setup; do not deactivate it.
- The new Mac app opens the stable, user-owned `https://presstalk.app/buy.html`.
  That page stays paused until the service passes acceptance, then redirects to
  its verified `/buy` URL. Changing hosts will not require another Mac release.

## Invariants and limits

Each session issues exactly one stored licence. A deterministic licence ID and
issue timestamp also reproduce that licence after a database restore using the
same signing key. Atomic SQL claims prevent concurrent sends. Resend receives a
stable idempotency key on retries; its deduplication window is 24 hours. A crash
after provider acceptance but before the database commit can cause a duplicate
receipt on a much later retry, carrying the same licence, never another charge.

Refunds/disputes stop future fulfilment and recovery. An already imported offline
licence cannot be revoked remotely. Recovery has no account-existence response;
payment session IDs and receipt links are bearer credentials and must not be
logged or sent to analytics. Responses are private/no-store/no-referrer with a
restricted Content Security Policy. Logging excludes email, session IDs and keys.

Each scheduled run considers up to 50 jobs, paces them at 250 ms intervals, and
stops starting new jobs after 20 seconds. An in-flight request can finish after
that budget. Transient failures back off from one minute to one hour, and honour
the email provider's Retry-After delay up to 24 hours. Claims and provider
idempotency remain in force. Old recovery-rate-limit records are pruned in
bounded batches without resetting current limits.

The production Worker sends only allowlisted route/status/timing and retry
counters through a private `MONITOR` service binding. Logs and sampled traces
are enabled on that service. Automatic request logs and traces stay disabled on
the purchase Worker because incoming receipt URLs and outgoing Stripe URLs
contain bearer identifiers. Customer addresses, licence keys, raw URLs, headers,
bodies and provider errors do not cross the monitoring binding. A compiled
workerd test covers the actual binding call, and a live marker probe checks its
output. The monitoring service has no public route.

Distinguish provider acceptance from delivery. The current provider plan's
quotas are separate from database capacity: a free Resend account is limited to
100 emails per day and 3,000 per month. Verify and increase commercial quotas
before that volume is reached; do not silently add a paid plan. Paid owners'
installed apps do not generate recurring licence-server requests.

## Tests

`npm test` runs real PostgreSQL statements in PGlite. It exercises duplicate and
concurrent events, signature failures, wrong products/modes/currencies, delayed
payments, refunds, email outages and retry after service reconstruction, recovery
rate limits, protected retry access and real mail payload construction.

`TEST_STORE=d1 npm test` runs the same contracts in Cloudflare's D1 runtime.
`npm run build:worker` followed by `npm run test:worker` tests the exact compiled
worker in workerd, with intercepted Stripe/Resend HTTP. This caught two issues
that Node tests could not: the edge runtime needs asynchronous webhook signature
verification and the native fetch function's global receiver must be retained.
Set `PRESSTALK_WORKER_TEST_BUNDLE` to an absolute bundle path to verify a separate
deployment artifact. For the readiness script, use `--wrangler-config PATH`
with `--cloudflare` to verify that deployment's actual database binding.

`node scripts/check-order-capacity.js 500000` creates 500,000 fixture orders and
deliveries in local workerd/D1, then calls the actual store's pending-job query.
Selecting 20 jobs from a 37-job backlog read 20 rows; removing the production
index made it read 500,037. The absent-index control must fail the capacity
condition. This is a queue-query/storage test, not a claim about simultaneous
purchases, provider quotas or email throughput. D1 checkout health also rejects
the missing migration. `npm run build:monitor` builds the private monitoring
service; deploy that service before the purchase Worker.

Test-mode deployments require a random `STRIPE_TEST_REFERENCE` of at least
32 URL-safe characters. Include it as `client_reference_id` only in the private
acceptance Payment Link URL. Other sandbox payments cannot issue a licence,
even when they use the same product and otherwise appear paid. Keep this value
and the private test URL out of public pages, source control and logs. Live mode
does not require a test reference.

`node scripts/review-pages.js` renders labelled local fixtures at desktop and
phone sizes; set `CHROMIUM_PATH` if using an existing browser binary. These
screenshots are visual QA, not payment evidence.

The Mac's `OfflineLicenseStoreTests` verify the same JavaScript-issued fixture
through CryptoKit, a new preferences/store instance, an expired trial and a
future major version. Invalid imports cannot displace a working licence.

## Production acceptance (required before opening sales)

1. Confirm commercial hosting, provision the database, migrate it, verify the email DNS records and disable
   tracking. Use a persistent restricted Stripe read key, not expiring CLI keys.
   Run `node scripts/check-ready.js` (add `--cloudflare` for the actual remote D1
   database check); it must fail if any required service is
   absent. This check is necessary but does not replace the purchase test below.
2. Deploy with new sales disabled. Configure exact matching Stripe webhook
   secrets and test/live objects separately. Register session completed,
   async-payment-succeeded, charge refunded and charge dispute created events.
3. Complete a real Stripe test-mode Checkout, observe the signed webhook, the
   saved order, email provider delivery evidence and the receipt page. Import
   that delivered key in the built Mac app, restart offline and verify use after
   trial expiry. Test repeat event and failed-mail retry on the deployed service.
4. Sign/notarize and publish the app carrying the new public key and activation
   handlers. Audit the downloaded public artifact; retain original bundle identity.
5. Set the existing Payment Link's after-completion redirect to the verified
   service origin plus `/thanks?session_id={CHECKOUT_SESSION_ID}`.
   Verify the live mode/configuration and persistent credentials, enable the
   service's sales switch and existing link, then update the site's purchase links.
6. Record actual order/email/activation receipts privately. Never call isolated
   tests, preview screenshots, or free owner transactions verified customer sales.

`SALES_ENABLED=false` stops purchases through the service. The direct Stripe
link is independent; leave it active under the owner's current instruction.
Keep receipt/recovery routes and their keys/database available for existing
customers. Do not delete orders or replace trusted signing keys during rollback.
