# Release Status

Current fallback release: `v0.1.6-test4`.

- Release commit: `31bc4f6` (`Improve Parakeet quality fallback arbitration`)
- Release repo: `subtract0/presstalk-releases`
- Asset: `PressTalk-0.1.6-test4-macos-arm64.zip`
- SHA-256: `5d8327dc06da388679125aaf831dc35736c67c2d4e9728363b919965296f5161`
- Homebrew tap: `subtract0/presstalk`, cask `presstalk`, tap commit `413da5c`
- Default trigger: `Fn / Globe`
- Default ASR path: Parakeet v3 ANE, streaming disabled, WhisperKit
  large-v3-turbo quality fallback enabled at min confidence `0.96`

Current proof status:

- `studio1` / `s1`: ready locally with `com.am.presstalk`, Fn/Globe trigger,
  microphone authorized, Accessibility trusted, speech model ready, and
  active-field insertion ready through the Accessibility menu-paste path.
- `mbp1`: upgraded to `0.1.6-test4` under `~/Applications`, signed with its
  trusted local PressTalk development identity, bootstrapped to Fn/Globe, and
  readiness reports microphone authorized, Accessibility trusted, speech model
  ready, and active-field insertion ready.
- `mba1`: Alex reported that PressTalk works after restarting its existing
  `0.1.5` install; this is useful user proof but not a current-release install
  proof.
- `studio2` / `s2`: excluded from microphone/STT validation until a microphone
  is attached and Alex explicitly asks for local permission/signing work there.
  It is reachable and has `0.1.6-test4` installed under `~/Applications`, but
  readiness correctly reports no input microphone, ad-hoc signing, missing
  Accessibility trust, and not-determined microphone permission.

The current fallback build is useful and fast, but it is not the final
distribution product yet. True live streaming partial text, notarized signing,
polished first-run permission UX, and a final cross-machine proof gate remain
open productization work.

Latest proof-gate run:

- Time: `2026-06-10T09:56:15Z`
- Host discovery:
  `~/Library/Application Support/JarvisTap/Diagnostics/host-discovery-v0.1.6-test4-proof-refresh-20260610T095615Z.json`
- Matrix:
  `~/Library/Application Support/JarvisTap/Diagnostics/readiness-matrix-v0.1.6-test4-proof-refresh-20260610T095615Z.json`
- Gate:
  `~/Library/Application Support/JarvisTap/Diagnostics/proof-gate-v0.1.6-test4-proof-refresh-20260610T095615Z.json`
- Required targets: `local`, `mbp1-tb`
- Matrix-level excluded targets: `studio2=no attached microphone`
- Result: not proven. `local` / `studio1` passed with Fn/Globe trigger,
  Microphone authorized, Accessibility trusted, speech model ready, and
  active-field insertion ready. `mbp1-tb` failed before readiness collection
  because SSH to `10.77.77.3:22` timed out. The fallback `mbp1` alias at
  `100.106.125.111:22` also timed out; `mba1.local` did not resolve from this
  Mac during the same matrix run. Bonjour still advertised `mbp1` for SSH, and
  the Tailscale CLI failed to start, so treat this as a current network proof
  gap, not evidence of an app regression on mbp1 or mba1.

Current tooling update after that run:

- `scripts/presstalk_readiness_matrix.sh` accepts `--exclude-host HOST=WHY`.
  When an excluded host appears in a broad target list, the matrix records it as
  `status=excluded` and does not SSH into it. Use this for machines that are
  intentionally out of microphone/STT scope, such as `studio2` until Alex opts
  it back in with an attached microphone.
- `scripts/package_presstalk_release.sh` now has an explicit production
  distribution path: `PRESSTALK_DISTRIBUTION_SIGNING=1` requires a Developer ID
  identity, enables hardened runtime and secure timestamping, and
  `PRESSTALK_NOTARIZE=1` submits and staples a notarization ticket before the
  final zip is written. Without that flag, package output remains a
  test/prerelease artifact.
- `scripts/presstalk_release_artifact_audit.sh` audits an existing zip without
  installing it and records bundle metadata, SHA-256, codesign verification,
  Developer ID status, hardened runtime, and stapler validation. Use
  `--require-distribution --require-notarized` for stable production artifacts.
- Runtime status, machine readiness, matrix summaries, and proof-gate JSON now
  carry `asrBackend`, `asrMode`, and `realtimePartialTranscriptionEnabled` so
  release evidence can distinguish the current Parakeet ANE final-pass path from
  future realtime partial or true-streaming ASR backends.
- The app contains opt-in FluidAudio true-streaming backends for
  `PRESSTALK_ASR_BACKEND=parakeet-eou-320` and
  `PRESSTALK_ASR_BACKEND=nemotron-560`. These feed live chunks into the
  streaming manager, update the existing partial transcript path, finalize on
  release, and fall back to local WhisperKit if the streaming candidate is not
  acceptable. They are not the default release path yet.
- A local offline `chirp.wav` check keeps that line firm: `parakeet-eou-320`
  streamed quickly but produced an unusable mixed German transcript. The current
  default `parakeet-v3-ane` produced the accepted transcript in `0.226s` total
  processing, versus `3.508s` for the stock v1 GPU WhisperKit route.
- `scripts/publish_presstalk_homebrew.sh` refuses stable, non-hyphenated
  versions unless both production distribution signing and notarization are
  explicitly enabled. It now also runs `presstalk_release_artifact_audit.sh`
  before upload; stable releases require the audit to prove Developer ID,
  hardened runtime, and stapled notarization. Hyphenated `test` / prerelease
  versions keep the existing smoke-test publishing path.
- `scripts/publish_presstalk_prerelease.sh` also refuses stable-looking,
  non-hyphenated versions unless `PRESSTALK_ALLOW_STABLE_PRERELEASE_TAG=1` is
  deliberately set, so smoke artifacts cannot accidentally occupy stable
  version tags. It now runs the artifact audit before upload too, without
  production signing requirements, to catch wrong bundle id, wrong version, or
  broken code-signing artifacts.
- Both publish scripts support `PRESSTALK_PUBLISH_DRY_RUN=1`, which packages
  and audits the artifact but exits before any GitHub release or Homebrew tap
  write. `PRESSTALK_DIST_DIR=/path/to/dist` can isolate generated zips,
  checksums, and audit JSON for local preflight tests.
- `scripts/presstalk_release_readiness_preflight.sh` combines an artifact audit
  JSON and proof-gate JSON into one readiness verdict. Default mode can pass for
  an audited test artifact with proven machine smoke coverage; `--require-production`
  requires Developer ID, hardened runtime, stapled notarization, proven machine
  coverage, and the expected `parakeet_v3_ane_final_pass` ASR mode on every
  proof target.
- Stable `scripts/publish_presstalk_homebrew.sh` now refuses to publish unless
  `PRESSTALK_RELEASE_PROOF_GATE_JSON` points at a proof-gate JSON, then runs the
  readiness preflight with `--require-production` before any GitHub release or
  Homebrew tap write. Prerelease publishers can opt into the same combined
  check with `PRESSTALK_REQUIRE_RELEASE_READINESS=1`.

Historical status: local `main` previously proved Option+Space real-field
dictation and active-field insertion on the eligible machines `studio1` / `s1`
and `mbp1` using the Accessibility menu-paste path. Older notes below preserve
that evidence trail.

Streaming feature branch:

- `feature/streaming-whisper-tail` is separate from the frozen `main` /
  `v0.1.5-rc104` direct-distribution baseline. It starts a PressTalk-owned
  realtime Whisper loop on the existing preferred microphone path, waits after
  release for `0.10 s` of silence or up to `0.50 s`, and accepts realtime text
  as final only when the streaming snapshot is fresh and within `0.65 s` of the
  frozen audio. Offline Whisper remains the fallback.
- On `studio1` / M4 Max with the Shure MV7i, a `27.3 s` German dictation used
  the realtime final path and inserted through `ax_menu_paste` about `1.59 s`
  after release. The trace logged `Realtime release pass lag ... 0.30`,
  `Using realtime Whisper streaming transcript as final transcript`, and
  `Dictation inserted method=ax_menu_paste`.
- This branch still runs WhisperKit with `cpu-gpu-no-ane`; the ANE/NPU path
  remains a separate backend track aimed at base M-series customer machines
  such as MacBook Air.

Latest local evidence:

- After Accessibility was granted for the exact signed `com.am.presstalk` app,
  a real-field test still failed because direct AX insertion returned success
  without visible text. Three attempts saying "A short phrase" were transcribed
  correctly, but the trace logged `Dictation inserted method=ax_selected_text`.
  Local `main` now avoids that false-success path for normal dictation: it sets
  the clipboard, presses the focused app's Paste menu item through
  Accessibility, and falls back to synthesized Cmd+V only if menu paste is
  unavailable.
- The fresh `studio1` production insertion probe at
  `~/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-09T12-37-30-590Z.json`
  reports `success=true`, `targetCaptureSuccess=true`, and
  `traceProductionMethod=ax_menu_paste`. The verifier exits `0` with
  `Result: proven` for this menu-paste path.
- On 2026-06-09 at 12:45 local time, Alex focused a real text field on
  `studio1`, held Option+Space, said "A short phrase", released, and reported
  that it auto-inserted correctly without Cmd+V. The trace confirms the same
  run: `Primary offline Whisper transcript: A short phrase.`,
  `Paste menu pressed target_pid=39451`, and
  `Dictation inserted method=ax_menu_paste`. This closes the local insertion
  transport blocker for the current signed app.
- On 2026-06-09 at 13:11 UTC, Alex focused a ZSH terminal text field on `mbp1`,
  held Option+Space, said "I'm gonna test what is going to happen if I say a
  short phrase", released, and reported that it auto-inserted correctly. The
  trace confirms the end-to-end run using `MacBook Pro-Mikrofon`, with
  `Primary offline Whisper transcript: I'm gonna test what is gonna happen if I
  say a short phrase.`, `Paste menu pressed target_pid=1231`, and
  `Dictation inserted method=ax_menu_paste`.
- On 2026-06-09, Alex focused a real text field on `studio1`, held
  Option+Space, said "Does it work now?" three times, and released each time.
  PressTalk heard the trigger, selected the Shure/MV7 audio input, transcribed
  the phrase correctly, copied it to the clipboard, and then failed direct
  input-method insertion with `no_active_controller` on each attempt. This
  proves the current blocker is real-field insertion transport, not microphone,
  STT, trigger registration, or clipboard fallback.
- Normal dictation now treats the bundled input method as `probe_only` unless
  launched with `PRESSTALK_ENABLE_EXPERIMENTAL_INPUT_METHOD_DICTATION=1`.
  Runtime active-field readiness requires Accessibility for the exact signed
  PressTalk app; helper-window or production-probe
  `input_method_notification` success is no longer release proof for arbitrary
  focused text fields.

Previous direct prerelease smoke artifact:

- Tag: `v0.1.5-rc104`
- Commit: `827f274c6a464c3bc073b4f7c63217974a3f98e6`
- URL: `https://github.com/subtract0/presstalk/releases/tag/v0.1.5-rc104`
- Asset: `PressTalk-0.1.5-rc104-macos-arm64.zip`
- SHA-256: `69d246492b7d38f4adb358021b547f49d8fadda34e365e605bb494b5f888f6b9`

Verified during 2026-06-06 through 2026-06-09:

- `v0.1.5-rc104` is the previous direct prerelease smoke artifact. It includes
  the `ax_menu_paste` trusted insertion path proven by the 2026-06-09 real-field
  Option+Space test on `studio1`, isolated release packaging so publishing no
  longer overwrites the live local app in `~/Applications/PressTalk.app`, and a
  self-healing Accessibility desktop command that falls back to the current
  user's `~/Applications/PressTalk.app` when a stale command contains another
  user's home directory. GitHub reports asset digest
  `sha256:69d246492b7d38f4adb358021b547f49d8fadda34e365e605bb494b5f888f6b9`,
  matching the local `dist/PressTalk-0.1.5-rc104-macos-arm64.zip`, and the tag
  points at `827f274c6a464c3bc073b4f7c63217974a3f98e6`.
- `v0.1.5-rc104` was installed on `mbp1` from the GitHub release artifact with
  SHA-256 verified. Bootstrap used the existing trusted local signing identity
  without opening permission panes, and the refreshed runtime reports
  `CodeSignatureCDHash=dc881cde2820913f3dd14ede322d94c977a9f31f`,
  `AccessibilityStatus=ax_trusted`, `ActiveFieldInsertionStatus=ready_accessibility`,
  `InputMethodFallbackStatus=probe_only`, `InputListener=carbon:registered`,
  and `SpeechModel=Ready`.
- The `mbp1` production insertion probe at
  `/Users/alexandermonas/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-09T13-08-24-985Z.json`
  reports `success=true`, `targetCaptureSuccess=true`, and
  `traceProductionMethod=ax_menu_paste`. The verifier reports `Result: proven`.
  The refreshed `mbp1` readiness artifact is
  `/Users/alexandermonas/Desktop/presstalk-readiness-mbp1-rc104.json`.
- The local plus `mbp1-tb` proof gate at
  `~/Desktop/presstalk-proof-gate-local-mbp1-rc104.json` reports
  `Result: proven`. The full matrix at
  `~/Desktop/presstalk-readiness-matrix-after-mbp1-rc104.json` still records
  that SSH host aliases `s1` / `s1.local` do not resolve from `studio1`, but
  this is not a separate app proof blocker while `s1` means the local
  `studio1` machine already covered by the `local` target.
- `v0.1.5-rc103` is the previous public prerelease smoke artifact. It includes
  the `ax_menu_paste` trusted insertion path and isolated release packaging, but
  it predates the self-healing Accessibility desktop command.
- Local source commit `3d95bb7` uses Accessibility to press the focused app's
  Paste menu item for trusted insertion, with targeted Cmd+V and direct AX text
  writes only as backups. The latest local readiness report at
  `~/Desktop/presstalk-readiness-local-after-ax-menu-paste.json` reports
  `PhysicalSTTSmokeReady=true` and `ActiveFieldSmokeReady=true`. The matching
  readiness matrix at
  `~/Desktop/presstalk-readiness-matrix-after-ax-menu-paste.json` reports local
  ready, `s1` / `s1.local` unresolved, `mbp1-tb` reachable but
  `active=false`, and `studio2` excluded until a microphone is attached.
- `v0.1.5-rc102` is the previous public prerelease smoke artifact. It handles the
  terminal/text-field blue input-source badge failure by making the input-method
  helper write an acknowledgement failure reason (`no_active_controller` or
  `no_current_client`) and making the main app record recent real insertion
  failures as `inputMethodFallbackStatus=client_unavailable` or `ack_timeout`
  instead of continuing to report `ready_input_method`. Normal dictation copies
  during the cooldown instead of repeatedly selecting the input source;
  production insertion probes can still force a retry and clear the degraded
  state on success. The `v0.1.5-rc102` GitHub release is a prerelease; GitHub
  reports asset digest
  `sha256:1112931886fc9c167fed623b1827c1e09c47773da4c10d55f49d2fe6fef3d514`,
  matching the local `dist/PressTalk-0.1.5-rc102-macos-arm64.zip`, and the tag
  points at `be2088c0623e5b0c5ba0342a1907924b77f013bd`. After rc102 packaging,
  `studio1` was restored to stable local signing and no-pane launch. The current
  installed app reports
  `CodeSignatureCDHash=06aa6b30c8386937189bb69bbe29f28d2515bd9b`,
  `inputListener=carbon:registered`, `triggerPath=Option + Space ready`,
  `speechModel=Ready`, and `inputMethodFallbackStatus=ready` before a new real
  failure. The fresh production insertion probe at
  `~/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-09T10-36-55-843Z.json`
  reports `success=true`, `targetCaptureSuccess=true`, and
  `traceProductionMethod=input_method_notification`; it required IMK retries and
  succeeded on attempt 3.
- `swift build -c release` succeeds.
- `scripts/build_jarvistap.sh` produces `~/Applications/PressTalk.app`.
- The generated bundle declares microphone, input monitoring, and accessibility usage descriptions.
- `scripts/install_jarvistap_launchd.sh` now defaults to `PRESSTALK_TRIGGER_KEY=option_space`.
- Current studio1 manual trigger triage: physical F5/Mic generated
  `systemDefined subtype=7 mediaKeyCode=0` debug events and system beeps but no
  PressTalk capture because the app was configured for Fn; physical Fn did not
  emit the expected modifier event in the trace. Bare Option also hit the
  writable event-tap blocker on studio1. The current direct portability route is
  `Option + Space`, backed by a registered macOS hotkey; keep bare Option/Fn as
  advanced modifier-only triggers and F5/Mic as a legacy fallback.
- `v0.1.5-rc101` is the previous public prerelease smoke artifact. It kept the
  `Option + Space` registered-hotkey route and the Accessibility handoff helper,
  and detected a disabled Accessibility TCC row for PressTalk. For the
  current mbp1 state, machine readiness and smoke-status diagnostics report
  `AccessibilityTCCAuthValue=0` / `accessibilityTCC=listed_disabled` and say
  that PressTalk is already listed in Accessibility but disabled. The refreshed
  Desktop command tells the user to turn on the existing PressTalk entry only,
  then run the insertion probe and verifier. Ad-hoc `recognized_disabled`
  remains on the no-pane Repair Signing path. The app and bundled diagnostics
  still avoid another Microphone, Input Monitoring, signing repair, Karabiner,
  or generic privacy-pane pass for the mbp1 post-repair state.
- The `v0.1.5-rc101` GitHub release was verified as a prerelease. GitHub
  reports asset digest
  `sha256:74d8d41c100a969b0e56478be81c6ea16ef9cbb22f29ead21df721164ea2ecd8`,
  matching the local `dist/PressTalk-0.1.5-rc101-macos-arm64.zip`. The
  `v0.1.5-rc101` tag points at
  `1fd04bcac4c943affd7a62fc0bc3f055505b8f1f`.
