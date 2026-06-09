# Apple Silicon Test Checklist

Use this on another Apple Silicon Mac such as:

- M1 Max MacBook Pro
- M4 MacBook Air

## Goal

Verify that a fresh machine can install PressTalk with minimal thinking:

1. install
2. approve permissions if the machine has not already granted PressTalk
3. hold `Option + Space`
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

## ASR Backend Benchmark

The `feature/ane-parakeet-backend` branch includes an isolated benchmark
executable. It does not touch the installed PressTalk app, microphone
permissions, or active-field insertion. It transcribes local audio files and
measures model load time, processing time, finalization time, RTFx, and partial
updates.

Generate repeatable fixtures:

```bash
/bin/bash scripts/make_presstalk_asr_bench_fixtures.sh
```

Build the benchmark:

```bash
swift build -c release --product presstalk-asr-bench
```

Run the warmed-cache ANE baseline:

```bash
./.build/release/presstalk-asr-bench \
  --input /tmp/presstalk-asr-bench/en-30s.aiff \
  --backend parakeet-v3-ane --language en --runs 3 --json
./.build/release/presstalk-asr-bench \
  --input /tmp/presstalk-asr-bench/de-30s.aiff \
  --backend parakeet-v3-ane --language de --runs 3 --json
```

Run true-streaming contenders:

```bash
./.build/release/presstalk-asr-bench \
  --input /tmp/presstalk-asr-bench/en-30s.aiff \
  --backend parakeet-eou-320 --runs 3 --json
./.build/release/presstalk-asr-bench \
  --input /tmp/presstalk-asr-bench/en-30s.aiff \
  --backend nemotron-560 --runs 3 --json
```

The first run for each backend may download and compile CoreML model bundles.
After caches are populated, rerun with `--offline` to ensure no benchmark result
depends on network access:

```bash
./.build/release/presstalk-asr-bench \
  --input /tmp/presstalk-asr-bench/en-30s.aiff \
  --backend parakeet-v3-ane --language en --runs 3 --offline --json
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

To collect host and alias evidence before the release matrix, run. This is
read-only: it records SSH config aliases, Bonjour SSH advertisements, Tailscale
status, ARP table host/IP candidates, target `ssh -G` resolution, and strict
SSH probe results without installing, repairing, trusting host keys, or opening
permission panes.

```bash
/bin/bash scripts/presstalk_host_discovery.sh \
  --targets local,s1,s1.local,mbp1,mbp1-tb,studio1.local,mba1.local \
  --probe-ssh --timeout 3 \
  --json-output "$HOME/Desktop/presstalk-host-discovery.json"
```

When chasing an unresolved host such as `s1`, add `--probe-arp-ssh` to run
read-only `ssh-keyscan` against ARP candidate IPs. This records public SSH host
key fingerprints without editing `known_hosts` and is candidate evidence only.
The JSON also includes fingerprints from the local `known_hosts` file and
attaches `knownHostMatches` to any ARP keyscan fingerprint that already matches
a known host key. A match can identify an existing known machine, but it still
does not promote ARP evidence into release proof.

To collect a matrix that includes local readiness plus SSH host blockers, run:

```bash
/bin/bash scripts/presstalk_readiness_matrix.sh \
  --local --host s1 --host s1.local --host mbp1 --host mbp1-tb \
  --host studio1.local --host mba1.local --timeout 3 \
  --json-output "$HOME/Desktop/presstalk-readiness-matrix.json"
plutil -extract targets raw -o - "$HOME/Desktop/presstalk-readiness-matrix.json"
```

Then run the release proof gate against the required machines. It exits nonzero
until every required target is reachable, physical-STT ready, and active-field
ready. If `s1` means the local `studio1` machine, require `local`; do not also
require an unresolved SSH alias for the same Mac.

```bash
/bin/bash scripts/presstalk_release_proof_gate.sh \
  --matrix "$HOME/Desktop/presstalk-readiness-matrix.json" \
  --require local --require mbp1-tb \
  --exclude "studio2=no attached microphone" \
  --json-output "$HOME/Desktop/presstalk-proof-gate.json"
