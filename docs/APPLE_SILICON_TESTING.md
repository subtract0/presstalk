# Apple Silicon Test Checklist

Use this on another Apple Silicon Mac such as:

- M1 Max MacBook Pro
- M4 MacBook Air

## Goal

Verify that a fresh machine can install PressTalk with minimal thinking:

1. install
2. approve permissions if the machine has not already granted PressTalk
3. hold `Fn / Globe`
4. dictate

## Machine Readiness Preflight

Before installing or counting a machine in the release matrix, run the read-only
machine readiness helper. From the repo:

```bash
/bin/bash scripts/presstalk_machine_readiness.sh
```

On a remote Mac with SSH already working:

```bash
ssh <host> 'bash -s' < scripts/presstalk_machine_readiness.sh
```

After installing the app, the same helper is bundled at:

```bash
/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-machine-readiness.sh"
```

For machine-readable release evidence, write JSON and extract the proof fields
with `plutil`:

```bash
/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-machine-readiness.sh" \
  --json-output "$HOME/Desktop/presstalk-readiness.json"
plutil -extract eligibility.physicalSTTSmokeReady raw -o - "$HOME/Desktop/presstalk-readiness.json"
plutil -extract eligibility.activeFieldSmokeReady raw -o - "$HOME/Desktop/presstalk-readiness.json"
```

To collect a matrix that includes local readiness plus SSH host blockers, run:

```bash
/bin/bash scripts/presstalk_readiness_matrix.sh \
  --local --host s1 --host mbp1 --json-output "$HOME/Desktop/presstalk-readiness-matrix.json"
plutil -extract targets raw -o - "$HOME/Desktop/presstalk-readiness-matrix.json"
```

It does not open System Settings or start signing repair. It reports Apple
Silicon eligibility, audio input hardware, installed PressTalk identity, runtime
speech readiness, active-field insertion readiness, latest production insertion
probe, and the next action. If it reports
`MicrophoneHardwareDetected: false`, skip microphone/STT smoke for that machine
until a microphone is attached.

## Install

For the current prerelease smoke artifact:

```bash
tmpdir="$(mktemp -d /tmp/presstalk.XXXXXX)"
curl -L -o "$tmpdir/PressTalk-0.1.5-rc71-macos-arm64.zip" \
  https://github.com/subtract0/presstalk/releases/download/v0.1.5-rc71/PressTalk-0.1.5-rc71-macos-arm64.zip
echo "377412a2fe341e29760694b9abdaeea11536e9adb6ebea51eff73448e000bbf4  $tmpdir/PressTalk-0.1.5-rc71-macos-arm64.zip" | shasum -a 256 -c -
ditto -x -k "$tmpdir/PressTalk-0.1.5-rc71-macos-arm64.zip" "$tmpdir"
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/PressTalk.app"
ditto "$tmpdir/PressTalk.app" "$HOME/Applications/PressTalk.app"
PRESSTALK_OPEN_PERMISSION_PANES=0 PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
  PRESSTALK_TRIGGER_KEY=fn \
  /bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

Expected SHA-256:

```text
377412a2fe341e29760694b9abdaeea11536e9adb6ebea51eff73448e000bbf4
```

Homebrew install is the intended stable path after the smoke artifact is
promoted:

```bash
brew tap subtract0/presstalk
brew install --cask presstalk
```

If an older build is already installed:

```bash
brew update
brew upgrade --cask presstalk
```

## Expected Install Side Effects

The cask should:

- install `PressTalk.app`
- run the bundled bootstrap helper
- create or reuse a local development code-signing identity, then re-sign
  `PressTalk.app` before launchd starts it when macOS allows noninteractive
  Keychain trust changes
- write `~/Library/Application Support/JarvisTap/runtime-status.json`
- write the LaunchAgent
- leave macOS permission panes closed during bootstrap
- pass `PRESSTALK_OPEN_PERMISSION_PANES` into the app so Settings cannot open
  macOS privacy panes during no-pane smoke runs
- write diagnostics quietly when `PRESSTALK_OPEN_PERMISSION_PANES=0`, without
  activating Finder

When bootstrap is run over SSH and `PRESSTALK_BOOTSTRAP_STABLE_SIGNING` was not
set explicitly, it only reuses an already-valid PressTalk local signing identity.
If no valid identity exists, it skips local signing so it cannot create a
surprise Mac-password trust prompt on the remote user's desktop. In that case
the app still starts, but `status.adHocSigned=true` and the bootstrap summary
reports stable signing skipped. That is a signing/identity blocker, not a reason
to open privacy panes repeatedly.

If a Mac skipped the signing trust password prompt, repair it from the logged-in
desktop session rather than reopening permission panes:

```bash
/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-repair-local-signing.sh"
```

For the ad-hoc `recognized_disabled` input-method state, current builds show
`Repair Signing` in the PressTalk menu bar and in Settings. That action runs the
same no-pane repair wrapper and then runs the production insertion probe.

The repair wrapper keeps `PRESSTALK_OPEN_PERMISSION_PANES=0` and
`PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, prepares the local signing identity,
restarts PressTalk with stable signing, signs the bundled
`PressTalkInputMethod.app`, refreshes the installed copy in
`~/Library/Input Methods`, and preserves the current trigger key. To verify the
running app insertion path immediately after repair:

