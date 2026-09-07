#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-hal-sanitizers.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
for sanitizer in address,undefined thread; do
  xcrun clang -g -O1 -fsanitize="$sanitizer" \
    -I "$ROOT/Sources/PressTalkHAL/include" \
    "$ROOT/Sources/PressTalkHAL/PressTalkHAL.c" \
    "$ROOT/Tests/Fixtures/capture_transport_stress.c" \
    -framework AudioToolbox -framework CoreAudio -o "$TEST_TMPDIR/transport"
  "$TEST_TMPDIR/transport"
done
