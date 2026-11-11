#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-updater-delegates.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
FRAMEWORK_ROOT="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
[[ -d "$FRAMEWORK_ROOT/Sparkle.framework" ]] || { echo 'Resolve the pinned Sparkle package first.' >&2; exit 1; }
POLICY_SOURCE="${PRESSTALK_TEST_UPDATE_POLICY_SOURCE:-$ROOT/Sources/PressTalkCore/UpdateSafetyPolicy.swift}"
UPDATER_SOURCE="${PRESSTALK_TEST_UPDATER_SOURCE:-$ROOT/Sources/JarvisTap/PressTalkUpdater.swift}"
swiftc -emit-library -emit-module -module-name PressTalkCore "$POLICY_SOURCE" \
  -emit-module-path "$TEST_ROOT/PressTalkCore.swiftmodule" -o "$TEST_ROOT/libPressTalkCore.dylib"
swiftc -parse-as-library -I "$TEST_ROOT" -L "$TEST_ROOT" -lPressTalkCore \
  -F "$FRAMEWORK_ROOT" -framework Sparkle \
  -Xlinker -rpath -Xlinker "$FRAMEWORK_ROOT" -Xlinker -rpath -Xlinker "$TEST_ROOT" \
  "$ROOT/Tests/Fixtures/UpdaterDelegates/Driver.swift" "$UPDATER_SOURCE" \
  -o "$TEST_ROOT/updater-delegates"
"$TEST_ROOT/updater-delegates"