- After rc101 packaging, `studio1` was restored to stable local signing and
  no-pane launch. The current installed app reports
  `CodeSignatureCDHash=af7338c6766e2c46eb5e159461d6e01cf2682c1e`,
  `inputListener=carbon:registered`, `triggerPath=Option + Space ready`,
  `speechModel=Ready`, and `activeFieldInsertionStatus=ready_input_method`.
  The fresh production insertion probe at
  `~/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-08T01-39-03-152Z.json`
  reports `success=true`, `targetCaptureSuccess=true`, and
  `traceProductionMethod=input_method_notification`.
- The rc101 candidate was also installed on `mbp1` with no-pane bootstrap and
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING=existing`. It reused the existing mbp1
  PressTalk local signing identity and reports
  `CodeSignatureCDHash=1d390b547be5f3fd593bc82e8a7d7937592e56e8`,
  `inputListener=carbon:registered`, `triggerPath=Option + Space ready`,
  `speechModel=Ready`, `activeFieldInsertionStatus=blocked_recognized_disabled`,
  `inputMethodFallbackStatus=recognized_disabled`, and
  `AccessibilityTCCAuthValue=0`. The refreshed desktop command at
  `/Users/alexandermonas/Desktop/Grant PressTalk Accessibility.command` is the
  next meatspace step: turn on the existing PressTalk Accessibility entry only.
- The fresh rc101 readiness matrix at
  `~/Library/Application Support/JarvisTap/Diagnostics/readiness-matrix-rc101-local-mbp1-20260608T013913Z.json`
  required `local` and `mbp1-tb` and excluded `studio2=no_attached_microphone`.
  The matching proof gate at
  `~/Library/Application Support/JarvisTap/Diagnostics/proof-gate-rc101-local-mbp1-20260608T013913Z.json`
  remains `proven=false` with one failure:
  `mbp1-tb active_field_not_ready`.
- `v0.1.5-rc100` is the previous public prerelease smoke artifact. It added
  direct handoff-command guidance, but it did not detect and name the disabled
  Accessibility TCC row now visible on mbp1.
- `v0.1.5-rc99` is an older public prerelease smoke artifact. It added the
  Accessibility handoff helper, but its post-repair diagnostics still needed
  the direct handoff-command guidance added in rc100. `v0.1.5-rc98` fixed the
  trusted-local-signing diagnostic loop, but it did not include the
  Accessibility handoff helper.
- On mbp1, no-prompt preflight for the rc99 candidate reports
  `AccessibilityTrusted=false` for the exact installed `com.am.presstalk` app,
  `CodeSignatureCDHash=54fad20b0c5c406be99e2b83f14205298a44e469`,
  `activeFieldInsertionStatus=blocked_recognized_disabled`, and
  `inputMethodFallbackStatus=recognized_disabled`. It also wrote
  `~/Desktop/Grant PressTalk Accessibility.command` without opening System
  Settings; that command is the next meatspace step for proving the
  Accessibility insertion fallback on mbp1.
- The same candidate's latest `studio1` insertion probe at
  `~/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-08T01-08-50-764Z.json`
  reports `success=true`, `targetCaptureSuccess=true`,
  `CodeSignatureCDHash=feeabc565c8e465747ad60245064d3f5d304df2a`, and
  `traceProductionMethod=input_method_notification`. The latest mbp1 probe at
  `~/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-08T01-05-55-869Z.json`
  still reports `success=false`,
  `targetCaptureFailureHint=input_method_enable_no_effect`, and
  `traceProductionFailure=accessibility_preflight_unavailable`.
- The fresh rc99 readiness matrix at
  `~/Library/Application Support/JarvisTap/Diagnostics/readiness-matrix-rc99-local-mbp1-20260608T010903Z.json`
  required `local` and `mbp1-tb` and excluded `studio2=no_attached_microphone`.
  The matching proof gate at
  `~/Library/Application Support/JarvisTap/Diagnostics/proof-gate-rc99-local-mbp1-20260608T010903Z.json`
  remains `proven=false` with one failure:
  `mbp1-tb active_field_not_ready`.
- The latest rc97 marker-gated production insertion probe on `studio1`
  reported `success=true`, `targetCaptureSuccess=true`, and
  `traceProductionMethod=input_method_notification` at
  `~/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-08T00-26-18-648Z.json`.
  It inserted on input-method attempt 1 while preserving the running app
  `CodeSignatureCDHash=6223f47dc419a75d6fd07e0354d56301f83279fa`.
- After rc97 packaging, `studio1` was restored with the public
  `com.am.presstalk` identity, no-pane flags, and
  `PRESSTALK_TRIGGER_KEY=option_space`. The current readiness report shows
  `MicrophoneAuthorizationStatus=authorized`, `inputListener=carbon:registered`,
  `speechModel=Ready`, `activeFieldInsertionStatus=ready_input_method`,
  `InputMethodFallbackStatus=ready`,
  `AccessibilityStatus=ax_false_input_method_fallback_ready`, and trigger path
  `Option + Space ready`.
- The latest studio1 manual physical `Option + Space` smoke at
  `~/Library/Application Support/JarvisTap/Diagnostics/manual-trigger-smoke-2026-06-07T23-11-42.644Z.json`
  reported `success=true`, `expectedTriggerProof=true`,
  `targetCaptureSuccess=true`, and `traceFinalTranscript="Das ist ein..."`.
  That artifact was generated before the rc91 helper parser fix, so its
  `traceRegisteredHotKeyObserved=false` field is stale; the trace contains the
  actual `Option + Space` pressed/released lines and rc91 classifies those as
  registered-hotkey evidence in future manual-smoke JSON.
- After the logged-in desktop repair command was approved on `mbp1`, the
  current unreleased candidate was copied over `mbp1-tb` and bootstrapped with
  no-pane flags plus stable local signing. The signed app reports
  `CodeSignatureAuthority=PressTalk Local Development Code Signing`,
  `CodeSignatureCDHash=aebf72503e121385ff1b1f47b5a7a22bce3d0c2c`,
  `triggerPath=Option + Space ready`, `inputListener=carbon:registered`,
  `speechModel=Ready`, and `microphoneAuthorizationStatus=authorized`.
  The repair preflight now correctly reports `RepairNeeded=false`,
  `SigningTrustPromptNeeded=false`, and `ExistingSigningIdentity=ready`.
- `mbp1` active-field insertion is still not proven, but the blocker is now
  classified correctly as TIS/input-method enable no-effect rather than signing
  repair. Runtime reports `activeFieldInsertionStatus=blocked_recognized_disabled`,
  `inputMethodFallbackStatus=recognized_disabled`, and `AdHocSigned=false`.
  The fresh production insertion probe at
  `~/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-08T00-47-10-218Z.json`
  reports `success=false`, `targetCaptureFailureHint=input_method_enable_no_effect`,
  `traceInputMethodEnableNoEffect=true`, and
  `traceInputMethodFailure="enable_no_effect status=-50"`.
- A second reversible mbp1 HIToolbox test added PressTalk to
  `AppleEnabledInputSources`, flushed `cfprefsd`, `TextInputMenuAgent`,
  `keyboardservicesd`, and `imklaunchagent`, then reran
  `TISRegisterInputSource`/`TISEnableInputSource`. TIS still returned
  `enableStatus=0` plus `enableNoEffect=true`; the backup at
  `~/Library/Application Support/JarvisTap/Diagnostics/hitoolbox-before-presstalk-enabled-test-20260608T003922Z.plist`
  was restored. Do not add a HIToolbox plist repair helper for this state.
- The current rebuilt `studio1` app remains green after the diagnostic fix:
  `CodeSignatureCDHash=7dea8d78fd7d9fed386605fec0e0e51191b4b77f`,
  `activeFieldInsertionStatus=ready_input_method`, and the production insertion
  probe at
  `~/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-08T00-53-45-223Z.json`
  reports `success=true`, `targetCaptureSuccess=true`, and
  `traceProductionMethod=input_method_notification`.
- The fresh rc98 readiness matrix at
  `~/Library/Application Support/JarvisTap/Diagnostics/readiness-matrix-rc98-local-mbp1-20260608T005356Z.json`
  required `local` and `mbp1-tb` and excluded `studio2=no_attached_microphone`.
  The matching proof gate at
  `~/Library/Application Support/JarvisTap/Diagnostics/proof-gate-rc98-local-mbp1-20260608T005356Z.json`
  remains `proven=false` with one failure:
  `mbp1-tb active_field_not_ready`. `mbp1` is reachable and
  `physicalSTTSmokeReady=true`; only active-field insertion is blocked.
- The latest rc97 readiness matrix at
  `~/Library/Application Support/JarvisTap/Diagnostics/readiness-matrix-rc97-local-mbp1-20260608T002634Z.json`
  required `local` and `mbp1-tb` and excluded `studio2` because it has no
  attached microphone. It reports `local` as ready for physical dictation smoke
  and active-field smoke, while `mbp1-tb` is reachable with speech ready but
  `activeFieldSmokeReady=false`. The matching rc97 proof gate at
  `~/Library/Application Support/JarvisTap/Diagnostics/proof-gate-rc97-local-mbp1-20260608T002634Z.json`
  is still `proven=false` with `failureCount=1`, failing only `mbp1-tb` for
  `active_field_not_ready`.
- `v0.1.5-rc90` was superseded by rc91 after proving that the Settings/menu
  manual-smoke launch path could still silently exit through detached `nohup`.
  rc90 remains the insertion-retry baseline: if the first input-method
  notification times out, production insertion reselects the original input
  source and PressTalk source before retrying, for up to three attempts.
- `v0.1.5-rc89` was superseded by rc90 before mbp1 rollout because production
  insertion retry handling advanced again after rc89 packaging.
- `v0.1.5-rc88` was the previous public prerelease smoke artifact. It includes
  the rc87 compiled manual physical-smoke helper and adds explicit cancellation
  evidence: closing the helper window before completion writes a `window_closed`
  manual-smoke JSON instead of leaving no artifact.
- `v0.1.5-rc87` was the previous public prerelease smoke artifact. It includes the
  rc86 input-method insertion hardening and replaces the fragile background
  `swift presstalk-manual-fn-smoke.swift` launcher with a compiled
  `presstalk-manual-fn-smoke` helper in the app bundle. Settings and the menu
  bar now prefer the compiled helper and keep the Swift source only as a
  fallback. The compiled helper was verified in detached `nohup` mode with a
  short timeout: it wrote the expected manual-smoke JSON instead of silently
  exiting.
- The `v0.1.5-rc87` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:646456f11afd8886cce7bb18d3b68385c19db703bef23e6c81b54f5f571f08b3`,
  matching the local `dist/PressTalk-0.1.5-rc87-macos-arm64.zip`. The
  `v0.1.5-rc87` tag points at
  `5fc4831316bc599ad41046a0455214dd09994d19`.
- After rc87 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and
  `PRESSTALK_TRIGGER_KEY=option_space`. The final restored readiness report
  shows `CodeSignatureCDHash=c9bf7264ab344b1022cda0d077fd70d9c21b83f3`,
  `inputListener=carbon:registered`, `speechModel=Ready`,
  `activeFieldInsertionStatus=ready_input_method`, and trigger path
  `Option + Space ready`.
- The latest rc87 current-signed-app production insertion probe on `studio1`
  reported `success=true`, `targetCaptureSuccess=true`, and
  `traceProductionMethod=input_method_notification` at
  `~/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-07T22-36-23-689Z.json`.
  Its trace includes
  `Input method insertion acknowledgement inserted=1 attempt=1` before
  `Production insertion probe inserted`; the same final readiness report still
  shows `latestManualPhysicalTriggerSmoke.path=none`, so physical
  `Option + Space` STT/paste proof remains the studio1 blocker.
- `mbp1` was updated from the public rc87 artifact over `mbp1-tb` with the
  expected SHA and no-pane bootstrap flags. It reports
  `triggerPath=Option + Space ready`, `inputListener=carbon:registered`,
  `speechModel=Ready`, and `microphoneAuthorizationStatus=authorized`.
  Active-field insertion is still blocked by signing repair:
  `activeFieldInsertionStatus=needs_signing_repair`,
  `inputMethodFallbackStatus=recognized_disabled`, and `AdHocSigned=true`.
  The rc87 bootstrap reused only existing signing state, skipped stable signing
  because the existing PressTalk local identity is still untrusted, did not open
  System Settings, and did not start a signing trust prompt.
- The latest rc87 readiness matrix at
  `~/Library/Application Support/JarvisTap/Diagnostics/readiness-matrix-rc87-mbp1-updated-20260607T223718Z.json`
  required `local` and `mbp1-tb`. It reports `local` as ready for physical
  dictation smoke and `mbp1-tb` as reachable with speech ready but
  `activeFieldSmokeReady=false`. The matching rc87 proof gate at
  `~/Library/Application Support/JarvisTap/Diagnostics/proof-gate-rc87-mbp1-updated-20260607T223718Z.json`
  is still `proven=false` with `failureCount=1`, failing only `mbp1-tb` for
  `active_field_not_ready`.
- `v0.1.5-rc86` was the previous public prerelease smoke artifact. It includes the
  rc85 `Run Physical Smoke` launcher in Settings and the menu bar, the
  acknowledgement-gated input-method insertion path, and the rc86 hardening for
  app updates: bootstrap restarts the per-user InputMethodKit launch agent after
  refreshing `PressTalkInputMethod.app`, and the production insertion path
  retries once after the first input-method acknowledgement timeout by restoring
  and reselecting the input source before posting the insert notification again.
- The `v0.1.5-rc86` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:eb92d4de449f81fdbcad6c9342c190f16c91c202243ef37c68b3a98cd266bafb`,
  matching the local `dist/PressTalk-0.1.5-rc86-macos-arm64.zip`. The
  `v0.1.5-rc86` tag points at
  `2e32c92d0b063529731f5de1e96a21543a64c7f5`.
- After rc86 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and
  `PRESSTALK_TRIGGER_KEY=option_space`. The final restored readiness report
  shows `CodeSignatureCDHash=94881acaf5fdce259e8e7bef8fe417cc4785443c`,
  `inputListener=carbon:registered`, `speechModel=Ready`,
  `activeFieldInsertionStatus=ready_input_method`, and trigger path
  `Option + Space ready`.
- The latest rc86 current-signed-app production insertion probe on `studio1`
  reported `success=true`, `targetCaptureSuccess=true`, and
  `traceProductionMethod=input_method_notification` at
  `~/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-07T22-22-37-019Z.json`.
  Its trace includes
  `Input method insertion acknowledgement inserted=1 attempt=1` before
  `Production insertion probe inserted`; the same final readiness report still
  shows `latestManualPhysicalTriggerSmoke.path=none`, so physical
  `Option + Space` STT/paste proof remains the studio1 blocker.
- `mbp1` was updated from the public rc86 artifact over `mbp1-tb` with the
  expected SHA and no-pane bootstrap flags. It reports
  `triggerPath=Option + Space ready`, `inputListener=carbon:registered`,
  `speechModel=Ready`, and `microphoneAuthorizationStatus=authorized`.
  Active-field insertion is still blocked by signing repair:
  `activeFieldInsertionStatus=needs_signing_repair`,
  `inputMethodFallbackStatus=recognized_disabled`, and `AdHocSigned=true`.
  The rc86 bootstrap reused only existing signing state, skipped stable signing
  because the existing PressTalk local identity is still untrusted, did not open
  System Settings, and did not start a signing trust prompt.
- The latest rc86 readiness matrix at
  `~/Library/Application Support/JarvisTap/Diagnostics/readiness-matrix-rc86-mbp1-updated-20260607T222358Z.json`
  required `local` and `mbp1-tb`. It reports `local` as ready for physical
  dictation smoke and `mbp1-tb` as reachable with speech ready but
  `activeFieldSmokeReady=false`. The matching rc86 proof gate at
  `~/Library/Application Support/JarvisTap/Diagnostics/proof-gate-rc86-mbp1-updated-20260607T222358Z.json`
  is still `proven=false` with `failureCount=1`, failing only `mbp1-tb` for
  `active_field_not_ready`.
- `v0.1.5-rc84` was the previous public prerelease smoke artifact. It includes the
  `Option + Space` registered-hotkey default, the rc83 manual physical-trigger
  smoke proof fields, Settings copy that presents ready trigger/insertion paths
  as capabilities instead of missing permissions, and input-method insertion
  acknowledgement before PressTalk reports production insertion success.
- The `v0.1.5-rc84` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:f296e054d6362026adab3bf4dd10ab339cebce35494fc8933db53119b40ebdc0`,
  matching the local `dist/PressTalk-0.1.5-rc84-macos-arm64.zip`. The
  `v0.1.5-rc84` tag points at
  `2f53f1a93cdbda025c85c3c635aae79402e7c053`.
- After rc84 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and
  `PRESSTALK_TRIGGER_KEY=option_space`. The restored runtime reports
  `inputListener=carbon:registered`,
  `inputMonitoringStatus=registered_hotkey_ready`, `speechModel=Ready`,
  `activeFieldInsertionStatus=ready_input_method`, and trigger path
  `Option + Space ready`.
- The rc84 current-signed-app production insertion probe on `studio1`
  reported `success=true`, `targetCaptureSuccess=true`, and
  `traceProductionMethod=input_method_notification` at
  `~/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-07T21-52-46-956Z.json`.
  Its trace includes `Input method insertion acknowledgement inserted=1` before
  `Production insertion probe inserted`, so this proof is stronger than a
  notification-post trace alone. The same readiness report still shows
  `latestManualPhysicalTriggerSmoke.path=none`; physical `Option + Space`
  STT/paste proof remains the studio1 blocker.
- The rc84 readiness matrix at
  `~/Library/Application Support/JarvisTap/Diagnostics/readiness-matrix-rc84-mbp1-updated-20260607T215824Z.json`
  required `local` and `mbp1-tb`. It reports `local` as ready for physical
  dictation smoke and `mbp1-tb` as reachable with speech ready but
  `activeFieldSmokeReady=false`. The matching rc84 proof gate at
  `~/Library/Application Support/JarvisTap/Diagnostics/proof-gate-rc84-mbp1-updated-20260607T215824Z.json`
  is still `proven=false` with `failureCount=1`, failing only `mbp1-tb` for
  `active_field_not_ready`.
