# PressTalk

Native macOS push-to-talk dictation for Apple Silicon.

Current fallback release: `0.1.6-test4` (`v0.1.6-test4`, commit `31bc4f6`)

Homebrew cask name: `presstalk`

Production naming:
- shipped app bundle: `PressTalk.app`
- app bundle identifier: `com.am.presstalk`
- product name: `PressTalk`
- some legacy helper names such as `JARVISTAP_*` stay stable for now
- for machines with older working TCC grants, the bootstrap helper can preserve
  the legacy app identity with `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`

Current packaged behavior:
- hold `Fn / Globe` by default to bring up the light and start recording
- release the trigger key to finalize transcription with silence-aware tail capture
- choose `Option + Space`, `Option`, left/right `Option`, `Fn`, `F5`, or trackpad hold from settings
- moving too far while using the trackpad trigger cancels the capture instead of pasting garbage
- paste the final transcript into the currently focused app
- no cloud round-trip in the default path
- compact HUD and menu bar control surface
- small runtime settings window for HUD, auto-paste, language, and release tail

The current default runtime uses the local Parakeet v3 ANE backend for final dictation. Parakeet quality fallback is enabled by default: low-confidence or weakly punctuated Parakeet output is retried through local WhisperKit large-v3-turbo before paste, while high-confidence ANE output stays fast.

The current public fallback release is intentionally conservative: it is
hold-trigger, record locally, run a fast local ASR final pass, then paste on
release. True live streaming partial text remains a benchmark/product track,
not the release baseline.

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
- approve only any fresh macOS prompts that have not already been granted
- hold `Fn / Globe` to dictate

Legacy F5 compatibility still ships as an optional helper, but it is no longer the default path:

```bash
/bin/bash /Applications/PressTalk.app/Contents/Resources/presstalk-karabiner-fallback.sh --enable
```

Cross-device Apple Silicon checklist:

- [docs/APPLE_SILICON_TESTING.md](docs/APPLE_SILICON_TESTING.md)

If macOS shows a permission toggle as enabled but PressTalk still reports a
runtime preflight mismatch, do not keep re-approving it; see
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Build
```bash
bash scripts/build_jarvistap.sh
```

Local builds preserve the currently installed `PressTalk.app` bundle identifier
by default. That prevents a working development install from silently switching
between `com.am.jarvistap` and `com.am.presstalk`, which macOS treats as
different privacy clients. Source-tree builds also create or reuse the local
development code-signing identity by default; set
`PRESSTALK_BUILD_STABLE_SIGNING=0` only when you deliberately want an ad-hoc
debug build.

That produces:
- `bin/jarvistap`
- `~/Applications/PressTalk.app`

To build or bootstrap against a legacy local privacy identity:

```bash
PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap bash scripts/build_jarvistap.sh
PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap \
  PRESSTALK_OPEN_PERMISSION_PANES=0 PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
  "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

## Install As LaunchAgent
```bash
bash scripts/install_jarvistap_launchd.sh
```

The launchd installer prefers:
- `/Applications/PressTalk.app` if you installed via Homebrew cask
- `~/Applications/PressTalk.app` if you built locally from source
- legacy `JarvisTap.app` paths only as migration fallback

That installs `com.am.presstalk` with these defaults:
- `JARVISTAP_AGENT_MODE=dictation`
- `JARVISTAP_WHISPERKIT_MODEL=openai_whisper-large-v3-v20240930_turbo_632MB`
- `JARVISTAP_WHISPER_LANGUAGE=auto`
- `JARVISTAP_SAY_VOICE=Samantha`
- `JARVISTAP_RELEASE_TAIL_PADDING_SECONDS=0.35`
- `PRESSTALK_TRIGGER_KEY=fn`

Supported trigger values:
- `fn`
- `option_space`
- `option`
- `left_option`
- `right_option`
- `trackpad_hold`
- `f5`

## Public Packaging
Package a Homebrew test/prerelease zip:
```bash
bash scripts/package_presstalk_release.sh 0.1.6-test4
```

Audit an existing zip before handing it to testers:
```bash
bash scripts/presstalk_release_artifact_audit.sh \
  --zip dist/PressTalk-0.1.6-test4-macos-arm64.zip \
  --expected-version 0.1.6-test4 \
  --json-output dist/PressTalk-0.1.6-test4-artifact-audit.json
