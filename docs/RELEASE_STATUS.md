# Release Status

Current status: public prerelease smoke artifact published, full cross-machine
release not yet proven.

Public prerelease:

- Tag: `v0.1.5-rc27`
- Commit: `cf1131444a66475fd70e1ffe693b8eee051d41f6`
- URL: `https://github.com/subtract0/presstalk/releases/tag/v0.1.5-rc27`
- Asset: `PressTalk-0.1.5-rc27-macos-arm64.zip`
- SHA-256: `b8291aad43d3d7445274840e5606f9e3d0745de39bb960a1a3aa346f25f01ee6`

Verified on `studio1` on 2026-06-06:

- `swift build -c release` succeeds.
- `scripts/build_jarvistap.sh` produces `~/Applications/PressTalk.app`.
- The generated bundle declares microphone, input monitoring, and accessibility usage descriptions.
- `scripts/install_jarvistap_launchd.sh` writes and starts `com.am.jarvistap` with `PRESSTALK_TRIGGER_KEY=fn`.
- `v0.1.5-rc27` is published as a public prerelease smoke artifact, and GitHub
  reports the expected asset SHA-256 digest.
- The `v0.1.5-rc27` zip was inspected locally and contains the expected arm64
  `PressTalk.app`, permission usage descriptions, bundled bootstrap helper,
  bundled local-signing helper, bundled smoke-status collector, bundled manual
  Fn smoke helper, and bundled automated F5 smoke helper.
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
- `v0.1.5-rc21` passes `PRESSTALK_OPEN_PERMISSION_PANES` into the running app.
  With the default value `0`, current builds hide the Settings window's
  Microphone, Input Monitoring, and Accessibility buttons and suppress
  privacy-pane open calls, so no-pane smoke runs cannot accidentally reopen
  System Settings or suggest another approval pass.
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
  paste probe unless paste actually fails. Current builds record
  machine-readable `permissions.inputMonitoringStatus`,
  `permissions.microphoneStatus`, and `permissions.accessibilityStatus` strings
  so raw macOS preflight misses are visibly separate from effective runtime
  readiness.
- `v0.1.5-rc27` adds `permissions.microphoneAuthorizationStatus` to
  `runtime-status.json`, Settings, diagnostics export, and both smoke helpers.
  A blocked machine now distinguishes `authorized`, `denied`, `restricted`,
  `not_determined`, and `unknown` microphone preflight states without opening
  System Settings.
- `v0.1.5-rc27` also adds a read-only `TCC Rows` section to the bundled
  smoke-status collector. It reports `com.am.presstalk` and
  `com.am.jarvistap` rows for Microphone, Input Monitoring, and Accessibility
  from the user/system TCC databases when readable; it does not reset TCC or
  open privacy panes.
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
- `v0.1.5-rc20` and later improve `presstalk-manual-fn-smoke.swift`: the
  helper reads the configured runtime trigger key, labels Fn/Option/F5 or
  trackpad smoke correctly, and records readiness before and after the manual
  paste attempt.
- `v0.1.5-rc22` adds `presstalk-automated-f5-smoke.swift`, an explicit
  synthetic pipeline helper. It posts the F5 Darwin trigger bridge, speaks a
  local phrase through system audio, and records PressTalk trace evidence for
  transcription and paste command posting. Its JSON result sets
  `physicalTriggerProof=false`, includes `traceFinalTranscript` and
  `tracePasteCommandPosted`, and separately reports `targetCaptureSuccess` /
  `tracePasteCompleted`, so it helps isolate STT/paste failures but does not
  replace physical Fn or Option smoke.
- `studio1` local synthetic F5/Darwin/TTS smoke on 2026-06-06 succeeded at the
  trace pipeline level after a temporary no-pane F5 bootstrap. Result JSON:
  `success=true`, `reason=trace_pipeline_completed`,
  `physicalTriggerProof=false`, `tracePasteCompleted=true`,
  `traceFinalTranscript="Press Talg Automated Smoke Test."`,
  `targetCaptureSuccess=false`, with runtime readiness true at start and finish.
  The app was restored to `PRESSTALK_TRIGGER_KEY=fn` afterward and status
  consistency was clean.
- `v0.1.5-rc23` paste work changes insertion to pasteboard plus Cmd-V
  instead of per-code-unit Unicode key events, delays pasteboard restore to 1.0s,
  and changes trace wording from `Dictation paste completed` to
  `Dictation paste command posted`. The revised synthetic helper now separates
  `tracePasteCommandPosted` from `tracePasteCompleted`.
