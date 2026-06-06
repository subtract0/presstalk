# Troubleshooting

## Permission Toggle Is On, But PressTalk Still Cannot Use It

This usually means the running process and the app entry in macOS Privacy
settings do not match closely enough for TCC.

Common causes:

- A stale manually opened PressTalk process is still holding the singleton lock.
- PressTalk was rebuilt after the permission was granted.
- macOS has granted the app, but the already-running process has not refreshed
  the TCC state yet.
- The local development build is ad-hoc signed, so macOS may treat a new build as
  a different privacy client even if the app name looks unchanged.

If macOS already shows PressTalk enabled, use `Restart PressTalk` in PressTalk
Settings first. Current builds do not reopen the setup window after the first
setup guide; the restart button is the intended way to refresh a running
process after permission changes.

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

If a toggle is already on but PressTalk still reports it unavailable after
restart, turn the toggle off and on again for the newly built `PressTalk.app`,
then rerun:

```bash
PRESSTALK_TRIGGER_KEY=fn bash scripts/install_jarvistap_launchd.sh
```

Current builds check all three permissions during setup instead of stopping at
Input Monitoring first. They also keep a quiet setup retry loop running while
blocked on permissions, but some TCC changes still require a fresh process
before macOS reports them through the preflight APIs.

If macOS keeps showing a stale enabled row, reset only PressTalk's TCC entries
and approve the current build again:

```bash
tccutil reset ListenEvent com.am.jarvistap
tccutil reset Microphone com.am.jarvistap
tccutil reset Accessibility com.am.jarvistap
PRESSTALK_TRIGGER_KEY=fn bash scripts/install_jarvistap_launchd.sh
```

Current bootstrap helpers try to stabilize local signing automatically. They
create or reuse a self-signed local development identity, re-sign
`PressTalk.app`, then start the LaunchAgent. Disable that behavior only for
debugging:

```bash
PRESSTALK_BOOTSTRAP_STABLE_SIGNING=0 PRESSTALK_TRIGGER_KEY=fn \
  /bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

For repeated local development builds from the source tree, prefer a stable
signing identity:

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
