# PressTalk

Push-to-talk dictation for Apple Silicon Macs (M1 or later), running macOS 14 or
later. Hold `Fn`, speak, release, and PressTalk pastes the text into your focused
text field. Recognition runs on the Neural Engine in your Mac.

[Download PressTalk](https://presstalk.app/download.html) for a three-day free
trial, with no card or account required. Homebrew is also available:

```bash
brew tap subtract0/presstalk
brew install --cask presstalk
```

First launch walks through the permissions needed for your chosen shortcut and
downloads the speech model (~460 MB). Then click a text field, hold `Fn / Globe`,
speak, and release. If Fn does not respond, setup also offers `Option + Space`
or `F5`. Dictation works offline after setup.

## Where things are

| | |
|---|---|
| Privacy, in detail | [docs/PRIVACY.md](docs/PRIVACY.md) |
| Support and refunds | [docs/SUPPORT.md](docs/SUPPORT.md) |
| What it costs | [docs/MONETIZATION.md](docs/MONETIZATION.md) |
| Product website | [presstalk.app](https://presstalk.app/) · [source](site/index.html) |
| Current public release | [PressTalk 0.1.25](https://github.com/subtract0/presstalk/releases/tag/v0.1.25) |
| Purchase and licence delivery | [commerce/README.md](commerce/README.md) |
| What is measured, and how | [docs/MEASUREMENTS.md](docs/MEASUREMENTS.md) |
| Completed public launch record | [9 September release verification](docs/purchases/2026-09-09-public-release.md) |
| Earlier launch checklist (historical) | [docs/LAUNCH_GATES.md](docs/LAUNCH_GATES.md) |
| September launch plan (historical) | [docs/TWO_WEEK_PLAN_2026-09-05.md](docs/TWO_WEEK_PLAN_2026-09-05.md) |
| Distribution roadmap | [docs/PRESSTALK_DISTRIBUTION_ROADMAP_V1.md](docs/PRESSTALK_DISTRIBUTION_ROADMAP_V1.md) |
| Permission trouble | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |
| Testing on other Macs | [docs/APPLE_SILICON_TESTING.md](docs/APPLE_SILICON_TESTING.md) |

## Current state

**The public 0.1.25 release is Developer ID signed and notarized by Apple.**
Download the DMG, drag PressTalk into Applications, and open it from there.
The older certificate and manual-fulfilment tasks in the historical launch
checklist are not the current distribution status.

New installations receive a three-day trial starting with their first successful
dictation. The existing one-time purchase includes every future Mac release we
publish, including major versions; it does not promise indefinite development,
support, or compatibility with future macOS versions. Prior users retain their
grandfathered core dictation. See the [offer](docs/MONETIZATION.md) for details.

After purchase, the confirmation page provides the licence immediately and the
purchase service sends it by email. Activate through the app link, licence file,
or pasted key. Verification then happens locally, without recurring activation
checks. [Licence recovery](https://presstalk-licenses.presstalk.workers.dev/recover)
is available for existing buyers.

**Known limitations:** the first recording after connecting AirPods can stop
with a retry message; release the key, wait briefly, and dictate again.
Interrupted recordings insert nothing. Compatibility with macOS 27 has not yet
been verified on a Mac running that release. See [support](docs/SUPPORT.md) and
the [release notes](https://github.com/subtract0/presstalk/releases/tag/v0.1.25).

Recognition uses Parakeet v3 on the Neural Engine. A larger WhisperKit model can
re-check low-confidence results, but it is a separate ~620 MB download that is
never fetched implicitly — without it, dictation runs on Parakeet alone and
`currentQualityFallbackStatus()` says so.

Live partial text is off by default. PressTalk is push-to-talk, so key release
already supplies the endpoint; the preview never shortened the wait and put
teardown work on the paste path.

## Building

```bash
bash scripts/build_jarvistap.sh     # builds ~/Applications/PressTalk Dev.app
swift test                          # unit tests for the policy layer
```

Development builds use `com.am.presstalk.dev`, separate settings, runtime files,
and activation handlers. They never replace the daily `PressTalk.app`. Keep the
official release installed for everyday use and reproduce customer bugs there.
The builder stages and verifies the new app before moving it into place; an
earlier development app is preserved if compilation or signing fails.

Production artifacts require an explicit Developer ID distribution build for
the PressTalk signing team. Packaging uses a temporary destination, preserves
the official identity, and excludes developer probes and signing helpers:

```bash
PRESSTALK_DISTRIBUTION_SIGNING=1 \
PRESSTALK_CODESIGN_IDENTITY="Developer ID Application: <certificate name> (5HUC5LA94B)" \
PRESSTALK_NOTARIZE=1 PRESSTALK_NOTARYTOOL_PROFILE="<profile>" \
  bash scripts/package_presstalk_release.sh <version>
```

Without distribution signing, packaging produces a separately named development
artifact. Neither local nor ad-hoc signing may use the production bundle ID.
`PRESSTALK_BUILD_CLEAN=1` opts into a clean SwiftPM build when needed.
See [Troubleshooting](docs/TROUBLESHOOTING.md) for permission recovery.

## Gates worth knowing about

These exist because each one caught something that had already shipped.

```bash
# Refuses a build the notary service would reject, without needing a certificate:
# unsigned nested Mach-O, missing entitlements, no secure timestamp.
bash scripts/presstalk_notarization_readiness.sh --app ~/Applications/PressTalk.app

# Refuses marketing copy the evidence does not support.
bash scripts/presstalk_claims_gate.sh

# Invariants runtime tests cannot see: no code path writes dictated words
# to a log, and the grandfathering decision is recorded before anything else.
bash scripts/test_presstalk_source_invariants.sh

# Runs the whole journey headlessly -- trigger, capture, recognition, delivery --
# and reports every attempt, not just the successful ones.
bash scripts/presstalk_e2e_harness.sh --fixture path/to/audio.wav --runs 10
```

## Measured

144 German clips through the shipped pipeline end to end: 144/144 produced text,
12.71% word error rate against written references in the configuration a buyer
actually receives, release-to-transcript 0.618 s at p50 and 0.629 s at worst on
an M4 Max. Recognition realtime factor 115× on M4 Max, 62× on M1 Ultra, 57× on
M1 Max.

Apple's own on-device engine scores 19.38% on the same clips with the same
vocabulary pass, so PressTalk makes about a third fewer errors here. The test
set, references and scorer are in `eval/de` -- re-run it rather than believing
this paragraph.

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
