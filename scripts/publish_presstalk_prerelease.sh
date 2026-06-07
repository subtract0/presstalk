#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.5-rc1}"
PUBLIC_NAME="${PUBLIC_NAME:-PressTalk}"
RELEASE_REPO="${RELEASE_REPO:-subtract0/presstalk}"
ARCH="${ARCH:-$(uname -m)}"
ASSET_NAME="${PUBLIC_NAME}-${VERSION}-macos-${ARCH}.zip"
ASSET_PATH="$ROOT/dist/$ASSET_NAME"
SHA_PATH="$ROOT/dist/${PUBLIC_NAME}-${VERSION}-macos-${ARCH}.sha256"
RELEASE_TAG="v$VERSION"

if ! command -v gh >/dev/null 2>&1; then
  echo "Missing required command: gh" >&2
  exit 1
fi

bash "$ROOT/scripts/package_presstalk_release.sh" "$VERSION" >/dev/null

if [[ ! -f "$ASSET_PATH" || ! -f "$SHA_PATH" ]]; then
  echo "Missing packaged artifact for $VERSION" >&2
  exit 1
fi

SHA256="$(awk '{print $1}' "$SHA_PATH")"
NOTES_TEMPLATE_PATH="$(mktemp "${TMPDIR:-/tmp}/presstalk-release-notes.XXXXXX")"
cat >"$NOTES_TEMPLATE_PATH" <<'EOF'
PressTalk __PRESSTALK_VERSION__ prerelease smoke artifact for Apple Silicon macOS.

Default trigger: Option.

The bundled bootstrap creates or reuses a local development code-signing
identity on the target Mac, re-signs PressTalk.app before launchd starts it
when macOS allows the noninteractive Keychain trust update, and leaves macOS
permission panes closed. When bootstrap is launched over SSH and stable signing
was not requested explicitly, it reuses an already-valid PressTalk local signing
identity if one exists. If no valid identity exists, it skips the local signing
trust flow so a remote install cannot create a surprise Mac-password prompt on
the desktop. Bootstrap never opens System Settings; the
permission-pane flag only controls whether the app manual Settings buttons are
enabled. The bootstrap summary reports both whether stable signing was requested
and whether it was actually applied. This is intended to avoid repeated ad-hoc
TCC identity drift without repeatedly prompting for already approved permissions
during smoke testing and updates.

The local signing helper now retries trust on an existing untrusted PressTalk
identity instead of importing another duplicate certificate on every failed
attempt. It prints a clear signing-trust message before macOS may ask for the
user's Mac login password. The repair wrapper refuses to start that trust flow
over SSH unless --allow-ssh is passed deliberately.

The app bundle now includes presstalk-repair-local-signing.sh. Run it from the
logged-in desktop session when a Mac skipped the signing trust password prompt:
it prepares the local signing identity, restarts PressTalk with
PRESSTALK_OPEN_PERMISSION_PANES=0 and PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0, signs
the bundled PressTalkInputMethod.app before the outer app, refreshes the copy in
~/Library/Input Methods, and can optionally run the production insertion probe.
This is a signing/input-method repair path; it is not a reason to reopen
Microphone, Input Monitoring, or Accessibility panes.

The repair helper now supports --preflight. That mode reports whether repair is
needed, whether repair would be refused over SSH, whether an existing trusted
local signing identity can be reused, and whether a Mac login-password signing
trust prompt would be required. It does not create or trust a certificate, sign
or restart PressTalk, run an insertion probe, or open System Settings.
Preflight now also distinguishes a truly missing local signing identity from an
existing but untrusted PressTalk local signing identity, reporting the latter as
ExistingSigningIdentity=untrusted with its hash. That keeps mbp1-style repair
diagnostics honest without starting the signing trust prompt remotely.

Settings now shows a Repair Signing button for PressTalk signing states where
macOS recognizes the PressTalk input method but has not enabled it. The button
runs the bundled repair helper with permission panes disabled and then runs the
production insertion probe, so the desktop repair path no longer requires typing
a shell command. The settings action launches the helper through nohup and
writes a diagnostics .pid file next to the signing repair log, so the repair can
survive the app restart it initiates and the smoke collector can report whether
the latest repair helper is still running. When the repair is run with --probe,
the helper now appends a full post-repair smoke-status snapshot to the same
diagnostics log after the production insertion probe, while preserving the probe
exit status.

