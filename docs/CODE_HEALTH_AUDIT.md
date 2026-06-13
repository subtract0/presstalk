# PressTalk Code Health Audit

Date: 2026-06-13
Branch: `refactor/skills-code-health-audit`
Baseline: `faa30ba` on `feature/ane-parakeet-backend`
External workflow input: `/Users/am/Code/agent-skills`

## Objective

Make PressTalk simple, legible, and maintainable without breaking the frozen
working product. The target is not fewer lines for its own sake; it is code
that a serious Mac engineer can inspect without needing to reconstruct the
entire history of the project.

## Guardrails

- Do not refactor the frozen product branch directly.
- Preserve runtime behavior exactly unless a bug fix is explicitly scoped.
- Keep each change reviewable; target about 100-300 changed lines unless a
  patch is a pure file move.
- Run focused tests after each slice.
- Require a real Fn/Globe dictation smoke before merging a runtime-affecting
  refactor back toward the product branch.
- Do not reintroduce correction learning, permission-pane churn, Karabiner as
  a default path, or broad ASR model experiments in this code-health branch.

## Skills Applied

From `addyosmani/agent-skills`:

- `code-simplification`: preserve exact behavior, understand before moving,
  simplify one slice at a time.
- `code-review-and-quality`: review on correctness, readability, architecture,
  security, and performance.
- `api-and-interface-design`: define clear module boundaries and make wrong
  state transitions hard.
- `test-driven-development`: add regression guards before changing risky logic.
- `documentation-and-adrs`: document architectural direction before large code
  movement.
- `deprecation-and-migration`: remove legacy behavior only when usage is proven
  absent and migration risk is understood.
- `observability-and-instrumentation`: keep diagnostics useful while avoiding
  dictated-content leakage in new telemetry.

## Current Metrics

Largest files:

- `Sources/JarvisTap/main.swift`: 7,944 lines.
- `Sources/JarvisTap/ProductUI.swift`: 1,525 lines.
- `Sources/PressTalkAsrBench/main.swift`: 1,182 lines.

Main responsibilities currently mixed in `main.swift`:

- app lifecycle and singleton lock
- config loading
- logging
- remote responder
- Codex agent mode
- local conversation memory
- speech synthesis
- setup and permission checks
- menu bar state
- HUD presentation state
- runtime status snapshot writing
- signing and diagnostic helper orchestration
- trigger listeners and event taps
- trackpad hold behavior
- audio input selection
- audio capture lifecycle
- streaming partial transcription
- Parakeet/Whisper final transcription
- transcript cleanup and validation
- pasteboard, Accessibility, and input-method insertion

This is the core debt. The code works, but too many unrelated concepts share
one type and one file.

## Highest-Risk Areas

1. Capture state machine: recent regressions came from recording/processing
   state and stale audio sessions.
2. Insertion transport: macOS Accessibility and paste behavior have many
   false-success paths.
3. Permission/signing identity: repeated permission prompts create user pain.
4. ASR fallback arbitration: quality and latency tradeoffs are subtle.
5. Release scripts: signing, notarization, and Homebrew publishing are high
   blast-radius workflows.

## Target Architecture

The long-term shape should be:

```text
JarvisTapApp
PressTalkStateMachine
TriggerController
AudioCaptureSession
StreamingPartialEngine
FinalTranscriptionEngine
InsertionController
PresentationController
PermissionReadiness
DiagnosticsReporter
SettingsStore
ReleaseToolingScripts
```

This does not need to land as one rewrite. It should land as a sequence of
behavior-preserving extractions, each guarded by tests.

## Refactor Sequence

### Slice 1: Foundation Extraction

Move generic support types out of `main.swift`:

- `String.nonEmpty`
- `TraceLogger`
- `NativeSpeaker`
- shared error/result types
- small transcript candidate type

Risk: low. These are top-level helpers with no behavioral coupling.

Verification:

- `swift build -c release --product jarvistap`
- `bash scripts/test_presstalk_capture_lifecycle_source.sh`
- `bash scripts/test_presstalk_permission_status_labels.sh`
- `git diff --check`

### Slice 2: Config Extraction

Move `JarvisTapConfig` to its own file.

Risk: low-medium because config defaults are product-critical.

Additional guard:

- Add a source/defaults test that asserts Fn default, Parakeet ANE finalizer,
  Parakeet EOU streaming partials, quality fallback enabled, and permission
  panes disabled unless explicitly requested.

### Slice 3: Codex/Responder Extraction

Move remote responder, conversation memory, and Codex agent mode into separate
files. These are not on the normal dictation path but currently distract from
the dictation app.

Risk: medium because process execution and memory persistence have side
effects.

### Slice 4: Insertion Controller

Extract pasteboard, Accessibility, input method, and paste-command logic behind
one `InsertionController`.

Risk: high. Only do after adding focused insertion transport tests and after
preserving current `ax_menu_paste` behavior.

### Slice 5: Capture State Machine

Extract capture session state after the above simplifications. This must be
done last among core runtime slices because it touches the path most likely to
break Fn dictation.

Risk: high. Requires real meatspace proof before merge.

## Non-Goals For This Branch

- No product feature work.
- No new ASR model selection.
- No pricing or launch work.
- No automatic correction learning.
- No wholesale rewrite.
- No hidden behavior change in permission or signing flows.

## Completion Standard

This campaign is not complete until:

- `main.swift` is split into clear modules with stable responsibilities.
- every moved behavior has at least existing or new regression coverage.
- full build and shell test suite pass.
- local app can be rebuilt and bootstrapped without permission panes.
- Alex confirms a real Fn/Globe dictation test after any runtime-affecting
  extraction.
- the refactor branch is merged or deliberately parked with a clean handoff.
