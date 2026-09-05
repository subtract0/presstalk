# PressTalk

Push-to-talk dictation for Apple Silicon. Hold `Fn`, speak, release, and the text
lands in whatever app you were using. Recognition runs on the Neural Engine in
your Mac.

```bash
brew tap subtract0/presstalk
brew install --cask presstalk
```

Then hold `Fn / Globe` and start talking. First launch walks through the three
permissions macOS requires and downloads the speech model (~460 MB), ending in a
dictation you can see arrive.

## Where things are

| | |
|---|---|
| Privacy, in detail | [docs/PRIVACY.md](docs/PRIVACY.md) |
| Support and refunds | [docs/SUPPORT.md](docs/SUPPORT.md) |
| What it costs | [docs/MONETIZATION.md](docs/MONETIZATION.md) |
| Landing page draft | [site/index.html](site/index.html) |
| Getting to a paid launch | [docs/PRESSTALK_DISTRIBUTION_ROADMAP_V1.md](docs/PRESSTALK_DISTRIBUTION_ROADMAP_V1.md) |
| Permission trouble | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |
| Testing on other Macs | [docs/APPLE_SILICON_TESTING.md](docs/APPLE_SILICON_TESTING.md) |

## Current state

**Not notarized.** Builds are ad-hoc signed, so macOS reports an unverified
developer and first launch needs right-click → Open. A Developer ID certificate
is the remaining gate; everything downstream of it is scripted and tested.

Recognition uses Parakeet v3 on the Neural Engine. A larger WhisperKit model can
re-check low-confidence results, but it is a separate ~620 MB download that is
never fetched implicitly — without it, dictation runs on Parakeet alone and
`currentQualityFallbackStatus()` says so.

Live partial text is off by default. PressTalk is push-to-talk, so key release
already supplies the endpoint; the preview never shortened the wait and put
teardown work on the paste path.

## Building

```bash
bash scripts/build_jarvistap.sh     # builds and installs to ~/Applications
swift test                          # unit tests for the policy layer
```

Set `PRESSTALK_INCLUDE_DEV_TOOLS=0` to leave the probe and smoke helpers out, as
distribution packaging does.

## Gates worth knowing about

These exist because each one caught something that had already shipped.

```bash
# Refuses a build the notary service would reject, without needing a certificate:
# unsigned nested Mach-O, missing entitlements, no secure timestamp.
bash scripts/presstalk_notarization_readiness.sh --app ~/Applications/PressTalk.app

# Refuses marketing copy the evidence does not support.
bash scripts/presstalk_claims_gate.sh

# Runs the whole journey headlessly -- trigger, capture, recognition, delivery --
# and reports every attempt, not just the successful ones.
bash scripts/presstalk_e2e_harness.sh --fixture path/to/audio.wav --runs 10
```

## Measured

144 German clips through the shipped pipeline end to end: 144/144 produced text,
11.25% word error rate against written references, release-to-transcript 0.95 s
at p50 and 1.45 s at p95 on an M4 Max. Recognition realtime factor 115× on M4
Max, 62× on M1 Ultra, 57× on M1 Max.

The audio is synthesised speech in three voices, so treat the error rate as a
regression baseline rather than a claim about your voice. No comparison against
other dictation apps has been run.

## Layout

- `Sources/PressTalkCore/` — decision logic with no AppKit or AVFoundation, so it
  can be tested: setup ordering, transcript cleanup, German vocabulary repair,
  licence verification, entitlements, retention rules.
- `Sources/JarvisTap/` — the app. Trigger handling, capture, recognition,
  insertion, menu bar, settings, first-run setup.
- `Sources/PressTalkLicenseTool/` — issues offline licences. Never bundled; the
  app holds only public keys.
- `scripts/` — build, package, publish, and the gates above.