- `mbp1` was updated from the public rc84 artifact over `mbp1-tb` with the
  expected SHA and no-pane bootstrap flags. It now reports
  `triggerPath=Option + Space ready`, `inputListener=carbon:registered`,
  `speechModel=Ready`, and `microphoneAuthorizationStatus=authorized`.
  Active-field insertion is still blocked by signing repair:
  `activeFieldInsertionStatus=needs_signing_repair`,
  `inputMethodFallbackStatus=recognized_disabled`, and `AdHocSigned=true`.
  The rc84 repair preflight reports `RunningOverSSH=true`,
  `RepairAllowedHere=false`, `SigningTrustPromptNeeded=true`, and
  `ExistingSigningIdentity=untrusted` with hash
  `2EA0B09365E72779413B98BA6319E5D9FBA09205`; it did not start a trust prompt,
  sign or restart PressTalk, run an insertion probe, or open System Settings.
- `v0.1.5-rc83` added the
  `Option + Space` registered-hotkey default, manual physical-trigger smoke
  `smokeVersion=4` with `expectedTriggerProof`, and readiness/smoke collectors
  that surface the latest manual physical-trigger JSON separately from production
  insertion proof.
- The `v0.1.5-rc83` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:2605a87a945e2811b61a242fe35b0394466f8599eec0f84f42b6ed8772d4ddad`,
  matching the local `dist/PressTalk-0.1.5-rc83-macos-arm64.zip`. The
  `v0.1.5-rc83` tag points at
  `94ed53823fcceb4e55d6e035f50df2b5b3e3607c`.
- After rc83 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and
  `PRESSTALK_TRIGGER_KEY=option_space`. The restored runtime reports
  `inputListener=carbon:registered`,
  `inputMonitoringStatus=registered_hotkey_ready`, `speechModel=Ready`,
  `activeFieldInsertionStatus=ready_input_method`, and trigger path
  `Option + Space ready`.
- The rc83 current-signed-app production insertion probe on `studio1` reported
  `success=true`, `targetCaptureSuccess=true`, and
  `traceProductionMethod=input_method_notification` at
  `~/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-07T21-31-27-808Z.json`.
  The same readiness report still shows
  `latestManualPhysicalTriggerSmoke.path=none`; physical `Option + Space`
  STT/paste proof remains the studio1 blocker.
- The rc83 readiness matrix at
  `~/Library/Application Support/JarvisTap/Diagnostics/readiness-matrix-rc83-20260607T213316Z.json`
  required `local` and `mbp1-tb`. It reports `local` as ready for physical
  dictation smoke and `mbp1-tb` as reachable with speech ready but
  `activeFieldSmokeReady=false`. The matching rc83 proof gate at
  `~/Library/Application Support/JarvisTap/Diagnostics/proof-gate-rc83-20260607T213327Z.json`
  is still `proven=false` with `failureCount=1`, failing only `mbp1-tb` for
  `active_field_not_ready`.
- `v0.1.5-rc82` adds read-only `known_hosts` fingerprint matching to the
  bundled host-discovery helper. The helper now records local known-host
  fingerprints and adds `knownHostMatches` to scanned ARP fingerprints that
  match an already-known host key. This is still candidate-discovery evidence
  only; it does not edit `known_hosts`, trust host keys, or promote ARP evidence
  into release proof.
- The `v0.1.5-rc82` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:5351a14a91bef8ed370f9f23a5a2000ac0f4c2876e9cc9d0428226dd433bd727`,
  matching the local `dist/PressTalk-0.1.5-rc82-macos-arm64.zip`. The
  `v0.1.5-rc82` tag points at
  `f6f327048bc32888d230d18863f4b71baa8cf5f2`.
- After rc82 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The restored
  bundle reports CDHash `ed0ec70f6348fe947a141f9ee74db8c76dcca3b8`,
  `speechModel=Ready`, `inputPipelineReady=true`,
  `microphoneAuthorizationStatus=authorized`, `inputMonitoringEffective=true`,
  `activeFieldInsertionReady=true`, and
  `activeFieldInsertionStatus=ready_input_method`.
- `v0.1.5-rc81` adds optional read-only ARP SSH keyscan evidence to the bundled
  host-discovery helper. It only runs when `--probe-arp-ssh` is passed, records
  public host-key fingerprints for ARP candidate IPs, and does not edit
  `known_hosts`.
- The `v0.1.5-rc81` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:4e840296917987777316d743d57b521c2b7df7c4997f873599cc39f0700ca6b4`,
  matching the local `dist/PressTalk-0.1.5-rc81-macos-arm64.zip`. The
  `v0.1.5-rc81` tag points at
  `9a9d2121625ae7407c04fdcadc393d3adeed92e7`.
- After rc81 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The restored
  bundle reports CDHash `b5aa21d404a94156cc98cd5ecb8b3cb928b54036`,
  `speechModel=Ready`, `inputPipelineReady=true`,
  `microphoneAuthorizationStatus=authorized`, `inputMonitoringEffective=true`,
  `activeFieldInsertionReady=true`, and
  `activeFieldInsertionStatus=ready_input_method`.
- `v0.1.5-rc80` adds read-only ARP table collection to the bundled
  host-discovery helper. ARP collection is enabled by default, can be skipped
  with `--no-arp`, and records local host/IP candidates as discovery evidence
  only, not proof of a machine identity.
- The `v0.1.5-rc80` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:1978179eb683e5443b7625b3b1087bd9c7e8de6b565782bf04eda40e6e9fbc22`,
  matching the local `dist/PressTalk-0.1.5-rc80-macos-arm64.zip`. The
  `v0.1.5-rc80` tag points at
  `7a5f8c5510bd0d4cea4dedfbd57f5057eff80c91`.
- After rc80 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The restored
  bundle reports CDHash `ae8db8f2288d292f3cff83d39d457d4dc4b3f6ce`,
  `speechModel=Ready`, `inputPipelineReady=true`,
  `microphoneAuthorizationStatus=authorized`, `inputMonitoringEffective=true`,
  `activeFieldInsertionReady=true`, and
  `activeFieldInsertionStatus=ready_input_method`.
- `v0.1.5-rc79` adds read-only Tailscale status collection to the bundled
  host-discovery helper. Tailscale collection is enabled by default, can be
  skipped with `--no-tailscale`, and records CLI startup failures as
  `tailscale.statusAvailable=false` with the failure text in JSON.
- The `v0.1.5-rc79` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:5bdbbd4c0bc35e2ab03d877d91c38821b63dfc1c948fffcb302b2393a7626cee`,
  matching the local `dist/PressTalk-0.1.5-rc79-macos-arm64.zip`. The
  `v0.1.5-rc79` tag points at
  `89f8a7f6d510d53987b3a69abfae48de7c0b3855`.
- After rc79 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The restored
  bundle reports CDHash `c487a0ae39f419bb9030b02013e483933e5613a8`,
  `speechModel=Ready`, `inputPipelineReady=true`,
  `microphoneAuthorizationStatus=authorized`, `inputMonitoringEffective=true`,
  `activeFieldInsertionReady=true`, and
  `activeFieldInsertionStatus=ready_input_method`.
- `v0.1.5-rc78` makes no-prompt signing preflight distinguish a missing local
  identity from an existing but untrusted PressTalk local identity. The
  preflight reports the latter as `ExistingSigningIdentity=untrusted` with the
  identity hash, without creating or trusting a certificate, signing, probing,
  restarting, opening panes, or starting a signing trust prompt.
- The `v0.1.5-rc78` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:c8fda32c78611b58d3d1a48d3d8d133fea1c56d4dad217d28c67a89a5bcdfc8b`,
  matching the local `dist/PressTalk-0.1.5-rc78-macos-arm64.zip`. The
  `v0.1.5-rc78` tag points at
  `faa00bebcdaad399b1011ae2d3a353c694cff0b0`.
- After rc78 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The restored
  bundle reports CDHash `3c141646e78066cce6a806a2a1817338cb19e545`,
  `speechModel=Ready`, `inputPipelineReady=true`,
  `microphoneAuthorizationStatus=authorized`, `inputMonitoringEffective=true`,
  `activeFieldInsertionReady=true`, and
  `activeFieldInsertionStatus=ready_input_method`.
- `v0.1.5-rc77` routes the non-ad-hoc
  `PressTalk Local Development Code Signing` plus `recognized_disabled`
  input-method state to the same no-pane `Repair Signing` path as the ad-hoc
  release install. This covers the mbp1 no-prompt signing experiment where
  signing without adding trust changed `AdHocSigned=false` but TIS still left
  the input method disabled.
- The `v0.1.5-rc77` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:e321d2da0cad0c8ae602a52eb457cb6ab53eb48c2207ca49b63bf809be113005`,
  matching the local `dist/PressTalk-0.1.5-rc77-macos-arm64.zip`. The
  `v0.1.5-rc77` tag points at
  `eb53617b6d6ac972bb56544eda2dd74d7d76bc5f`.
- After rc77 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The restored
  bundle reports CDHash `92c0506759f2496b6d0109b2f0fca833af706b1e`,
  `speechModel=Ready`, `inputPipelineReady=true`,
  `microphoneAuthorizationStatus=authorized`, `inputMonitoringEffective=true`,
  `activeFieldInsertionReady=true`, and
  `activeFieldInsertionStatus=ready_input_method`.
- `v0.1.5-rc76` adds bundled `presstalk-host-discovery.sh`. This read-only
  helper records local SSH config aliases, Bonjour SSH advertisements, target
  `ssh -G` resolution, and optional strict BatchMode SSH probes before release
  matrix runs. It does not install, repair, open System Settings, or request a
  signing trust prompt.
- The `v0.1.5-rc76` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:4121ba2093f8045a1ef87a92a3501e016b8430421f4ca6deaf3fef91f73a80be`,
  matching the local `dist/PressTalk-0.1.5-rc76-macos-arm64.zip`. The
  `v0.1.5-rc76` tag points at
  `4c040a2d4561691c25d15ea92cf12d4c1cf46755`.
- After rc76 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The restored
  bundle reports CDHash `e1d0a5e07f82b22a3283c51ea3597b5d2c4cb00f`,
  `speechModel=Ready`, `inputPipelineReady=true`,
  `microphoneAuthorizationStatus=authorized`, `inputMonitoringEffective=true`,
  `activeFieldInsertionReady=true`, and
  `activeFieldInsertionStatus=ready_input_method`.
- `v0.1.5-rc75` adds `--json-output PATH` to
  `presstalk-release-proof-gate.sh`. The proof gate now writes a parseable
  result with `proven`, `failureCount`, required targets, excluded targets,
  and per-target pass/fail fields plus failure reasons such as
  `active_field_not_ready`.
- The `v0.1.5-rc75` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:b32e89be07ee6dca2d5930076a01d60d234e922acda826a2cf8dd72087331bb3`,
  matching the local `dist/PressTalk-0.1.5-rc75-macos-arm64.zip`. The
  `v0.1.5-rc75` tag points at
  `2761bf21a940790e5e94a353b52687755fa78e15`.
- After rc75 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The restored
  bundle reports CDHash `2be6b57ca1dc0c2522445938a9149686a714c3f3`,
  `speechModel=Ready`, `inputPipelineReady=true`,
  `microphoneAuthorizationStatus=authorized`, `inputMonitoringEffective=true`,
  `activeFieldInsertionReady=true`, and
  `activeFieldInsertionStatus=ready_input_method`.
- `v0.1.5-rc74` adds bundled `presstalk-release-proof-gate.sh`, a
  machine-readable release gate for readiness matrix JSON. It exits `0` only
  when every required target is reachable, reports readiness, has
  `physicalSTTSmokeReady=true`, and has `activeFieldSmokeReady=true`. Fixture
  coverage proves the gate passes a fully ready matrix, fails a matrix where
  mbp1 has `activeFieldSmokeReady=false`, and fails when a required target such
  as `s1` is missing.
- The `v0.1.5-rc74` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:9718cca16bfe200ae9fbf621f1e94c27e90d52461ca18ca86dba5f54d17d17fd`,
  matching the local `dist/PressTalk-0.1.5-rc74-macos-arm64.zip`. The
  `v0.1.5-rc74` tag points at
  `c278d90c6212c6defd283245b3dbf5291cc93605`.
- After rc74 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The restored
  bundle includes executable `presstalk-release-proof-gate.sh`, reports CDHash
  `a555bfdca1bdc4da13ede7bdf222666d29d17e59`, `speechModel=Ready`,
  `inputPipelineReady=true`, `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, `activeFieldInsertionReady=true`, and
  `activeFieldInsertionStatus=ready_input_method`.
- `v0.1.5-rc73` adds a no-prompt
  `presstalk-repair-local-signing.sh --preflight` mode. It reports whether
  signing repair is needed, whether repair is refused over SSH, whether an
  existing trusted local signing identity can be reused, whether a Mac login
  signing trust prompt would be required, and the current runtime fields. It
  does not create or trust a certificate, sign or restart PressTalk, run an
  insertion probe, or open System Settings.
- The `v0.1.5-rc73` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:2455a1b5bf38f15f03d150a53af2e790616f55ab7fd70e7be92c69aff12c254a`,
  matching the local `dist/PressTalk-0.1.5-rc73-macos-arm64.zip`. The
  `v0.1.5-rc73` tag points at
  `ed5f36e1f96ad15689b279115a0164516b1057e3`.
- After rc73 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The restored
  bundle reports CDHash `cced9ee3335b38deef774b9bda1d721e41685277`,
  `speechModel=Ready`, `inputPipelineReady=true`,
  `microphoneAuthorizationStatus=authorized`, `inputMonitoringEffective=true`,
  `activeFieldInsertionReady=true`, and
  `activeFieldInsertionStatus=ready_input_method`. The installed
  `--preflight` helper reports `RepairNeeded=false`,
  `SigningTrustPromptNeeded=false`, and `ExistingSigningIdentity=ready`.
- `v0.1.5-rc72` factors the Settings permission row decisions into a pure
  runtime-status model and adds
  `scripts/test_presstalk_permission_status_labels.sh`. The regression fixture
  proves that a no-pane ready state with `inputMonitoringGranted=false`,
  `inputPipelineReady=true`, `microphoneAuthorizationStatus=authorized`,
  `AXIsProcessTrusted=false`, and `inputMethodFallbackStatus=ready` displays as
  `Listener ready`, `Granted`, and `Input method ready` rather than a missing
  permission loop. It also proved the then-current mbp1 ad-hoc
  `recognized_disabled` state points to `Needs signing repair`.
- The `v0.1.5-rc72` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:c94495eda5de6f8adc99c5b52f0264075cf23f0ffde4c1bd59d7fa55b91de60f`,
  matching the local `dist/PressTalk-0.1.5-rc72-macos-arm64.zip`. The
  `v0.1.5-rc72` tag points at
  `5d8fe79760eee87ff1047e827f708839c4779518`.
- After rc72 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The restored
  bundle reports CDHash `d747ab96d9551d472e9a9c4f8e2f6f2981552a7e`,
  `speechModel=Ready`, `inputPipelineReady=true`,
  `microphoneAuthorizationStatus=authorized`, `inputMonitoringEffective=true`,
  `activeFieldInsertionReady=true`, and
  `activeFieldInsertionStatus=ready_input_method`; the bundled repair verifier
  exits `0` with `Result: proven`.
- `v0.1.5-rc71` fixes the bundled `presstalk-readiness-matrix.sh` helper path.
  The source-tree helper uses underscore naming, but bundled resources use
  hyphen naming. A regression test now simulates the bundled resource layout.
- The `v0.1.5-rc71` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:377412a2fe341e29760694b9abdaeea11536e9adb6ebea51eff73448e000bbf4`,
  matching the local `dist/PressTalk-0.1.5-rc71-macos-arm64.zip`. The
  `v0.1.5-rc71` tag points at
  `96c9c08fde4f0b9a819195407a6f5181b5dd1ffe`, and the inspected asset's bundled
  matrix helper reports local target status `ready_reported`.
- After rc71 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The bundled
  matrix helper reports local `activeFieldSmokeReady=true`; the bundled
  verifier exits `0`.