```bash
/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-repair-local-signing.sh" --probe
```

The repair wrapper refuses to start the signing trust flow over SSH unless
`--allow-ssh` is passed deliberately.

The normal bootstrap summary now also reports `Bundled input method signing
applied` and `Installed input method refreshed`. On mbp1, those fields must be
`1` before treating the repaired input-method path as tested.

Runtime status now also reports `runtime.activeFieldInsertionReady` and
`runtime.activeFieldInsertionStatus`. For the requested PressTalk behavior,
`activeFieldInsertionReady=true` is the machine-readable distinction between a
speech pipeline that is merely transcription-ready and one that is ready to
insert into the active field.

After repair or bootstrap, collect one read-only status report:

```bash
/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-collect-smoke-status.sh"
```

For a compact SSH-safe pass/fail check after desktop repair, run:

```bash
/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-verify-repair-result.sh"
```

That verifier is read-only. It exits `0` only when the runtime insertion path is
ready and the latest production insertion probe captured text in the focused
target. It exits nonzero without opening permission panes or starting any
signing trust flow.

The `Input Method` section should show matching bundled and installed
`PressTalkInputMethod.app` CDHashes plus TIS status with
`recognizedSourceCount=1`, `recognizedEnabledSourceCount=1`, and
`selectCapable=true`. If the installed input-method CDHash differs from the
bundled one, rerun bootstrap/repair before interpreting insertion probes.

The `Repair And Probe Status` section should name the current repair state and
latest production insertion probe. If it says `adHocSigned=true` and
`inputMethodFallbackStatus=recognized_disabled`, use desktop `Repair Signing`
from the menu bar or Settings; do not re-grant Microphone, Input Monitoring, or
Accessibility for that state.

Runtime status also reports `permissions.inputMethodFallbackStatus`. Expected
values:

- `ready`: the fallback is enabled and worth probing.
- `recognized_disabled`: macOS sees a select-capable PressTalk source but has
  not enabled it; this is the current mbp1 ad-hoc blocker.
- `recognized_not_selectable`, `source_not_recognized`, or `not_installed`:
  collect diagnostics before treating insertion as a runtime/STT failure.

## Runtime Checks

Approve only fresh macOS prompts that are not already granted for the current
PressTalk identity:

- PressTalk microphone access
- PressTalk input monitoring
- PressTalk accessibility

Karabiner is not required for the default `Fn / Globe` path. Do not install or
approve Karabiner during the core smoke unless you are explicitly testing the
optional legacy `F5` fallback.

If macOS already shows PressTalk enabled but PressTalk reports a preflight as
unavailable, stop re-approving and collect diagnostics. That state is a
listener/probe blocker, not proof that the user skipped a permission.

