# Release Status

Current status: public prerelease smoke artifact published, full cross-machine
release not yet proven.

Public prerelease:

- Tag: `v0.1.5-rc35`
- Commit: `af8b562f5414122cdaafa5f3a05d6a4ef008fe5b`
- URL: `https://github.com/subtract0/presstalk/releases/tag/v0.1.5-rc35`
- Asset: `PressTalk-0.1.5-rc35-macos-arm64.zip`
- SHA-256: `808ae31787962ea335deae80b45500340e018b30c81ece9337b3234b852629f8`

Verified on `studio1` on 2026-06-06:

- `swift build -c release` succeeds.
- `scripts/build_jarvistap.sh` produces `~/Applications/PressTalk.app`.
- The generated bundle declares microphone, input monitoring, and accessibility usage descriptions.
- `scripts/install_jarvistap_launchd.sh` writes and starts `com.am.jarvistap` with `PRESSTALK_TRIGGER_KEY=fn`.
- `v0.1.5-rc31` is published as a public prerelease smoke artifact, and GitHub
  reports the expected asset SHA-256 digest.
- The `v0.1.5-rc31` zip was inspected locally and contains the expected arm64
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
- Current startup code stops force-presenting the PressTalk Settings window
  after successful startup. Automatic setup presentation requires both
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=1` and
  `PRESSTALK_OPEN_PERMISSION_PANES=1`; no-pane installs stay quiet even when
  setup checks are running.
- Current bootstrap runs launch PressTalk through LaunchServices via
  `/usr/bin/open -gjW` so macOS privacy identity is app-bundle based, and it no
  longer opens System Settings panes automatically.
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
- `v0.1.5-rc28` adds decoded TCC code requirements to the same collector and
  prints the running app's designated requirement. This makes stale grants tied
  to an old certificate root or CDHash visible without opening System Settings.
- `v0.1.5-rc29` closes the remaining success-path setup-window regression:
  a machine with working microphone/listener runtime proof is not sent back to
  the PressTalk Settings permission UI just because this is the first launch.
- `v0.1.5-rc30` upgrades the bundled manual physical-trigger smoke helper to
  record `traceFinalTranscript`, `traceInserted`, `traceCopyFallback`,
  `targetCaptureSuccess`, and `targetCaptureFailureHint`. This separates
  physical trigger/STT proof from active-field insertion proof.
- `v0.1.5-rc31` adds an opt-in InputMethodKit insertion prototype. The release
  bundle contains `PressTalkInputMethod.app`,
  `presstalk-install-input-method.sh`, and
  `presstalk-input-method-insert-probe.sh`. The prototype is not installed or
  selected automatically, and it does not open System Settings. It is a concrete
  experiment for proving whether a selected PressTalk input method can insert
  text into the active client without Accessibility trust.
- `v0.1.5-rc32` removes bootstrap's automatic System Settings open path. Even
  if `PRESSTALK_OPEN_PERMISSION_PANES=1` is present, bootstrap prints a warning
  instead of opening Microphone, Input Monitoring, or Accessibility panes.
  Startup setup-window presentation now requires both
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=1` and
  `PRESSTALK_OPEN_PERMISSION_PANES=1`; no-pane local restores use
  `PRESSTALK_OPEN_PERMISSION_PANES=0` and
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`.
- `v0.1.5-rc32` adds `presstalk-input-method-status.swift` to the release
  bundle. The helper is read-only by default and reports current input source,
  installed bundle state, all-installed recognition, enabled recognition, and
  explicit `--register`, `--enable`, and `--select` statuses.
- On `studio1`, the rc32 local restore was rebuilt as `com.am.jarvistap`,
  re-signed by `Authority=PressTalk Local Development Code Signing`, and
  restarted with no-pane flags. Runtime status after restart:
  `permissionPaneOpeningAllowed=false`, `setupRetryActive=false`,
  `microphoneAuthorizationStatus=authorized`, `microphoneGranted=true`,
  `inputMonitoringEffective=true`, `inputListener=hid:listen_only`,
  `inputPipelineReady=true`, `status.speechModel=Ready`, and
  `status.triggerPath=Fn / Globe ready`.
- On `studio1`, the installed `PressTalkInputMethod.app` is recognized by TIS
  as `TISTypeKeyboardInputMethodWithoutModes` in
  `TISCategoryKeyboardInputSource`, with `recognizedAllSourceCount=1` and
  `recognizedEnabledSourceCount=0`. It was not enabled or selected during this
  verification; the current input source remained `com.apple.keylayout.German`.
- The `v0.1.5-rc32` GitHub release asset digest is
  `sha256:ed7d0ac9274253982d1dbc790e28b93b28d0d1c150e8aa51ba89fa932be29537`,
  and the remote tag was corrected to point at
  `b08f648b8535207a0a105593e2e9ff330b787016` after publish.
- `v0.1.5-rc33` adds `presstalk-input-method-client-probe.swift` to the
  release bundle. The probe performs the reversible end-to-end IMK test:
  register, temporarily enable/select the PressTalk input method, focus a local
  `NSTextView`, post the insert payload, check whether text appears, write JSON
  diagnostics, and restore the original input source.
- `v0.1.5-rc33` fixes the input-method server startup path by replacing the
  delegate-as-`@main` pattern with an explicit `NSApplication.shared` run loop.
  A manual background launch of the installed input-method app now writes
  `app launched` and `insert notification observer installed` to
  `~/Library/Logs/presstalk_input_method.log`.
- `v0.1.5-rc33` also hardens the generated input-method bundle metadata:
  `CFBundleSupportedPlatforms`, `CFBundleSignature`,
  `NSSupportsSuddenTermination`, `TISIconIsTemplate`, a visible
  `ComponentInputModeDict`, and exported `PressTalkIMController` ObjC class.
  The installer attempts to clear quarantine/provenance metadata from the copied
  `~/Library/Input Methods/PressTalkInputMethod.app`.
- Current `studio1` rc33 evidence: the bundled client probe from
  `~/Applications/PressTalk.app` fails cleanly with
  `success=false`, `reason=input_method_not_selectable`, `registerStatus=0`,
  `recognizedSourceCount=0`, `observedText=""`, and final input source restored
  to `com.apple.keylayout.German`. This means active-field insertion through
  IMK is still not proven; current TIS state does not expose the PressTalk input
  method as an enable/select-capable source.
- After publishing `v0.1.5-rc33`, `studio1` was restored to the legacy working
  privacy identity with `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status after restore: `permissionPaneOpeningAllowed=false`,
  `setupRetryActive=false`, `microphoneAuthorizationStatus=authorized`,
  `microphoneGranted=true`, `inputMonitoringEffective=true`,
  `inputListener=hid:listen_only`, `inputPipelineReady=true`,
  `status.speechModel=Ready`, and `status.triggerPath=Fn / Globe ready`.
