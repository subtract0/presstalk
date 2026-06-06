# Apple Silicon Test Checklist

Use this on another Apple Silicon Mac such as:

- M1 Max MacBook Pro
- M4 MacBook Air

## Goal

Verify that a fresh machine can install PressTalk with minimal thinking:

1. install
2. approve permissions
3. hold `Fn / Globe`
4. dictate

## Install

For the current prerelease smoke artifact:

```bash
tmpdir="$(mktemp -d /tmp/presstalk.XXXXXX)"
curl -L -o "$tmpdir/PressTalk-0.1.5-rc7-macos-arm64.zip" \
  https://github.com/subtract0/presstalk/releases/download/v0.1.5-rc7/PressTalk-0.1.5-rc7-macos-arm64.zip
echo "b6b7180e3c6553aa60f3277d6f29f40e5841f9beb8158c1ca17ca788d47e2633  $tmpdir/PressTalk-0.1.5-rc7-macos-arm64.zip" | shasum -a 256 -c -
ditto -x -k "$tmpdir/PressTalk-0.1.5-rc7-macos-arm64.zip" "$tmpdir"
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/PressTalk.app"
ditto "$tmpdir/PressTalk.app" "$HOME/Applications/PressTalk.app"
PRESSTALK_TRIGGER_KEY=fn /bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

Expected SHA-256:

```text
b6b7180e3c6553aa60f3277d6f29f40e5841f9beb8158c1ca17ca788d47e2633
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

## Approvals

Approve the prompts for:

- PressTalk microphone access
- PressTalk input monitoring
- PressTalk accessibility
- Karabiner-Elements input monitoring / driver extension if macOS asks

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

1. Click into any text field.
2. Hold `Fn / Globe`.
3. Speak a short sentence.
4. Release `Fn / Globe`.

Expected:

- no Apple Dictation popup
- no stray `^P`
- listening light appears
- transcript is inserted into the focused app

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
- `Dictation paste completed`

## Machine Matrix

Record each machine result before claiming release coverage:

- `studio1`: M4 Max, local build/runtime smoke
- `s1`: install + Fn smoke
- `s2`: install + Fn smoke
- `mbp1`: M1 Max install + Fn or Option smoke

Attach or paste the output of `presstalk-collect-smoke-status.sh` for each
machine. A successful smoke should show `inputPipelineReady: true`, the trigger
key used, `WhisperKit ready` / `PressTalk armed` in the trace, and a completed
dictation paste line.
