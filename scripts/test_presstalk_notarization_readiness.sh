#!/usr/bin/env bash
# The readiness gate is only worth having if it still fails on the defects it
# was written for. Builds throwaway bundles that reproduce each one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/presstalk_notarization_readiness.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-readiness-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0

check() {
  # check <name> <expected-exit> <command...>
  local name="$1" expected="$2"; shift 2
  local actual=0
  "$@" >"$WORK/out.txt" 2>&1 || actual=$?
  if [[ "$actual" == "$expected" ]]; then
    printf 'ok    %s\n' "$name"
  else
    printf 'FAIL  %s (expected exit %s, got %s)\n' "$name" "$expected" "$actual"
    sed 's/^/        /' "$WORK/out.txt"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_output() {
  # expect_output <name> <needle>
  if grep -q "$2" "$WORK/out.txt"; then
    printf 'ok    %s\n' "$1"
  else
    printf 'FAIL  %s (output did not mention "%s")\n' "$1" "$2"
    FAILURES=$((FAILURES + 1))
  fi
}

make_bundle() {
  # make_bundle <dir> <hardened:0|1> <entitlements:0|1> <stray-macho:0|1>
  local dir="$1" hardened="$2" entitlements="$3" stray="$4"
  rm -rf "$dir"
  mkdir -p "$dir/Contents/MacOS" "$dir/Contents/Resources"

  cat >"$WORK/tiny.c" <<'C'
int main(void) { return 0; }
C
  cc -o "$dir/Contents/MacOS/tinyapp" "$WORK/tiny.c"

  cat >"$dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>tinyapp</string>
  <key>CFBundleIdentifier</key><string>com.am.presstalk.readinesstest</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSMicrophoneUsageDescription</key><string>test</string>
  <key>NSInputMonitoringUsageDescription</key><string>test</string>
  <key>NSAccessibilityUsageDescription</key><string>test</string>
</dict>
</plist>
PLIST

  local args=(--force --sign - --timestamp=none)
  [[ "$hardened" == "1" ]] && args+=(--options runtime)
  [[ "$entitlements" == "1" ]] && args+=(--entitlements "$ROOT/resources/PressTalk.entitlements")

  if [[ "$stray" == "1" ]]; then
    # Compiled into Resources and deliberately left with only its linker
    # signature -- the exact shape the smoke helper shipped in.
    cc -o "$dir/Contents/Resources/stray-helper" "$WORK/tiny.c"
  fi

  codesign "${args[@]}" "$dir/Contents/MacOS/tinyapp"
  codesign "${args[@]}" "$dir"
}

echo "== a clean hardened bundle passes =="
make_bundle "$WORK/Clean.app" 1 1 0
check "clean hardened bundle is ready" 0 bash "$GATE" --app "$WORK/Clean.app"

echo
echo "== hardened with no entitlements fails =="
make_bundle "$WORK/NoEnt.app" 1 0 0
check "missing audio-input entitlement is caught" 1 bash "$GATE" --app "$WORK/NoEnt.app"
expect_output "  names the entitlement" "com.apple.security.device.audio-input"

echo
echo "== a linker-signed Mach-O under Resources fails =="
make_bundle "$WORK/Stray.app" 1 1 1
check "stray Mach-O is caught" 1 bash "$GATE" --app "$WORK/Stray.app"
expect_output "  names the stray binary" "stray-helper"

echo
echo "== the stray Mach-O passes codesign's own deep check =="
# Documents why this gate exists at all: the tool everyone reaches for is happy.
if codesign --verify --deep --strict "$WORK/Stray.app" >/dev/null 2>&1; then
  printf 'ok    codesign --verify --deep --strict accepts the bad bundle\n'
else
  printf 'FAIL  codesign now rejects it too; this gate may be redundant\n'
  FAILURES=$((FAILURES + 1))
fi

echo
echo "== --allow-unhardened tolerates a local dev build =="
make_bundle "$WORK/Dev.app" 0 0 0
check "unhardened dev build passes with the flag" 0 bash "$GATE" --app "$WORK/Dev.app" --allow-unhardened
check "unhardened dev build fails without it" 1 bash "$GATE" --app "$WORK/Dev.app"

echo
echo "== an ad-hoc bundle is not Developer ID ready =="
check "--require-developer-id rejects ad-hoc signing" 1 \
  bash "$GATE" --app "$WORK/Clean.app" --require-developer-id
expect_output "  names the missing authority" "Developer ID Application"

echo
echo "== missing usage strings are caught =="
make_bundle "$WORK/NoPlist.app" 1 1 0
/usr/libexec/PlistBuddy -c 'Delete :NSMicrophoneUsageDescription' "$WORK/NoPlist.app/Contents/Info.plist" >/dev/null
codesign --force --sign - --timestamp=none --options runtime \
  --entitlements "$ROOT/resources/PressTalk.entitlements" "$WORK/NoPlist.app" >/dev/null 2>&1
check "missing NSMicrophoneUsageDescription is caught" 1 bash "$GATE" --app "$WORK/NoPlist.app"

echo
echo "== json output is valid =="
bash "$GATE" --app "$WORK/Clean.app" --json-output "$WORK/result.json" >/dev/null 2>&1 || true
check "json output parses" 0 python3 -c "import json,sys; json.load(open('$WORK/result.json'))"

echo
if [[ "$FAILURES" -gt 0 ]]; then
  echo "$FAILURES check(s) failed" >&2
  exit 1
fi
echo "All readiness-gate checks passed."
