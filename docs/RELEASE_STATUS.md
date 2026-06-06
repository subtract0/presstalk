# Release Status

Current status: public prerelease smoke artifact published, full cross-machine
release not yet proven.

Public prerelease:

- Tag: `v0.1.5-rc19`
- Commit: `d5152e28576abe29445bd00dcd2c04518961c8b1`
- URL: `https://github.com/subtract0/presstalk/releases/tag/v0.1.5-rc19`
- Asset: `PressTalk-0.1.5-rc19-macos-arm64.zip`
- SHA-256: `ff5e56ebb8fde1be69bcc36461534ab71edea21f728823625d6eb11d77103c98`

Verified on `studio1` on 2026-06-06:

- `swift build -c release` succeeds.
- `scripts/build_jarvistap.sh` produces `~/Applications/PressTalk.app`.
- The generated bundle declares microphone, input monitoring, and accessibility usage descriptions.
- `scripts/install_jarvistap_launchd.sh` writes and starts `com.am.jarvistap` with `PRESSTALK_TRIGGER_KEY=fn`.
- `v0.1.5-rc19` is published as a public prerelease smoke artifact, and GitHub
  reports the expected asset SHA-256 digest.
- The `v0.1.5-rc19` zip was inspected locally and contains the expected arm64
  `PressTalk.app`, permission usage descriptions, bundled bootstrap helper,
  bundled local-signing helper, bundled smoke-status collector, and bundled
  manual Fn smoke helper.
- A local development code-signing identity was created on `studio1`, and a
  local build now signs as `Authority=PressTalk Local Development Code Signing`
  instead of ad-hoc. The LaunchAgent was restarted against that stable-signed
  build with `PRESSTALK_TRIGGER_KEY=fn`.
- The bundled bootstrap path was tested on `studio1`: a normal ad-hoc build was
  re-signed by the app-bundled local-signing helper before launchd started it.
  The resulting app reports `Authority=PressTalk Local Development Code
  Signing`, and launchd is running it with `PRESSTALK_TRIGGER_KEY=fn`.
- While blocked on Input Monitoring, the local app now starts a quiet setup retry
  timer. Trace evidence on `studio1`: `Setup retry timer started
  interval_seconds=5.0`.
- Current builds write machine-readable runtime status to
  `~/Library/Application Support/JarvisTap/runtime-status.json`; the bundled
  `presstalk-collect-smoke-status.sh` helper collects that file together with
  app signature, launchd state, machine info, and trace tail for cross-machine
  proof.
- Current local builds do not auto-show the settings window by default. They add
  a `Restart PressTalk` settings action for refreshing the running process and
  run read-only preflights plus real listener capability probes during setup.
- Current bootstrap runs launch PressTalk through LaunchServices via
  `/usr/bin/open -gjW` so macOS privacy identity is app-bundle based, and they
  no longer open System Settings panes unless `PRESSTALK_OPEN_PERMISSION_PANES=1`
  is set.
- Current startup/setup checks no longer call macOS permission-request APIs
  automatically. They only preflight and attempt the real listener capability,
  so repeated restarts do not keep prompting for already-approved permissions.
- For `Fn`, `Option`, and `trackpad_hold`, current builds try listen-only HID
  and session event taps before falling back to writable taps. Runtime status
  records `runtime.inputListener` so smoke tests can distinguish
  `hid:listen_only`, `session:listen_only`, `hid:default`, and `failed`.
- Settings now distinguish read-only permission preflights from effective
  runtime capability. If the real listener is armed, Input Monitoring renders as
  listener-ready and `runtime-status.json` records
  `permissions.inputMonitoringEffective=true` instead of sending the user back
  through already-enabled macOS privacy toggles. Accessibility is treated as a
  paste probe unless paste actually fails. Microphone now reports as unavailable
  to the current build rather than claiming the user failed to grant it, which
  matters when ad-hoc code identity drift invalidates an older TCC row.
- Bootstrap now clears `com.apple.quarantine` and `com.apple.provenance` xattrs,
  explicitly re-enables `gui/$UID/com.am.jarvistap`, and does not silently treat
  a failed launchd bootstrap as success.
- On `studio1`, a no-pane/no-auto-window restart of the rc10-equivalent local
  build reports `runtime.inputListener=hid:listen_only`,
  `runtime.inputPipelineReady=true`, `status.speechModel=Ready`, and
  `status.triggerPath=Fn / Globe ready`. Trace evidence also shows the actual
  WhisperKit cache layout under `Models/models/...` and the local tokenizer
  folder under `Models/models/openai/whisper-large-v3`.
- After the rc6 publish path, the local app was re-bootstrapped and re-signed as
  `Authority=PressTalk Local Development Code Signing`; the collector reports
  LaunchAgent `program = /usr/bin/open`, `Open permission panes: 0`,
  `microphoneGranted=true`, `inputMonitoringGranted=false`,
  `accessibilityGranted=false`, and `setupRetryActive=true`.
