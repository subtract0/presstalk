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

- Node 24. An isolated Vercel `presstalk-licenses` project is prepared, but the
  current team is Hobby, which does not permit commercial hosting. A commercial
  hosting route must be selected before production (Vercel Pro or Cloudflare
  Workers on its free plan). `worker.js` and the tested D1 adapter are ready for
  the latter. `wrangler.jsonc` needs the real account/database binding and secrets.
- PostgreSQL for orders, email attempts and recovery limits. Apply `schema.sql`
  with `npm run migrate`; configuration/secrets are runtime environment variables.
- Resend for purchase receipts, with open/click tracking disabled. Its accepted
  send response is not proof that a person received the email.
- Signature-checked Stripe webhooks retry transient failures. The durable outbox
  also has a fallback cron (every five minutes on Cloudflare, daily on the
  prepared Vercel configuration) and can be processed through the authorized
  `/api/retry` endpoint. The paid receipt remains available during mail outages.
- `SALES_ENABLED=false` pauses `/buy` while preserving all existing receipt and
  recovery routes. The Stripe link's `active` flag independently protects old
  app versions that still contain the direct link.
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

Fallback delivery waits for the next scheduled run after Stripe's own retries
are exhausted. Each run processes up to five pending jobs. Monitor pending and
failed deliveries, and distinguish provider acceptance from delivery. Do not
silently add a paid plan to increase throughput.

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

Rollback new purchases with both `SALES_ENABLED=false` and the exact link's
`active=false`. Keep the service and its keys/database available for existing
customers. Do not delete orders or replace trusted signing keys during rollback.