- The `v0.1.5-rc33` GitHub release asset digest is
  `sha256:462256f9b9d775b548aec2334ac7f087b874ff62767e48aa775cd7bce8d86e40`,
  and the remote tag points at
  `37dbb045e44142daa46c5045805f1dc1a3686918`.
- Post-rc33 local debugging reproduced the settings-loop root cause on
  `studio1`: running `scripts/build_jarvistap.sh` without an explicit bundle id
  rebuilt the installed app as `com.am.presstalk`. The no-pane launch then
  reported `microphoneAuthorizationStatus=not_determined`,
  `microphoneGranted=false`, `inputMonitoringEffective=false`,
  `inputListener=not_installed`, and `setupRetryActive=true`, even though the
  same machine's working privacy grants are under `com.am.jarvistap`. This was
  an identity mismatch, not evidence that the user had skipped permissions.
- Post-rc33 local fix: `scripts/build_jarvistap.sh` now preserves the currently
  installed `PressTalk.app` bundle identifier by default and creates or reuses
  the stable local development code-signing identity unless
  `PRESSTALK_BUILD_STABLE_SIGNING=0` is explicitly set, while
  `scripts/package_presstalk_release.sh` explicitly forces the public
  `com.am.presstalk` identity and disables local signing for release artifacts.
  This keeps local rebuilds from silently switching a working development
  install into a different macOS privacy client or a new ad-hoc CDHash.
- Runtime status and Settings now expose `status.codeSignatureIdentifier`,
  `status.codeSignatureCDHash`, and `status.codeSignatureAuthority`; the
  no-pane Settings hint names the exact bundle id/CDHash being checked and says
  that the run will not open System Settings.
- The release bundle now includes `presstalk-unicode-event-insert-probe.swift`.
  On `studio1`, the original probe posted Unicode CGEvents into a focused local
  `NSTextView` while `AXIsProcessTrusted=false`, but observed no inserted text.
  Post-rc35 local debugging expanded the same probe to test HID, session,
  annotated-session, and PID-targeted posting. Result JSON
  `unicode-event-insert-probe-2026-06-06T21-54-53-225Z.json` reports
  `success=false`, `reason=timeout_waiting_for_payload`, `observedText=""`,
  and all four `methodResults` have `postResult=posted` with `success=false`.
  This rules out these CGEvent routes as reliable no-Accessibility insertion
  fallbacks on this machine.
