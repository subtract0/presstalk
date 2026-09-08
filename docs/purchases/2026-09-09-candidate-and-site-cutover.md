# Candidate and website cutover — 2026-09-09

The owner’s live Fn recordings are preserved in the offline-dictation receipt.
The three described routes delivered text: Shure with AirPods in their case,
explicit Shure with AirPods connected, and AirPods input. The first AirPods
attempt was interrupted before the subsequent successes. Its cause remains
unresolved; this work does not declare capture reliability or public launch.

## Installed candidate

PressTalk 0.1.23/build 23.4 is installed at `~/Applications/PressTalk.app`.
Native source commit: `9d77bac1723dc05a96dad15c764cbf43d8d00e3e`.

- Binary SHA-256: `513cf2ab08fdc836cc5841b0d782f19691c057639f258abd7737add67a349801`.
- Stapled ZIP SHA-256: `4e810986242f962dbd7ddfeaa71163d409cd091194a2f8fa1db926dc393c490b`.
- Apple notarization: `bb176327-ffab-48b0-bcb1-b80bd14b1217`, Accepted.
- Developer ID, team, secure timestamp, hardened runtime, microphone
  entitlement, stapled ticket and Gatekeeper checks pass.

The change preserves expected/observed timestamps and raw reason/status in a
failed capture receipt, with plain retry guidance in the customer message.
The continuity check is unchanged. It does not reconstruct missing audio or
establish why the earlier AirPods timestamp jumped.

All 227 Swift tests and 22 capture-wiring mutations pass. The installed binary's
actual `--audio-selftest` retained 19,285 converted frames (1.205 seconds); that
is transport evidence, not speech or insertion acceptance. The earlier live
speech acceptance belongs to build 23.3, not this new artifact.

The installer verified idle input, released Fn and completed processing before
quitting the previous app gracefully. Build 23.3 was preserved in the owner's
application backup folder. Licence, microphone preference and shortcut
fingerprints match before and after installation. Startup recognizes the three
existing permissions and reports the speech model Ready. No TCC grant, system
audio property, or signing identity was changed.

Private evidence: `.local/commerce/capture-diagnostics-23.4/`, including the
manifest, release receipt, readiness report, notarization result, preference
fingerprints and installed-binary transport report.

## Prepared customer pages

The local English and German homepage, download and purchase pages now describe
normal purchase and activation. Prices, three-day trial, fourteen-day refund
and included-update promises are preserved. Setup instructions follow the
actual Fn permission requirements; the support page no longer directs owners
to an obsolete release or treats every permission mismatch as a signing change.

Six pages at two viewport sizes passed local browser checks for navigation,
horizontal overflow and automatic external requests. Checkout spacing was
visually reviewed after adjustment. The in-app browser had no available
backend; the preview used the installed Chrome binary with an isolated
temporary browser profile. No owner browser cookies were reused. The initial
default Playwright launch failed because its bundled browser was absent; that
attempt is not counted as a preview pass.

Claims, offer and privacy gates pass, together with their existing mutation
checks. The link gate now parses actual anchors, checks local page targets,
requires the Mac app's own checkout page and its purchase-service link, and
follows external redirects to their final result. Its real entrypoint rejects
missing/commented checkout and download controls and a 503 purchase service.
A local HTTP fixture confirms that a redirect ending in 404 remains a failure.
The Pages workflow includes these regression checks.

The live link preflight deliberately remains red:

- The intended v0.1.23 ZIP has not been published and returns 404.
- Production `/buy` returns 503 because new sales remain disabled.
- Production `/recover` returns 200.

The current public site and release have not been replaced by these prepared
pages. Existing Stripe checkout remains active; its staged new webhook and
receipt redirect have not been enabled. Do not bypass the link gate to deploy.

## Remaining release work

Resolve or characterize the AirPods transition with useful timestamp evidence;
the owner does not need to repeat the whole acceptance sequence. Verify support
forwarding and actual provider plan capacity. The observed Resend rate-limit
header permits ten requests per second, which does not establish the daily or
monthly email quota. Porkbun's published API overview mentions email forwarding,
but the retrieved OpenAPI paths did not expose its retrieval operation; DNS MX
records alone do not prove that `help@presstalk.app` reaches an inbox.

Then publish the reviewed app artifact, enable the new live webhook, configure
the existing Payment Link's receipt redirect, enable service sales, and deploy
the matching pages only after their actual links pass. Verify the public
purchase and licence path. The local 500,000-order queue measurement is not a
claim about 500,000 simultaneous buyers or the email provider's plan capacity.