- `v0.1.5-rc24` settings/status work suppresses automatic setup
  window presentation when `PRESSTALK_OPEN_PERMISSION_PANES=0`, makes Run Setup
  Check refresh status without reopening the Settings window, hides privacy-pane
  buttons in no-pane mode, and removes `missing` / `refresh macOS permissions`
  wording from diagnostics. After packaging rc24, `studio1` was restored to the
  legacy `com.am.jarvistap` no-pane path; runtime status reports
  `permissionPaneOpeningAllowed=false`, `setupRetryActive=false`,
  `inputMonitoringStatus=listener_ready_preflight_unavailable`,
  `microphoneStatus=preflight_granted`,
  `accessibilityStatus=paste_probe_pending`, and
  `status.triggerPath=Fn / Globe ready`.
- `v0.1.5-rc25` adds a paste-event self-test to the automated F5 smoke helper.
  Before synthetic dictation, the helper tries focused-window Cmd-V insertion
  across several CGEvent source/tap combinations and records `pasteSelfTest`
  plus `targetCaptureFailureHint`. This separates STT/trigger success from a
  local paste-event synthesis blocker.
- `v0.1.5-rc26` changes production insertion behavior. If Accessibility is
  trusted, PressTalk first tries direct AX insertion into the focused text
  element, then falls back to pasteboard plus Cmd-V. If Accessibility is not
  trusted, PressTalk copies the transcript to the clipboard and records
  `dictation_copy_fallback` instead of posting a Cmd-V command that cannot land.
  Runtime status reports `accessibilityStatus=copy_fallback_accessibility_untrusted`
  in that state.
- `studio1` local post-rc22 synthetic F5/Darwin/TTS smoke with the revised
  helper and paste path reported `success=true`,
  `reason=trace_pipeline_command_posted`,
  `traceFinalTranscript="Press Teig Automated Smoke Test."`,
  `tracePasteCommandPosted=true`, `tracePasteCompleted=false`, and
  `targetCaptureSuccess=false`. Runtime readiness was true, and the app was
  restored to Fn with clean status consistency. This shows STT and paste-command
  posting work, but target-field insertion remains unproven while
  `accessibilityGranted=false`.