The status menu also shows Repair Signing... in the PressTalk signing states
where macOS recognizes the input method but leaves it disabled. This covers both
ad-hoc release installs and local-signing identities that exist but still need
desktop trust repair. It gives a logged-in desktop user a direct repair action
from the menu bar without reopening the full Settings window.

The menu-bar status no longer says plain "Ready" for that state. It now reports
Paste Repair Needed while transcription is ready but active-field paste still
needs the local signing repair, so the blocked state is visible before a user
tries dictation.

Runtime status now also records activeFieldInsertionReady and
activeFieldInsertionStatus. These fields separate a ready speech pipeline from
a proven active-field insertion path, and the bundled smoke collector and repair
verifier print them for cross-machine evidence. The repair preflight,
machine-readiness helper, smoke collector, and verifier now route the
non-ad-hoc PressTalk Local Development Code Signing plus recognized_disabled
state to the same no-pane Repair Signing action instead of calling it a generic
insertion blocker.

The production insertion probe now records active-field insertion readiness in
its start/finish snapshots, including activeFieldInsertionReady,
activeFieldInsertionStatus, and inputMethodFallbackStatus. The read-only repair
verifier accepts every proven active-field insertion path: InputMethodKit,
direct Accessibility insertion, or Accessibility-backed paste command. It still
fails mbp1 recognized_disabled states as signing repair blockers when they are
ad-hoc or signed by the PressTalk local development identity.

Bootstrap now re-signs the bundled PressTalkInputMethod.app whenever it
re-signs PressTalk.app, then refreshes the installed input-method bundle before
launching the app. Its summary reports both Bundled input method signing applied
and Installed input method refreshed. This targets the mbp1 rc50 shape where the
running app received the production insertion notification but TIS enable had no
visible effect on the ad-hoc input-method install.

While blocked on macOS privacy approvals, PressTalk keeps a quiet setup retry
timer running. Startup/setup checks use read-only preflights and real listener
capability probes by default; the setup window is not auto-shown unless
PRESSTALK_AUTO_SHOW_SETUP_WINDOW=1 and PRESSTALK_OPEN_PERMISSION_PANES=1 are
both explicitly set.

Even when the first-run setup guide is explicitly enabled, successful startup no
longer force-presents the Settings window. The setup window is only auto-shown
for a real startup failure, so a machine with working microphone/listener
runtime proof will not be sent back through the permission UI.

The default Option + Space trigger uses a registered macOS hotkey. Modifier-only
Fn/Option triggers remain available as advanced choices and still report whether
the required writable event-tap path armed successfully.

PressTalk also recognizes the actual WhisperKit local cache layout under
~/Library/Application Support/JarvisTap/Models/models/... and prefetches the
small Whisper tokenizer files explicitly, so a populated model cache does not
leave the app stuck at "Warming up".

The app bundle includes presstalk-manual-fn-smoke.swift, a focused-window helper
that records physical trigger dictation smoke results as JSON without opening
macOS permission panes. It now reads the configured runtime trigger key, supports
Option + Space/Fn/Option/F5/trackpad labels, and records readiness before and
after the manual paste smoke. It also records traceFinalTranscript, traceInserted,
traceCopyFallback, traceInputMethodSelectFailed, targetCaptureSuccess, and
targetCaptureFailureHint, so a physical trigger/STT success is visibly separate
from an active-field insertion failure.

The bundle also includes presstalk-run-production-insertion-probe.sh and
presstalk-production-insertion-probe.swift. The wrapper temporarily restarts
PressTalk with PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE=1, opens a focused
local text window, asks the running PressTalk app to insert a payload through
the same production insertion path used after dictation, records whether the
payload lands, then restores normal no-probe startup. It reads the current
trigger key through macOS plutil rather than a Python dependency. This tests the
app process itself rather than only the standalone input-method client probe.

The bundle now also carries a separate PressTalkInputMethod.app plus
presstalk-install-input-method.sh, presstalk-input-method-status.swift,
presstalk-input-method-client-probe.swift, and
presstalk-input-method-insert-probe.sh. These helpers diagnose the
InputMethodKit fallback used when Accessibility is untrusted. Production
dictation installs/registers the bundled input method if needed, temporarily
selects it for insertion, restores the original input source, and does not open
System Settings. The status helper is read-only by default; registration,
enabling, and selection require explicit flags. The client probe temporarily
enables/selects the source, focuses a local text view, posts a payload, records
whether text lands, and restores the original input source.

