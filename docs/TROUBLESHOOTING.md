# Troubleshooting

## Permission Toggle Is On, But PressTalk Still Says Missing

This usually means the running process and the app entry in macOS Privacy
settings do not match closely enough for TCC.

Common causes:

- A stale manually opened PressTalk process is still holding the singleton lock.
- PressTalk was rebuilt after the permission was granted.
- The local development build is ad-hoc signed, so macOS may treat a new build as
  a different privacy client even if the app name looks unchanged.

First reset the running process:

```bash
PRESSTALK_TRIGGER_KEY=fn bash scripts/install_jarvistap_launchd.sh
```

Then open:

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
```

If a toggle is already on but PressTalk still reports it missing, turn the toggle
off and on again for the newly built `PressTalk.app`, then rerun:

```bash
PRESSTALK_TRIGGER_KEY=fn bash scripts/install_jarvistap_launchd.sh
```

If macOS keeps showing a stale enabled row, reset only PressTalk's TCC entries
and approve the current build again:

```bash
tccutil reset ListenEvent com.am.jarvistap
tccutil reset Microphone com.am.jarvistap
tccutil reset Accessibility com.am.jarvistap
PRESSTALK_TRIGGER_KEY=fn bash scripts/install_jarvistap_launchd.sh
```

For repeated local development builds, prefer a stable signing identity:

```bash
bash scripts/create_presstalk_local_codesign_identity.sh
PRESSTALK_CODESIGN_IDENTITY="<hash printed by the setup script>" bash scripts/build_jarvistap.sh
PRESSTALK_TRIGGER_KEY=fn bash scripts/install_jarvistap_launchd.sh
```

If no signing identity exists, the build script uses ad-hoc signing. That is fine
for local smoke tests, but privacy approvals may need to be refreshed after a
rebuild.

The local identity script creates a self-signed code-signing identity in
`~/Library/Keychains/presstalk-local-dev.keychain-db` and adds that keychain to
the user search list. It stores the keychain password locally under
`~/Library/Application Support/PressTalk/` with user-only permissions. This is
for development builds only; public release artifacts still need normal release
signing/notarization before they are treated as production-grade.
