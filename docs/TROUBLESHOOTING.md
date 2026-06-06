# Troubleshooting

## Permission Toggle Is On, But PressTalk Still Cannot Use It

This means the macOS Privacy UI state and PressTalk's runtime capability probe
are disagreeing. Treat it as a PressTalk listener/probe bug first, not as a user
approval mistake.

Common causes:

- A stale manually opened PressTalk process is still holding the singleton lock.
- PressTalk was rebuilt after the permission was granted.
- macOS has granted the app, but the runtime preflight or event-tap probe still
  cannot observe that grant.
- The local development build is ad-hoc signed, so macOS may treat a new build as
  a different privacy client even if the app name looks unchanged.

If macOS already shows PressTalk enabled, do not repeatedly reopen Privacy
panes, toggle approvals, or reset TCC as the default response. First collect the
read-only status:

```bash
bash scripts/presstalk_collect_smoke_status.sh
```

Current builds keep the setup retry loop quiet. They do not auto-open System
Settings panes, do not auto-show the PressTalk Settings window unless
`PRESSTALK_AUTO_SHOW_SETUP_WINDOW=1` is set, and do not call macOS
permission-request APIs during startup/setup.

For `Fn`, `Option`, and `trackpad_hold`, current builds try listen-only HID and
session event taps before falling back to writable taps. Check
`runtime.inputListener` in the collected status to see which path armed, for
example `hid:listen_only`, `session:listen_only`, `hid:default`, or `failed`.
If `permissions.inputMonitoringGranted=false` but
`permissions.inputMonitoringEffective=true`, the listener is armed and the
Settings window should show Input Monitoring as listener-ready, not missing.
Treat Accessibility false-preflight as a paste probe unless paste actually
fails.
If Microphone is unavailable even though macOS already shows PressTalk enabled,
check the app signature and TCC identity before re-granting. Ad-hoc builds can
change CDHash between releases, leaving old TCC rows that no longer match the
current binary.

On a machine where launchd reports `Bootstrap failed: 5: Input/output error`,
first check whether the label was disabled:

```bash
launchctl print-disabled "gui/$(id -u)" | grep com.am.jarvistap
launchctl enable "gui/$(id -u)/com.am.jarvistap"
```

Current bootstrap helpers do this automatically and also remove
`com.apple.quarantine` and `com.apple.provenance` xattrs from the installed app
bundle before launch.

If you are deliberately refreshing a development process after changing code,
restart the LaunchAgent without opening panes:

```bash
PRESSTALK_OPEN_PERMISSION_PANES=0 PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
  PRESSTALK_TRIGGER_KEY=fn bash scripts/install_jarvistap_launchd.sh
```

Only when intentionally preparing a fresh machine should bootstrap open the
privacy panes:

```bash
PRESSTALK_OPEN_PERMISSION_PANES=1 PRESSTALK_TRIGGER_KEY=fn \
  /bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

Use TCC reset only as an explicit last-resort debugging step, because it discards
the already-approved state:

```bash
tccutil reset ListenEvent com.am.jarvistap
tccutil reset Microphone com.am.jarvistap
tccutil reset Accessibility com.am.jarvistap
PRESSTALK_OPEN_PERMISSION_PANES=0 PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
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