The bundle also carries presstalk-unicode-event-insert-probe.swift. This opens a
local text view and posts per-character Unicode CGEvents without opening System
Settings. It tests HID, session, annotated-session, and PID-targeted event
delivery. On studio1 these paths posted events but observed no inserted text
while Accessibility was untrusted, which rules out these CGEvent routes as
reliable no-Accessibility insertion fallbacks on that machine.

The bundle also carries presstalk-virtual-hid-paste-probe.swift. It opens a
local text view, places a payload on the pasteboard, and tries Cmd-V through an
IOHIDUserDevice virtual keyboard. Apple's SDK requires the
com.apple.developer.hid.virtual.device entitlement to create that virtual HID
device; on studio1 the probe reports reason=device_create_failed before sending
any report, so this is diagnostic evidence rather than a public unsigned
fallback.

The bundled smoke-status collector now includes an Input Method section. It
prints the bundled and installed PressTalkInputMethod.app signatures, warns if
their CDHashes differ, and embeds the read-only TIS status JSON from
presstalk-input-method-status.swift. This makes the mbp1 post-repair checklist
visible in one command: stable app signing, matching input-method signing, and
recognized/enabled/select-capable PressTalk input source.

The same collector now includes a Repair And Probe Status section. It reports
the current ad-hoc/input-method repair state, shows the latest signing repair
log if one exists, summarizes the latest production insertion probe JSON, and
for the ad-hoc recognized_disabled state explicitly points to desktop Repair
Signing instead of another Microphone/Input Monitoring/Accessibility permission
loop.

The app bundle also includes presstalk-machine-readiness.sh. This read-only
helper reports Apple Silicon eligibility, audio input hardware, installed
PressTalk identity, runtime speech readiness, active-field insertion readiness,
latest production insertion probe, and a concrete next action. It is intended to
exclude machines without an attached microphone from physical STT smoke and to
separate host/setup blockers from app regressions before cross-machine release
claims. It also supports --json and --json-output PATH so each machine can
produce a parseable readiness artifact for release evidence.

The bundle also includes presstalk-readiness-matrix.sh. It collects local and
SSH-host readiness reports into one parseable JSON matrix, using BatchMode SSH
with strict host-key checking and a short connect timeout. Failed host
resolution, host-key verification, and SSH timeouts are recorded as failed
targets instead of being confused with app regressions.

The bundle also includes presstalk-host-discovery.sh. It collects read-only
host/alias evidence before matrix runs: local SSH config aliases, Bonjour SSH
advertisements, Tailscale status by default, ARP table host/IP candidates,
target ssh -G resolution, and optional strict BatchMode SSH probes. Tailscale
collection can be skipped with --no-tailscale, ARP collection can be skipped
with --no-arp, and Tailscale CLI failures are recorded as unavailable status
with the failure text in JSON instead of being confused with missing hosts. ARP
entries are candidate-discovery evidence only, not proof of a machine identity.
When --probe-arp-ssh is passed, it also runs read-only ssh-keyscan against ARP
candidate IPs and records public host-key fingerprints without editing
known_hosts. The JSON now also indexes local known_hosts fingerprints and adds
knownHostMatches to scanned ARP fingerprints that match an already-known host
key. This makes missing aliases such as s1, strict host-key blockers, Tailscale
status, local network candidates, known-machine matches, and the reachable
mbp1-tb path visible without installing or repairing PressTalk.

The bundle also includes presstalk-release-proof-gate.sh. It consumes the
readiness matrix and exits 0 only when every required target is reachable,
reports readiness, has physical STT smoke ready, and has active-field smoke
ready. This makes the current cross-machine proof gaps fail mechanically instead
of relying on release-status prose. It also supports --json-output PATH to save
a parseable proof result with required targets, excluded targets, per-target
failures, failureCount, and proven=true/false.

The app bundle also includes presstalk-verify-repair-result.sh. This is a
read-only post-repair verifier for SSH checks: it reports the current runtime
signing/input-method state plus the latest production insertion probe, exits 0
only when insertion into the focused target is proven, and exits nonzero without
opening permission panes or starting any signing trust flow.

