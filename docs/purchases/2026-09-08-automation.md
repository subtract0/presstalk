# Automatic purchase delivery — 2026-09-08

Status: email DNS and persistent Stripe access are verified. The isolated
**acceptance service is deployed**; the production service is not deployed or
open for sales. The owner completed a real sandbox checkout, received a delivered
receipt, downloaded the valid licence and activated installed 0.1.23 / 23.1.
The saved licence matches the downloaded file. Apple notarization credentials
are now validated. A broader Mac setup/release review is in progress; full-app
offline relaunch and production publication remain outstanding. Corrected build
23.2 is frozen and hash-bound; the Downloads release finisher is ready because
codesign's secure timestamp step failed in the earlier agent session. The owner
installed that candidate; a real native paste failure was then repaired. Build
**23.3 is now notarized and installed**, with the licence and permissions
preserved. See `2026-09-08-setup-paste-repair.md` for the current artifact and
verification boundaries. Public 0.1.22 remains unchanged.

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
| Mac suite | The purchase baseline passed 222 tests; the setup review expanded this to 226 passing tests, including a negative check that owners never read the trial anchor while actual trials still do. |
| Native app store | Actual ProductUI entitlement and trial-start call sites pass with isolated preferences and counting stores. Two deliberate call-site defects are rejected by behavioral assertions. No real Keychain access. |
| Cross-language licence | Actual JavaScript issuer matches the Swift fixture; CryptoKit accepts it, new store/defaults instances retain it, expired trial and future major 99 remain licensed. Not yet a customer app relaunch. |
| PostgreSQL | 15 purchase/delivery/recovery tests passed using real PGlite SQL. |
| Cloudflare D1 | The same 15 tests passed in the D1 runtime, including concurrent duplicate delivery, missing-schema rejection and unrelated sandbox-payment rejection. |
| Remote D1 | `presstalk-orders` created with EU jurisdiction in account `cbcced21185315aff602a2938ac194ee`; migration `0001_orders.sql` applied and actual required columns verified remotely. Empty purchase store, no buyer transaction. |
| Compiled Worker | Actual Wrangler bundle ran in workerd: signed webhook → stored licence → outgoing HTTP receipt attachment → receipt page. HTTP payment/email providers are intercepted local fixtures. Invalid signature and duplicate-page checks pass. |
| Runtime defects found | Switched to asynchronous Stripe webhook verification; retained native fetch's global receiver. Both defects escaped the Node-only tests and failed the compiled-worker test first. |
| Visuals | Receipt/recovery controls verified at 1100px desktop and 390px phone widths. Screenshots reviewed; no horizontal clipping. Local fixtures only. |
| Existing app behavior | Capture source unchanged; capture wiring, offer consistency and site privacy gates pass. |
| Readiness gate | Correctly fails with missing real configuration; cannot pass using the fixture screenshots or unit-test results. |
| Signed Mac candidate | 0.1.23 / 23.1 built; deep/strict signature, original designated requirement, both public keys and activation metadata verified. Binary SHA-256 `c6d96605fa56de229fc5535057a97f5e1a0c9232d42241db102de85386557387`. Installed and activated by the owner; not notarized or published. A corrected setup candidate is being prepared. |
| Acceptance deployment | `presstalk-licenses-acceptance.presstalk.workers.dev`, version `a5901c57-7b6b-4623-b600-64b8c30d82c5`. Tested and deployed bundle SHA-256 both `56dc4030c62dca19dbf94117afe3a38ad2db363ef048c7eec6d312b401149199`. Remote schema health passes; invalid webhook returns 400; anonymous retry returns 401; authorized empty retry returns 200. This is not completed purchase evidence. |

Receipts and logs are under `.local/commerce/` in this worktree. The owner has
installed 0.1.23 / 23.1; public 0.1.22 remains the live release. See
`2026-09-08-release-review.md` for the expanded native review and acceptance evidence.

## External setup and actual blockers

1. **Hosting:** the owner completed Wrangler authorization. Account
   `cbcced21185315aff602a2938ac194ee` is pinned in the Worker configuration.
   The initial grant omitted `workers_scripts:write`; an actual Workers request
   returned authentication error 10000. The owner approved the additional scope.
   Registered `presstalk.workers.dev` and deployed the acceptance Worker. No
   production Worker or plan upgrade was made. The existing Vercel
   Hobby project remains unused; its commercial-plan limitation does not block
   the selected Cloudflare route.