- `v0.1.5-rc17` defaults WhisperKit to a no-Neural-Engine compute preset:
  `mel=cpuAndGPU`, `audioEncoder=cpuAndGPU`, `textDecoder=cpuAndGPU`, and
  `prefill=cpuOnly`. This avoids the mbp1/macOS 26.5 Core ML load path where
  isolated probes timed out for `TextDecoder` with `.cpuAndNeuralEngine` and
  `.all`, and for `AudioEncoder` with `.cpuAndNeuralEngine` and `.all`.
- `PRESSTALK_WHISPER_COMPUTE=default` is retained as an escape hatch for
  WhisperKit's upstream compute defaults when explicitly desired.
- `v0.1.5-rc18` adds `PRESSTALK_BUNDLE_IDENTIFIER` for the build/bootstrap
  path. The default app identity remains `com.am.presstalk`, but a machine with
  older working grants can preserve `com.am.jarvistap` without opening privacy
  panes.
- `v0.1.5-rc19` adds a `Status Consistency` section to the bundled smoke-status
  collector. It compares `runtime-status.json` with the live PressTalk process
  and installed app signature, so stale or mismatched diagnostics are visible.
- `studio1`: rc19 was downloaded from GitHub with SHA-256
  `ff5e56ebb8fde1be69bcc36461534ab71edea21f728823625d6eb11d77103c98`, then
  bootstrapped with `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status reports `microphoneGranted=true`,
  `inputMonitoringEffective=true`, `inputListener=hid:listen_only`,
  `inputPipelineReady=true`, `setupRetryActive=false`,
  `status.triggerPath=Fn / Globe ready`, and `status.speechModel=Ready`.
  `Status Consistency` reports matching live process ID, bundle identifier, and
  CDHash. Trace evidence shows `WhisperKit ready` at
  `2026-06-06T17:37:00Z`.

Known current blocker:

- `studio1` no longer has a listener/probe setup blocker after the listen-only
  event-tap fix. The remaining `studio1` proof gap is a physical Fn hold
  dictation and paste smoke; a synthetic Fn event was not counted as proof.
- `studio2`: rc19 was downloaded from GitHub with SHA-256
  `ff5e56ebb8fde1be69bcc36461534ab71edea21f728823625d6eb11d77103c98` and
  bootstrapped with `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, `PRESSTALK_TRIGGER_KEY=fn`, and
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING=0`. LaunchAgent starts, but runtime is
  blocked before dictation because `microphoneGranted=false`,
  `inputMonitoringEffective=false`, `inputListener=not_installed`,
  `inputPipelineReady=false`, and `setupRetryActive=true`. Read-only TCC
  inspection returned no `com.am.presstalk` or `com.am.jarvistap` rows on
  `studio2`, so this is a first-grant/setup gap rather than the
  already-granted-but-reported-missing bug. The rc19 `Status Consistency`
  section reports matching live process ID, bundle identifier, and CDHash, so
  the blocked status describes the current process.
- `mbp1`: `v0.1.5-rc19` was downloaded from GitHub with SHA-256
  `ff5e56ebb8fde1be69bcc36461534ab71edea21f728823625d6eb11d77103c98` and
  bootstrapped with `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, `PRESSTALK_TRIGGER_KEY=fn`, and
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING=0`. The installed app is ad-hoc signed
  with bundle identifier `com.am.presstalk` and CDHash
  `234a45356ce762d393f9e9564015fcc97cc9847f`.
- `mbp1` no longer has the rc15 microphone/listener blocker. Runtime status
  after rc19 reports `microphoneGranted=true`,
  `inputMonitoringEffective=true`, `inputListener=hid:listen_only`,
  `inputPipelineReady=true`, `setupRetryActive=false`,
  `status.triggerPath=Fn / Globe ready`, and `status.speechModel=Ready`.
  `Status Consistency` reports matching live process ID, bundle identifier, and
  CDHash. Trace evidence shows `WhisperKit ready` at
  `2026-06-06T17:37:47Z`.
- `v0.1.5-rc19` includes the listen-only event-tap fallback, WhisperKit cache
  layout/tokenizer prefetch fixes, no-automatic-prompt/no-auto-settings window
  fixes, settings status fixes for already-granted permission toggles, the mbp1
  launchd disabled-label/provenance fix, the `com.am.presstalk` bundle
  identifier fix, the no-ANE WhisperKit compute preset,
  `PRESSTALK_BUNDLE_IDENTIFIER` for legacy identity fallback, the smoke-status
  consistency checker, and
  `presstalk-manual-fn-smoke.swift`, which opens a focused text window and
  records physical Fn dictation smoke results as JSON. It is the artifact to use
  for the next cross-machine smoke attempts.
- Local SSH aliases `s1` and `s2` are still not configured on `studio1`.
  `studio2` is reachable as `studio2` or `studio2-tb`; `mbp1` is reachable via
  `mbp1-tb`.

Do not claim full release coverage until these are recorded:

- `studio1`: physical Fn dictation and paste smoke.
- `s1`: install plus Fn dictation smoke.
- `s2`/`studio2`: first-time grants, then Fn dictation smoke.
- `mbp1`: M1 Max physical Fn or Option dictation and paste smoke.