- After the local identity regression was reproduced, `studio1` was restored
  with `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status after restore: `bundleIdentifier=com.am.jarvistap`,
  `codeSignatureAuthority=PressTalk Local Development Code Signing`,
  `microphoneAuthorizationStatus=authorized`, `microphoneGranted=true`,
  `inputMonitoringEffective=true`, `inputListener=hid:listen_only`,
  `inputPipelineReady=true`, `setupRetryActive=false`,
  `status.speechModel=Ready`, and `status.triggerPath=Fn / Globe ready`.
- Post-rc34 local debugging tightened the bundled InputMethodKit prototype:
  generated metadata now includes a separate visible input mode id,
  background-only IMK metadata, a bundled TIFF icon, and a character repertoire;
  the input-method bundle signs with the same
  `PressTalk Local Development Code Signing` identity by default. Verification
  still shows `TISRegisterInputSource=0` but `recognizedSourceCount=0`, even
  after LaunchServices registration and a TextInputMenuAgent restart. The
  exported `PressTalkIMController` Objective-C class and on-disk code signature
  both verify. Treat the remaining IMK failure as a macOS input-source
  discovery/trust blocker, not as missing Microphone, Input Monitoring, or
  Accessibility permissions.
- Post-rc35 local debugging made the generated input-method bundle more
  Apple-like by removing `LSBackgroundOnly`, using string-valued `LSUIElement`,
  adding `CFBundleIconFile`, and making the build-script `--install` path
  attempt quarantine/provenance cleanup. Rebuild/install/register still reports
  `TISRegisterInputSource=0` and `recognizedSourceCount=0`, so these metadata
  changes are not sufficient to solve TIS discovery on `studio1`.
- A skipped macOS signing/trust password prompt can explain earlier unstable
  local identity behavior: builds may still receive a code signature, but a
  self-signed development identity is not a production Gatekeeper approval. Do
  not reopen privacy panes repeatedly in this state; inspect the bundle id,
  CDHash, and signing authority first.
- `v0.1.5-rc35` updates the bundled automated F5 smoke helper to classify
  near-silent TTS captures as an audio-routing failure instead of a generic STT
  timeout. If `/usr/bin/say` playback goes only to AirPods or other headphones,
  helper JSON reports `reason=tts_audio_not_captured_by_microphone`,
  `targetCaptureFailureHint=tts_output_not_heard_by_microphone`, and
  `traceAudioCapture` RMS/peak evidence.
- After publishing `v0.1.5-rc35`, `studio1` was restored to
  `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status after restore: `bundleIdentifier=com.am.jarvistap`,
  `codeSignatureAuthority=PressTalk Local Development Code Signing`,
  `microphoneAuthorizationStatus=authorized`, `microphoneGranted=true`,
  `inputMonitoringEffective=true`, `inputListener=hid:listen_only`,
  `inputPipelineReady=true`, `setupRetryActive=false`,
  `permissionPaneOpeningAllowed=false`, `status.speechModel=Ready`, and
  `status.triggerPath=Fn / Globe ready`.
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
- `studio1` rc27 synthetic F5/Darwin/TTS smoke succeeded at the trace pipeline
  level after a temporary no-pane F5 bootstrap, then the app was restored to Fn.
  Result JSON:
  `~/Library/Application Support/JarvisTap/Diagnostics/automated-f5-smoke-2026-06-06T19-36-28.582Z.json`
  reported `success=true`, `reason=trace_pipeline_copy_fallback`,
  `physicalTriggerProof=false`, `microphoneAuthorizationStatus=authorized`,
  `traceCopyFallback=true`, `tracePasteCommandPosted=false`,
  `tracePasteCompleted=false`,
  `traceFinalTranscript="Press type automated smoke test."`,
  `targetCaptureSuccess=false`, and
  `targetCaptureFailureHint=accessibility_untrusted_copy_fallback`. Final
  restored status was `triggerKey=fn`, `triggerPath=Fn / Globe ready`, and
  `speechModel=Ready`.
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
- `studio1`: after publishing `v0.1.5-rc31`, the local app was restored with
  `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status reports `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, `permissionPaneOpeningAllowed=false`,
  `inputListener=hid:listen_only`, `inputPipelineReady=true`,
  `setupRetryActive=false`, `status.triggerPath=Fn / Globe ready`, and
  `status.speechModel=Ready`. The local bundle includes
  `PressTalkInputMethod.app`, `presstalk-install-input-method.sh`, and
  `presstalk-input-method-insert-probe.sh`; the local installed manual smoke
  helper is schema `smokeVersion=3`.

