#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${PRESSTALK_DIST_DIR:-$ROOT/dist}"
PUBLIC_NAME="${PUBLIC_NAME:-PressTalk}"
VERSION="${1:-0.1.5}"
ARCH="${ARCH:-$(uname -m)}"
ZIP_PATH="$DIST_DIR/${PUBLIC_NAME}-${VERSION}-macos-${ARCH}.zip"
SHA_PATH="$DIST_DIR/${PUBLIC_NAME}-${VERSION}-macos-${ARCH}.sha256"
RUN_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-package.XXXXXX")"
APP_BUNDLE="$RUN_TMPDIR/PressTalk.app"
SUBMISSION_ZIP="$RUN_TMPDIR/${PUBLIC_NAME}-${VERSION}-notary-submission.zip"
trap 'rm -rf "$RUN_TMPDIR"' EXIT

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

signature_authority() {
  local bundle="$1"
  codesign -dv --verbose=4 "$bundle" 2>&1 |
    awk -F= '/^Authority=/ { print $2; exit }'
}

DISTRIBUTION_SIGNING="${PRESSTALK_DISTRIBUTION_SIGNING:-0}"
NOTARIZE="${PRESSTALK_NOTARIZE:-0}"

if truthy "$NOTARIZE" && ! truthy "$DISTRIBUTION_SIGNING"; then
  echo "PRESSTALK_NOTARIZE=1 requires PRESSTALK_DISTRIBUTION_SIGNING=1." >&2
  exit 2
fi

if truthy "$DISTRIBUTION_SIGNING"; then
  if [[ -z "${PRESSTALK_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}" ]]; then
    cat >&2 <<'EOF'
PRESSTALK_DISTRIBUTION_SIGNING=1 requires a Developer ID signing identity.
Set PRESSTALK_CODESIGN_IDENTITY="Developer ID Application: ..." or a matching
identity hash before packaging a production distribution artifact.
EOF
    exit 2
  fi
  PRESSTALK_CODESIGN_HARDENED_RUNTIME="${PRESSTALK_CODESIGN_HARDENED_RUNTIME:-1}"
  PRESSTALK_CODESIGN_TIMESTAMP="${PRESSTALK_CODESIGN_TIMESTAMP:-1}"
else
  PRESSTALK_CODESIGN_HARDENED_RUNTIME="${PRESSTALK_CODESIGN_HARDENED_RUNTIME:-0}"
  PRESSTALK_CODESIGN_TIMESTAMP="${PRESSTALK_CODESIGN_TIMESTAMP:-none}"
fi

PRESSTALK_BUNDLE_IDENTIFIER="${PRESSTALK_BUNDLE_IDENTIFIER:-com.am.presstalk}" \
PRESSTALK_BUILD_STABLE_SIGNING=0 \
PRESSTALK_CODESIGN_HARDENED_RUNTIME="$PRESSTALK_CODESIGN_HARDENED_RUNTIME" \
PRESSTALK_CODESIGN_TIMESTAMP="$PRESSTALK_CODESIGN_TIMESTAMP" \
PRESSTALK_VERSION="$VERSION" \
PRESSTALK_APP_BUNDLE="$APP_BUNDLE" \
  bash "$ROOT/scripts/build_jarvistap.sh" >/dev/null

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  exit 1
fi

if truthy "$DISTRIBUTION_SIGNING"; then
  echo "Verifying distribution signature..."
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  AUTHORITY="$(signature_authority "$APP_BUNDLE")"
  if [[ "$AUTHORITY" != Developer\ ID\ Application* ]]; then
    echo "Distribution signing requires Developer ID Application authority; got: ${AUTHORITY:-unknown}" >&2
    exit 1
  fi
  echo "Distribution signature authority: $AUTHORITY"
fi

if truthy "$NOTARIZE"; then
  require_cmd xcrun
  notary_args=()
  if [[ -n "${PRESSTALK_NOTARYTOOL_PROFILE:-}" ]]; then
    notary_args+=(--keychain-profile "$PRESSTALK_NOTARYTOOL_PROFILE")
  elif [[ -n "${PRESSTALK_NOTARY_APPLE_ID:-}" &&
          -n "${PRESSTALK_NOTARY_TEAM_ID:-}" &&
          -n "${PRESSTALK_NOTARY_PASSWORD:-}" ]]; then
    notary_args+=(
      --apple-id "$PRESSTALK_NOTARY_APPLE_ID"
      --team-id "$PRESSTALK_NOTARY_TEAM_ID"
      --password "$PRESSTALK_NOTARY_PASSWORD"
    )
  else
    cat >&2 <<'EOF'
PRESSTALK_NOTARIZE=1 requires either:
  PRESSTALK_NOTARYTOOL_PROFILE=<xcrun notarytool keychain profile>
or all of:
  PRESSTALK_NOTARY_APPLE_ID, PRESSTALK_NOTARY_TEAM_ID, PRESSTALK_NOTARY_PASSWORD
EOF
    exit 2
  fi

  rm -f "$SUBMISSION_ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$SUBMISSION_ZIP"
  echo "Submitting PressTalk.app for notarization..."
  xcrun notarytool submit "$SUBMISSION_ZIP" --wait "${notary_args[@]}"
  echo "Stapling notarization ticket..."
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
fi

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH" "$SHA_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" | tee "$SHA_PATH"

echo
echo "Packaged release:"
echo "  $ZIP_PATH"
if truthy "$DISTRIBUTION_SIGNING"; then
  echo "Distribution signing: enabled"
else
  echo "Distribution signing: disabled (test/prerelease artifact)"
fi
if truthy "$NOTARIZE"; then
  echo "Notarization: stapled"
else
  echo "Notarization: not requested"
fi
