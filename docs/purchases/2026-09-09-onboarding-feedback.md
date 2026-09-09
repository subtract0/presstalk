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
`.local/onboarding-24/`. Publication and final artifact verification are recorded
below after they complete.
