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
and leaves macOS permission panes closed unless
PRESSTALK_OPEN_PERMISSION_PANES=1 is explicitly set. This is intended to avoid
repeated ad-hoc TCC identity drift without repeatedly prompting for already
approved permissions during smoke testing and updates.

While blocked on macOS privacy approvals, PressTalk keeps a quiet setup retry
timer running. Startup/setup checks use read-only preflights and real listener
capability probes by default; the setup window is not auto-shown unless
PRESSTALK_AUTO_SHOW_SETUP_WINDOW=1 is explicitly set.

For Fn, Option, and trackpad triggers, PressTalk now attempts listen-only HID
and session event taps before falling back to writable taps. Runtime status
records the selected input listener mode so cross-machine smoke tests can tell
whether the lower-permission path armed successfully.

PressTalk also recognizes the actual WhisperKit local cache layout under
~/Library/Application Support/JarvisTap/Models/models/... and prefetches the
small Whisper tokenizer files explicitly, so a populated model cache does not
leave the app stuck at "Warming up".

The app bundle includes presstalk-manual-fn-smoke.swift, a focused-window helper
that records physical Fn dictation smoke results as JSON without opening macOS
permission panes.

Settings now distinguish read-only permission preflight results from effective
runtime capability. If the real input listener is armed, Input Monitoring shows
as listener-ready instead of sending users back through already-granted macOS
privacy toggles; Accessibility is treated as a paste probe until paste actually
fails. Microphone now reports as unavailable to the current build instead of
implying the user failed to grant it, which is important for ad-hoc TCC identity
drift.

Bootstrap now clears both quarantine and provenance metadata from the installed
app bundle and explicitly re-enables the com.am.jarvistap launchd label before
bootstrapping. This fixes the mbp1 failure mode where launchd had the label
disabled and returned "5: Input/output error" even though the same app could
launch through LaunchServices.

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