- `mbp1` is reachable through the configured `mbp1-tb` alias. rc82 was
  downloaded from GitHub over `mbp1-tb` with the expected SHA, installed with
  no-pane flags, and bootstrapped with
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING=existing`. Bootstrap detected the
  existing untrusted local PressTalk identity
  `2EA0B09365E72779413B98BA6319E5D9FBA09205`, skipped stable signing because
  no existing trusted identity was available without a prompt, and did not open
  panes or start a signing-trust prompt. Readiness reports
  `speechModel=Ready`, `inputPipelineReady=true`,
  `InputListener=hid:listen_only`,
  `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`,
  `microphoneHardwareDetected=true`, `physicalSTTSmokeReady=true`,
  `activeFieldInsertionReady=false`,
  `activeFieldInsertionStatus=needs_signing_repair`,
  `inputMethodFallbackStatus=recognized_disabled`, and `AdHocSigned=true`.
  The installed app is ad-hoc signed with CDHash
  `0f28db53d84003f6882970a0c6d8d7b5808b5cbe`.
  The bundled preflight reports `ExistingSigningIdentity=untrusted`,
  `SigningTrustPromptNeeded=true`, `RepairAllowedHere=false` over SSH, and the
  next action is logged-in desktop `Repair Signing`, not another permission
  grant or remote signing flow.
- The installed rc73 repair preflight on `mbp1` reports
  `RunningOverSSH=true`, `RepairNeeded=true`, `RepairAllowedHere=false`,
  `WouldRunRepair=false`, `SigningTrustPromptNeeded=true`,
  `ExistingSigningIdentity=missing`, `AdHocSigned=true`,
  `InputMethodFallbackStatus=recognized_disabled`,
  `ActiveFieldInsertionStatus=needs_signing_repair`,
  `MicrophoneAuthorizationStatus=authorized`, and
  `InputMonitoringEffective=true`. It did not create or trust a certificate,
  sign or restart PressTalk, run an insertion probe, or open System Settings.
- The installed rc76 bundle on `mbp1` includes executable
  `presstalk-host-discovery.sh`, and `mbp1` readiness still reports
  `speechModel=Ready`, `inputPipelineReady=true`, `microphoneHardwareDetected=true`,
  `physicalSTTSmokeReady=true`, `activeFieldInsertionReady=false`,
  `activeFieldInsertionStatus=needs_signing_repair`,
  `inputMethodFallbackStatus=recognized_disabled`, and `AdHocSigned=true`.
  The next action is logged-in desktop `Repair Signing`; do not reopen privacy
  panes for this state.
- Last rc82 readiness matrix command:
  `scripts/presstalk_readiness_matrix.sh --local --host s1 --host s1.local --host mbp1-tb --timeout 3 --json-output <path>`.
  The matrix reports `local` as `ready_reported` with
  `activeFieldSmokeReady=true`; `s1` and `s1.local` fail DNS resolution;
  `mbp1-tb` is `ready_reported` with `activeFieldSmokeReady=false` and next
  action `Repair Signing`. These were host/matrix blockers, not app
  regressions. `studio2` remains excluded from microphone/STT smoke until a
  microphone is attached.
- The rc82 proof gate run against required `local`, `s1`, and `mbp1-tb`,
  excluding `studio2=no attached microphone`, exits nonzero with `proven=false`
  and `failureCount=5`. It passes `local`, fails `s1` for not reachable /
  missing physical STT / missing active-field readiness, and fails `mbp1-tb`
  only for `active_field_not_ready`.
- The rc82 live host discovery run targeted `local`, `s1`, `s1.local`,
  `mbp1-tb`, `studio1.local`, and `mba1.local` with strict SSH probes but
  without opt-in ARP SSH keyscan, to keep `studio2` out of live probing while it
  has no attached microphone. The scripted host-discovery fixture covers the new
  `knownHosts.fingerprints` and `knownHostMatches` JSON contract.
- The rc81 host discovery probe targeted `local`, `s1`, `s1.local`, `mbp1`,
  `mbp1-tb`, `studio1.local`, and `mba1.local`, with opt-in
  `--probe-arp-ssh` evidence. Only `mbp1-tb` answered the strict SSH probe.
  `s1` and `s1.local` do not resolve, plain `mbp1` times out at
  `100.106.125.111:22`, and `studio1.local` / `mba1.local` remain strict
  host-key blockers. Bonjour passively advertises `studio1`, `studio2`,
  `mbp1`, and `mba1`, but no `s1`; `studio2` was not an SSH or STT target in
  this probe. Tailscale was present at `/usr/local/bin/tailscale` but reported
  `The Tailscale CLI failed to start: The operation couldn’t be completed.
  (Tailscale.CLIError error 1.)`, so `tailscale.statusAvailable=false` and no
  Tailscale nodes were available as `s1` evidence. ARP candidate entries
  include `mac` at `192.168.0.19`, `macbookpro` at `192.168.0.41`, and unknown
  hosts at `192.168.0.13`, `192.168.0.42`, `192.168.0.72`,
  `192.168.0.210`, and `192.168.0.243`; these are local-network candidates,
  not confirmed `s1` identity proof. The opt-in keyscan shows
  `192.168.0.41` shares mbp1 fingerprints
  `SHA256:zm/r7lgK7/obIbpd1Ye7km5BdWHbhcUh80d+lqWBR9s` (ED25519),
  `SHA256:vgMu0L/qG82ZP2DAoad498TEUo0wc62gYzcsi1To0+E` (RSA), and
  `SHA256:em2WKtB8v3u/DW0N0M+YqDEJn0PJ9b9EayxVzQM01jI` (ECDSA), while
  `192.168.0.42` shares the earlier mba1 fingerprints. Earlier read-only
  `ssh-keyscan` observed `mba1.local` key
  fingerprints, not trusted or added: RSA
  `SHA256:uA9g7l4TV0EVDgTn1d1X3g/aDQ5vBJmVaTe7gwj7lnI`, ED25519
  `SHA256:3d9YHlo6UXSwPW8JCg9GoVIuSGAU38SVhm4a9Ow1Mg4`, ECDSA
  `SHA256:BhdJk5PV1aV/VhYi8FCJu5oR0DTzA8K+bdIN+rVzS+Q`. Do not bypass or add
  host keys without out-of-band verification.

Earlier prerelease notes retained for provenance:

- `v0.1.5-rc69` makes the machine-readiness helper produce parseable JSON
  with `--json` and `--json-output PATH`, and adds a fixture test for the JSON
  contract. The JSON schema includes `eligibility.physicalSTTSmokeReady`,
  `eligibility.activeFieldSmokeReady`, `audio.microphoneHardwareDetected`, and
  `nextAction` for release evidence.
- The `v0.1.5-rc69` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:09bd78f93e1a68d476d2d0bb0589e94b96b3d5d3e07dde6f0871cadda7ab2f8f`,
  matching the local `dist/PressTalk-0.1.5-rc69-macos-arm64.zip`. The
  `v0.1.5-rc69` tag points at
  `52ee02481d175b19c82a3e5fbb090cb2708a2172`, and the inspected asset contains
  a bundled readiness helper whose `--json` output exposes `schemaVersion=1`.
- After rc69 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The bundled
  readiness helper JSON reports `eligibility.physicalSTTSmokeReady=true` and
  `eligibility.activeFieldSmokeReady=true`; the bundled verifier exits `0`.

- `v0.1.5-rc70` added bundled `presstalk-readiness-matrix.sh` for local and SSH
  readiness matrix JSON, but artifact inspection found the bundled helper path
  bug fixed in rc71.

- `v0.1.5-rc68` adds bundled `presstalk-machine-readiness.sh`, a read-only
  machine eligibility helper. It reports Apple Silicon eligibility, detected
  audio input hardware, installed PressTalk identity, runtime speech readiness,
  active-field insertion readiness, latest production insertion probe, and the
  next action. This is now the first cross-machine preflight before counting a
  Mac in physical STT smoke coverage.
- The `v0.1.5-rc68` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:d97390a372669496e739811573b82c8a1ecd656cad698baa669fe1e818b85e85`,
  matching the local `dist/PressTalk-0.1.5-rc68-macos-arm64.zip`. The
  `v0.1.5-rc68` tag points at
  `f8c1fc90fafeaa9a92f9441149b6a5b5654636a6`, and the inspected asset contains
  executable `presstalk-machine-readiness.sh`.
- After rc68 packaging, `studio1` was restored to stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The bundled
  readiness helper reports `MicrophoneHardwareDetected=true`,
  `PhysicalSTTSmokeReady=true`, and `ActiveFieldSmokeReady=true`; the bundled
  verifier exits `0` using the latest successful production insertion probe.
- Current host/machine blockers: `s1` and `s1.local` do not resolve,
  `studio1.local` and `mba1.local` fail SSH host-key verification, and `mbp1`
  SSH to port 22 times out. Do not bypass host-key checks silently. `studio2`
  remains excluded from microphone/STT smoke until a microphone is attached.

- `v0.1.5-rc67` fixes the read-only repair verifier so it accepts every proven
  active-field insertion path: InputMethodKit, direct Accessibility insertion,
  or Accessibility-backed paste command. It still reports the mbp1 ad-hoc
  `recognized_disabled` state as a signing repair blocker. The production
  insertion probe now records `activeFieldInsertionReady`,
  `activeFieldInsertionStatus`, and `inputMethodFallbackStatus` in its
  readiness snapshots.
- The `v0.1.5-rc67` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:15b54c839c4a4d26c177dea9118614ede8e3ccdf02cd47ff14fdca33a865345a`,
  matching the local `dist/PressTalk-0.1.5-rc67-macos-arm64.zip`. The
  `v0.1.5-rc67` tag points at
  `2bad7440cc23140084162966bb7f0bc1e7167049`, and the inspected asset contains
  the updated verifier reason plus production-probe readiness fields.
- After rc67 packaging, `studio1` was restored to the stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. Runtime status
  reports `activeFieldInsertionReady=true` and
  `activeFieldInsertionStatus=ready_input_method`; the bundled verifier exits
  `0` using the latest successful production insertion probe.
- An rc67 install attempt on `mbp1` did not reach the host because SSH to port
  22 timed out before the checksum or bootstrap step. Do not treat `mbp1` as
  rc67-refreshed; latest verified `mbp1` app state remains the rc66
  `needs_signing_repair` blocker below.

- `v0.1.5-rc66` adds machine-readable active-field insertion readiness.
  Runtime status now records `runtime.activeFieldInsertionReady` and
  `runtime.activeFieldInsertionStatus`, and the smoke collector plus repair
  verifier print those fields. This separates "speech pipeline ready" from
  "active-field paste ready" in one JSON snapshot.
- The `v0.1.5-rc66` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:df52b2d5edebad4baec59e3626a289f389d209c8857647a536bcdc2444fe58bc`,
  matching the local `dist/PressTalk-0.1.5-rc66-macos-arm64.zip`. The
  `v0.1.5-rc66` tag points at
  `f8466deb685b729bf765c7b1db41a5fe938f2724`, and the inspected asset contains
  the new runtime/collector readiness fields.
- After rc66 packaging, `studio1` was restored to the stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. Runtime status
  reports `activeFieldInsertionReady=true` and
  `activeFieldInsertionStatus=ready_input_method`; the bundled verifier exits
  `0` using the latest successful production insertion probe.
- On `mbp1`, rc66 was downloaded from GitHub over SSH with the expected SHA,
  installed with no-pane flags, and bootstrapped through the `existing` signing
  path without a trust prompt. Runtime status reports
  `activeFieldInsertionReady=false` and
  `activeFieldInsertionStatus=needs_signing_repair`, while `speechModel=Ready`
  and `inputListener=hid:listen_only`. Active-field insertion remains unproven
  until logged-in desktop `Repair Signing`.

- `v0.1.5-rc65` makes the known mbp1 blocker visible in the menu-bar status.
  When transcription is ready but ad-hoc input-method signing still blocks
  active-field paste, the menu summary says `Paste Repair Needed` instead of
  plain `Ready` and the detail points to `Repair Signing` in the menu bar. A
  generic non-ready fallback status reports `Paste Fallback Blocked`.
- The `v0.1.5-rc65` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:73ef9f26096cd80b234f2d63322ee766ce2c145ca700a4a55260779f25379593`,
  matching the local `dist/PressTalk-0.1.5-rc65-macos-arm64.zip`. The
  `v0.1.5-rc65` tag points at
  `8589091746b98f3455b6b6affcea14b07b8a3647`, and the inspected asset contains
  the `Paste Repair Needed` and `Paste Fallback Blocked` status strings.
- After rc65 packaging, `studio1` was restored to the stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The installed
  binary contains the new paste repair status strings, and the bundled verifier
  still exits `0` using the latest successful production insertion probe.
- On `mbp1`, rc65 was downloaded from GitHub over SSH with the expected SHA,
  installed with no-pane flags, and bootstrapped through the `existing` signing
  path without a trust prompt. The installed binary contains the new paste
  repair status strings. Runtime remains transcription-ready, but active-field
  insertion is still unproven: `adHocSigned=true`,
  `inputMethodFallbackStatus=recognized_disabled`, and the no-window TIS enable
  diagnostic still reports `enableStatus=0` with `enableNoEffect=true`.
- `v0.1.5-rc64` publishes the direct menu-bar repair path and matching
  collector wording. In the ad-hoc `recognized_disabled` state, the status menu
  shows `Repair Signing...` so a logged-in desktop user can start the no-pane
  repair helper without reopening the full Settings window. The smoke-status
  collector now says to use `Repair Signing` from the PressTalk menu bar or
  Settings.
- The `v0.1.5-rc64` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:90fcaa56566cd40ebbedddae9d88e6c4099b1c6ae891f65b590c4ed11b4b2534`,
  matching the local `dist/PressTalk-0.1.5-rc64-macos-arm64.zip`. The
  `v0.1.5-rc64` tag points at
  `53c37d59223c42b834ca5c10d866dc330e5dab79`, and the inspected asset contains
  the corrected collector text.
- After rc64 packaging, `studio1` was restored to the stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The installed
  collector contains the menu-bar-or-Settings repair text, and the bundled
  verifier still exits `0` using the latest successful production insertion
  probe.
- On `mbp1`, rc64 was downloaded from GitHub over SSH with the expected SHA,
  installed with no-pane flags, and bootstrapped through the `existing` signing
  path without a trust prompt. The installed collector reports the corrected
  menu-bar-or-Settings repair action. A no-window TIS enable diagnostic returned
  `enableStatus=0` with `enableNoEffect=true`, leaving
  `recognizedEnabledSourceCount=0`. Runtime remains transcription-ready, but
  active-field insertion is still unproven until logged-in desktop
  `Repair Signing`.
- `v0.1.5-rc63` adds the status-menu `Repair Signing...` item for the exact
  ad-hoc `recognized_disabled` input-method state. The item is hidden otherwise
  and runs the same no-pane repair helper as the Settings button.
- `v0.1.5-rc62` suppresses Finder reveal on diagnostics export during no-pane
  runs. When `PRESSTALK_OPEN_PERMISSION_PANES=0`, Export Diagnostics writes the
  diagnostics file, logs its path, and shows a short HUD message without
  activating another window. Normal interactive runs can still reveal the file.
- The `v0.1.5-rc62` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:dd70d4f4f801b3a41aba2b6add6ed87547c3d09f4838dee4c4adcc80d235dcc4`,
  matching the local `dist/PressTalk-0.1.5-rc62-macos-arm64.zip`. The
  `v0.1.5-rc62` tag points at
  `bf063347999933277483d40e0adff29f2fea6ec4`.
- After rc62 packaging, `studio1` was restored to the stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. The installed
  binary contains the quiet diagnostics strings, runtime status is still
  `speechModel=Ready`, `inputListener=hid:listen_only`,
  `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, `inputMethodFallbackStatus=ready`, and the
  bundled verifier exits `0` using the latest successful production insertion
  probe.
- On `mbp1`, rc62 was downloaded from GitHub over SSH with the expected SHA,
  installed with no-pane flags, and bootstrapped through the `existing` signing
  path without a trust prompt. The quiet diagnostics strings are present and
  runtime remains transcription-ready, but active-field insertion is still
  unproven because `adHocSigned=true` and
  `inputMethodFallbackStatus=recognized_disabled`. The correct next action is
  still logged-in desktop `Repair Signing`, not another permission pass.
- `v0.1.5-rc61` adds a bundled read-only
  `presstalk-verify-repair-result.sh` helper. It reports the current runtime
  signing/input-method state plus the latest production insertion probe and
  exits `0` only when active-field insertion has been proven in the focused
  target. It does not open permission panes and does not start any signing trust
  flow.
- The `v0.1.5-rc61` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:b4e9b48f2fd3e5b7840e374884d2bff31ac0daa4f5a3266abea8f9cdb1cb166d`,
  matching the local `dist/PressTalk-0.1.5-rc61-macos-arm64.zip`. The
  `v0.1.5-rc61` tag points at
  `06be461f87b8cbf255340f65d559888701346430`, and the inspected asset contains
  `presstalk-verify-repair-result.sh`.
- After rc61 packaging, `studio1` was restored to the stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. Runtime status
  reports `Authority=PressTalk Local Development Code Signing`,
  `speechModel=Ready`, `inputListener=hid:listen_only`,
  `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, `inputMethodFallbackStatus=ready`, and
  `accessibilityStatus=ax_false_input_method_fallback_ready`. The bundled
  verifier exits `0` on `studio1` using the latest successful production
  insertion probe:
  `Diagnostics/production-insertion-probe-2026-06-07T02-10-16-571Z.json`.
- On `mbp1`, rc61 was downloaded from GitHub over SSH with the expected SHA,
  installed with no-pane flags, and bootstrapped through the `existing` signing
  path without a trust prompt. Runtime remains transcription-ready:
  `speechModel=Ready`, `triggerPath=Fn / Globe ready`,
  `inputListener=hid:listen_only`, `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, and `inputPipelineReady=true`. The bundled
  verifier is present and exits nonzero with `Result: not proven` because the
  app is still ad-hoc signed and
  `inputMethodFallbackStatus=recognized_disabled`. The correct next action is
  still the logged-in desktop `Repair Signing` path, not another Microphone,
  Input Monitoring, or Accessibility permission pass.
- `studio2` / `s2` is intentionally excluded from current microphone/STT smoke
  coverage because it has no attached microphone.
- `v0.1.5-rc53` is published as a public prerelease smoke artifact, and GitHub
  reports the expected asset SHA-256 digest.
- The `v0.1.5-rc53` zip was inspected locally and contains the expected arm64
  `PressTalk.app`, permission usage descriptions, bundled bootstrap helper,
  bundled local-signing helper, bundled signing-repair helper, bundled
  smoke-status collector, bundled manual Fn smoke helper, bundled automated F5
  smoke helper, bundled actual-bundle Accessibility probe, bundled production
  insertion probe helpers, and bundled input-method app/helpers with `PkgInfo`.
- `v0.1.5-rc53` adds `permissions.inputMethodFallbackStatus` to runtime status
  and Settings. On `studio1`, local restore reports
  `inputMethodFallbackStatus=ready`,
  `accessibilityStatus=ax_false_input_method_fallback_ready`, and the production
  insertion probe succeeded with `success=true`, `targetCaptureSuccess=true`,
  and `traceProductionMethod=input_method_notification`. On `mbp1`, rc53
  no-pane/ad-hoc install reports
  `inputMethodFallbackStatus=recognized_disabled` and
  `accessibilityStatus=ax_false_input_method_recognized_disabled`, matching the
  collector evidence that TIS recognizes the source but has not enabled it.