2. **Database:** D1 `presstalk-orders`, ID
   `f4ee6ffd-a0ef-45c5-b240-381724cb3f53`, now exists with EU jurisdiction.
   `0001_orders.sql` applied successfully and the remote schema contract passed.
   Neon provisioning is unnecessary for this route.
   Acceptance uses a separate EU `presstalk-orders-acceptance` database,
   `84b65ca6-ad3e-4a03-8638-1642cab684c3`, with the same migration and a verified
   remote schema. The production binding was preserved.
3. **Email:** Resend Free resource `presstalk-receipts` was provisioned through
   Vercel and connected to the isolated project. Domain `presstalk.app`, ID
   `81e788ea-1a6e-4351-b8ce-eeba31b7f691`, is now verified. Created the three
   sending records through Porkbun after dry runs, verified authoritative DNS
   and preserved all nine previous records. Open/click tracking remain disabled.
   The purchase receipt and a recovery receipt have both reached provider status `delivered`.
4. **Stripe access:** the owner completed CLI OAuth for the existing account,
   including live mode, and saved a persistent restricted live key through the
   hidden-input launcher. All five required resource reads and Payment Link
   line-item reads pass. The private key file is mode 0600. The existing live
   link remains active with hosted confirmation; three sessions are present,
   none paid at the latest scoped check. Live mutation permissions have not yet
   been exercised with the new OAuth session.
   Created a separate sandbox product, price, Managed Payments link and webhook
   for acceptance. The sandbox product uses the existing product's tax code and
   the same three price amounts. Its private reference restricts issuance to
   the acceptance link. One sandbox checkout is now paid and complete. Stripe's
   actual completed event has no pending webhooks; redelivery left one order and
   one purchase receipt delivery. No live transaction was created by this test.
   The owner's subsequent instruction is explicit: leave the existing checkout
   active and finish automatic delivery. Do not repeat the attempted pause.
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
`Authorize PressTalk Hosting.command`. `Connect PressTalk Accounts.command`
adds Porkbun's PKCE browser approval before the hidden Stripe key entry.
`Install PressTalk Purchase Test.command` verifies and installs the exact local
candidate after the owner quits PressTalk, preserving the previous app.
`Test PressTalk Purchase.html` contains the private sandbox checkout link and
instructions. `Test PressTalk Offline.command` launches only PressTalk with
network access denied. Script syntax, candidate signature/hash and designated
requirement pass; actual installation and offline launch still require owner
execution. This agent's sandbox rejects nested `sandbox-exec` with
`sandbox_apply: Operation not permitted`, so its successful operation is not
claimed.
The launcher saves the Stripe restricted key without displaying it. The HTML
contains the exact public DNS records, current blockers and host choices.

Cloudflare agent setup is also installed locally: 14 official skills under
`~/.codex/skills/` and the five requested MCP connections in
`~/.codex/config.toml`. Main Cloudflare and bindings OAuth succeeded; public docs
passed an actual initialize/tools-list protocol check. Builds and observability
are registered but unauthenticated after their initial callback timeouts; they
can request OAuth when used. Codex has now restarted; main Cloudflare, bindings
metadata and public documentation passed live read checks. No browser backend
was connected, and the owner reports no Browser control or working shortcut.
Use the normal browser for provider authorization; do not treat a saved browser
configuration as a working connection. Existing Codex settings were preserved.
Setup and remote database receipts are in
`.local/commerce/cloudflare-agent-setup/`.

## Required operational finish

Apple notarization credentials are now validated in the explicit login Keychain
under profile `presstalk-notary`. The owner completed the secure Downloads
launcher and a real `notarytool history` request succeeds. Corrected build 23.3
has since received its own Accepted result and stapled ticket and is installed.
Never use an older ticket for a changed binary, access the protected original
signing directory or retry the failed local-development keychain password.

No new installation or authorization is required. If needed later,
`~/Downloads/Install PressTalk Release Candidate.command` reinstalls the verified
0.1.23 / 23.3 artifact with a backup. `Test PressTalk Offline.command` targets the
same exact installed build. Both reject changed artifacts or ambiguous process
checks. Earlier installers are preserved under `~/Downloads/PressTalk Previous
Setup/`. Current verification limits are in `2026-09-08-setup-paste-repair.md`.

Use `commerce/README.md` for the acceptance sequence. Keep the original offline
license promise. The email provider's successful API response is acceptance for
sending, not proof of inbox delivery. The provider's 24-hour idempotency window
means a crash across that boundary can send a second receipt with the same key;
it never creates another charge or a different entitlement.

Publish only the isolated purchase branch after review. Local main contains
unrelated unpublished business documents; do not blindly push it.