The app bundle also includes presstalk-automated-f5-smoke.swift for explicit
synthetic pipeline checks. It posts the F5 Darwin trigger bridge, speaks a local
phrase through system audio, and records whether PressTalk transcribes, posts
the paste command, and actually lands text in the focused helper window. It also
runs a local paste-event self-test first and records pasteSelfTest plus
targetCaptureFailureHint, so failed target capture can be separated from STT or
trigger failures. Results are marked physicalTriggerProof=false, and
targetCaptureSuccess is tracked separately, so this does not replace physical
Option + Space smoke.

If automated F5 helper playback is routed somewhere the microphone cannot hear,
the microphone may capture near silence. The helper reports this as
reason=tts_audio_not_captured_by_microphone with traceAudioCapture RMS/peak
evidence, not as generic STT failure.

Settings now distinguish read-only permission preflight results from effective
runtime capability. If the real input listener is armed, Input Monitoring shows
as listener-ready instead of sending users back through already-granted macOS
privacy toggles; Accessibility is treated as a paste probe until paste actually
fails. Runtime status also records inputMonitoringStatus, microphoneStatus, and
accessibilityStatus so raw macOS preflight misses are visibly separate from
effective readiness.

Runtime status and Settings now also expose inputMethodFallbackStatus. When
Accessibility is false and auto-paste is enabled, PressTalk reports whether the
InputMethodKit fallback is ready, recognized but disabled, not selectable, not
installed, or not recognized. This prevents mbp1's ad-hoc TIS state from being
presented as a working fallback merely because auto-paste is on.

When Accessibility is not trusted but dictation can use the InputMethodKit
fallback, Settings labels the Accessibility row as input method ready and
runtime status records accessibilityStatus=ax_false_input_method_fallback_ready
instead of naming it as a missing permission or copy-only path.

The Settings window is now resizable and scrollable, and the Accessibility row
names the exact runtime state when AXIsProcessTrusted=false for this signed app.
With auto-paste enabled, PressTalk tries the input method fallback before copy
fallback instead of sending users back through an already-enabled macOS Privacy
toggle.

Runtime status also records microphoneAuthorizationStatus, so a blocked machine
can distinguish authorized, denied, restricted, not_determined, and unknown
microphone preflight states without opening System Settings.

For insertion, PressTalk now tries direct Accessibility insertion into the
focused text element when Accessibility is trusted. If Accessibility is not
trusted, it tries the InputMethodKit insertion fallback before copying the
transcript to the clipboard. It does not post a Cmd-V event that cannot land.
The automated smoke helper records traceInserted, traceCopyFallback, and
targetCaptureFailureHint so these paths are visible in JSON.

The running app now receives PRESSTALK_OPEN_PERMISSION_PANES from bootstrap and
launchd. When that value is 0, the Settings window hides the Microphone, Input
Monitoring, and Accessibility privacy-pane buttons, suppresses any attempted
privacy pane opens, and does not auto-present setup windows from setup checks or
successful startup. This keeps no-pane smoke tests from accidentally reopening
System Settings or suggesting another approval pass.

Diagnostics export now also respects no-pane smoke runs. When
PRESSTALK_OPEN_PERMISSION_PANES=0, Export Diagnostics writes the diagnostics file
and logs its path without activating Finder, so troubleshooting does not create
another surprise window.

Bootstrap now clears both quarantine and provenance metadata from the installed
app bundle and explicitly re-enables the com.am.jarvistap launchd label before
bootstrapping. This fixes the mbp1 failure mode where launchd had the label
disabled and returned "5: Input/output error" even though the same app could
launch through LaunchServices.

Release packaging builds the public app bundle identifier com.am.presstalk while
the launchd label remains com.am.jarvistap for compatibility. Local source-tree
builds now preserve the currently installed app bundle identifier and create or
reuse the local development signing identity by default, so a working
development install under com.am.jarvistap is not silently rebuilt as
com.am.presstalk or as a new ad-hoc CDHash and sent back through a different
macOS privacy client.

Bootstrap can now preserve a legacy working privacy identity by setting
PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap before running
presstalk-bootstrap.sh. This is for machines whose existing microphone/input
grants are under the older JarvisTap identity; new installs continue to default
to com.am.presstalk.

The bundled smoke-status collector now reports a Status Consistency section
that compares runtime-status.json against the live PressTalk process and the
installed app signature. It now derives the inspected app bundle from the live
PressTalk process before falling back to install defaults, and prints both the
status bundle path and inspected app bundle path. This makes stale or mismatched
diagnostics visible when a machine is blocked before dictation.

