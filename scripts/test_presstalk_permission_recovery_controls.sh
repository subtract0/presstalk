#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-permission-controls.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
BUILD_ROOT="$ROOT/.build/arm64-apple-macosx/debug"
[[ -d "$BUILD_ROOT/PressTalkCore.build" ]] || { echo 'Run swift test --disable-sandbox first.' >&2; exit 1; }
swiftc -I "$BUILD_ROOT/Modules" "$ROOT/Tests/Fixtures/PermissionRecoveryControls/main.swift" \
  "$ROOT/Sources/JarvisTap/FirstRunSetupWindow.swift" \
  "$BUILD_ROOT"/PressTalkCore.build/*.swift.o -o "$TEST_ROOT/permission-controls"
"$TEST_ROOT/permission-controls"