- `v0.1.5-rc54` adds remote-signing guardrails. Bootstrap skips stable local
  signing by default when launched over SSH unless
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING` is set explicitly, and the repair helper
  refuses the signing trust flow over SSH unless `--allow-ssh` is passed. This
  prevents surprise Mac-password signing prompts while keeping the explicit
  logged-in desktop repair path available.
- The `v0.1.5-rc54` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:8d7c2bbf1e260fb0cf3141faf2c461a7486b946c1901a602e922e376c7aaad11`,
  matching the local `dist/PressTalk-0.1.5-rc54-macos-arm64.zip`.
- After rc54 packaging, `studio1` was restored to the stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. Runtime status
  reports `Authority=PressTalk Local Development Code Signing`,
  `speechModel=Ready`, `inputListener=hid:listen_only`,
  `inputMethodFallbackStatus=ready`, and
  `accessibilityStatus=ax_false_input_method_fallback_ready`.
- The `studio1` rc54 production insertion probe succeeded without audio:
  `Diagnostics/production-insertion-probe-2026-06-07T01-54-34-727Z.json`
  reported `success=true`, `targetCaptureSuccess=true`,
  `traceProductionMethod=input_method_notification`,
  `traceCopyFallback=false`, and `traceInputMethodEnableNoEffect=false`.
- A post-rc54 virtual-HID paste probe was added for diagnostics. It opens a
  focused local text view, sets a pasteboard payload, and attempts Cmd-V through
  `IOHIDUserDevice`. Apple's local SDK header says virtual HID device creation
  requires the `com.apple.developer.hid.virtual.device` entitlement, and
  `studio1` confirmed the route is blocked for this unsigned/public fallback:
  `Diagnostics/virtual-hid-paste-probe-2026-06-07T02-00-59-948Z.json` reported
  `success=false`, `reason=device_create_failed`, and `deviceCreated=false`.
- A post-rc54 Settings wording fix now labels the ad-hoc
  `recognized_disabled` input-method state as `Needs signing repair` and the
  hint explicitly says to run the logged-in desktop signing repair helper plus
  production insertion probe instead of re-granting Microphone, Input
  Monitoring, or Accessibility.
- `v0.1.5-rc55` publishes the Settings signing repair action. For the exact
  ad-hoc `recognized_disabled` input-method state, Settings now shows
  `Repair Signing`; clicking it runs the bundled no-pane
  `presstalk-repair-local-signing.sh --probe` helper from the desktop session,
  writes a diagnostics log, restarts PressTalk, and runs the production
  insertion probe. This makes the mbp1 repair path intentional and GUI-driven
  instead of requiring a shell command.
- The `v0.1.5-rc55` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:6ce317c8cbb26fb6f82d5961b789d5784261dfc2f1e57502d15c2a930a0a2e19`,
  matching the local `dist/PressTalk-0.1.5-rc55-macos-arm64.zip`. The inspected
  asset contains the `Repair Signing` action strings and the virtual-HID paste
  diagnostic helper.
- After rc55 packaging, `studio1` was restored to the stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. One
  production insertion probe run traced successful input-method insertion but
  missed target-window capture; a serial rerun succeeded:
  `Diagnostics/production-insertion-probe-2026-06-07T02-10-16-571Z.json`
  reported `success=true`, `targetCaptureSuccess=true`,
  `traceProductionMethod=input_method_notification`, and
  `traceCopyFallback=false`.
- On `mbp1`, rc55 was downloaded from GitHub over SSH with the expected SHA,
  installed with no-pane flags, and bootstrapped without explicitly setting
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING`. Bootstrap again skipped stable signing
  without opening panes or starting a trust prompt. Runtime remains
  transcription-ready: `speechModel=Ready`, `triggerPath=Fn / Globe ready`,
  `inputListener=hid:listen_only`, `microphoneAuthorizationStatus=authorized`,
  and `inputMonitoringEffective=true`.
- The `mbp1` rc55 app is still ad-hoc, so active-field insertion is not yet
  proven there: runtime status remains
  `inputMethodFallbackStatus=recognized_disabled`. Smoke-status reports matching
  bundled/installed input-method CDHash
  `ab9ad270622a8fa409dcd9c2cad7e3bc17cf7979`, and TIS recognizes one
  select-capable PressTalk source but `recognizedEnabledSourceCount=0`. The
  installed rc55 binary contains `Needs signing repair` and the Settings repair
  action strings, so the next required proof is clicking `Repair Signing` in the
  logged-in mbp1 desktop session and checking the resulting production insertion
  probe.
- `v0.1.5-rc56` publishes the improved smoke-status collector. The new
  `Repair And Probe Status` section prints the current ad-hoc/input-method
  repair state, latest signing repair log if one exists, latest production
  insertion probe summary, and for ad-hoc `recognized_disabled` explicitly says
  to use desktop `Repair Signing` instead of re-granting Microphone, Input
  Monitoring, or Accessibility.
- The `v0.1.5-rc56` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:31a784c7d8933b5245e9dc9f2f537980aa0879d74f92cdb36fcd720cd57ada73`,
  matching the local `dist/PressTalk-0.1.5-rc56-macos-arm64.zip`, and the tag
  points at `1f88adbfc0d0a4eb48362998cfd663c2ea09a6b3`.
- After rc56 packaging, `studio1` was restored to the stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. Runtime status
  reports `Authority=PressTalk Local Development Code Signing`,
  `speechModel=Ready`, `inputListener=hid:listen_only`,
  `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, `inputMethodFallbackStatus=ready`, and
  `accessibilityStatus=ax_false_input_method_fallback_ready`. The installed
  collector reports the latest production insertion probe as
  `success=true`, `targetCaptureSuccess=true`, and
  `traceProductionMethod=input_method_notification`.
- On `mbp1`, rc56 was downloaded from GitHub over SSH with the expected SHA,
  installed with no-pane flags, and bootstrapped without explicitly setting
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING`. Bootstrap again skipped stable signing
  without opening panes or starting a trust prompt. Runtime remains
  transcription-ready: `speechModel=Ready`, `triggerPath=Fn / Globe ready`,
  `inputListener=hid:listen_only`, `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, and `inputPipelineReady=true`. Active-field
  insertion remains unproven until the logged-in desktop signing repair:
  `adHocSigned=true`, `inputMethodFallbackStatus=recognized_disabled`, and the
  rc56 collector reports the correct next action, desktop `Repair Signing`, plus
  the prior failed insertion probe with `targetCaptureFailureHint=input_method_enable_no_effect`.
- `v0.1.5-rc57` fixes remote-update behavior after a future desktop signing
  repair. When bootstrap is launched over SSH and
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING` was not explicitly set, it now requests
  `existing`: reuse an already-valid PressTalk local signing identity without a
  trust prompt, otherwise skip stable signing. This preserves the no-surprise
  prompt rule while avoiding a future regression where a successfully repaired
  Mac would be downgraded to ad-hoc on the next remote install.
- The `v0.1.5-rc57` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:c1a9cc4ad63738e3f5a060f2bfdd2c6221b6153a9f2ba013afd41dd2f7d0c208`,
  matching the local `dist/PressTalk-0.1.5-rc57-macos-arm64.zip`. The inspected
  asset contains `PRESSTALK_BOOTSTRAP_STABLE_SIGNING=existing` in
  `presstalk-bootstrap.sh` and `PRESSTALK_LOCAL_CODESIGN_EXISTING_ONLY` in the
  local signing helper.
- After rc57 packaging, `studio1` was restored to the stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. Runtime status
  reports `Authority=PressTalk Local Development Code Signing`,
  `speechModel=Ready`, `inputListener=hid:listen_only`,
  `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, `inputMethodFallbackStatus=ready`, and
  `accessibilityStatus=ax_false_input_method_fallback_ready`.
- On `mbp1`, rc57 was downloaded from GitHub over SSH with the expected SHA,
  installed with no-pane flags, and bootstrapped without explicitly setting
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING`. The new bootstrap correctly reported
  `Stable local signing requested: existing`, then
  `No existing valid PressTalk local code-signing identity is available` and
  skipped stable signing without a trust prompt. No `add-trusted-cert` or helper
  process remained after install. Runtime remains transcription-ready:
  `speechModel=Ready`, `triggerPath=Fn / Globe ready`,
  `inputListener=hid:listen_only`, `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, and `inputPipelineReady=true`. Active-field
  insertion remains unproven until the logged-in desktop signing repair:
  `adHocSigned=true` and `inputMethodFallbackStatus=recognized_disabled`.
- `v0.1.5-rc58` removes the Python dependency from the production insertion
  probe wrapper. `presstalk-run-production-insertion-probe.sh` now reads the
  current trigger key from `runtime-status.json` with macOS `plutil`, which
  keeps the post-repair verifier native to macOS.
- The `v0.1.5-rc58` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:9b17ad8c824ee10bba2ef47fcb99c5147c93306f290b97d5016f78cd39d58149`,
  matching the local `dist/PressTalk-0.1.5-rc58-macos-arm64.zip`. The inspected
  asset contains `plutil -extract runtime.triggerKey` in
  `presstalk-run-production-insertion-probe.sh`.
- After rc58 packaging, `studio1` was restored to the stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. Runtime status
  reports `Authority=PressTalk Local Development Code Signing`,
  `speechModel=Ready`, `inputListener=hid:listen_only`,
  `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, `inputMethodFallbackStatus=ready`, and
  `accessibilityStatus=ax_false_input_method_fallback_ready`.
- On `mbp1`, rc58 was downloaded from GitHub over SSH with the expected SHA,
  installed with no-pane flags, and bootstrapped through the `existing` signing
  path without a trust prompt. The installed production insertion probe wrapper
  contains the native `plutil` trigger-key lookup. Runtime remains
  transcription-ready: `speechModel=Ready`, `triggerPath=Fn / Globe ready`,
  `inputListener=hid:listen_only`, `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, and `inputPipelineReady=true`. Active-field
  insertion remains unproven until the logged-in desktop signing repair:
  `adHocSigned=true` and `inputMethodFallbackStatus=recognized_disabled`.
- `v0.1.5-rc59` hardens the Settings `Repair Signing` action. The app now
  launches the bundled repair helper through `nohup`, writes a sibling
  `presstalk-signing-repair-*.pid` file next to the diagnostics log, and traces
  that pid file. This lets the repair survive the app restart it initiates. The
  smoke-status collector now reports the latest signing repair pid file and
  whether that helper process is still running.
- The `v0.1.5-rc59` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:23e0495559d8c875400ba3df7d8ad64504dbbed89a2feb95a504ee0f5b5ae1dd`,
  matching the local `dist/PressTalk-0.1.5-rc59-macos-arm64.zip`. The inspected
  asset contains `/usr/bin/nohup /bin/bash` in the app binary and the new
  signing repair pid reporting lines in `presstalk-collect-smoke-status.sh`.
- After rc59 packaging, `studio1` was restored to the stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. Runtime status
  reports `Authority=PressTalk Local Development Code Signing`,
  `speechModel=Ready`, `inputListener=hid:listen_only`,
  `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, `inputMethodFallbackStatus=ready`, and
  `accessibilityStatus=ax_false_input_method_fallback_ready`.
- On `mbp1`, rc59 was downloaded from GitHub over SSH with the expected SHA,
  installed with no-pane flags, and bootstrapped through the `existing` signing
  path without a trust prompt. The installed app contains the `nohup` repair
  launch and the installed collector contains the signing repair pid reporting
  lines. Runtime remains transcription-ready: `speechModel=Ready`,
  `triggerPath=Fn / Globe ready`, `inputListener=hid:listen_only`,
  `microphoneAuthorizationStatus=authorized`, `inputMonitoringEffective=true`,
  and `inputPipelineReady=true`. Active-field insertion remains unproven until
  the logged-in desktop signing repair: `adHocSigned=true` and
  `inputMethodFallbackStatus=recognized_disabled`.
- `v0.1.5-rc60` improves post-click repair evidence. When the repair helper is
  run with `--probe`, it now runs the production insertion probe, preserves the
  probe exit status, then appends a full post-repair
  `presstalk-collect-smoke-status.sh` snapshot to the same diagnostics log. That
  means the `Repair Signing` log should contain the probe result plus the final
  runtime/input-method status needed for SSH-side verification.
- The `v0.1.5-rc60` GitHub release was verified as a prerelease. GitHub reports
  asset digest
  `sha256:e7328bfdb2fda714f2a991acaaaa2a752b43f2873c5e72a920867ab1870e0953`,
  matching the local `dist/PressTalk-0.1.5-rc60-macos-arm64.zip`. The inspected
  asset contains `SMOKE_COLLECTOR`, `Collecting post-repair smoke status`, and
  `exit "$probe_status"` in `presstalk-repair-local-signing.sh`.
- After rc60 packaging, `studio1` was restored to the stable local
  `com.am.jarvistap` identity with no-pane flags and Fn trigger. Runtime status
  reports `Authority=PressTalk Local Development Code Signing`,
  `speechModel=Ready`, `inputListener=hid:listen_only`,
  `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, `inputMethodFallbackStatus=ready`, and
  `accessibilityStatus=ax_false_input_method_fallback_ready`.
- On `mbp1`, rc60 was downloaded from GitHub over SSH with the expected SHA,
  installed with no-pane flags, and bootstrapped through the `existing` signing
  path without a trust prompt. The installed repair helper contains the
  post-repair smoke collector snapshot path. Runtime remains transcription-ready:
  `speechModel=Ready`, `triggerPath=Fn / Globe ready`,
  `inputListener=hid:listen_only`, `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, and `inputPipelineReady=true`. Active-field
  insertion remains unproven until the logged-in desktop signing repair:
  `adHocSigned=true` and `inputMethodFallbackStatus=recognized_disabled`.
- On `mbp1`, rc54 was downloaded from GitHub over SSH with the expected SHA,
  installed with no-pane flags, and bootstrapped without explicitly setting
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING`. The rc54 bootstrap correctly reported
  `Stable local signing skipped: PRESSTALK_BOOTSTRAP_STABLE_SIGNING=0`, proving
  the SSH default does not start the signing trust prompt. Runtime status after
  install reports `speechModel=Ready`, `triggerPath=Fn / Globe ready`,
  `inputListener=hid:listen_only`, `microphoneAuthorizationStatus=authorized`,
  and `inputMonitoringEffective=true`.
- The bundled rc54 repair helper was also checked over SSH on `mbp1`; it exited
  with code `2` before starting the signing trust flow and printed the
  desktop-session repair instruction. This is the intended no-surprise-prompt
  behavior.
- `mbp1` active-field insertion is still not proven on the ad-hoc rc54 install:
  smoke-status reports matching bundled/installed input-method CDHash
  `3e05dd4d24434d204631282139592215e7bebe3d`, TIS recognizes one
  select-capable source `com.am.presstalk.inputmethod.container`, but
  `recognizedEnabledSourceCount=0` and runtime status remains
  `inputMethodFallbackStatus=recognized_disabled`. This still needs the
  logged-in desktop signing repair plus production insertion probe proof.
- `v0.1.5-rc52` extends the bundled smoke-status collector with an `Input
  Method` section. It prints bundled and installed `PressTalkInputMethod.app`
  signatures, warns if their CDHashes differ, and embeds the read-only TIS JSON
  from `presstalk-input-method-status.swift`. Local studio1 verification after
  restore showed matching bundled/installed input-method CDHash
  `8cd10e2458bdf0cb10661361017ad706826c2f10`,
  `recognizedSourceCount=1`, `recognizedEnabledSourceCount=1`,
  `selectCapable=true`, and `enableNoEffect=false`.
- `v0.1.5-rc51` adds the bundled
  `presstalk-repair-local-signing.sh` helper. It runs with no-pane flags,
  prepares a local signing identity, restarts PressTalk with stable signing,
  signs the bundled `PressTalkInputMethod.app`, refreshes the installed copy in
  `~/Library/Input Methods`, and can optionally run the production insertion
  probe. This is the next repair path for mbp1 after the skipped signing trust
  password prompt; it is not a reason to reopen privacy panes.
- Current bootstrap signs the bundled input method before signing the outer app
  and refreshes the installed input method before launch. On `studio1`, local
  bootstrap reported `Stable local signing applied: 1`,
  `Bundled input method signing applied: 1`, and
  `Installed input method refreshed: 1`. The bundled and installed input method
  then shared CDHash `a55ba84210b2dfbf2d82839807dabf8448801527` and
  `Authority=PressTalk Local Development Code Signing`.
- After that bootstrap change, the `studio1` production insertion probe still
  succeeds from the running app process:
  `Diagnostics/production-insertion-probe-2026-06-07T01-13-01-575Z.json`
  reported `success=true`, `targetCaptureSuccess=true`,
  `traceProductionMethod=input_method_notification`,
  `traceInputMethodEnableNoEffect=false`, and `traceCopyFallback=false`.
- A local development code-signing identity was created on `studio1`, and a
  local build now signs as `Authority=PressTalk Local Development Code Signing`
  instead of ad-hoc. The LaunchAgent was restarted against that stable-signed
  build with `PRESSTALK_TRIGGER_KEY=fn`.
- The bundled bootstrap path was tested on `studio1`: a normal ad-hoc build was
  re-signed by the app-bundled local-signing helper before launchd started it.
  The resulting app reports `Authority=PressTalk Local Development Code
  Signing`, and launchd is running it with `PRESSTALK_TRIGGER_KEY=fn`.
- While blocked on Input Monitoring, the local app now starts a quiet setup retry
  timer. Trace evidence on `studio1`: `Setup retry timer started
  interval_seconds=5.0`.
- Current builds write machine-readable runtime status to
  `~/Library/Application Support/JarvisTap/runtime-status.json`; the bundled
  `presstalk-collect-smoke-status.sh` helper collects that file together with
  app signature, launchd state, machine info, and trace tail for cross-machine
  proof.
- Current local builds do not auto-show the settings window by default. They add
  a `Restart PressTalk` settings action for refreshing the running process and
  run read-only preflights plus real listener capability probes during setup.
- Current startup code stops force-presenting the PressTalk Settings window
  after successful startup. Automatic setup presentation requires both
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=1` and
  `PRESSTALK_OPEN_PERMISSION_PANES=1`; no-pane installs stay quiet even when
  setup checks are running.
