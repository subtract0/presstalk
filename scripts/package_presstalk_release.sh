#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$HOME/Applications/PressTalk.app"
DIST_DIR="$ROOT/dist"
PUBLIC_NAME="${PUBLIC_NAME:-PressTalk}"
VERSION="${1:-0.1.5}"
ARCH="${ARCH:-$(uname -m)}"
ZIP_PATH="$DIST_DIR/${PUBLIC_NAME}-${VERSION}-macos-${ARCH}.zip"
SHA_PATH="$DIST_DIR/${PUBLIC_NAME}-${VERSION}-macos-${ARCH}.sha256"

bash "$ROOT/scripts/build_jarvistap.sh" >/dev/null

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH" "$SHA_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" | tee "$SHA_PATH"

echo
echo "Packaged release:"
echo "  $ZIP_PATH"