The InputMethodKit fallback now uses a no-mode source id
com.am.presstalk.inputmethod.container. On studio1 TIS reports it as
TISTypeKeyboardInputMethodWithoutModes with recognizedSourceCount=1,
recognizedEnabledSourceCount=1, and selectCapable=true. The focused client probe
selects it, posts the insert notification, observes the payload in the local text
view, and restores the original input source. Production dictation now attempts
this input-method insertion route before copy fallback when Accessibility is
untrusted.

The generated input-method bundle now includes the documented
LSBackgroundOnly=true metadata for InputMethodKit servers. The client probe also
records enabled/all-installed PressTalk source snapshots before the probe, after
enable, and after select, plus the current input source after select. This makes
mbp1-style failures visible when TISEnableInputSource reports success but
TISSelectInputSource still returns -50.

InputMethodKit diagnostics now distinguish source recognition from selection
failure. If macOS recognizes the input method but refuses
TISSelectInputSource, the client probe reports reason=input_method_select_failed
and the numeric selectStatus instead of the older generic not-selectable label.
Production insertion also attempts direct selection from the recognized source
when the enabled-source requery is stale or empty, and logs the enabled/all
installed source counts before selection.

If TISEnableInputSource returns 0 but the enabled-source requery still shows no
PressTalk source, the client probe now reports
reason=input_method_enable_no_effect and enableNoEffect=true. Production traces
the same state as reason=enable_no_effect, and manual physical-trigger smoke
sets targetCaptureFailureHint=input_method_enable_no_effect when the transcript
path worked but insertion was blocked by that TIS state.

The bundle also includes presstalk-actual-accessibility-probe.sh. It launches
the installed PressTalk.app itself in a diagnostic mode with the Accessibility
prompt flag disabled, records the exact bundle path, bundle id, CDHash, signing
authority, and AX trust result, then exits before normal startup. This checks the
actual signed app identity before asking anyone to re-grant permissions.

The bundle also includes presstalk-accessibility-identity-probe.sh. It launches
small background probe apps for com.am.jarvistap and com.am.presstalk with the
Accessibility prompt flag disabled, records each probe signing identity, and
reports whether either identity is already trusted for Accessibility without
opening System Settings.

The same collector now includes a read-only TCC Rows section for
com.am.presstalk and com.am.jarvistap across Microphone, Input Monitoring, and
Accessibility. It does not reset TCC or open privacy panes; it only reports
whether the current user/system TCC databases contain matching rows.

The collector also decodes matching TCC code-requirement blobs with csreq and
prints the current app designated requirement. This makes stale grants tied to
an old certificate root or old CDHash visible without changing permissions.

WhisperKit now defaults to a no-Neural-Engine compute preset
(mel/audio encoder/text decoder on CPU+GPU, prefill on CPU) because mbp1 on
macOS 26.5 can hang while Core ML loads the large-v3 turbo decoder/encoder via
the Neural Engine path. Set PRESSTALK_WHISPER_COMPUTE=default only when you
explicitly want the upstream WhisperKit compute defaults.

This prerelease is for machine verification on studio1, s1, studio2/s2 only
when a microphone is attached, and mbp1. Do not treat it as fully verified
until docs/RELEASE_STATUS.md records successful dictation smoke tests on the
machines currently eligible for microphone coverage.

SHA-256:

\`\`\`
__PRESSTALK_SHA256__
\`\`\`
EOF
NOTES="$(sed \
  -e "s/__PRESSTALK_VERSION__/$VERSION/g" \
  -e "s/__PRESSTALK_SHA256__/$SHA256/g" \
  "$NOTES_TEMPLATE_PATH")"
rm -f "$NOTES_TEMPLATE_PATH"

if gh release view "$RELEASE_TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
  gh release upload "$RELEASE_TAG" "$ASSET_PATH" --repo "$RELEASE_REPO" --clobber
  gh release edit "$RELEASE_TAG" --repo "$RELEASE_REPO" --notes "$NOTES" --prerelease
else
  gh release create "$RELEASE_TAG" "$ASSET_PATH" \
    --repo "$RELEASE_REPO" \
    --title "PressTalk ${VERSION}" \
    --notes "$NOTES" \
    --prerelease
fi

echo "Published prerelease: https://github.com/${RELEASE_REPO}/releases/tag/${RELEASE_TAG}"
echo "Asset: $ASSET_PATH"
echo "SHA-256: $SHA256"