If Accessibility reports `AXIsProcessTrusted=false` while the toggle appears
enabled in macOS Settings, treat it as a current signed-app identity mismatch.
Run the identity probe and keep permission panes closed unless the user
explicitly asks to open them.

If a machine was already working under the older JarvisTap privacy identity and
regresses after a new install, preserve that identity instead of reopening
privacy panes:

```bash
PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap \
PRESSTALK_OPEN_PERMISSION_PANES=0 \
PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
PRESSTALK_TRIGGER_KEY=fn \
  /bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

Karabiner is only needed when testing the optional `F5` fallback path. The default
trigger is native `Fn / Globe`.

For a fresh machine, keep bootstrap quiet and inspect diagnostics before opening
any macOS privacy panes manually:

```bash
PRESSTALK_OPEN_PERMISSION_PANES=0 PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 PRESSTALK_TRIGGER_KEY=fn \
  /bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

## Trigger Choices

The default LaunchAgent value is:

```bash
PRESSTALK_TRIGGER_KEY=fn
```

Supported values:

- `fn`
- `option`
- `left_option`
- `right_option`
- `f5`
- `trackpad_hold`

## Smoke Test

First confirm readiness:

```bash
/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-collect-smoke-status.sh"
```

If Accessibility appears enabled in macOS but PressTalk still reports
`accessibilityGranted=false`, run the bundled actual-bundle probe. It does not
open permission panes, does not request prompts, and reports trust for the exact
installed app bundle:

```bash
"$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-actual-accessibility-probe.sh"
```

If that still leaves an identity question, run the bundled identity probe for
the legacy and public bundle ids:

```bash
"$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-accessibility-identity-probe.sh"
```

Expected readiness fields:

- `runtime.inputPipelineReady=true`
- `runtime.inputListener` is not `failed`
- `status.speechModel=Ready`
- `status.triggerPath=Fn / Globe ready`

Then run the bundled manual smoke helper:

```bash
swift "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-manual-fn-smoke.swift"
```

The helper opens a focused text window and reads the configured PressTalk
trigger from `runtime-status.json`. Hold that physical trigger, say a short
sentence, then release. It writes a machine-readable result under
`~/Library/Application Support/JarvisTap/Diagnostics/` with the captured text,
expected trigger, runtime readiness before and after the attempt, runtime status,
and trace lines since the helper started. Current helpers also record
`traceFinalTranscript`, `traceInserted`, `traceCopyFallback`,
`traceInputMethodSelectFailed`, `targetCaptureSuccess`, and
`targetCaptureFailureHint`, so physical trigger/STT proof is separate from
active-field insertion proof. On a machine like the current mbp1 ad-hoc SSH
install, `targetCaptureFailureHint=input_method_select_failed` means the trigger
and transcription path may have worked, but macOS refused to select the
InputMethodKit fallback for active-field insertion.

Expected:

- no Apple Dictation popup
- no stray `^P`
- listening light appears
- transcript is inserted into the helper window
- the helper result JSON has `"success": true`
- the helper result JSON has `"targetCaptureSuccess": true`
- the helper result JSON has the expected `expectedTriggerKey` and readiness
  fields for the tested machine

For a synthetic pipeline check that does not prove the physical trigger, first
bootstrap with the F5 trigger and no panes:

```bash
PRESSTALK_OPEN_PERMISSION_PANES=0 PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
  PRESSTALK_TRIGGER_KEY=f5 \
  /bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
swift "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-automated-f5-smoke.swift"
PRESSTALK_OPEN_PERMISSION_PANES=0 PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
  PRESSTALK_TRIGGER_KEY=fn \
  /bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

This helper first runs a focused-window paste-event self-test, then posts the
PressTalk F5 bridge notifications, speaks a local phrase, and records PressTalk
trace evidence for transcription and paste completion. Its JSON result sets
`physicalTriggerProof=false`, includes `pasteSelfTest`,
`targetCaptureFailureHint`, `traceFinalTranscript` /
`tracePasteCommandPosted`, and separately reports `targetCaptureSuccess` plus
`tracePasteCompleted` for whether the helper text window captured enough pasted
text. Use it to debug STT/paste separately from the real Fn/Option trigger.

For this automated helper, the `/usr/bin/say` playback must be physically
audible to the microphone. If the system output route is isolated from the
microphone, the app may record near silence. Current helper JSON reports that as
`reason=tts_audio_not_captured_by_microphone` with `traceAudioCapture` RMS/peak
evidence rather than a generic STT failure.

## Input Method Fallback Diagnostics

The release bundle includes the InputMethodKit fallback used when Accessibility
is untrusted. Production dictation installs/registers the bundled input method
if needed, temporarily selects it for insertion, restores the original input
source, and does not open System Settings.

Install the input method without opening System Settings if you want to inspect
it before dictation reaches the fallback path:

```bash
/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-install-input-method.sh"
```

Check recognition without changing the active input source:

```bash
swift "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-input-method-status.swift"
```

If the installed input method is not recognized yet, register it without
selecting it:

```bash
swift "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-input-method-status.swift" --register
```

When ready to run an insertion probe, enable it explicitly, then select it:

```bash
swift "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-input-method-status.swift" --enable
swift "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-input-method-status.swift" --select
```

Or run the reversible client probe, which temporarily handles enable/select,
posts a payload into a local text view, and restores the original input source:

```bash
swift "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-input-method-client-probe.swift" --json
```

If the client probe reports `reason=input_method_select_failed` with
`selectStatus=-50`, macOS recognized the input method but refused to select it.
That is an active-field insertion blocker: dictation may still transcribe, but
without Accessibility trust the app will copy instead of inserting into the
focused field.

If the client probe reports `reason=input_method_enable_no_effect`,
`enableStatus=0`, and `enableNoEffect=true`, macOS recognized the input method
and accepted the enable API call, but the enabled-source list still did not
contain PressTalk. That is the current mbp1 ad-hoc SSH-install blocker; do not
reopen privacy panes for it.

To test the actual running PressTalk app process rather than only the standalone
client probe, run the production insertion probe. It temporarily enables the app
diagnostic notification, opens a focused local helper window, asks PressTalk to
insert one payload through the same production insertion path used after
dictation, writes JSON diagnostics, and restores normal no-probe startup:

```bash
/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-run-production-insertion-probe.sh" --json
```

For insertion proof, require `success=true`, `targetCaptureSuccess=true`, and a
production trace such as `traceProductionMethod=input_method_notification` or an
Accessibility insertion method.

After macOS recognizes and you select `PressTalk Input Method`, focus an
editable text field and run:

```bash
/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-input-method-insert-probe.sh" "PressTalk input method probe"
```

Then inspect:

```bash
tail -n 40 ~/Library/Logs/presstalk_input_method.log
```

This is not release success until the probe text appears in the focused field.

If you need to force the F5 bridge manually on that Mac, use:

```bash
/bin/bash /Applications/PressTalk.app/Contents/Resources/presstalk-karabiner-fallback.sh --enable
```

Then approve Karabiner-Elements if macOS asks.

## Debug Commands

```bash
tail -f ~/Library/Logs/jarvistap_trace.log
launchctl print gui/$(id -u)/com.am.jarvistap | sed -n '1,80p'
/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-collect-smoke-status.sh"
```

## Success Criteria

- `WhisperKit ready`
- `PressTalk armed`
- `🎙️ Fn / Globe pressed: recording started`
- `📝 Transkription abgeschlossen: ...`
- `targetCaptureSuccess: true` in the manual or automated smoke JSON

## Machine Matrix

Record each machine result before claiming release coverage:

- `studio1`: M4 Max, local build/runtime smoke
- `s1`: install + Fn smoke
- `s2` / `studio2`: excluded from current microphone/STT coverage until a
  microphone is attached
- `mbp1`: M1 Max install + Fn or Option smoke

Attach or paste the output of `presstalk-collect-smoke-status.sh` for each
machine. A successful smoke should show `inputPipelineReady: true`, the trigger
key used, `WhisperKit ready` / `PressTalk armed` in the trace, matching values
in `Status Consistency`, and a completed dictation paste line.