```

To exercise packaging and publish-time audit checks without uploading anything:
```bash
PRESSTALK_PUBLISH_DRY_RUN=1 bash scripts/publish_presstalk_homebrew.sh 0.1.6-test5
```

Set `PRESSTALK_DIST_DIR=/path/to/dist` when you want generated zips, checksums,
and audit JSON written outside the repo `dist/` directory.

To collect the current no-publish release-candidate evidence in one pass:
```bash
bash scripts/presstalk_release_candidate_preflight.sh 0.1.6-test5 \
  --local \
  --host mbp1-tb \
  --require studio1 \
  --require mbp1 \
  --exclude-host "studio2=no attached microphone"
```

This wrapper collects the readiness matrix, runs the proof gate, performs the
Homebrew publish dry-run, and records the combined readiness JSON. It does not
install PressTalk, open System Settings, upload a release, or SSH anywhere
except hosts supplied with `--host` / `--hosts`. Passing and failing runs both
write `PressTalk-<version>-candidate-preflight.json`; failed runs include the
failed step and exit status so target-machine blockers remain machine-readable.

Release packaging explicitly builds the public `com.am.presstalk` identity even
when your local development install is preserving `com.am.jarvistap`.

For a production distribution artifact, use an explicit Developer ID signing
identity, hardened runtime, secure timestamping, and notarization:

```bash
PRESSTALK_DISTRIBUTION_SIGNING=1 \
PRESSTALK_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
PRESSTALK_NOTARIZE=1 \
PRESSTALK_NOTARYTOOL_PROFILE=presstalk-notary \
  bash scripts/package_presstalk_release.sh 0.1.6
```

Then require the production signature and stapled notarization ticket:
```bash
bash scripts/presstalk_release_artifact_audit.sh \
  --zip dist/PressTalk-0.1.6-macos-arm64.zip \
  --expected-version 0.1.6 \
  --require-distribution \
  --require-notarized
```

After collecting a proof-gate JSON for the target machines, combine artifact
and machine evidence into one release-readiness verdict:
```bash
bash scripts/presstalk_release_readiness_preflight.sh \
  --artifact-audit dist/PressTalk-0.1.6-macos-arm64-artifact-audit.json \
  --proof-gate "$HOME/Library/Application Support/JarvisTap/Diagnostics/proof-gate-0.1.6.json" \
  --require-production \
  --json-output dist/PressTalk-0.1.6-release-readiness.json
```

Without `PRESSTALK_DISTRIBUTION_SIGNING=1`, the packaged zip is a test artifact
and should not be described as a production-grade notarized Mac release.

Publish a public prerelease artifact for machine smoke testing:
```bash
bash scripts/publish_presstalk_prerelease.sh 0.1.6-test5
```

`publish_presstalk_prerelease.sh` also requires a hyphenated version by default
so smoke artifacts do not look like stable production tags. Before upload it
runs `presstalk_release_artifact_audit.sh` against the packaged zip and writes
`dist/PressTalk-<version>-macos-arm64-artifact-audit.json`.

Publish the public binary release plus Homebrew tap:
```bash
bash scripts/publish_presstalk_homebrew.sh 0.1.6-test5
```

For a stable version without a hyphen, `publish_presstalk_homebrew.sh` refuses
to continue unless `PRESSTALK_DISTRIBUTION_SIGNING=1` and
`PRESSTALK_NOTARIZE=1` are both set. It also runs the artifact audit before
upload; stable releases require `--require-distribution --require-notarized`,
so a weakly signed or unstapled zip cannot be published just because the
environment variables were set. Stable releases also require
`PRESSTALK_RELEASE_PROOF_GATE_JSON=/path/to/proof-gate.json`; the publish script
runs `presstalk_release_readiness_preflight.sh --require-production` before any
GitHub release or Homebrew tap write. By default stable publishing requires
proof targets for `studio1` and `mbp1`; override or extend that with
`PRESSTALK_REQUIRED_PROOF_TARGETS=studio1,mbp1,studio2` once `studio2` is back
in microphone/STT scope.

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
tail -f ~/Library/Logs/presstalk_trace.log
```

Other runtime logs:
- `~/Library/Logs/presstalk.out.log`
- `~/Library/Logs/presstalk.err.log`

Legacy local bootstrap paths may still write `jarvistap_*` logs when preserving
an older `com.am.jarvistap` privacy identity.

## Permissions
Grant `PressTalk.app`:
- Microphone
- Accessibility, if paste insertion uses the direct paste path
- Input Monitoring only for modifier-only triggers such as bare `Option` or `Fn`

## Optional Modes
The codebase still supports a `codex-confirm-execute` mode, but that is no longer the packaged default. The packaged installer is optimized for local dictation first.

## Full Stack Installer
The repo still contains `install_jarvis_os.sh` for the larger localbrain + Jarvis setup, but the clean dictation install path is:
```bash
bash scripts/install_jarvistap_launchd.sh
```