```

It does not open System Settings or start signing repair. It reports Apple
Silicon eligibility, audio input hardware, installed PressTalk identity, runtime
speech readiness, active-field insertion readiness, latest production insertion
probe, and the next action. If it reports
`MicrophoneHardwareDetected: false`, skip microphone/STT smoke for that machine
until a microphone is attached. Do not include `studio2` / `s2` in the current
STT smoke matrix while it has no attached microphone.

## Install

For the current prerelease smoke artifact:

```bash
tmpdir="$(mktemp -d /tmp/presstalk.XXXXXX)"
curl -L -o "$tmpdir/PressTalk-0.1.5-rc104-macos-arm64.zip" \
  https://github.com/subtract0/presstalk/releases/download/v0.1.5-rc104/PressTalk-0.1.5-rc104-macos-arm64.zip
echo "69d246492b7d38f4adb358021b547f49d8fadda34e365e605bb494b5f888f6b9  $tmpdir/PressTalk-0.1.5-rc104-macos-arm64.zip" | shasum -a 256 -c -
ditto -x -k "$tmpdir/PressTalk-0.1.5-rc104-macos-arm64.zip" "$tmpdir"
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/PressTalk.app"
ditto "$tmpdir/PressTalk.app" "$HOME/Applications/PressTalk.app"
PRESSTALK_OPEN_PERMISSION_PANES=0 PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
  PRESSTALK_TRIGGER_KEY=fn \
  /bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

Expected SHA-256:

```text
69d246492b7d38f4adb358021b547f49d8fadda34e365e605bb494b5f888f6b9
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

To inspect that state without creating or trusting a certificate, signing,
restarting, probing, or opening panes, run the no-prompt preflight first:

```bash
/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-repair-local-signing.sh" --preflight
```

`ExistingSigningIdentity=ready` means repair can reuse a trusted identity.
`ExistingSigningIdentity=untrusted` means the local identity exists but still
needs the logged-in desktop signing trust prompt. `missing` means the repair
will create and trust a new local identity from the logged-in desktop session.

For the `recognized_disabled` input-method state caused by either ad-hoc
signing or an untrusted PressTalk local signing identity, current builds show
`Repair Signing` in the PressTalk menu bar and in Settings. That action runs
the same no-pane repair wrapper and then runs the production insertion probe.
If `--preflight` reports `ExistingSigningIdentity=ready` and
`RepairNeeded=false`, do not rerun signing repair for `recognized_disabled`;
that state is a TIS/input-method enable blocker or an Accessibility insertion
choice, not a signing prompt problem.

For that post-repair state, write the one-time Accessibility handoff command
instead of reopening generic permission panes:

```bash
ssh mbp1-tb '/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-accessibility-handoff.sh" --write-desktop-command'
```

That only writes `~/Desktop/Grant PressTalk Accessibility.command`. It does not
open System Settings, request Accessibility, run insertion, or alter Microphone
or Input Monitoring. The logged-in desktop user double-clicks it, turns on the
existing PressTalk Accessibility entry if PressTalk is already listed but off,
or adds/enables only PressTalk if it is not listed yet. The command then runs
the production insertion probe plus verifier.

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

If you are diagnosing over SSH and need to hand the repair to the logged-in
desktop user without starting a remote trust prompt, write a double-clickable
Desktop command:

```bash
ssh mbp1-tb '/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-repair-local-signing.sh" --write-desktop-command'
```

That command only writes `~/Desktop/Repair PressTalk Signing.command`. It does
not create or trust a certificate, sign or restart PressTalk, run a probe, open
System Settings, or request any privacy approval. The desktop user then
double-clicks it and approves only the PressTalk local signing password prompt
if macOS asks.

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
If it says `adHocSigned=false`, `ExistingSigningIdentity=ready`, and
`inputMethodFallbackStatus=recognized_disabled`, do not run Repair Signing
again; inspect `input_method_enable_no_effect` evidence or use the
Accessibility insertion path.

Runtime status also reports `permissions.inputMethodFallbackStatus`. Expected
values:

- `ready`: the fallback is enabled, has no recent real insertion failure, and is
  worth probing. It does not prove arbitrary real focused text fields.
- `probe_only`: normal dictation will copy instead of selecting the input
  method; real active-field auto-insert requires Accessibility for the exact
  signed PressTalk app.
- `client_unavailable`: the fallback is enabled, but a recent real insertion
  attempt reached the helper and could not attach to the focused text client.
- `ack_timeout`: the fallback is enabled, but the helper did not acknowledge the
  insertion request.
- `recognized_disabled`: macOS sees a select-capable PressTalk source but has
  not enabled it; this is the current mbp1 TIS blocker after signing repair.
- `recognized_not_selectable`, `source_not_recognized`, or `not_installed`:
  collect diagnostics before treating insertion as a runtime/STT failure.

## Runtime Checks

Approve only fresh macOS prompts that are not already granted for the current
PressTalk identity, and only when runtime status says the selected path needs
them:

- Microphone access is required for local STT.
- Accessibility is required for real active-field auto-insert. Without it,
  PressTalk should still transcribe and copy, but helper-window or production
  input-method probes are not release proof for arbitrary focused fields.
- Input Monitoring is required for the default `Fn / Globe` modifier trigger
  because it needs a writable event tap. It is also relevant for bare
  `Option`, trackpad, or legacy trigger paths that report it as required.
  `Option + Space` remains supported as a registered hotkey path.

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
PRESSTALK_TRIGGER_KEY=option_space \
  /bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
```

