# Troubleshooting

## Permission is enabled, but dictation or pasting is blocked

Open **Set Up PressTalk** from the PressTalk menu. Setup checks the running app's
actual permission and shortcut state. An enabled System Settings row can still
refer to an older copy with a different signing identity; the switch alone does
not prove the running copy can use the permission.

Use **Open System Settings** to approve PressTalk when needed. Returning from
System Settings rechecks access without showing another native permission
prompt. **Check access again** also performs that check. After returning, setup
may offer one restart of this exact app to refresh permission state. It waits
until dictation and processing have finished.

If access remains blocked, **Renew PressTalk Permission** explains what will
change and asks for confirmation. It clears only the official PressTalk app's
Accessibility approval, restarts the app, and guides you to approve it again.
It preserves microphone approval and every other app's permissions. macOS must
still receive your approval; PressTalk cannot grant itself access. Renewal is
attempted once per blocked episode, including failure, so it cannot become a
reset or prompt loop.

If macOS still refuses access, setup offers **Show PressTalk in Finder** to
identify the running copy and **Open System Settings** for the system approval.
On a managed Mac, an administrator may control the permission. Export diagnostics
from PressTalk Settings for support, including the app version, exact bundle
path, signature and permission state. Report whether recording, the trigger,
recognition, or insertion is the failing step.

Use the signed official release for daily dictation. Do not re-sign it, change
its bundle identifier, or run an old Jarvis/Tab signing repair on it. Current
build and bootstrap scripts reject those identity changes. If the installed
copy predates these safeguards, replace it with the official release and use
the native setup flow. Public releases do not include developer probe tools.

## Choosing the recognition processor

In Settings, select the available local recognition mode. The mode is a request
to the local runtime; a processor preference is not a hardware utilization
measurement. Diagnostics record the selected mode and active backend. Compare
both when investigating different behavior across Macs.

Live partial transcription and the optional Whisper quality fallback are off
by default in both Finder and legacy launcher paths. Existing explicit
configuration overrides remain effective. An unexpected GPU workload can come
from a different backend or an enabled fallback, so verify the active settings
before comparing hardware graphs.

## Development builds

```bash
bash scripts/build_jarvistap.sh
open "$HOME/Applications/PressTalk Dev.app"
```

The default development identity is `com.am.presstalk.dev`. Its settings,
runtime files, launch label and activation handlers are separate from the
released app. A local development signing certificate can keep the development
identity stable between rebuilds; it is never a repair for the official app.
Ad-hoc development builds can require fresh macOS permission after a rebuild.

To deliberately build without a local certificate:

```bash
PRESSTALK_BUILD_STABLE_SIGNING=0 bash scripts/build_jarvistap.sh
```

For an explicit development LaunchAgent:

```bash
PRESSTALK_APP_BUNDLE="$HOME/Applications/PressTalk Dev.app" \
  bash scripts/install_jarvistap_launchd.sh
```

The development installer targets the development app and its `.dev` label. It
does not stop the production app or replace its installed input method. Avoid
running both apps' dictation shortcuts simultaneously during a test.

The local-signing repair helper accepts only `.dev` apps and refuses Developer
ID signed bundles. Diagnostic scripts in this repository are developer tools;
do not direct customers to missing bundled scripts or global permission resets.
Historical JarvisTap and compatibility-identity instructions do not apply to
current releases.