- Current bootstrap runs launch PressTalk through LaunchServices via
  `/usr/bin/open -gjW` so macOS privacy identity is app-bundle based, and it no
  longer opens System Settings panes automatically.
- `v0.1.5-rc21` passes `PRESSTALK_OPEN_PERMISSION_PANES` into the running app.
  With the default value `0`, current builds hide the Settings window's
  Microphone, Input Monitoring, and Accessibility buttons and suppress
  privacy-pane open calls, so no-pane smoke runs cannot accidentally reopen
  System Settings or suggest another approval pass.
- Current startup/setup checks no longer call macOS permission-request APIs
  automatically. They only preflight and attempt the real listener capability,
  so repeated restarts do not keep prompting for already-approved permissions.
- For `Fn` and `Option`, current builds try writable HID/session event taps
  first. A listen-only fallback is not effective for modifier-key triggers and
  now records `permissions.inputMonitoringStatus=writable_key_tap_unavailable`.
  `trackpad_hold` can use a listen-only tap after it observes a real pointer
  trigger; until then it records
  `permissions.inputMonitoringStatus=waiting_for_trackpad_event`. Runtime
  status records `runtime.inputListener` so smoke tests can distinguish
  `hid:listen_only`, `session:listen_only`, `hid:default`, and `failed`.
- Settings now distinguish read-only permission preflights from effective
  runtime capability. If the real listener is armed, Input Monitoring renders as
  listener-ready and `runtime-status.json` records
  `permissions.inputMonitoringEffective=true` instead of sending the user back
  through already-enabled macOS privacy toggles. Accessibility is treated as a
  paste probe unless paste actually fails. Current builds record
  machine-readable `permissions.inputMonitoringStatus`,
  `permissions.microphoneStatus`, and `permissions.accessibilityStatus` strings
  so raw macOS preflight misses are visibly separate from effective runtime
  readiness.
- `v0.1.5-rc27` adds `permissions.microphoneAuthorizationStatus` to
  `runtime-status.json`, Settings, diagnostics export, and both smoke helpers.
  A blocked machine now distinguishes `authorized`, `denied`, `restricted`,
  `not_determined`, and `unknown` microphone preflight states without opening
  System Settings.
- `v0.1.5-rc27` also adds a read-only `TCC Rows` section to the bundled
  smoke-status collector. It reports `com.am.presstalk` and
  `com.am.jarvistap` rows for Microphone, Input Monitoring, and Accessibility
  from the user/system TCC databases when readable; it does not reset TCC or
  open privacy panes.
- `v0.1.5-rc28` adds decoded TCC code requirements to the same collector and
  prints the running app's designated requirement. This makes stale grants tied
  to an old certificate root or CDHash visible without opening System Settings.
- `v0.1.5-rc29` closes the remaining success-path setup-window regression:
  a machine with working microphone/listener runtime proof is not sent back to
  the PressTalk Settings permission UI just because this is the first launch.
- `v0.1.5-rc30` upgrades the bundled manual physical-trigger smoke helper to
  record `traceFinalTranscript`, `traceInserted`, `traceCopyFallback`,
  `targetCaptureSuccess`, and `targetCaptureFailureHint`. This separates
  physical trigger/STT proof from active-field insertion proof.
- `v0.1.5-rc31` adds an opt-in InputMethodKit insertion prototype. The release
  bundle contains `PressTalkInputMethod.app`,
  `presstalk-install-input-method.sh`, and
  `presstalk-input-method-insert-probe.sh`. The prototype is not installed or
  selected automatically, and it does not open System Settings. It is a concrete
  experiment for proving whether a selected PressTalk input method can insert
  text into the active client without Accessibility trust.
- `v0.1.5-rc32` removes bootstrap's automatic System Settings open path. Even
  if `PRESSTALK_OPEN_PERMISSION_PANES=1` is present, bootstrap prints a warning
  instead of opening Microphone, Input Monitoring, or Accessibility panes.
  Startup setup-window presentation now requires both
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=1` and
  `PRESSTALK_OPEN_PERMISSION_PANES=1`; no-pane local restores use
  `PRESSTALK_OPEN_PERMISSION_PANES=0` and
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`.
- `v0.1.5-rc32` adds `presstalk-input-method-status.swift` to the release
  bundle. The helper is read-only by default and reports current input source,
  installed bundle state, all-installed recognition, enabled recognition, and
  explicit `--register`, `--enable`, and `--select` statuses.
- On `studio1`, the rc32 local restore was rebuilt as `com.am.jarvistap`,
  re-signed by `Authority=PressTalk Local Development Code Signing`, and
  restarted with no-pane flags. Runtime status after restart:
  `permissionPaneOpeningAllowed=false`, `setupRetryActive=false`,
  `microphoneAuthorizationStatus=authorized`, `microphoneGranted=true`,
  `inputMonitoringEffective=true`, `inputListener=hid:listen_only`,
  `inputPipelineReady=true`, `status.speechModel=Ready`, and
  `status.triggerPath=Fn / Globe ready`.
- On `studio1`, the installed `PressTalkInputMethod.app` is recognized by TIS
  as `TISTypeKeyboardInputMethodWithoutModes` in
  `TISCategoryKeyboardInputSource`, with `recognizedAllSourceCount=1` and
  `recognizedEnabledSourceCount=0`. It was not enabled or selected during this
  verification; the current input source remained `com.apple.keylayout.German`.
- The `v0.1.5-rc32` GitHub release asset digest is
  `sha256:ed7d0ac9274253982d1dbc790e28b93b28d0d1c150e8aa51ba89fa932be29537`,
  and the remote tag was corrected to point at
  `b08f648b8535207a0a105593e2e9ff330b787016` after publish.
- `v0.1.5-rc33` adds `presstalk-input-method-client-probe.swift` to the
  release bundle. The probe performs the reversible end-to-end IMK test:
  register, temporarily enable/select the PressTalk input method, focus a local
  `NSTextView`, post the insert payload, check whether text appears, write JSON
  diagnostics, and restore the original input source.
- `v0.1.5-rc33` fixes the input-method server startup path by replacing the
  delegate-as-`@main` pattern with an explicit `NSApplication.shared` run loop.
  A manual background launch of the installed input-method app now writes
  `app launched` and `insert notification observer installed` to
  `~/Library/Logs/presstalk_input_method.log`.
- `v0.1.5-rc33` also hardens the generated input-method bundle metadata:
  `CFBundleSupportedPlatforms`, `CFBundleSignature`,
  `NSSupportsSuddenTermination`, `TISIconIsTemplate`, a visible
  `ComponentInputModeDict`, and exported `PressTalkIMController` ObjC class.
  The installer attempts to clear quarantine/provenance metadata from the copied
  `~/Library/Input Methods/PressTalkInputMethod.app`.
- Current `studio1` rc33 evidence: the bundled client probe from
  `~/Applications/PressTalk.app` fails cleanly with
  `success=false`, `reason=input_method_not_selectable`, `registerStatus=0`,
  `recognizedSourceCount=0`, `observedText=""`, and final input source restored
  to `com.apple.keylayout.German`. This means active-field insertion through
  IMK is still not proven; current TIS state does not expose the PressTalk input
  method as an enable/select-capable source.
- After publishing `v0.1.5-rc33`, `studio1` was restored to the legacy working
  privacy identity with `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status after restore: `permissionPaneOpeningAllowed=false`,
  `setupRetryActive=false`, `microphoneAuthorizationStatus=authorized`,
  `microphoneGranted=true`, `inputMonitoringEffective=true`,
  `inputListener=hid:listen_only`, `inputPipelineReady=true`,
  `status.speechModel=Ready`, and `status.triggerPath=Fn / Globe ready`.
- The `v0.1.5-rc33` GitHub release asset digest is
  `sha256:462256f9b9d775b548aec2334ac7f087b874ff62767e48aa775cd7bce8d86e40`,
  and the remote tag points at
  `37dbb045e44142daa46c5045805f1dc1a3686918`.
- Post-rc33 local debugging reproduced the settings-loop root cause on
  `studio1`: running `scripts/build_jarvistap.sh` without an explicit bundle id
  rebuilt the installed app as `com.am.presstalk`. The no-pane launch then
  reported `microphoneAuthorizationStatus=not_determined`,
  `microphoneGranted=false`, `inputMonitoringEffective=false`,
  `inputListener=not_installed`, and `setupRetryActive=true`, even though the
  same machine's working privacy grants are under `com.am.jarvistap`. This was
  an identity mismatch, not evidence that the user had skipped permissions.
- Post-rc33 local fix: `scripts/build_jarvistap.sh` now preserves the currently
  installed `PressTalk.app` bundle identifier by default and creates or reuses
  the stable local development code-signing identity unless
  `PRESSTALK_BUILD_STABLE_SIGNING=0` is explicitly set, while
  `scripts/package_presstalk_release.sh` explicitly forces the public
  `com.am.presstalk` identity and disables local signing for release artifacts.
  This keeps local rebuilds from silently switching a working development
  install into a different macOS privacy client or a new ad-hoc CDHash.
- Runtime status and Settings now expose `status.codeSignatureIdentifier`,
  `status.codeSignatureCDHash`, and `status.codeSignatureAuthority`; the
  no-pane Settings hint names the exact bundle id/CDHash being checked and says
  that the run will not open System Settings.
- The release bundle now includes `presstalk-unicode-event-insert-probe.swift`.
  On `studio1`, the original probe posted Unicode CGEvents into a focused local
  `NSTextView` while `AXIsProcessTrusted=false`, but observed no inserted text.
  Post-rc35 local debugging expanded the same probe to test HID, session,
  annotated-session, and PID-targeted posting. Result JSON
  `unicode-event-insert-probe-2026-06-06T21-54-53-225Z.json` reports
  `success=false`, `reason=timeout_waiting_for_payload`, `observedText=""`,
  and all four `methodResults` have `postResult=posted` with `success=false`.
  This rules out these CGEvent routes as reliable no-Accessibility insertion
  fallbacks on this machine.
- After the local identity regression was reproduced, `studio1` was restored
  with `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status after restore: `bundleIdentifier=com.am.jarvistap`,
  `codeSignatureAuthority=PressTalk Local Development Code Signing`,
  `microphoneAuthorizationStatus=authorized`, `microphoneGranted=true`,
  `inputMonitoringEffective=true`, `inputListener=hid:listen_only`,
  `inputPipelineReady=true`, `setupRetryActive=false`,
  `status.speechModel=Ready`, and `status.triggerPath=Fn / Globe ready`.
- Post-rc34 local debugging tightened the bundled InputMethodKit prototype:
  generated metadata now includes a separate visible input mode id,
  background-only IMK metadata, a bundled TIFF icon, and a character repertoire;
  the input-method bundle signs with the same
  `PressTalk Local Development Code Signing` identity by default. Verification
  still shows `TISRegisterInputSource=0` but `recognizedSourceCount=0`, even
  after LaunchServices registration and a TextInputMenuAgent restart. The
  exported `PressTalkIMController` Objective-C class and on-disk code signature
  both verify. Treat the remaining IMK failure as a macOS input-source
  discovery/trust blocker, not as missing Microphone, Input Monitoring, or
  Accessibility permissions.
- Post-rc35 local debugging made the generated input-method bundle more
  Apple-like by using string-valued `LSUIElement`, adding `CFBundleIconFile`,
  and making the build-script `--install` path attempt quarantine/provenance
  cleanup. Post-rc36 debugging restored the docs-required `LSBackgroundOnly=1`
  key for `IMKServer.init(name:bundleIdentifier:)`. Rebuild/install/register
  still reports `TISRegisterInputSource=0` and `recognizedSourceCount=0`, so
  these metadata changes are not sufficient to solve TIS discovery on
  `studio1`.
- Post-rc36 local debugging added `presstalk-accessibility-identity-probe.sh`.
  It launches no-prompt background probes for `com.am.jarvistap` and
  `com.am.presstalk`, both stable-signed and ad-hoc. On `studio1`,
  `accessibility-identity-probe-2026-06-06T22-13-46Z.json` reported
  `accessibilityTrusted=false` for all four candidates. This supports the
  running app's `AXIsProcessTrusted=false` result and means there is no broad
  Accessibility trust currently visible to those PressTalk identities.
- After publishing `v0.1.5-rc36`, `studio1` was restored to
  `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status after restore: `bundleIdentifier=com.am.jarvistap`,
  `codeSignatureAuthority=PressTalk Local Development Code Signing`,
  `microphoneAuthorizationStatus=authorized`, `microphoneGranted=true`,
  `inputMonitoringEffective=true`, `inputListener=hid:listen_only`,
  `inputPipelineReady=true`, `setupRetryActive=false`,
  `permissionPaneOpeningAllowed=false`, `status.speechModel=Ready`, and
  `status.triggerPath=Fn / Globe ready`.
- `v0.1.5-rc37` includes the no-prompt Accessibility identity probe, restores
  `LSBackgroundOnly=1` in the bundled input-method prototype, and replaces
  product-specific automated-smoke audio-route wording with the generic rule:
  `/usr/bin/say` playback must be audible to the microphone for acoustic TTS
  smoke tests to be meaningful.
- `v0.1.5-rc38` fixes the Settings permission-loop UX: the Settings window is
  resizable and scrollable, the Accessibility row now reports `AX false; copy
  fallback` / `AX false; copy-only mode`, diagnostics write
  `accessibilityStatus=ax_false_copy_fallback` or `ax_false_copy_only`, and the
  no-pane hint names `AXIsProcessTrusted=false` for the exact signed app instead
  of sending users back through already-enabled macOS Privacy toggles.
- The `v0.1.5-rc38` GitHub release asset digest is
  `sha256:af84fafc1b1bf0e014afdce776ef4d69f09f1e0ab2bb54eb9dfb0d569c802562`,
  and the remote tag points at
  `02e74505e91572fe1463943cb6bea61261a3f9a3`.
- After publishing `v0.1.5-rc38`, `studio1` was restored to
  `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status after restore: `bundleIdentifier=com.am.jarvistap`,
  `codeSignatureAuthority=PressTalk Local Development Code Signing`,
  `codeSignatureCDHash=169354db5cd453fab31ad47d2e0e87cb15d4102b`,
  `microphoneAuthorizationStatus=authorized`, `microphoneGranted=true`,
  `microphoneStatus=preflight_granted`,
  `inputMonitoringEffective=true`,
  `inputMonitoringStatus=listener_ready_preflight_unavailable`,
  `inputListener=hid:listen_only`, `inputPipelineReady=true`,
  `setupRetryActive=false`, `permissionPaneOpeningAllowed=false`,
  `accessibilityStatus=ax_false_copy_fallback`, `status.speechModel=Ready`,
  and `status.triggerPath=Fn / Globe ready`.
- Post-rc38 local debugging tested whether the Accessibility mismatch was caused
  by the app path. Copying the same `com.am.jarvistap` stable-signed app to
  `/Applications/PressTalk.app` and bootstrapping with no-pane flags still
  reported `accessibilityStatus=ax_false_copy_fallback`, so the current
  `AXIsProcessTrusted=false` blocker is not fixed by switching from
  `~/Applications/PressTalk.app` to `/Applications/PressTalk.app`.
- Post-rc38 local debugging fixed a smoke-status blind spot: the bundled
  collector now derives the inspected app bundle from the live PressTalk process
  before falling back to install defaults, and it prints both
  `Status bundle path` and `App bundle path`. This prevents path/signature
  mismatch audits from accidentally inspecting `~/Applications/PressTalk.app`
  while launchd is running `/Applications/PressTalk.app`.
- Post-rc38 InputMethodKit debugging removed the stale
  `com.am.presstalk.inputmethod.dictation` mode assumption from the status and
  client probes. The generated input method now uses the single source id
  `com.am.presstalk.inputmethod` with Apple-documented IMK metadata. On
  `studio1`, `TISRegisterInputSource=0`, but
  `recognizedSourceCount=0`, `recognizedEnabledSourceCount=0`, and
  `recognizedAllSourceCount=0` remain after installing, registering, moving aside
  `~/Library/Caches/com.apple.tiswitcher.cache`, and restarting text-input
  agents.
- `v0.1.5-rc39` publishes the live-process-aware smoke-status collector and the
  single-source IMK diagnostics. The GitHub release asset digest is
  `sha256:2c8b31b1a7c0c0d6eb09c1df0a2b9f7fc66d6c6255d7b4d47977e6a6afda77c5`,
  and the remote tag points at
  `5425a3fe02eefcdafb299c4e824f7661048c0495`.
- `v0.1.5-rc40` publishes the actual-bundle Accessibility trust probe. The
  bundled `presstalk-actual-accessibility-probe.sh` launches the installed
  `PressTalk.app` itself with `PRESSTALK_ACCESSIBILITY_TRUST_PROBE=1` and
  `kAXTrustedCheckOptionPrompt=false`, records bundle path, bundle id, CDHash,
  signing authority, and `accessibilityTrusted`, then exits before normal
  startup. The GitHub release asset digest is
  `sha256:1125ec492764f718580a3c3f68985bddadc0fce72629d664bf267a4734e83406`,
  and the remote tag points at
  `8e88a2c2714e4d4713f6b953008e5872b4014620`.
