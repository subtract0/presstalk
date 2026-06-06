#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_BUNDLE="$SCRIPT_DIR/PressTalkInputMethod.app"
TARGET_DIR="$HOME/Library/Input Methods"
TARGET_BUNDLE="$TARGET_DIR/PressTalkInputMethod.app"

if [[ ! -d "$SOURCE_BUNDLE" ]]; then
  echo "Missing bundled input method prototype: $SOURCE_BUNDLE" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_BUNDLE"
ditto "$SOURCE_BUNDLE" "$TARGET_BUNDLE"

cat <<EOF
Installed PressTalk input method prototype:
  $TARGET_BUNDLE

This helper does not open System Settings, select the input source, or request
permissions. macOS may require logout/login or manual input-source selection
before the prototype can receive a focused text client.

After selecting it, probe insertion with:
  /bin/bash "$SCRIPT_DIR/presstalk-input-method-insert-probe.sh" "PressTalk input method probe"
EOF
