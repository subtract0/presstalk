# PressTalk 0.1.23 release review — 2026-09-08

Latest: corrected build **23.3 is notarized and installed**. A real keyboard-paste
failure in the setup field was subsequently reproduced and repaired; see
`2026-09-08-setup-paste-repair.md` for the current result and remaining limits.
The preparation history below describes the earlier 23.2 stage.

The owner requested a thorough native app review after completing the real
sandbox purchase. Installed 0.1.23 / 23.1 contains the valid downloaded commerce
licence. Public 0.1.22 remains unchanged while the corrected candidate is tested.

## Purchase evidence

- A real Stripe sandbox Checkout Session is complete and paid, with the private
  acceptance reference. It produced one D1 order and one purchase delivery.
- Resend reports the purchase receipt `delivered`. The downloaded licence has a
  valid Ed25519 signature and matches the licence stored on the owner's Mac.
- The actual native `PressTalkLicenseStore` and CryptoKit verifier accept that
  downloaded licence in isolated preferences, retain it in a new store instance,
  preserve it after an invalid import and allow dictation with an expired trial.
  Paid access never reads the counting trial anchor. This is a native-store test,
  not a claim that the full Mac app has restarted with networking denied.
- Stripe redelivered the actual completed event to the acceptance webhook. One
  order and one purchase delivery remained; the purchase send count stayed one.
- In the isolated acceptance Worker only, an intentionally invalid email key
  caused licence recovery to retain a pending delivery. The original working
  configuration was restored. The real retry endpoint attempted and sent one
  job; its provider status is `delivered`, with two attempts and one unchanged
  order. No live payment, production webhook or live checkout setting changed.
- Apple validated the `presstalk-notary` login-Keychain profile. The final changed
  binary still needs its own notarization submission and stapled ticket.

Private evidence: `.local/commerce/purchase-owner-acceptance-observation.json`,
`acceptance-after-stripe-replay.json`, `deployed-recovery-test.json`, and the
corresponding private provider/deployment receipts. No licence, email address,
session capability or secret belongs in public release notes.

## Native defects addressed

- **Setup actions:** Settings and menu setup checks now open the guided check.
  It requires a fresh dictation, rather than silently repeating startup work or
  accepting an old successful dictation as proof of today's check.
- **Shortcut test:** the menu previously launched a developer helper excluded
  from customer builds. Settings hid that action in those builds. Both now use
  the built-in practice field and the production capture/insertion path.
- **Microphone:** an asynchronous capture check shows its busy, failure and retry
  state. It cannot overlap a normal recording. The selected device's completed
  capture receipt supplies its identity; a different or denied microphone does
  not inherit that proof. No system default input is changed.
- **Permissions:** denied microphone access opens the appropriate Settings pane.
  Fn/modifier shortcuts cannot skip the Accessibility permission their writable
  event tap needs. A registered Option-Space shortcut retries registration instead
  of opening an irrelevant Input Monitoring pane. A later permission grant takes
  precedence over an earlier skip decision.
- **Model preparation:** the guide shows preparation in progress and an explicit
  retry after failure. It no longer repeats a fixed download-size claim or leaves
  an apparently active download button doing nothing while loading.
- **Dictation proof:** the practice field checks that a fresh recognised sentence
  arrives in full. An unchanged field or a truncated sentence cannot complete the
  check. It examines the insertion at the saved selection, so an older complete
  sentence cannot conceal a truncated new paste. Replacing selected text works.
  A person testing another app explicitly confirms the whole sentence.
  Posting a paste command by itself does not complete this guide.
- **Window behaviour:** closing the guide stops polling without saving success.
  Wrapped messages scroll within the window at its minimum width; progress counts
  legitimate skipped optional steps consistently. The first launch opens one
  guide instead of also placing Settings over it.
- **Licensing copy:** removed the obsolete Pro upgrade wording, show the licence
  in Settings, and hide the purchase button for an activated licence.

## Verification boundaries and corrections

