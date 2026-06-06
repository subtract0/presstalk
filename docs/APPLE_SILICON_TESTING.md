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
- write the LaunchAgent
- open the macOS permission panes

## Approvals

Approve the prompts for:

- PressTalk microphone access
- PressTalk input monitoring
- PressTalk accessibility
- Karabiner-Elements input monitoring / driver extension if macOS asks

Karabiner is only needed when testing the optional `F5` fallback path. The default
trigger is native `Fn / Globe`.

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
