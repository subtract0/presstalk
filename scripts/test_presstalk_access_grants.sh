#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# == 2 ]] || { echo 'Usage: test_presstalk_access_grants.sh EXTENSION_FILE PERMANENT_FILE' >&2; exit 2; }
[[ -f "$1" && -f "$2" ]] || { echo 'Both licence files are required.' >&2; exit 2; }
BUILD_ROOT="$ROOT/.build/arm64-apple-macosx/debug"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-grants.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
swiftc -I "$BUILD_ROOT/Modules" "$ROOT/Tests/Fixtures/AccessGrants/main.swift" \
  "$ROOT/Sources/JarvisTap/ProductUI.swift" "$ROOT/Sources/JarvisTap/JarvisTapConfig.swift" \
  "$ROOT/Sources/JarvisTap/PressTalkRuntimeStatus.swift" "$ROOT/Sources/JarvisTap/PressTalkFoundation.swift" \
  "$ROOT/Sources/JarvisTap/TrialAnchorStores.swift" "$BUILD_ROOT"/PressTalkCore.build/*.swift.o \
  -o "$TEST_ROOT/access-grants"
PRESSTALK_OPEN_PERMISSION_PANES=0 PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 "$TEST_ROOT/access-grants" "$1" "$2"
