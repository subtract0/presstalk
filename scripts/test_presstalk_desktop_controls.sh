#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-desktop-controls.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
BUILD_ROOT="$ROOT/.build/arm64-apple-macosx/debug"
[[ -d "$BUILD_ROOT/PressTalkCore.build" ]] || { echo 'Run swift test --disable-sandbox first.' >&2; exit 1; }
UI_SOURCE="${PRESSTALK_TEST_PRODUCT_UI_SOURCE:-$ROOT/Sources/JarvisTap/ProductUI.swift}"
for configuration in debug release; do
  # DEBUG permits the isolated owner fixture. The optimized build deliberately
  # omits that define and must reject the same unverified override at runtime.
  if [[ "$configuration" == debug ]]; then
    compiler_flags=(-D DEBUG)
  else
    compiler_flags=(-O)
  fi
  swiftc "${compiler_flags[@]}" -I "$BUILD_ROOT/Modules" \
    "$ROOT/Tests/Fixtures/DesktopControls/main.swift" \
    "$UI_SOURCE" \
    "$ROOT/Sources/JarvisTap/JarvisTapConfig.swift" \
    "$ROOT/Sources/JarvisTap/PressTalkRuntimeStatus.swift" \
    "$ROOT/Sources/JarvisTap/PressTalkFoundation.swift" \
    "$ROOT/Sources/JarvisTap/TrialAnchorStores.swift" \
    "$BUILD_ROOT"/PressTalkCore.build/*.swift.o \
    -o "$TEST_ROOT/desktop-controls-$configuration"
  PRESSTALK_OPEN_PERMISSION_PANES=0 PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 "$TEST_ROOT/desktop-controls-$configuration"
done
