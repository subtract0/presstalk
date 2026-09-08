# Automatic purchase delivery — 2026-09-08

Status: implementation, local verification and the remote D1 schema are complete;
the **purchase service is not deployed or open for sales**. Email DNS, persistent
Stripe access and live acceptance remain required.

## Implemented

- Existing Stripe Managed Payments checkout remains the payment provider.
  Verified checkout configuration: `plink_1UCjsiJpvh3XLeRlvwQnSfDk`,
  `price_1UCjhFJpvh3XLeRlgcMWwBHf`, one Founder licence, EUR 20 / USD 20 / CAD 28.
- Signature-verified webhooks and a receipt page converge on one durable order.
  Only settled payments for the expected link, price, currency and quantity issue
  a key. Refunds and disputes block future delivery/recovery.
- Automatic email receipt with licence attachment, direct Mac activation link,
  manual-key fallback, private receipt page and limited email-based recovery.
- Durable SQL delivery claims and retries; the same licence on duplicate events.
  No customer account or recurring app activation is introduced.
- The new `commerce-2026` public key is added beside the existing founder key.
  Existing signed licences keep verifying. No access to the protected original
  signing directory, Keychain signing export, or microphone-default change.
- Native URL and licence-file activation, sharing the offline persistence layer
  with manual import. Invalid activation preserves an existing valid licence.
- Paid and early-user entitlements skip the trial Keychain record, including
  trial-start handling after dictation. Actual trials still consult their anchor.
- Stable app purchase address `https://presstalk.app/buy.html`; the prepared page
  remains paused until the tested service destination is known and ready.

## Evidence

| Check | Result and scope |
|---|---|
| Mac suite | 222 tests passed, including a negative check that owners never read the trial anchor while actual trials still do. |
| Native app store | Actual ProductUI entitlement and trial-start call sites pass with isolated preferences and counting stores. Two deliberate call-site defects are rejected by behavioral assertions. No real Keychain access. |
| Cross-language licence | Actual JavaScript issuer matches the Swift fixture; CryptoKit accepts it, new store/defaults instances retain it, expired trial and future major 99 remain licensed. Not yet a customer app relaunch. |
| PostgreSQL | 14 purchase/delivery/recovery tests passed using real PGlite SQL. |
| Cloudflare D1 | The same 14 tests passed in the D1 runtime, including concurrent duplicate delivery and missing-schema rejection. |
| Remote D1 | `presstalk-orders` created with EU jurisdiction in account `cbcced21185315aff602a2938ac194ee`; migration `0001_orders.sql` applied and actual required columns verified remotely. Empty purchase store, no buyer transaction. |
| Compiled Worker | Actual Wrangler bundle ran in workerd: signed webhook → stored licence → outgoing HTTP receipt attachment → receipt page. HTTP payment/email providers are intercepted local fixtures. Invalid signature and duplicate-page checks pass. |
| Runtime defects found | Switched to asynchronous Stripe webhook verification; retained native fetch's global receiver. Both defects escaped the Node-only tests and failed the compiled-worker test first. |
| Visuals | Receipt/recovery controls verified at 1100px desktop and 390px phone widths. Screenshots reviewed; no horizontal clipping. Local fixtures only. |
| Existing app behavior | Capture source unchanged; capture wiring, offer consistency and site privacy gates pass. |
| Readiness gate | Correctly fails with missing real configuration; cannot pass using the fixture screenshots or unit-test results. |
| Signed Mac candidate | 0.1.23 / 23.1 built; deep/strict signature, original designated requirement, both public keys and activation metadata verified. Binary SHA-256 `c6d96605fa56de229fc5535057a97f5e1a0c9232d42241db102de85386557387`. Not notarized, installed or published. |

Receipts and logs are under `.local/commerce/` in this worktree. No new app
artifact has been published or installed. Public 0.1.22 remains the live release.

## External setup and actual blockers

1. **Hosting:** the owner completed Wrangler authorization. Account
   `cbcced21185315aff602a2938ac194ee` is pinned in the Worker configuration.
   No Worker has been deployed and no plan upgrade was made. The existing Vercel
   Hobby project remains unused; its commercial-plan limitation does not block
   the selected Cloudflare route.
2. **Database:** D1 `presstalk-orders`, ID
   `f4ee6ffd-a0ef-45c5-b240-381724cb3f53`, now exists with EU jurisdiction.
   `0001_orders.sql` applied successfully and the remote schema contract passed.
   Neon provisioning is unnecessary for this route.
3. **Email:** Resend Free resource `presstalk-receipts` was provisioned through
   Vercel and connected to the isolated project. Domain `presstalk.app`, ID
   `81e788ea-1a6e-4351-b8ce-eeba31b7f691`, awaits DKIM plus sending-subdomain
   SPF/MX records in Porkbun. Tracking is disabled. Real email has not been sent.
   Credentials are present. A Python request returned 403, while subsequent Node
   requests using the same saved credential returned the domain list and detail.
   The cause of that client-dependent difference is not established; it is not
   evidence that another email credential is required.
4. **Stripe access:** existing CLI authentication supports live reads but rejected
   `active=false` twice with `more_permissions_required`. **The old link is still
   active.** A persistent restricted read key is needed for the deployed service;
   checkout/webhook changes need operator permissions or the owner dashboard.
   No payment settings were successfully changed and no transaction was made.
5. **Acceptance/publication:** complete real Stripe sandbox checkout, provider
   delivery, built-app activation and offline relaunch before enabling sales.
   Publish the app carrying the new key and activation handlers, then configure
   the receipt redirect and stable website purchase page. Do not count any test
   transaction as customer demand.

The generated issuer material is in owner-only durable local storage outside the
worktree and upload root. Its location, not its value, is recorded in operating
memory. Never replace the original trusted public key or retry the old failed
local code-signing password.

User-facing setup files are in Downloads:
`PressTalk Purchase Setup.html`, `Finish PressTalk Purchase Setup.command` and
`Authorize PressTalk Hosting.command`.
The launcher saves the Stripe restricted key without displaying it. The HTML
contains the exact public DNS records, current blockers and host choices.

Cloudflare agent setup is also installed locally: 14 official skills under
`~/.codex/skills/` and the five requested MCP connections in
`~/.codex/config.toml`. Main Cloudflare and bindings OAuth succeeded; public docs
passed an actual initialize/tools-list protocol check. Builds and observability
are registered but unauthenticated after their initial callback timeouts; they
can request OAuth when used. Restart Codex to load the new tools. Existing Codex
settings were preserved. Setup and remote database receipts are in
`.local/commerce/cloudflare-agent-setup/`.

## Required operational finish

Use `commerce/README.md` for the acceptance sequence. Keep the original offline
license promise. The email provider's successful API response is acceptance for
sending, not proof of inbox delivery. The provider's 24-hour idempotency window
means a crash across that boundary can send a second receipt with the same key;
it never creates another charge or a different entitlement.

Publish only the isolated purchase branch after review. Local main contains
unrelated unpublished business documents; do not blindly push it.