Known current proof gaps:

- `studio1` no longer has a listener/probe setup blocker after the listen-only
  event-tap fix. The remaining `studio1` proof gap is a physical Fn hold
  dictation and paste smoke; a synthetic Fn event was not counted as proof.
- `studio2`: `v0.1.5-rc31` was downloaded from GitHub with SHA-256
  `38106cb2c2917348ab13332661e0b4463f55d56d39caef89a0cca04dfae2d553` and
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
  `setupRetryActive=true`. The current ad-hoc CDHash is
  `ce7df45396445744313871a15d7003ac652c1a68`. The installed manual smoke
  helper is schema `smokeVersion=3` with `targetCaptureSuccess` and
  `traceCopyFallback` fields, and the app bundle contains the input-method
  prototype plus installer/probe helpers. The rc28 read-only TCC audit
  reported no user TCC rows for `com.am.presstalk` or `com.am.jarvistap`;
  system TCC only contained a denied Accessibility row for `com.am.presstalk`
  with requirement `cdhash H"ede4ea701e897b06b9d7817353f228c192602161"`,
  while the rc28 app had designated requirement
  `cdhash H"3021d05388aae5e1a73d6dc9c02947e4e319a40b"`. This remains a
  first-grant/setup gap, not an already-granted false-missing state.
- `mbp1`: `v0.1.5-rc31` was downloaded from GitHub with SHA-256
  `38106cb2c2917348ab13332661e0b4463f55d56d39caef89a0cca04dfae2d553` and
  bootstrapped with `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING=0`. The installed app is ad-hoc signed
  with bundle identifier `com.am.presstalk` and CDHash
  `ce7df45396445744313871a15d7003ac652c1a68`. The installed manual smoke
  helper is schema `smokeVersion=3` with `targetCaptureSuccess` and
  `traceCopyFallback` fields, and the app bundle contains the input-method
  prototype plus installer/probe helpers.
- `mbp1` no longer has the rc15 microphone/listener blocker. Runtime status
  after rc31 reports `microphoneGranted=true`,
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
- The rc28 collector decoded the mbp1 requirements: the then-running
  `com.am.presstalk` app was ad-hoc signed with designated requirement
  `cdhash H"3021d05388aae5e1a73d6dc9c02947e4e319a40b"`. The stale allowed
  `com.am.jarvistap` Microphone/Input Monitoring/Accessibility rows require
  `identifier "com.am.jarvistap" and certificate root =
  H"f2671c00575e4d2f123bb3c28ab3e2461de33fb3"`, and that certificate/private
  signing identity was not found on mbp1, studio1, or studio2. A normal new
  local signing identity would not match those old grants.
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
- `v0.1.5-rc31` includes the listen-only event-tap fallback, WhisperKit cache
  layout/tokenizer prefetch fixes, no-automatic-prompt/no-auto-settings window
  fixes, settings status fixes for already-granted permission toggles, the mbp1
  launchd disabled-label/provenance fix, the `com.am.presstalk` bundle
  identifier fix, the no-ANE WhisperKit compute preset,
  `PRESSTALK_BUNDLE_IDENTIFIER` for legacy identity fallback, the smoke-status
  consistency checker, decoded TCC code-requirement diagnostics, app-level
  no-pane enforcement, and
  `presstalk-manual-fn-smoke.swift`, which opens a focused text window and
  records physical Fn dictation smoke results as JSON. It also includes the
  rc29 success-path setup-window fix, the rc30 manual-smoke insertion evidence
  fields, and the rc31 opt-in InputMethodKit insertion prototype. It is the
  artifact to use for the next cross-machine smoke attempts.
- Local SSH aliases `s1` and `s2` are still not configured on `studio1`.
  Direct SSH to `s1` / `s2` does not resolve from this host, and mDNS/DNS lookup
  only resolves `studio1` and `studio2`. `studio2` is reachable as `studio2` or
  `studio2-tb`; `mbp1` is reachable via `mbp1-tb`.
- Karabiner-Elements is installed on `studio1`, but `karabiner_cli` only exposes
  profile/device/variable management. It does not provide a direct command to
  emit a virtual Cmd-V paste event, so it is not currently a no-Accessibility
  fallback for active-field insertion.

Do not claim full release coverage until these are recorded:

- `studio1`: physical Fn dictation and paste smoke.
- `s1`: install plus Fn dictation smoke.
- `s2`/`studio2`: first-time grants, then Fn dictation smoke.
- `mbp1`: M1 Max physical Fn or Option dictation and paste smoke.
