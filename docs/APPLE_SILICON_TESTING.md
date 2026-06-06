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
curl -L -o "$tmpdir/PressTalk-0.1.5-rc22-macos-arm64.zip" \
  https://github.com/subtract0/presstalk/releases/download/v0.1.5-rc22/PressTalk-0.1.5-rc22-macos-arm64.zip
echo "e5d5f6d42b71a4b6f99b44fb34eadcc66036673488a5ad1e73a8eb66e665c6b9  $tmpdir/PressTalk-0.1.5-rc22-macos-arm64.zip" | shasum -a 256 -c -
ditto -x -k "$tmpdir/PressTalk-0.1.5-rc22-macos-arm64.zip" "$tmpdir"
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/PressTalk.app"
ditto "$tmpdir/PressTalk.app" "$HOME/Applications/PressTalk.app"
PRESSTALK_OPEN_PERMISSION_PANES=0 PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
  PRESSTALK_TRIGGER_KEY=fn \
  /bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

Expected SHA-256:

```text
e5d5f6d42b71a4b6f99b44fb34eadcc66036673488a5ad1e73a8eb66e665c6b9
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
- leave macOS permission panes closed unless `PRESSTALK_OPEN_PERMISSION_PANES=1`
  is set for bootstrap
- pass `PRESSTALK_OPEN_PERMISSION_PANES` into the app so Settings cannot open
  macOS privacy panes during no-pane smoke runs

## Approvals

Approve the prompts for:

- PressTalk microphone access
- PressTalk input monitoring
- PressTalk accessibility
- Karabiner-Elements input monitoring / driver extension if macOS asks

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

If you want bootstrap to open the panes for a fresh machine, run it with:

```bash
PRESSTALK_OPEN_PERMISSION_PANES=1 PRESSTALK_TRIGGER_KEY=fn \
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
and trace lines since the helper started.

Expected:

- no Apple Dictation popup
- no stray `^P`
- listening light appears
- transcript is inserted into the helper window
- the helper result JSON has `"success": true`
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

This helper posts the PressTalk F5 bridge notifications, speaks a local phrase,
and records PressTalk trace evidence for transcription and paste completion.
Its JSON result sets `physicalTriggerProof=false`, includes
`traceFinalTranscript` / `tracePasteCommandPosted`, and separately reports
`targetCaptureSuccess` plus `tracePasteCompleted` for whether the helper text
window captured enough pasted text. Use it to debug STT/paste separately from
the real Fn/Option trigger.

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
