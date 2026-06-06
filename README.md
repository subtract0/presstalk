# PressTalk

Native macOS push-to-talk dictation for Apple Silicon.

Current repo version: `0.1.5`

Homebrew cask name: `presstalk`

Production naming:
- shipped app bundle: `PressTalk.app`
- product name: `PressTalk`
- internal compatibility identifiers such as `com.am.jarvistap` and `JARVISTAP_*` stay stable for now

Current packaged behavior:
- hold `Fn / Globe` by default to bring up the light and start recording
- release the trigger key to finalize transcription with silence-aware tail capture
- choose `Fn`, either `Option`, left/right `Option`, `F5`, or trackpad hold from settings
- moving too far while using the trackpad trigger cancels the capture instead of pasting garbage
- paste the final transcript into the currently focused app
- no cloud round-trip in the default path
- compact HUD and menu bar control surface
- small runtime settings window for HUD, auto-paste, language, and release tail

The current default runtime is a local WhisperKit dictation agent, intended as a Wispr Flow replacement.

## Release Status

The current public source is staged for Apple Silicon testing. See
[docs/RELEASE_STATUS.md](docs/RELEASE_STATUS.md) before treating a build as a
verified release across all target machines.

## Homebrew Cask

The public cask is live.

```bash
brew tap subtract0/presstalk
brew install --cask presstalk
```

The Homebrew cask runs the bundled bootstrap helper so a fresh Mac lands closer to:

- install
- approve the macOS prompts
- hold `Fn / Globe` to dictate

Legacy F5 compatibility still ships as an optional helper, but it is no longer the default path:

```bash
/bin/bash /Applications/PressTalk.app/Contents/Resources/presstalk-karabiner-fallback.sh --enable
```

Cross-device Apple Silicon checklist:

- [docs/APPLE_SILICON_TESTING.md](docs/APPLE_SILICON_TESTING.md)

## Build
```bash
bash scripts/build_jarvistap.sh
```

That produces:
- `bin/jarvistap`
- `~/Applications/PressTalk.app`

## Install As LaunchAgent
```bash
bash scripts/install_jarvistap_launchd.sh
```

The launchd installer prefers:
- `/Applications/PressTalk.app` if you installed via Homebrew cask
- `~/Applications/PressTalk.app` if you built locally from source
- legacy `JarvisTap.app` paths only as migration fallback

That installs `com.am.jarvistap` with these defaults:
- `JARVISTAP_AGENT_MODE=dictation`
- `JARVISTAP_WHISPERKIT_MODEL=openai_whisper-large-v3-v20240930_turbo_632MB`
- `JARVISTAP_WHISPER_LANGUAGE=de`
- `JARVISTAP_SAY_VOICE=Samantha`
- `JARVISTAP_RELEASE_TAIL_PADDING_SECONDS=0.35`
- `PRESSTALK_TRIGGER_KEY=fn`

Supported trigger values:
- `fn`
- `option`
- `left_option`
- `right_option`
- `f5`
- `trackpad_hold`

## Public Packaging
Package a Homebrew release zip:
```bash
bash scripts/package_presstalk_release.sh 0.1.5
```

Publish a public prerelease artifact for machine smoke testing:
```bash
bash scripts/publish_presstalk_prerelease.sh 0.1.5-rc1
```

Publish the public binary release plus Homebrew tap:
```bash
bash scripts/publish_presstalk_homebrew.sh 0.1.5
```

That makes this install path work:
```bash
brew tap subtract0/presstalk
brew install --cask presstalk
```

## Performance

Measured local performance notes for the current `0.1` build are in:

- [docs/PERFORMANCE.md](docs/PERFORMANCE.md)

Product / pricing plan:

- [docs/MONETIZATION.md](docs/MONETIZATION.md)

## Logs
```bash
tail -f ~/Library/Logs/jarvistap_trace.log
```

Other runtime logs:
- `~/Library/Logs/jarvistap.out.log`
- `~/Library/Logs/jarvistap.err.log`

## Permissions
Grant `PressTalk.app`:
- Microphone
- Input Monitoring
- Accessibility

## Optional Modes
The codebase still supports a `codex-confirm-execute` mode, but that is no longer the packaged default. The packaged installer is optimized for local dictation first.

## Full Stack Installer
The repo still contains `install_jarvis_os.sh` for the larger localbrain + Jarvis setup, but the clean dictation install path is:
```bash
bash scripts/install_jarvistap_launchd.sh
```
