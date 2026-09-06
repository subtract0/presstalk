#!/usr/bin/env bash
# Regression test for the failure that made distribution signing silently
# produce no package at all.
#
# signature_authority() piped codesign into `awk ... { exit }`. awk closes the
# pipe on the first match, codesign takes SIGPIPE, and `set -o pipefail` turns
# that into exit 141. At the call site the function runs inside a command
# substitution, so `set -e` killed the whole script with no output. The build
# looked like it had finished; no zip was ever written.
#
# This asserts both halves: the helper returns the right authority, AND it
# returns status 0 under the same shell options the release script uses.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_SCRIPT="$ROOT/scripts/package_presstalk_release.sh"
failures=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf 'ok    %s\n' "$label"
  else
    printf 'FAIL  %s\n        expected: %s\n        actual:   %s\n' \
      "$label" "$expected" "$actual"
    failures=$((failures + 1))
  fi
}

# Pull the helper out of the release script so the test exercises the shipping
# definition rather than a copy that can drift away from it.
helper="$(awk '/^signature_authority\(\)/,/^}/' "$RELEASE_SCRIPT")"
if [[ -z "$helper" ]]; then
  echo "FAIL  could not extract signature_authority() from $RELEASE_SCRIPT" >&2
  exit 1
fi

# Sign a throwaway bundle with whatever identity this machine has, so the test
# runs on a developer Mac with only the local identity as well as on one with a
# Developer ID certificate.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null |
  awk '/Developer ID Application/ { print $2; exit }')"
[[ -z "$IDENTITY" ]] && IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null |
  awk '/[0-9]\)/ { print $2; exit }')"

if [[ -z "$IDENTITY" ]]; then
  echo "SKIP  no code signing identity available on this machine"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-authority-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
BUNDLE="$WORK/Probe.app"
mkdir -p "$BUNDLE/Contents/MacOS"
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.am.presstalk.authorityprobe</string>
<key>CFBundleExecutable</key><string>probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
cp /usr/bin/true "$BUNDLE/Contents/MacOS/probe"
codesign --force --sign "$IDENTITY" "$BUNDLE" >/dev/null 2>&1

EXPECTED="$(codesign -dv --verbose=4 "$BUNDLE" 2>&1 |
  grep '^Authority=' | head -1 | cut -d= -f2-)"

# The defect only appears under `set -e` plus `set -o pipefail`, which is what
# the release script runs with. Reproduce those options exactly.
actual="$(bash -c "
  set -euo pipefail
  $helper
  signature_authority '$BUNDLE'
" 2>/dev/null)"
status=$?

check "returns the signing authority" "$EXPECTED" "$actual"
check "exits 0 under set -euo pipefail" "0" "$status"

# Prove the test would have caught the original bug, so a future rewrite that
# reintroduces the pipe cannot pass by accident.
buggy='signature_authority() {
  local bundle="$1"
  codesign -dv --verbose=4 "$bundle" 2>&1 |
    awk -F= "/^Authority=/ { print \$2; exit }"
}'
bash -c "
  set -euo pipefail
  $buggy
  signature_authority '$BUNDLE'
" >/dev/null 2>&1
buggy_status=$?
if (( buggy_status == 0 )); then
  printf 'FAIL  %s\n' "the known-bad piped version passed; this test proves nothing"
  failures=$((failures + 1))
else
  printf 'ok    known-bad piped version still fails (status %d)\n' "$buggy_status"
fi

echo
if (( failures == 0 )); then
  echo "PASS"
else
  echo "FAILED: $failures check(s)"
fi
exit $(( failures > 0 ))
