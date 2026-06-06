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
NOTES="$(cat <<EOF
PressTalk ${VERSION} prerelease smoke artifact for Apple Silicon macOS.

Default trigger: Fn / Globe.

The bundled bootstrap creates or reuses a local development code-signing
identity on the target Mac, re-signs PressTalk.app before launchd starts it,
and leaves macOS permission panes closed. Bootstrap never opens System Settings;
the permission-pane flag only controls whether the app manual Settings
buttons are enabled. This is intended to avoid repeated ad-hoc TCC identity
drift without repeatedly prompting for already approved permissions during smoke
testing and updates.

While blocked on macOS privacy approvals, PressTalk keeps a quiet setup retry
timer running. Startup/setup checks use read-only preflights and real listener
capability probes by default; the setup window is not auto-shown unless
PRESSTALK_AUTO_SHOW_SETUP_WINDOW=1 and PRESSTALK_OPEN_PERMISSION_PANES=1 are
both explicitly set.

Even when the first-run setup guide is explicitly enabled, successful startup no
longer force-presents the Settings window. The setup window is only auto-shown
for a real startup failure, so a machine with working microphone/listener
runtime proof will not be sent back through the permission UI.

For Fn, Option, and trackpad triggers, PressTalk now attempts listen-only HID
and session event taps before falling back to writable taps. Runtime status
records the selected input listener mode so cross-machine smoke tests can tell
whether the lower-permission path armed successfully.

PressTalk also recognizes the actual WhisperKit local cache layout under
~/Library/Application Support/JarvisTap/Models/models/... and prefetches the
small Whisper tokenizer files explicitly, so a populated model cache does not
leave the app stuck at "Warming up".

The app bundle includes presstalk-manual-fn-smoke.swift, a focused-window helper
that records physical trigger dictation smoke results as JSON without opening
macOS permission panes. It now reads the configured runtime trigger key, supports
Fn/Option/F5/trackpad labels, and records readiness before and after the manual
paste smoke. It also records traceFinalTranscript, traceInserted,
traceCopyFallback, targetCaptureSuccess, and targetCaptureFailureHint, so a
physical trigger/STT success is visibly separate from an active-field insertion
failure.

The bundle now also carries a separate PressTalkInputMethod.app prototype plus
presstalk-install-input-method.sh, presstalk-input-method-status.swift,
presstalk-input-method-client-probe.swift, and
presstalk-input-method-insert-probe.sh. This is an explicit, opt-in
InputMethodKit insertion experiment for the current active-field blocker. It is
not selected or installed automatically and does not open System Settings; it
gives testers a concrete path to verify whether a selected PressTalk input
method can insert text without Accessibility trust. The status helper is
read-only by default; registration, enabling, and selection require explicit
flags. The client probe temporarily enables/selects the source, focuses a local
text view, posts a payload, records whether text lands, and restores the
original input source.

The bundle also carries presstalk-unicode-event-insert-probe.swift. This opens a
local text view and posts per-character Unicode CGEvents without opening System
Settings. It tests HID, session, annotated-session, and PID-targeted event
delivery. On studio1 these paths posted events but observed no inserted text
while Accessibility was untrusted, which rules out these CGEvent routes as
reliable no-Accessibility insertion fallbacks on that machine.

The app bundle also includes presstalk-automated-f5-smoke.swift for explicit
synthetic pipeline checks. It posts the F5 Darwin trigger bridge, speaks a local
phrase through system audio, and records whether PressTalk transcribes, posts
the paste command, and actually lands text in the focused helper window. It also
runs a local paste-event self-test first and records pasteSelfTest plus
targetCaptureFailureHint, so failed target capture can be separated from STT or
trigger failures. Results are marked physicalTriggerProof=false, and
targetCaptureSuccess is tracked separately, so this does not replace physical
Fn/Option smoke.

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

The Settings window is now resizable and scrollable, and the Accessibility row
names the exact runtime state when auto-paste is blocked:
AXIsProcessTrusted=false for this signed app. In that state PressTalk copies the
transcript instead of sending users back through an already-enabled macOS Privacy
toggle.

Runtime status also records microphoneAuthorizationStatus, so a blocked machine
can distinguish authorized, denied, restricted, not_determined, and unknown
microphone preflight states without opening System Settings.

For insertion, PressTalk now tries direct Accessibility insertion into the
focused text element when Accessibility is trusted. If Accessibility is not
trusted, it copies the transcript to the clipboard and records a copy fallback
instead of posting a Cmd-V event that cannot land. The automated smoke helper
records traceInserted, traceCopyFallback, and targetCaptureFailureHint so these
paths are visible in JSON.

The running app now receives PRESSTALK_OPEN_PERMISSION_PANES from bootstrap and
launchd. When that value is 0, the Settings window hides the Microphone, Input
Monitoring, and Accessibility privacy-pane buttons, suppresses any attempted
privacy pane opens, and does not auto-present setup windows from setup checks or
successful startup. This keeps no-pane smoke tests from accidentally reopening
System Settings or suggesting another approval pass.

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
installed app signature. This makes stale or mismatched diagnostics visible
when a machine is blocked before dictation.

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

This prerelease is for machine verification on studio1, s1, s2, and mbp1. Do not treat it as fully verified until docs/RELEASE_STATUS.md records successful dictation smoke tests on those machines.

SHA-256:

\`\`\`
${SHA256}
\`\`\`
EOF
)"

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
