#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-setup-controls.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
BUILD_ROOT="$ROOT/.build/arm64-apple-macosx/debug"
[[ -d "$BUILD_ROOT/PressTalkCore.build" ]] || { echo 'Run swift test --disable-sandbox first.' >&2; exit 1; }
UI_SOURCE="${PRESSTALK_TEST_SETUP_UI_SOURCE:-$ROOT/Sources/JarvisTap/FirstRunSetupWindow.swift}"
swiftc -I "$BUILD_ROOT/Modules" "$ROOT/Tests/Fixtures/SetupControls/main.swift" \
  "$UI_SOURCE" "$BUILD_ROOT"/PressTalkCore.build/*.swift.o -o "$TEST_ROOT/setup-controls"
"$TEST_ROOT/setup-controls"