- `studio1`: a no-pane rc21-equivalent local install from commit
  `f92daebee990f7d45d66cb577cce05e250894d4b` was bootstrapped with
  `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status reports `microphoneGranted=true`,
  `inputMonitoringEffective=true`, `permissionPaneOpeningAllowed=false`,
  `inputListener=hid:listen_only`, `inputPipelineReady=true`,
  `setupRetryActive=false`, `status.triggerPath=Fn / Globe ready`, and
  `status.speechModel=Ready`. `Status Consistency` reports matching live
  process ID, bundle identifier `com.am.jarvistap`, and CDHash
  `66f3283b9e152b633bb4102603d3c6f9bd61699e`.

Known current proof gaps:

- `studio1` no longer has a listener/probe setup blocker after the listen-only
  event-tap fix. The remaining `studio1` proof gap is a physical Fn hold
  dictation and paste smoke; a synthetic Fn event was not counted as proof.
- `studio2`: `v0.1.5-rc27` was downloaded from GitHub with SHA-256
  `b8291aad43d3d7445274840e5606f9e3d0745de39bb960a1a3aa346f25f01ee6` and
  bootstrapped with `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, `PRESSTALK_TRIGGER_KEY=fn`, and
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING=0`. LaunchAgent starts and
  `permissionPaneOpeningAllowed=false`, but runtime is blocked before dictation
  because `microphoneGranted=false`,
  `microphoneAuthorizationStatus=not_determined`,
  `microphoneStatus=preflight_not_determined`,
  `inputMonitoringEffective=false`,
  `inputMonitoringStatus=preflight_unavailable`,
  `inputListener=not_installed`, `inputPipelineReady=false`, and
  `setupRetryActive=true`. The rc27 read-only TCC audit reports no user TCC rows
  for `com.am.presstalk` or `com.am.jarvistap`; system TCC only contains a
  denied Accessibility row for `com.am.presstalk`. This is a first-grant/setup
  gap, not an already-granted false-missing state. `Status Consistency` reports
  matching live process ID, bundle identifier `com.am.presstalk`, and CDHash
  `52db8c8f5ad0bbd735881c7a65d7d8003aef2d89`.
- `mbp1`: `v0.1.5-rc27` was downloaded from GitHub with SHA-256
  `b8291aad43d3d7445274840e5606f9e3d0745de39bb960a1a3aa346f25f01ee6` and
  bootstrapped with `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING=0`. The installed app is ad-hoc signed
  with bundle identifier `com.am.presstalk` and CDHash
  `e621fe76aa15b0d838b05bf53caf45c2b7935fdc` after the final restored Fn
  bootstrap.
- `mbp1` no longer has the rc15 microphone/listener blocker. Runtime status
  after rc27 reports `microphoneGranted=true`,
  `microphoneAuthorizationStatus=authorized`,
  `microphoneStatus=preflight_granted`, `inputMonitoringEffective=true`,
  `inputMonitoringStatus=listener_ready_preflight_unavailable`,
  `accessibilityStatus=copy_fallback_accessibility_untrusted`,
  `permissionPaneOpeningAllowed=false`, `inputListener=hid:listen_only`,
  `inputPipelineReady=true`, `setupRetryActive=false`,
  `status.triggerPath=Fn / Globe ready`, and `status.speechModel=Ready`.
  `Status Consistency` reports matching live process ID, bundle identifier, and
  CDHash.
- `mbp1` rc27 TCC audit explains the apparent settings mismatch: Microphone
  rows exist for both `com.am.presstalk` and `com.am.jarvistap`; Input
  Monitoring rows exist for both identities in system TCC; Accessibility has an
  allowed row for stale `com.am.jarvistap` but a denied row for
  `com.am.presstalk`. A no-pane rc27 bootstrap under `com.am.jarvistap` did not
  satisfy the old row's code requirement and regressed to
  `microphoneAuthorizationStatus=not_determined`, `inputPipelineReady=false`,
  and `accessibilityGranted=false`, so mbp1 was restored to the working
  `com.am.presstalk` Fn path.
- `mbp1` rc24 synthetic F5/Darwin/TTS smoke succeeded at the trace pipeline
  level after a temporary no-pane F5 bootstrap, then the app was restored to Fn.
  Result JSON:
  `success=true`, `reason=trace_pipeline_command_posted`,
  `physicalTriggerProof=false`, `tracePasteCommandPosted=true`,
  `tracePasteCompleted=false`,
  `traceFinalTranscript="Press-Teil-Automated-Smoke-Test"`,
  `targetCaptureSuccess=false`, with runtime readiness true at start and finish.
  Final restored Fn status was ready.
- `mbp1` rc25 synthetic F5/Darwin/TTS smoke with paste self-test succeeded at
  the trace pipeline level after a temporary no-pane F5 bootstrap, then the app
  was restored to Fn. Result JSON: `success=true`,
  `reason=trace_pipeline_command_posted`, `physicalTriggerProof=false`,
  `tracePasteCommandPosted=true`, `tracePasteCompleted=false`,
  `targetCaptureSuccess=false`, `pasteSelfTest.success=false`, and
  `targetCaptureFailureHint=local_cmd_v_event_synthesis_unavailable`.
  `Status Consistency` reports matching live process ID, bundle identifier, and
  CDHash after the restored Fn restart. Read-only TCC inspection on mbp1 shows
  microphone rows for `com.am.presstalk` and `com.am.jarvistap`, but no
  Accessibility row for PressTalk, matching the paste self-test result.
- `mbp1` rc26 synthetic F5/Darwin/TTS smoke succeeded at the trace pipeline
  level after a temporary no-pane F5 bootstrap, then the app was restored to Fn.
  Result JSON: `success=true`, `reason=trace_pipeline_copy_fallback`,
  `physicalTriggerProof=false`, `traceCopyFallback=true`,
  `tracePasteCommandPosted=false`, `tracePasteCompleted=false`,
  `targetCaptureSuccess=false`, and
  `targetCaptureFailureHint=accessibility_untrusted_copy_fallback`. This proves
  the app no longer posts a fake paste command on mbp1 when Accessibility is not
  trusted; active-field paste remains unproven until Accessibility trust exists.
- `mbp1` rc27 synthetic F5/Darwin/TTS smoke succeeded at the trace pipeline
  level after a temporary no-pane F5 bootstrap, then the app was restored to Fn.
  Result JSON:
  `~/Library/Application Support/JarvisTap/Diagnostics/automated-f5-smoke-2026-06-06T19-32-00.323Z.json`
  reported `success=true`, `reason=trace_pipeline_copy_fallback`,
  `physicalTriggerProof=false`, `microphoneAuthorizationStatus=authorized`,
  `traceCopyFallback=true`, `tracePasteCommandPosted=false`,
  `tracePasteCompleted=false`,
  `traceFinalTranscript="Press-Tag Automated Smoke Test"`,
  `targetCaptureSuccess=false`, and
  `targetCaptureFailureHint=accessibility_untrusted_copy_fallback`. Final
  restored status was `triggerKey=fn`, `triggerPath=Fn / Globe ready`, and
  `speechModel=Ready`.
- `v0.1.5-rc27` includes the listen-only event-tap fallback, WhisperKit cache
  layout/tokenizer prefetch fixes, no-automatic-prompt/no-auto-settings window
  fixes, settings status fixes for already-granted permission toggles, the mbp1
  launchd disabled-label/provenance fix, the `com.am.presstalk` bundle
  identifier fix, the no-ANE WhisperKit compute preset,
  `PRESSTALK_BUNDLE_IDENTIFIER` for legacy identity fallback, the smoke-status
  consistency checker, app-level no-pane enforcement, and
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
