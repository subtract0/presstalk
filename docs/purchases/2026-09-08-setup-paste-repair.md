# Setup paste repair — 2026-09-08

Installed build 23.2 could recognise speech while leaving its own setup practice
field empty. PressTalk had no application Edit menu, so posting Command-V did not
invoke the text responder's paste action. The capture and permission checks were
not the cause of this report.

## Reproduction and repair

A native Accessibility/CGEvent probe focused the actual installed setup field,
staged a known marker while preserving the owner's clipboard, and sent Command-V.
The field remained empty: zero characters before and after. The app's trace also
showed paste commands posted to its own process. This reproduced the customer
failure; a posted command was not evidence of insertion.

The app now installs the standard Edit commands (Undo, Redo, Cut, Copy, Paste and
Select All) using the normal responder chain. This covers the practice field and
other native text fields. No special assignment of recognised text to the practice
box was added, and microphone routing, recognition and licence enforcement were
unchanged.

The previous fixture assigned `.string` directly and therefore missed keyboard
routing. It now runs the actual app UI installation in an AppKit event loop,
focuses the practice field and delivers the complete sentence through the actual
Command-V menu equivalent. The window must contain the complete text before the
guide can finish. Removing the production menu-installation call makes this
behavioral assertion fail. The other four disconnected-call cases still fail at
their intended assertions. These tests now run serially because native focus and
the clipboard are shared resources. Asynchronous microphone fixtures use bounded
condition waits instead of assuming callbacks finish within 30 milliseconds.

## Installed artifact and evidence

- All 226 Swift tests, setup controls, five removed-call cases and capture source
  invariants pass. Seven release-finisher integrity tests also pass.
- The normal distribution build produced 0.1.23 / 23.3 with developer helpers
  excluded. Its Info.plist differs from installed 23.2 only in the build number.
- Apple accepted submission `75761123-dd3e-4601-ac48-1d09d7e447ca`. Secure
  timestamps, Developer ID, microphone entitlement, stapled ticket, Gatekeeper and
  the complete notarization-readiness audit pass. Signing works in the current
  session; the earlier signing/session restriction no longer blocks this build.
- Installed at `~/Applications/PressTalk.app` at 20:51:47 UTC. The prior 23.2 app
  is preserved under `~/Library/Application Support/PressTalk Install Backups/`.
  The licence fingerprint is unchanged and both microphone and Accessibility
  grants remain present. The local speech model reports Ready.
- Signed executable SHA-256:
  `e452f7e4600cafea275e6cfbf2713f4d4c0b225c546a9563cbc93e3ea70ddd12`.
  Stapled ZIP SHA-256:
  `ff64513a91916f9a13e2ef46d63e869afd3c0fcbecdb958643bacc1cbb07008e`.
- The owner subsequently reported that it works. The actual app logged
  `First-run setup completed` at 20:54:13 UTC, after installation. An attempted
  automated positive probe encountered the closed guide, and a later attempt
  found existing user text and stopped without replacing it. Those attempts are
  not counted as successful automated installed-keyboard tests. The successful
  keyboard regression is the compiled actual-app UI test described above.

Private logs, manifest, signed app, ZIP and installation receipt are under
`.local/commerce/setup-paste-repair/`. Downloads contains the updated
`Install PressTalk Release Candidate.command`, `Test PressTalk Offline.command`
and `PressTalk Release Test.html`. Old 23.1/23.2 installers were preserved in
`~/Downloads/PressTalk Previous Setup/` to prevent accidental rollback.

Public 0.1.22 is unchanged. The subsequent [owner offline dictation test](2026-09-09-owner-offline-dictation.md)
confirmed live offline insertion through the Shure and AirPods, while exposing
one interrupted AirPods attempt. That interruption and production purchase
service/publication remain open; the later observation supersedes the earlier
pending offline-test status.