- After publishing `v0.1.5-rc40`, `studio1` was restored to
  `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status after restore: `bundleIdentifier=com.am.jarvistap`,
  `bundlePath=/Users/am/Applications/PressTalk.app`,
  `codeSignatureAuthority=PressTalk Local Development Code Signing`,
  `codeSignatureCDHash=fb494efe3b8cacf28cc2130e6693a4a498dfd0c1`,
  `microphoneAuthorizationStatus=authorized`, `microphoneGranted=true`,
  `microphoneStatus=preflight_granted`,
  `inputMonitoringEffective=true`,
  `inputMonitoringStatus=listener_ready_preflight_unavailable`,
  `inputListener=hid:listen_only`, `inputPipelineReady=true`,
  `setupRetryActive=false`, `permissionPaneOpeningAllowed=false`,
  `accessibilityStatus=ax_false_copy_fallback`, `status.speechModel=Ready`,
  and `status.triggerPath=Fn / Globe ready`. Status consistency reports matching
  live process, status bundle path, app bundle path, bundle id, and CDHash.
- The restored `studio1` actual-bundle probe ran without prompts and reported
  `status=ran`, `promptRequested=false`, `accessibilityTrusted=false`,
  `bundleIdentifier=com.am.jarvistap`,
  `codeSignatureCDHash=fb494efe3b8cacf28cc2130e6693a4a498dfd0c1`, and
  `codeSignatureAuthority=PressTalk Local Development Code Signing` for
  `/Users/am/Applications/PressTalk.app`.
- `v0.1.5-rc41` publishes the adjusted InputMethodKit diagnostics. The generated
  input-method prototype now includes `Contents/PkgInfo`, a visible mode id
  `com.am.presstalk.inputmethod.dictation`, no `LSBackgroundOnly`, and script
  repertoire `Latn`. The status helper also scans the full installed TIS table
  for PressTalk-like sources. On `studio1`, `TISRegisterInputSource` still
  returns `0`, but `recognizedSourceCount=0` and
  `pressTalkLikeAllInstalledSourceCount=0`, so this remains an input-source
  discovery blocker rather than a missing Microphone, Input Monitoring, or
  Accessibility permission. The GitHub release asset digest is
  `sha256:4bd725368218416afdaf097a992783010cbd6e83e211211d3d795e7abdc06ddb`,
  and the remote tag points at
  `ce8f3c48e32afec990f843d8549c4ebd5561af6b`.
- After publishing `v0.1.5-rc41`, `studio1` was restored to
  `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status after restore: `bundleIdentifier=com.am.jarvistap`,
  `bundlePath=/Users/am/Applications/PressTalk.app`,
  `codeSignatureAuthority=PressTalk Local Development Code Signing`,
  `codeSignatureCDHash=c068e650a2f3a6ea7762920994eb2361efb7a1b5`,
  `microphoneAuthorizationStatus=authorized`, `microphoneGranted=true`,
  `microphoneStatus=preflight_granted`,
  `inputMonitoringEffective=true`,
  `inputMonitoringStatus=listener_ready_preflight_unavailable`,
  `inputListener=hid:listen_only`, `inputPipelineReady=true`,
  `setupRetryActive=false`, `permissionPaneOpeningAllowed=false`,
  `accessibilityStatus=ax_false_copy_fallback`, `status.speechModel=Ready`,
  and `status.triggerPath=Fn / Globe ready`. Status consistency reports matching
  live process, status bundle path, app bundle path, bundle id, and CDHash.
- The restored `studio1` actual-bundle probe ran without prompts and reported
  `status=ran`, `promptRequested=false`, `accessibilityTrusted=false`,
  `bundleIdentifier=com.am.jarvistap`,
  `codeSignatureCDHash=c068e650a2f3a6ea7762920994eb2361efb7a1b5`, and
  `codeSignatureAuthority=PressTalk Local Development Code Signing` for
  `/Users/am/Applications/PressTalk.app`.
- Post-rc41 InputMethodKit debugging found the selectable source shape for
  macOS 26.5 on `studio1`: a no-mode input method with bundle/source id
  `com.am.presstalk.inputmethod.container`. The generated bundle no longer uses
  the visible `.dictation` mode id for the active source. Current status helper
  evidence after install/register: `recognizedSourceCount=1`,
  `recognizedEnabledSourceCount=1`, `source.id=com.am.presstalk.inputmethod.container`,
  `type=TISTypeKeyboardInputMethodWithoutModes`, `selectCapable=true`, and
  `registerStatus=0`.
- The focused input-method client probe now succeeds on `studio1` without
  opening System Settings and while the restored app remains
  `AXIsProcessTrusted=false`: `success=true`, `reason=payload_inserted`,
  `selectStatus=0`, `restoreStatus=0`, `observedText="PressTalk input method
  client probe"`. The input-method log records `client updated context=init`,
  `controller initialized`, `insert requested characters=35`, and
  `insert notification handled inserted=1`.
- Production dictation now attempts this input-method insertion route before
  copy fallback when Accessibility is untrusted. It installs/registers the
  bundled `PressTalkInputMethod.app` if needed, selects
  `com.am.presstalk.inputmethod.container`, writes the transcript to
  `~/Library/Application Support/JarvisTap/input-method-insert.txt`, posts
  `com.am.presstalk.inputmethod.insert`, restores the original input source, and
  only copies if that setup fails. This proves the local focused-client insertion
  mechanism, but it is not yet cross-machine proof for `s1`, `s2`, or `mbp1`.
- After wiring the no-mode input-method fallback, `studio1` was rebuilt and
  restored again with `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`. Runtime
  status reports `codeSignatureCDHash=263a057d530e45af51d131962ebde5c07a99188b`,
  `microphoneAuthorizationStatus=authorized`, `inputMonitoringEffective=true`,
  `inputPipelineReady=true`, `setupRetryActive=false`,
  `accessibilityStatus=ax_false_input_method_fallback`,
  `permissionPaneOpeningAllowed=false`, `status.speechModel=Ready`, and
  `status.triggerPath=Fn / Globe ready`. The bundled input-method status helper
  reports `registerStatus=0`, `recognizedSourceCount=1`,
  `recognizedEnabledSourceCount=1`, `source.id=com.am.presstalk.inputmethod.container`,
  and `type=TISTypeKeyboardInputMethodWithoutModes`.
- After publishing `v0.1.5-rc39`, `studio1` was restored to
  `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status after restore: `bundleIdentifier=com.am.jarvistap`,
  `bundlePath=/Users/am/Applications/PressTalk.app`,
  `codeSignatureAuthority=PressTalk Local Development Code Signing`,
  `codeSignatureCDHash=40e2ad34497d13552fd78fa7009b460be6cf70b5`,
  `microphoneAuthorizationStatus=authorized`, `microphoneGranted=true`,
  `microphoneStatus=preflight_granted`,
  `inputMonitoringEffective=true`,
  `inputMonitoringStatus=listener_ready_preflight_unavailable`,
  `inputListener=hid:listen_only`, `inputPipelineReady=true`,
  `setupRetryActive=false`, `permissionPaneOpeningAllowed=false`,
  `accessibilityStatus=ax_false_copy_fallback`, `status.speechModel=Ready`,
  and `status.triggerPath=Fn / Globe ready`. Status consistency reports matching
  live process, status bundle path, app bundle path, bundle id, and CDHash.
- After publishing `v0.1.5-rc37`, `studio1` was restored to
  `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status after restore: `bundleIdentifier=com.am.jarvistap`,
  `codeSignatureAuthority=PressTalk Local Development Code Signing`,
  `microphoneAuthorizationStatus=authorized`, `microphoneGranted=true`,
  `inputMonitoringEffective=true`, `inputListener=hid:listen_only`,
  `inputPipelineReady=true`, `setupRetryActive=false`,
  `permissionPaneOpeningAllowed=false`, `status.speechModel=Ready`, and
  `status.triggerPath=Fn / Globe ready`.
- A skipped macOS signing/trust password prompt can explain earlier unstable
  local identity behavior: builds may still receive a code signature, but a
  self-signed development identity is not a production Gatekeeper approval. Do
  not reopen privacy panes repeatedly in this state; inspect the bundle id,
  CDHash, and signing authority first.
- `v0.1.5-rc35` updates the bundled automated F5 smoke helper to classify
  near-silent TTS captures as an audio-routing failure instead of a generic STT
  timeout. If `/usr/bin/say` playback is routed somewhere the microphone cannot
  hear, helper JSON reports `reason=tts_audio_not_captured_by_microphone`,
  `targetCaptureFailureHint=tts_output_not_heard_by_microphone`, and
  `traceAudioCapture` RMS/peak evidence.
- After publishing `v0.1.5-rc35`, `studio1` was restored to
  `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status after restore: `bundleIdentifier=com.am.jarvistap`,
  `codeSignatureAuthority=PressTalk Local Development Code Signing`,
  `microphoneAuthorizationStatus=authorized`, `microphoneGranted=true`,
  `inputMonitoringEffective=true`, `inputListener=hid:listen_only`,
  `inputPipelineReady=true`, `setupRetryActive=false`,
  `permissionPaneOpeningAllowed=false`, `status.speechModel=Ready`, and
  `status.triggerPath=Fn / Globe ready`.
- Bootstrap now clears `com.apple.quarantine` and `com.apple.provenance` xattrs,
  explicitly re-enables `gui/$UID/com.am.jarvistap`, and does not silently treat
  a failed launchd bootstrap as success.
- On `studio1`, a no-pane/no-auto-window restart of the rc10-equivalent local
  build reports `runtime.inputListener=hid:listen_only`,
  `runtime.inputPipelineReady=true`, `status.speechModel=Ready`, and
  `status.triggerPath=Fn / Globe ready`. Trace evidence also shows the actual
  WhisperKit cache layout under `Models/models/...` and the local tokenizer
  folder under `Models/models/openai/whisper-large-v3`.
- After the rc6 publish path, the local app was re-bootstrapped and re-signed as
  `Authority=PressTalk Local Development Code Signing`; the collector reports
  LaunchAgent `program = /usr/bin/open`, `Open permission panes: 0`,
  `microphoneGranted=true`, `inputMonitoringGranted=false`,
  `accessibilityGranted=false`, and `setupRetryActive=true`.
- `v0.1.5-rc17` defaults WhisperKit to a no-Neural-Engine compute preset:
  `mel=cpuAndGPU`, `audioEncoder=cpuAndGPU`, `textDecoder=cpuAndGPU`, and
  `prefill=cpuOnly`. This avoids the mbp1/macOS 26.5 Core ML load path where
  isolated probes timed out for `TextDecoder` with `.cpuAndNeuralEngine` and
  `.all`, and for `AudioEncoder` with `.cpuAndNeuralEngine` and `.all`.
- `PRESSTALK_WHISPER_COMPUTE=default` is retained as an escape hatch for
  WhisperKit's upstream compute defaults when explicitly desired.
- `v0.1.5-rc18` adds `PRESSTALK_BUNDLE_IDENTIFIER` for the build/bootstrap
  path. The default app identity remains `com.am.presstalk`, but a machine with
  older working grants can preserve `com.am.jarvistap` without opening privacy
  panes.
- `v0.1.5-rc19` adds a `Status Consistency` section to the bundled smoke-status
  collector. It compares `runtime-status.json` with the live PressTalk process
  and installed app signature, so stale or mismatched diagnostics are visible.
- `v0.1.5-rc20` and later improve `presstalk-manual-fn-smoke.swift`: the
  helper reads the configured runtime trigger key, labels Option + Space,
  Fn/Option/F5, or trackpad smoke correctly, and records exact expected-trigger
  proof plus readiness before and after the manual paste attempt.
- `v0.1.5-rc22` adds `presstalk-automated-f5-smoke.swift`, an explicit
  synthetic pipeline helper. It posts the F5 Darwin trigger bridge, speaks a
  local phrase through system audio, and records PressTalk trace evidence for
  transcription and paste command posting. Its JSON result sets
  `physicalTriggerProof=false`, includes `traceFinalTranscript` and
  `tracePasteCommandPosted`, and separately reports `targetCaptureSuccess` /
  `tracePasteCompleted`, so it helps isolate STT/paste failures but does not
  replace physical Fn or Option smoke.
- `studio1` local synthetic F5/Darwin/TTS smoke on 2026-06-06 succeeded at the
  trace pipeline level after a temporary no-pane F5 bootstrap. Result JSON:
  `success=true`, `reason=trace_pipeline_completed`,
  `physicalTriggerProof=false`, `tracePasteCompleted=true`,
  `traceFinalTranscript="Press Talg Automated Smoke Test."`,
  `targetCaptureSuccess=false`, with runtime readiness true at start and finish.
  The app was restored to `PRESSTALK_TRIGGER_KEY=fn` afterward and status
  consistency was clean.
- `v0.1.5-rc23` paste work changes insertion to pasteboard plus Cmd-V
  instead of per-code-unit Unicode key events, delays pasteboard restore to 1.0s,
  and changes trace wording from `Dictation paste completed` to
  `Dictation paste command posted`. The revised synthetic helper now separates
  `tracePasteCommandPosted` from `tracePasteCompleted`.
- `v0.1.5-rc24` settings/status work suppresses automatic setup
  window presentation when `PRESSTALK_OPEN_PERMISSION_PANES=0`, makes Run Setup
  Check refresh status without reopening the Settings window, hides privacy-pane
  buttons in no-pane mode, and removes `missing` / `refresh macOS permissions`
  wording from diagnostics. After packaging rc24, `studio1` was restored to the
  legacy `com.am.jarvistap` no-pane path; runtime status reports
  `permissionPaneOpeningAllowed=false`, `setupRetryActive=false`,
  `inputMonitoringStatus=listener_ready_preflight_unavailable`,
  `microphoneStatus=preflight_granted`,
  `accessibilityStatus=paste_probe_pending`, and
  `status.triggerPath=Fn / Globe ready`.
- `v0.1.5-rc25` adds a paste-event self-test to the automated F5 smoke helper.
  Before synthetic dictation, the helper tries focused-window Cmd-V insertion
  across several CGEvent source/tap combinations and records `pasteSelfTest`
  plus `targetCaptureFailureHint`. This separates STT/trigger success from a
  local paste-event synthesis blocker.
- `v0.1.5-rc26` changes production insertion behavior. If Accessibility is
  trusted, PressTalk first tries direct AX insertion into the focused text
  element, then falls back to pasteboard plus Cmd-V. If Accessibility is not
  trusted, PressTalk copies the transcript to the clipboard and records
  `dictation_copy_fallback` instead of posting a Cmd-V command that cannot land.
	  Runtime status reports an explicit copy-fallback Accessibility state in that
	  condition.
- `studio1` local post-rc22 synthetic F5/Darwin/TTS smoke with the revised
  helper and paste path reported `success=true`,
  `reason=trace_pipeline_command_posted`,
  `traceFinalTranscript="Press Teig Automated Smoke Test."`,
  `tracePasteCommandPosted=true`, `tracePasteCompleted=false`, and
  `targetCaptureSuccess=false`. Runtime readiness was true, and the app was
  restored to Fn with clean status consistency. This shows STT and paste-command
  posting work, but target-field insertion remains unproven while
  `accessibilityGranted=false`.
- `studio1` rc27 synthetic F5/Darwin/TTS smoke succeeded at the trace pipeline
  level after a temporary no-pane F5 bootstrap, then the app was restored to Fn.
  Result JSON:
  `~/Library/Application Support/JarvisTap/Diagnostics/automated-f5-smoke-2026-06-06T19-36-28.582Z.json`
  reported `success=true`, `reason=trace_pipeline_copy_fallback`,
  `physicalTriggerProof=false`, `microphoneAuthorizationStatus=authorized`,
  `traceCopyFallback=true`, `tracePasteCommandPosted=false`,
  `tracePasteCompleted=false`,
  `traceFinalTranscript="Press type automated smoke test."`,
  `targetCaptureSuccess=false`, and
  `targetCaptureFailureHint=accessibility_untrusted_copy_fallback`. Final
  restored status was `triggerKey=fn`, `triggerPath=Fn / Globe ready`, and
  `speechModel=Ready`.
- `studio1`: a no-pane rc21-equivalent local install from commit
  `f92daebee990f7d45d66cb577cce05e250894d4b` was bootstrapped with
  `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status reports `microphoneGranted=true`,
  `inputMonitoringEffective=true`, `permissionPaneOpeningAllowed=false`,
  `inputListener=hid:listen_only`, `inputPipelineReady=true`,
  `setupRetryActive=false`, `status.triggerPath=Fn / Globe ready`, and
  `status.speechModel=Ready`. `Status Consistency` reports matching live
  process ID, bundle identifier `com.am.jarvistap`, and CDHash
  `66f3283b9e152b633bb4102603d3c6f9bd61699e`.
- `studio1`: after publishing `v0.1.5-rc31`, the local app was restored with
  `PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  Runtime status reports `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, `permissionPaneOpeningAllowed=false`,
  `inputListener=hid:listen_only`, `inputPipelineReady=true`,
  `setupRetryActive=false`, `status.triggerPath=Fn / Globe ready`, and
  `status.speechModel=Ready`. The local bundle includes
  `PressTalkInputMethod.app`, `presstalk-install-input-method.sh`, and
  `presstalk-input-method-insert-probe.sh`; the local installed manual smoke
  helper is schema `smokeVersion=3`.

Known current proof gaps:

- `studio1` no longer has a listener/probe setup blocker after the listen-only
  event-tap fix. The remaining `studio1` proof gap is a physical Fn hold
  dictation and paste smoke; a synthetic Fn event was not counted as proof.
- `studio2`: `v0.1.5-rc31` was downloaded from GitHub with SHA-256
  `38106cb2c2917348ab13332661e0b4463f55d56d39caef89a0cca04dfae2d553` and
  bootstrapped with `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, `PRESSTALK_TRIGGER_KEY=fn`, and
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING=0`. LaunchAgent starts and
  `permissionPaneOpeningAllowed=false`, but runtime is blocked before dictation
  because `microphoneGranted=false`,
  `microphoneAuthorizationStatus=not_determined`,
  `microphoneStatus=preflight_not_determined`,
  `inputMonitoringEffective=false`,
  `inputMonitoringStatus=preflight_unavailable`,
  `inputListener=not_installed`, `inputPipelineReady=false`, and
  `setupRetryActive=true`. The current ad-hoc CDHash is
  `ce7df45396445744313871a15d7003ac652c1a68`. The installed manual smoke
  helper is schema `smokeVersion=3` with `targetCaptureSuccess` and
  `traceCopyFallback` fields, and the app bundle contains the input-method
  prototype plus installer/probe helpers. The rc28 read-only TCC audit
  reported no user TCC rows for `com.am.presstalk` or `com.am.jarvistap`;
  system TCC only contained a denied Accessibility row for `com.am.presstalk`
  with requirement `cdhash H"ede4ea701e897b06b9d7817353f228c192602161"`,
  while the rc28 app had designated requirement
  `cdhash H"3021d05388aae5e1a73d6dc9c02947e4e319a40b"`. This remains a
  first-grant/setup gap, not an already-granted false-missing state.
