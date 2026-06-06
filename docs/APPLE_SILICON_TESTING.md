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

## Install

For the current prerelease smoke artifact:

```bash
tmpdir="$(mktemp -d /tmp/presstalk.XXXXXX)"
curl -L -o "$tmpdir/PressTalk-0.1.5-rc34-macos-arm64.zip" \
  https://github.com/subtract0/presstalk/releases/download/v0.1.5-rc34/PressTalk-0.1.5-rc34-macos-arm64.zip
echo "74eb415184773e31a9e2fb36902ffdf48ea56c8f15e509dc54d551257868a859  $tmpdir/PressTalk-0.1.5-rc34-macos-arm64.zip" | shasum -a 256 -c -
ditto -x -k "$tmpdir/PressTalk-0.1.5-rc34-macos-arm64.zip" "$tmpdir"
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/PressTalk.app"
ditto "$tmpdir/PressTalk.app" "$HOME/Applications/PressTalk.app"
PRESSTALK_OPEN_PERMISSION_PANES=0 PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
  PRESSTALK_TRIGGER_KEY=fn \
  /bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

Expected SHA-256:

```text
74eb415184773e31a9e2fb36902ffdf48ea56c8f15e509dc54d551257868a859
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
  `PressTalk.app` before launchd starts it
- write `~/Library/Application Support/JarvisTap/runtime-status.json`
- write the LaunchAgent
- leave macOS permission panes closed during bootstrap
- pass `PRESSTALK_OPEN_PERMISSION_PANES` into the app so Settings cannot open
  macOS privacy panes during no-pane smoke runs

## Approvals

Approve the prompts for:

- PressTalk microphone access
- PressTalk input monitoring
- PressTalk accessibility

Karabiner is not required for the default `Fn / Globe` path. Do not install or
approve Karabiner during the core smoke unless you are explicitly testing the
optional legacy `F5` fallback.

If macOS already shows PressTalk enabled but PressTalk reports a preflight as
unavailable, stop re-approving and collect diagnostics. That state is a
listener/probe blocker, not proof that the user skipped a permission.

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
`accessibilityGranted=false`, run the bundled identity probe. It does not open
permission panes and does not request prompts:

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
`targetCaptureSuccess`, and `targetCaptureFailureHint`, so physical trigger/STT
proof is separate from active-field insertion proof.

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

## Optional Input Method Probe

The release bundle includes an opt-in InputMethodKit prototype for the
Accessibility-untrusted active-field insertion blocker. It is not installed or
selected automatically.

Install the prototype without opening System Settings:

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
- `s2`: install + Fn smoke
- `mbp1`: M1 Max install + Fn or Option smoke

Attach or paste the output of `presstalk-collect-smoke-status.sh` for each
machine. A successful smoke should show `inputPipelineReady: true`, the trigger
key used, `WhisperKit ready` / `PressTalk armed` in the trace, matching values
in `Status Consistency`, and a completed dictation paste line.
