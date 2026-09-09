# First-customer onboarding feedback — 2026-09-09

The owner supplied a customer's screenshots and report: ZIP installation was
unfamiliar, Finder showed a generic icon, setup looked busy while it was waiting
for a microphone-test click, and the external keyboard's Fn key did not trigger
dictation. Choosing F5 worked. The customer reported successful German and
English dictation and fast text delivery. This is customer-reported evidence,
not an agent-run transcription accuracy measurement.

## Changes for 0.1.24/build 24.1

- Register and package the existing fn brand mark as a full-resolution ICNS.
  Both app build and DMG packaging verify that the registered image decodes.
- Provide a drag-to-Applications disk image with English/German instructions.
  The signed ZIP remains an alternate release asset.
- Put the current setup action before completed checks. Replace the static
  percentage bar with a completed-check count and explicit waiting instructions.
- Offer supported shortcut choices directly in setup, with a Fn fallback hint,
  and reflect the selected shortcut in the practice instructions. Reuse the
  existing settings/listener transition and reject changes during capture or
  processing. Listening and recognition have distinct visible states.
- Update both download languages and the support guide to match the installer
  and shortcut choice. Teach the real link gate to check DMG downloads too.

The app's capture, model selection, inference, licence and payment code are
unchanged. The accepted first-AirPods-attempt retry remains disclosed.

## Verification

The Swift suite passed all 227 tests. Actual AppKit control and application
wiring fixtures verify selection, persistence, busy exclusion, failure feedback,
waiting/listening/recognition states and full-sentence confirmation. All seven
removed-callback cases fail on behavioral assertions. The new selection
mutation initially produced invalid Swift; it was corrected to replace the
optional callback expression with `false`, and then failed the intended control
assertion. A compiler rejection is not counted as behavioral coverage.

Icon verification rejects wrong registration, absent files and corrupt image
data. Link-gate regression coverage accepts a reachable DMG and rejects its 404.
Claims, offer, privacy and their existing regression checks pass.

Actual light/dark setup windows were captured with macOS screencapture. The old
offscreen snapshot helper produced invisible light text on a white composite;
those images were rejected and the helper now captures the real window.

## NPU activity report remains open

The customer saw NPU activity in TMOG after text appeared, and explicitly noted
that its display might be delayed. Their screenshots do not establish process
attribution, duration or the sampling interval. Their machine's diagnostics
have not been obtained.

The shipping configuration defaults streaming transcription off. Its main
final-recognition call is awaited before insertion; the dictation delivery
branch then resets processing and returns. The owner's installed build's trace
confirms streaming disabled and processing-finished outcomes. An idle CPU
sample on this Mac was 0.0 percent; that is not an NPU measurement and cannot
rule out the customer's observation. No speculative inference/cancellation
change was made in response to the graph.

If reproduced, collect the app's diagnostics and a timed observation covering
one dictation plus at least 30 seconds after insertion, noting TMOG's sampling
interval and other active local-model apps. Correlate the capture/inference/
insertion timestamps with the activity before attributing it to PressTalk or
changing model lifetime.

Private build, native UI, browser, signature and notarization evidence is in
`.local/onboarding-24/`. Final publication and artifact verification follow.

## Published release

[PressTalk 0.1.24/build 24.1](https://github.com/subtract0/presstalk/releases/tag/v0.1.24)
is public and marked latest. Native app source is `c5026b2`; the release target
is `cf2f447be800114d699a4f54a244af2a89074cd4`. Both app and final installer
were accepted by Apple, stapled, and accepted by Gatekeeper.

- App notarization: `aadc3f0c-d617-4ed2-b4d5-4eb58971c02e`.
- Final DMG notarization: `863d10c6-4143-4a56-8415-4e45e1995122`.
- DMG: 5,777,402 bytes; SHA-256
  `f88c6618ffd69d4cfb9e354953a3757b1cb71bab3a71953e699cee6f1bea79e4`.
- ZIP: 4,977,336 bytes; SHA-256
  `b9711c7114e218a12485ebf3324af8d0b7836ce8357b40dd5c0bbca73771e39a`.

The first 400-pixel-tall installer window clipped its instructions when Finder
showed the owner's status/path bars. That unpublished layout was rejected.
The final 500-pixel window was mounted and visually checked with both bars
visible. Its Applications symlink points to `/Applications`, its app icon is
registered and decodable, and the copied app retains its valid signature. A
fresh public DMG download matches the final verified bytes. A copy is in Downloads.

[PR #2](https://github.com/subtract0/presstalk/pull/2) merged as
`400b4f8c7bc98b84f4efefc415ec8ee1c989b534`.
[Pages run 34349715590](https://github.com/subtract0/presstalk/actions/runs/34349715590)
passed all gates and deployed. All six live pages match source; four updated
live download-page previews pass. Production purchase health remains live with
sales enabled. No new charge was made and no payment configuration was changed.

The owner's currently running 0.1.23/build 23.4 was not replaced or restarted
as part of this feedback release. The release installer is available in
`~/Downloads/PressTalk-0.1.24-macos-arm64.dmg`.