The release check runner records command exit codes and explicit completion
markers in `.local/commerce/release-app-checks.json`. Tests include the real
AppKit controls, microphone preference persistence through inventory changes,
and the app's actual Settings/menu callback wiring. The wiring fixture changes
access control and replaces the top-level application loop for isolated
assertions; it does not load a model, request permissions or use the real trial
Keychain. It is not the installed production binary under external UI control.

The native interaction tests must also reject deliberate removal of the setup,
model, delivery-observation and confirmation calls. A successful process exit
without the final assertion marker is a failure. The first full-UI harness exited
before its assertions; that was caught, its success criterion was corrected, and
menu/window construction was separated from status-bar installation so the real
wiring can be exercised independently. The runner now completes its assertions.

An early diagnosis blamed stale warming state. Inspection and the actual app
presentation test showed that an existing guard already handles it. The real
setup defect was missing visible feedback; no additional warming workaround was
added. An initial ad-hoc signature probe omitted the licence envelope's key ID
and encoded payload; correcting that probe and verifying with CryptoKit confirmed
that the delivered licence was valid.

Offscreen images under `.local/commerce/ui-review/` render actual AppKit controls
with fixture states. They verify layout, not microphone speech or external app
insertion. Direct native computer control in this agent process still reports
Accessibility unavailable; the owner has been asked to enable Codex access.

Before publication: build and notarize the corrected candidate, verify its
artifact, exercise it on the Mac through setup and whole-sentence dictation
(including the AirPods transition), and complete a full-app offline relaunch.
Production hosting/webhook/redirect and website activation follow acceptance.

## Frozen candidate and remaining owner action

The optimized 0.1.23 / 23.2 build is prepared under
`.local/commerce/release-23.2/PressTalk.app`. Its unsigned executable SHA-256 is
`5be0c696584cb2659885a313967c16dcc5b09d6f0cccc8f3e2c64c3627d55e26`.
The complete 18-file inventory, permissions, metadata and signing inputs are
bound in `release-23.2-manifest.json`; the prepared artifact is not signed,
notarized, installed or published. The unchanged nested input-method app retains
its verified Developer ID signature and secure timestamp.

All nine original release check groups passed (226 Swift tests). After the final
practice-insertion repair, actual setup controls, app wiring, four disconnected
callback cases and capture source invariants passed again. A separate mutation
restoring the stale-text check is rejected specifically because an old complete
sentence conceals a truncated new insertion. The fixture also checks successful
replacement of selected text. The release finisher passes seven integrity and
process-detection tests, including changed code, extra code, symlinks, changed
signing inputs, incorrect version and ambiguous process-check failures.

`codesign --timestamp` fails in this agent session with "A timestamp was expected
but was not found." An explicit HTTP Apple endpoint gives the same result;
codesign rejects HTTPS timestamp URLs as unsupported. A valid RFC 3161 POST to
Apple's timestamp endpoint succeeds with status Granted. This establishes a
codesign-path failure here, not an Apple outage or a failed notarization login.
No timestamp requirement was weakened. System log inspection is sandbox-denied.

`~/Downloads/Finish PressTalk Release.command` pins the release helper and
manifest, checks the complete reviewed payload, copies it to an isolated signing
directory, signs with the existing Developer ID in the login Keychain, submits
that exact archive with `presstalk-notary`, requires Accepted, staples and verifies
the ticket, and requires Gatekeeper and the readiness script to pass. Only then
does it ask the owner to quit PressTalk and install, preserving a backup. A failed
process check stops installation; it cannot count a service error as no running
app. A saved receipt permits retrying installation without notarizing again.

The launcher syntax and its actual prepared-artifact verification pass using the
system Python interpreter. Owner execution has not yet been observed. Final
receipts will be in `.local/commerce/release-23.2-final/`; the signed binary hash
will differ from the unsigned build hash above. `PressTalk Release Test.html` in
Downloads gives the physical acceptance sequence. The updated offline launcher
requires the exact notarized, installed artifact and denies network access only
to that app process. Full-app offline dictation remains unverified.

Direct native control still reports Accessibility unavailable in this Codex
session. The owner has already been asked to enable Codex; no grant/reset or
system-input preference change was attempted. Installed 23.1 and public 0.1.22
remain unchanged.
