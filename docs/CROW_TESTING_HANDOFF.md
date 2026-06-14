# Crow PressTalk Tester Handoff

Date: 2026-06-14

## Target

Crow should test the public Apple Silicon tester cask on his M1 MacBook Air
with 16 GB RAM, or another Apple Silicon Mac running macOS Sonoma or newer.

This is a prerelease tester build, not the final notarized paid release. The
core promise under test is:

> Hold Fn / Globe. Speak. Release. Text appears. Audio and transcripts stay on
> the Mac in the default path.

## Current Build

- Public cask: `0.1.6-test8`
- Source baseline: `d6c0da1` on `refactor/skills-code-health-audit`
- Known-good source tag: `known-good/d6c0da1-text-policy-smoke`
- Release repo: `subtract0/presstalk-releases`
- Release tag: `v0.1.6-test8`
- Asset: `PressTalk-0.1.6-test8-macos-arm64.zip`
- SHA-256: `e222363c9093da4c434dcbadd9c718aa0a9608beaf2bce1bbf7b3ccbec7de3e6`
- Homebrew tap: `subtract0/homebrew-presstalk`
- Tap commit: `bd695c4dcc2f192f2d77235ffe17d9f3098b1e2f`

## Install

Fresh install:

```bash
brew update
brew tap subtract0/presstalk
brew install --cask subtract0/presstalk/presstalk
```

Upgrade or repair an existing install:

```bash
brew update
brew tap subtract0/presstalk
brew upgrade --cask subtract0/presstalk/presstalk || brew reinstall --cask subtract0/presstalk/presstalk
```

Clean reinstall if the machine has stale or confusing earlier test builds:

```bash
osascript -e 'quit app "PressTalk"' 2>/dev/null || true
brew uninstall --cask presstalk --force 2>/dev/null || true
rm -rf "$HOME/Applications/PressTalk.app"
brew update
brew tap subtract0/presstalk
brew install --cask subtract0/presstalk/presstalk
```

## First Launch

Approve the three macOS permissions PressTalk needs:

- Microphone
- Input Monitoring
- Accessibility

If System Settings already lists `PressTalk.app`, enable that existing entry.
Do not create duplicate entries unless PressTalk is not listed.

Do not install or enable Karabiner for this test. Karabiner is only an optional
legacy bridge for the F5 trigger. The default trigger is `Fn / Globe`.

## Smoke Test

Use a real focused text field such as TextEdit, Notes, a browser text area, or
Terminal.

1. Hold `Fn / Globe`, speak one short English sentence, release.
2. Hold `Fn / Globe`, speak one short German sentence, release.
3. Hold `Fn / Globe`, speak for 15 to 25 seconds with mixed English and German,
   release.
4. Hold `Fn / Globe` very briefly without speaking, release, and check that it
   does not get stuck or spam warnings.

Expected behavior:

- A white listening light appears near the cursor and reacts to voice.
- The menu bar may show recording state while the key is held.
- Text auto-inserts after release.
- The app stays alive after the test.
- A small blue `A` bubble can be macOS input-source or press-and-hold UI, not
  necessarily PressTalk. Report it if it sticks or breaks typing.

Do not press Command+V during the first pass. We need to know whether
auto-insertion worked by itself.

## Report Template

```text
Mac model / chip / RAM:
macOS version:
Install path: fresh / upgrade / clean reinstall
Homebrew version shown for presstalk:
Permissions granted: Microphone / Input Monitoring / Accessibility
English smoke: inserted? latency after release? text:
German smoke: inserted? latency after release? text:
Mixed smoke: inserted? latency after release? text:
Any "Couldn't hear that"?:
Any crash or restart?:
Any stuck HUD, blue A bubble, or input weirdness?:
Notes:
```

## If It Fails

First quit and reopen PressTalk once. If permissions were just granted, reboot
once before deeper debugging.

If it still fails, collect diagnostics:

```bash
/Applications/PressTalk.app/Contents/Resources/presstalk-collect-smoke-status.sh --json > ~/Desktop/presstalk-smoke-status.json
cp ~/Library/Logs/presstalk_trace.log ~/Desktop/presstalk_trace.log
```

Send `~/Desktop/presstalk-smoke-status.json` and
`~/Desktop/presstalk_trace.log`.

Do not repeatedly toggle random permission entries. If System Settings looks
granted but PressTalk reports missing permissions, collect the diagnostics above
and stop.