- `mbp1`: `v0.1.5-rc31` was downloaded from GitHub with SHA-256
  `38106cb2c2917348ab13332661e0b4463f55d56d39caef89a0cca04dfae2d553` and
  bootstrapped with `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and
  `PRESSTALK_BOOTSTRAP_STABLE_SIGNING=0`. The installed app is ad-hoc signed
  with bundle identifier `com.am.presstalk` and CDHash
  `ce7df45396445744313871a15d7003ac652c1a68`. The installed manual smoke
  helper is schema `smokeVersion=3` with `targetCaptureSuccess` and
  `traceCopyFallback` fields, and the app bundle contains the input-method
  prototype plus installer/probe helpers.
- `mbp1` no longer has the rc15 microphone/listener blocker. Runtime status
  after rc31 reports `microphoneGranted=true`,
  `microphoneAuthorizationStatus=authorized`,
  `microphoneStatus=preflight_granted`, `inputMonitoringEffective=true`,
	  `inputMonitoringStatus=listener_ready_preflight_unavailable`,
	  `accessibilityGranted=false` with copy fallback active,
  `permissionPaneOpeningAllowed=false`, `inputListener=hid:listen_only`,
  `inputPipelineReady=true`, `setupRetryActive=false`,
  `status.triggerPath=Fn / Globe ready`, and `status.speechModel=Ready`.
  `Status Consistency` reports matching live process ID, bundle identifier, and
  CDHash.
- `mbp1` rc27 TCC audit explains the apparent settings mismatch: Microphone
  rows exist for both `com.am.presstalk` and `com.am.jarvistap`; Input
  Monitoring rows exist for both identities in system TCC; Accessibility has an
  allowed row for stale `com.am.jarvistap` but a denied row for
  `com.am.presstalk`. A no-pane rc27 bootstrap under `com.am.jarvistap` did not
  satisfy the old row's code requirement and regressed to
  `microphoneAuthorizationStatus=not_determined`, `inputPipelineReady=false`,
  and `accessibilityGranted=false`, so mbp1 was restored to the working
  `com.am.presstalk` Fn path.
- The rc28 collector decoded the mbp1 requirements: the then-running
  `com.am.presstalk` app was ad-hoc signed with designated requirement
  `cdhash H"3021d05388aae5e1a73d6dc9c02947e4e319a40b"`. The stale allowed
  `com.am.jarvistap` Microphone/Input Monitoring/Accessibility rows require
  `identifier "com.am.jarvistap" and certificate root =
  H"f2671c00575e4d2f123bb3c28ab3e2461de33fb3"`, and that certificate/private
  signing identity was not found on mbp1, studio1, or studio2. A normal new
  local signing identity would not match those old grants.
- `mbp1` rc24 synthetic F5/Darwin/TTS smoke succeeded at the trace pipeline
  level after a temporary no-pane F5 bootstrap, then the app was restored to Fn.
  Result JSON:
  `success=true`, `reason=trace_pipeline_command_posted`,
  `physicalTriggerProof=false`, `tracePasteCommandPosted=true`,
  `tracePasteCompleted=false`,
  `traceFinalTranscript="Press-Teil-Automated-Smoke-Test"`,
  `targetCaptureSuccess=false`, with runtime readiness true at start and finish.
  Final restored Fn status was ready.
- `mbp1` rc25 synthetic F5/Darwin/TTS smoke with paste self-test succeeded at
  the trace pipeline level after a temporary no-pane F5 bootstrap, then the app
  was restored to Fn. Result JSON: `success=true`,
  `reason=trace_pipeline_command_posted`, `physicalTriggerProof=false`,
  `tracePasteCommandPosted=true`, `tracePasteCompleted=false`,
  `targetCaptureSuccess=false`, `pasteSelfTest.success=false`, and
  `targetCaptureFailureHint=local_cmd_v_event_synthesis_unavailable`.
  `Status Consistency` reports matching live process ID, bundle identifier, and
  CDHash after the restored Fn restart. Read-only TCC inspection on mbp1 shows
  microphone rows for `com.am.presstalk` and `com.am.jarvistap`, but no
  Accessibility row for PressTalk, matching the paste self-test result.
- `mbp1` rc26 synthetic F5/Darwin/TTS smoke succeeded at the trace pipeline
  level after a temporary no-pane F5 bootstrap, then the app was restored to Fn.
  Result JSON: `success=true`, `reason=trace_pipeline_copy_fallback`,
  `physicalTriggerProof=false`, `traceCopyFallback=true`,
  `tracePasteCommandPosted=false`, `tracePasteCompleted=false`,
  `targetCaptureSuccess=false`, and
  `targetCaptureFailureHint=accessibility_untrusted_copy_fallback`. This proves
  the app no longer posts a fake paste command on mbp1 when Accessibility is not
  trusted; active-field paste remains unproven until Accessibility trust exists.
- `mbp1` rc27 synthetic F5/Darwin/TTS smoke succeeded at the trace pipeline
  level after a temporary no-pane F5 bootstrap, then the app was restored to Fn.
  Result JSON:
  `~/Library/Application Support/JarvisTap/Diagnostics/automated-f5-smoke-2026-06-06T19-32-00.323Z.json`
  reported `success=true`, `reason=trace_pipeline_copy_fallback`,
  `physicalTriggerProof=false`, `microphoneAuthorizationStatus=authorized`,
  `traceCopyFallback=true`, `tracePasteCommandPosted=false`,
  `tracePasteCompleted=false`,
  `traceFinalTranscript="Press-Tag Automated Smoke Test"`,
  `targetCaptureSuccess=false`, and
  `targetCaptureFailureHint=accessibility_untrusted_copy_fallback`. Final
  restored status was `triggerKey=fn`, `triggerPath=Fn / Globe ready`, and
  `speechModel=Ready`.
- `v0.1.5-rc52` adds the input-method state to the smoke collector so post-repair
  mbp1 evidence can prove matching input-method signatures and TIS enablement
  before interpreting insertion probes.
- `v0.1.5-rc53` makes that blocker visible in app runtime status and Settings:
  mbp1 reports `inputMethodFallbackStatus=recognized_disabled`, not a ready
  fallback. This is diagnostic progress, not active-field insertion proof.
- `v0.1.5-rc51` adds a bundled no-pane signing repair
  wrapper and updates bootstrap to sign/refresh `PressTalkInputMethod.app`
  alongside the outer app. This is intended for the mbp1
  `input_method_enable_no_effect` blocker after a skipped signing-trust password
  prompt. It has studio1 production-probe proof but still needs mbp1 desktop
  repair plus production insertion probe proof before the goal is complete.
- `v0.1.5-rc50` includes the listen-only event-tap fallback, WhisperKit cache
  layout/tokenizer prefetch fixes, no-automatic-prompt/no-auto-settings window
  fixes, settings status fixes for already-granted permission toggles, the mbp1
  launchd disabled-label/provenance fix, the `com.am.presstalk` bundle
  identifier fix, the no-ANE WhisperKit compute preset,
  `PRESSTALK_BUNDLE_IDENTIFIER` for legacy identity fallback, the smoke-status
  consistency checker, decoded TCC code-requirement diagnostics, app-level
  no-pane enforcement, the actual-bundle Accessibility trust probe, the no-mode
  InputMethodKit fallback before copy fallback when Accessibility is untrusted,
  the Accessibility row/status label fix for `ax_false_input_method_fallback`,
  adjusted InputMethodKit diagnostics, and bootstrap output that separates
  stable-signing requested from stable-signing applied. Input-method diagnostics
  also report `input_method_select_failed` when source recognition succeeds but
  `TISSelectInputSource` fails, and manual physical-trigger smoke records
  `traceInputMethodSelectFailed` / `traceInputMethodFailure` so STT success can
  be separated from active-field insertion failure. It also includes the
  `input_method_enable_no_effect` classifier for the mbp1 shape where
  `TISEnableInputSource` returns `0` but the source remains disabled, the
  `LSBackgroundOnly=true` input-method metadata fix, and a local signing helper
  fix that retries trust on existing untrusted PressTalk identities instead of
  importing another duplicate certificate. It also includes the opt-in
  production insertion probe, which asks the running PressTalk app process to
  insert into a focused helper window through the same path used after
  dictation, then restores normal startup. It also includes
  `presstalk-manual-fn-smoke.swift`, which opens a focused text window and
  records physical Fn dictation smoke results as JSON, plus the rc29
  success-path setup-window fix, the rc30 manual-smoke insertion evidence
  fields, and the rc31 opt-in InputMethodKit insertion prototype. It is the
  artifact to use for the next cross-machine smoke attempts.
- Local SSH aliases `s1` and `s2` are still not configured on `studio1`.
  Direct SSH to `s1` / `s2` does not resolve from this host, and mDNS/DNS lookup
  only resolves `studio1` and `studio2`. `studio2` is reachable as `studio2` or
  `studio2-tb`; `mbp1` is reachable via `mbp1-tb`.
- `mbp1` rc50 was installed from the GitHub release artifact over SSH with
  SHA-256 verified as
  `b72b147689089395fc1b33cb5b9b76130ac25860f9dc2062ffb71c6b8c3f8aaa`.
  Bootstrap used `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn`.
  After warmup, runtime status reported app CDHash
  `cd1123738fa7386223f07805100cf5ad94e9eed9`,
  `bundleIdentifier=com.am.presstalk`,
  `permissions.microphoneAuthorizationStatus=authorized`,
  `permissions.inputMonitoringEffective=true`,
  `runtime.inputPipelineReady=true`, `runtime.setupRetryActive=false`,
  `status.speechModel=Ready`, and `status.triggerPath=Fn / Globe ready`. This
  is runtime-readiness evidence, not physical Fn dictation/paste proof.
- On `mbp1`, bootstrap over SSH could not create a trusted local development
  signing identity because macOS denied Keychain trust changes without user
  interaction. The app therefore ran ad-hoc for the SSH install
  (`status.adHocSigned=true`), and the rc50 bootstrap summary correctly reported
  `Stable local signing requested: 1` and `Stable local signing applied: 0`.
  The fixed rc49 helper found the existing untrusted PressTalk local signing
  identity and retried trust instead of importing another duplicate; the mbp1
  local-signing identity count stayed at `13` before and after bootstrap. Treat
  this as a signing/identity caveat for remote installs, not as a missing
  microphone/input permission.
- `mbp1` rc50 input-method fallback is not yet a proven insertion path. After
  installing the bundled `PressTalkInputMethod.app`, the bundled reversible
  client probe reported `success=false`,
  `reason=input_method_enable_no_effect`, `registerStatus=0`,
  `enableStatus=0`, `enableNoEffect=true`, `selectStatus=-50`,
  `restoreStatus=0`, `disableStatus=0`,
  `pressTalkWasEnabledBeforeProbe=false`, and `observedText=""`. The source was
  visible in the all-installed list as
  `com.am.presstalk.inputmethod.container` with
  `TISTypeKeyboardInputMethodWithoutModes`, `enableCapable=true`, and
  `selectCapable=true`, but `enabled=false` before and after enable. This means
  macOS recognizes the input method and accepts the enable API call but does not
  actually enable it on the ad-hoc mbp1 install; active-field insertion remains
  blocked there unless Accessibility is trusted, the signing/trust state is
  repaired interactively, or another insertion mechanism is implemented.
- `mbp1` rc50 production insertion probe confirms the same blocker from the
  running PressTalk app process, not only from the standalone client probe. The
  helper temporarily enabled `PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE=1`,
  opened a focused local text window, and asked PressTalk to insert one payload.
  Result JSON
  `~/Library/Application Support/JarvisTap/Diagnostics/production-insertion-probe-2026-06-07T01-02-45-588Z.json`
  reported `success=false`, `targetCaptureSuccess=false`,
  `targetCaptureFailureHint=input_method_enable_no_effect`,
  `traceNotificationInstalled=true`, `traceNotificationReceived=true`,
  `traceInputMethodEnableNoEffect=true`,
  `traceInputMethodFailure="enable_no_effect status=-50"`,
  `traceCopyFallback=true`, and
  `traceProductionFailure=accessibility_preflight_unavailable`. Trace lines
  show `Input method insertion enable had no visible effect`, `enabled_count=0
  all_installed_count=1`, and `Input method insertion unavailable
  reason=enable_no_effect status=-50`. The wrapper restored normal no-probe
  startup afterward; final runtime remained ready.
- `mbp1` rc52 was installed from the GitHub release artifact over SSH with
  SHA-256 verified as
  `6e359be871ed408f871f98357e59e9c32544b977b92976e6e62990b6c2df694e`, then
  bootstrapped with `PRESSTALK_BOOTSTRAP_STABLE_SIGNING=0`,
  `PRESSTALK_OPEN_PERMISSION_PANES=0`,
  `PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0`, and `PRESSTALK_TRIGGER_KEY=fn` to avoid
  desktop signing-trust prompts and privacy panes. Runtime remains ready:
  `microphoneAuthorizationStatus=authorized`,
  `inputMonitoringEffective=true`, `inputListener=hid:listen_only`,
  `inputPipelineReady=true`, `setupRetryActive=false`, `speechModel=Ready`, and
  `triggerPath=Fn / Globe ready`.
- The rc52 mbp1 smoke collector proves the installed input method is no longer a
  stale-copy mismatch: bundled and installed `PressTalkInputMethod.app` both
  report CDHash `1429cebdf7da334efcd61d3add208c4f63c21daf` and
  `Signature=adhoc`. TIS recognizes exactly one PressTalk source with
  `type=TISTypeKeyboardInputMethodWithoutModes`, `enableCapable=true`, and
  `selectCapable=true`, but `recognizedEnabledSourceCount=0` and
  `enabled=false`. Running the status helper with `--enable --json` returns
  `enableStatus=0` and `enableNoEffect=true`, so the mbp1 blocker is still TIS
  enable no-effect on the ad-hoc install. The rc51 desktop-session signing
  repair or a proper trusted release-signing identity remains required before
  production insertion probes can pass there.
- A reversible mbp1 HIToolbox history test after rc53 also did not fix the
  blocker. The current `com.apple.HIToolbox` domain had only the German keyboard
  layout in `AppleInputSourceHistory`, while studio1 history contains the
  PressTalk input method after successful IMK selection. A backup was written to
  `~/Library/Application Support/JarvisTap/Diagnostics/hitoolbox-before-presstalk-history-test-20260607T013922Z.plist`,
  then `{ "Bundle ID" = "com.am.presstalk.inputmethod.container";
  InputSourceKind = "Keyboard Input Method"; }` was appended to
  `AppleInputSourceHistory` and `cfprefsd` was flushed. Read-only status still
  reported `recognizedEnabledSourceCount=0`, and `--enable --json` still
  returned `enableStatus=0` plus `enableNoEffect=true`. The HIToolbox backup was
  restored and the history returned to the German keyboard-only state. Do not
  add a history-repair helper; it is not sufficient for mbp1.
- Rebootstrapping the earlier rc45 install on `mbp1` as the legacy
  `com.am.jarvistap` identity did not recover the old TCC grants, because stable
  local signing still could not be applied over SSH and bootstrap fell back to a
  new ad-hoc signature. Runtime status under that ad-hoc legacy id reported
  `microphoneAuthorizationStatus=not_determined`,
  `inputMonitoringEffective=false`, `inputPipelineReady=false`,
  `accessibilityGranted=false`, and `status.speechModel=Waiting for setup`.
  The actual-bundle Accessibility probe also reported
  `accessibilityTrusted=false` for
  `/Users/alexandermonas/Applications/PressTalk.app`.
- `mbp1` still has an older `/Applications/PressTalk.app` signed as
  `com.am.jarvistap` by `Authority=JarvisTap Local Code Signing`, with
  designated requirement `identifier "com.am.jarvistap" and certificate root =
  H"f2671c00575e4d2f123bb3c28ab3e2461de33fb3"`, matching the old
  Microphone/Input Monitoring/Accessibility TCC rows. However,
  `security find-identity -v -p codesigning` reports `0 valid identities` in
  the login keychain, the PressTalk local-dev keychain, and the System keychain,
  so the current rc50 app cannot be re-signed with that historical trusted
  identity from SSH. A quiet launch of that old binary showed
  `Input Monitoring permission OK` and `Microphone permission OK`, but it stalled
  during WhisperKit load in the old Neural Engine/CoreML path even after the
  local model-cache compatibility symlink was present. It is therefore useful as
  TCC/signing evidence, not as a viable mbp1 runtime fallback.
- Karabiner-Elements is installed on `studio1`, but `karabiner_cli` only exposes
  profile/device/variable management. It does not provide a direct command to
  emit a virtual Cmd-V paste event, so it is not currently a no-Accessibility
  fallback for active-field insertion.
- `studio2` is intentionally excluded from current smoke coverage because it has
  no attached microphone.

Do not claim full release coverage until these are recorded:

- `studio1` / `s1`: local Option+Space dictation and real-field paste smoke is
  proven on 2026-06-09 through `ax_menu_paste`; rerun the bundled physical
  smoke helper only if a fresh machine-readable JSON artifact is required for
  the final release gate.
- `s2`: install plus Option+Space dictation smoke after a microphone is
  available.
- `mbp1`: rc104 install, active-field production insertion probe, and physical
  Option+Space real-field dictation are proven through `ax_menu_paste`.
