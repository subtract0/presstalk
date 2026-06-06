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
Settings panes, do not call macOS permission-request APIs during startup/setup,
and do not auto-show the PressTalk Settings window after successful startup.
Even when `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=1` is deliberately set for a
first-run guide, the window is only auto-shown for a real startup failure.
When launched with `PRESSTALK_OPEN_PERMISSION_PANES=0`, the Settings window's
Microphone, Input Monitoring, and Accessibility buttons are hidden too. This
keeps a no-pane diagnostic run from reopening System Settings or suggesting
another approval pass after the user has already confirmed the toggles.

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
current binary. Current PressTalk app bundles identify as `com.am.presstalk`;
`com.am.jarvistap` is retained as the legacy launchd/helper label.
Current builds write `permissions.microphoneAuthorizationStatus` into
`runtime-status.json`, so first distinguish `denied`, `not_determined`,
`restricted`, `authorized`, and `unknown` instead of treating every false
preflight as the same problem.

The bundled smoke-status collector also prints a read-only `TCC Rows` section
for `com.am.presstalk` and `com.am.jarvistap` across Microphone, Input
Monitoring, and Accessibility. Use that section to detect missing, stale, or
wrong-identity TCC rows without opening System Settings or resetting TCC.

If the TCC databases are not readable, run the bundled Accessibility identity
probe. It launches tiny background probes for `com.am.jarvistap` and
`com.am.presstalk` with the prompt flag disabled, then reports whether either
identity is already trusted for Accessibility:

```bash
"$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-accessibility-identity-probe.sh"
```

Some development machines have their existing working microphone/input grants
under the older `com.am.jarvistap` app identity. If a no-pane restart with
`com.am.presstalk` regresses a machine that was previously working, preserve the
legacy privacy identity instead of reopening settings:

```bash
PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap \
PRESSTALK_OPEN_PERMISSION_PANES=0 \
PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
PRESSTALK_TRIGGER_KEY=fn \
  "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

Use `com.am.presstalk` for new installs or machines where that identity already
works, such as the current mbp1 rc27 smoke path. Use `com.am.jarvistap` only as
a compatibility fallback for machines with older grants.

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

Only when intentionally preparing a fresh machine should the app's manual
privacy-pane buttons be enabled:

```bash
PRESSTALK_OPEN_PERMISSION_PANES=1 PRESSTALK_TRIGGER_KEY=fn \
  /bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

Bootstrap still will not open System Settings automatically; the flag only
allows the manual Settings buttons inside PressTalk.

Use TCC reset only as an explicit last-resort debugging step, because it discards
the already-approved state:

```bash
for bundle_id in com.am.presstalk com.am.jarvistap; do
  tccutil reset ListenEvent "$bundle_id"
  tccutil reset Microphone "$bundle_id"
  tccutil reset Accessibility "$bundle_id"
done
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

For repeated local development builds from the source tree, current builds
preserve both parts of the privacy identity by default: the build helper keeps
the currently installed bundle identifier and creates or reuses the local
development code-signing identity. A working `com.am.jarvistap` development
install should not silently rebuild as `com.am.presstalk` or as a new ad-hoc
CDHash.

```bash
bash scripts/create_presstalk_local_codesign_identity.sh
PRESSTALK_CODESIGN_IDENTITY="<hash printed by the setup script>" bash scripts/build_jarvistap.sh
PRESSTALK_TRIGGER_KEY=fn bash scripts/install_jarvistap_launchd.sh
```

If you need to force the local compatibility identity, make it explicit:

```bash
PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap \
PRESSTALK_CODESIGN_IDENTITY="<hash printed by the setup script>" \
  bash scripts/build_jarvistap.sh
PRESSTALK_OPEN_PERMISSION_PANES=0 PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
  PRESSTALK_TRIGGER_KEY=fn bash scripts/install_jarvistap_launchd.sh
```

If stable signing is disabled or the helper cannot prepare an identity, the
build script uses ad-hoc signing. That is fine for local smoke tests, but
privacy approvals may need to be refreshed after a rebuild.

To deliberately force an ad-hoc debug build:

```bash
PRESSTALK_BUILD_STABLE_SIGNING=0 bash scripts/build_jarvistap.sh
```

The local identity script creates a self-signed code-signing identity in
`~/Library/Keychains/presstalk-local-dev.keychain-db` and adds that keychain to
the user search list. It stores the keychain password locally under
`~/Library/Application Support/PressTalk/` with user-only permissions. This is
for development builds only; public release artifacts still need normal release
signing/notarization before they are treated as production-grade.

If macOS asks for a password while creating or trusting the local signing
identity and the prompt is cancelled, a build can still be signed but remain a
local self-signed development artifact. Do not respond by reopening permission
panes repeatedly. First inspect `runtime-status.json` and the app signature
fields (`codeSignatureIdentifier`, `codeSignatureCDHash`, and
`codeSignatureAuthority`) to confirm whether the bundle id or signing identity
changed.