Karabiner is only needed when testing the optional `F5` fallback path. The
default trigger is `Fn / Globe`, which works when the keyboard emits a normal
Fn modifier event and PressTalk can install a writable event tap. Do not treat
an inert Fn key as a generic permission problem; inspect runtime status and
fall back to `Option + Space` if the hardware path is unavailable.

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
- `option_space`
- `option`
- `left_option`
- `right_option`
- `trackpad_hold`
- `f5`

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
- `status.triggerPath=Option + Space ready`

Then run the bundled manual smoke helper:

```bash
"$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-manual-fn-smoke"
```

The helper opens a focused text window and reads the configured PressTalk
trigger from `runtime-status.json`. Hold that physical trigger, say a short
sentence, then release. It writes a machine-readable result under
`~/Library/Application Support/JarvisTap/Diagnostics/` with the captured text,
expected trigger, runtime readiness before and after the attempt, runtime status,
and trace lines since the helper started. Current helpers also record
`expectedTriggerProof`, `traceExpectedTriggerPressed`,
`traceExpectedTriggerReleased`, `traceExpectedTriggerSources`,
`traceRegisteredHotKeyObserved`, `traceFinalTranscript`, `traceInserted`,
`traceCopyFallback`, `traceInputMethodSelectFailed`, `targetCaptureSuccess`, and
`targetCaptureFailureHint`, so the exact trigger path, STT proof, and
active-field insertion proof are separate. On a machine like the current mbp1
ad-hoc SSH install, `targetCaptureFailureHint=input_method_select_failed` means
the trigger and transcription path may have worked, but macOS refused to select
the InputMethodKit fallback for active-field insertion.

Expected:

- no Apple Dictation popup
- no stray `^P`
- listening light appears
- transcript is inserted into the helper window
- the helper result JSON has `"success": true`
- the helper result JSON has `"expectedTriggerProof": true`
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
text. Use it to debug STT/paste separately from the real Option + Space trigger.

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
contain PressTalk. That is the current mbp1 TIS blocker even after local signing
trust was repaired; do not reopen privacy panes or rerun signing repair for it.

To test the actual running PressTalk app process rather than only the standalone
client probe, run the production insertion probe. It runs PressTalk in normal
no-pane mode, waits for the marker-gated diagnostic notification observer,
opens a focused local helper window, asks PressTalk to insert one payload
through the same production insertion path used after dictation, and writes JSON
diagnostics:

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
- `Option + Space` trigger observed in the trace
- `Transkription abgeschlossen: ...`
- `targetCaptureSuccess: true` in the manual or automated smoke JSON

## Machine Matrix

Record each machine result before claiming release coverage:

- `studio1` / `s1`: M4 Max, local build/runtime and Option + Space smoke
- `s2` / `studio2`: excluded from current microphone/STT coverage until a
  microphone is attached
- `mbp1`: M1 Max install + Option + Space smoke after logged-in signing repair

Attach or paste the output of `presstalk-collect-smoke-status.sh` for each
machine. A successful smoke should show `inputPipelineReady: true`, the trigger
key used, `WhisperKit ready` / `PressTalk armed` in the trace, matching values
in `Status Consistency`, and a completed dictation paste line.
