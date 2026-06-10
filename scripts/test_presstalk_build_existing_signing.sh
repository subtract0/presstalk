#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-build-existing-signing-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

fake_bin="$TEST_TMPDIR/bin"
home_dir="$TEST_TMPDIR/home"
swift_bin_dir="$TEST_TMPDIR/swift-bin"
app_bundle="$TEST_TMPDIR/PressTalk.app"
codesign_log="$TEST_TMPDIR/codesign.log"
mkdir -p "$fake_bin" "$home_dir/Library/Application Support/PressTalk" "$swift_bin_dir"

cat >"$fake_bin/swift" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "package clean" ]]; then
  exit 0
fi

if [[ "$*" == "build -c release --show-bin-path" ]]; then
  printf '%s\n' "$PRESSTALK_TEST_SWIFT_BIN_DIR"
  exit 0
fi

if [[ "$1" == "build" ]]; then
  mkdir -p "$PRESSTALK_TEST_SWIFT_BIN_DIR"
  for product in jarvistap presstalk-input-method; do
    cat >"$PRESSTALK_TEST_SWIFT_BIN_DIR/$product" <<EOF
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$PRESSTALK_TEST_SWIFT_BIN_DIR/$product"
  done
  exit 0
fi

echo "unexpected fake swift invocation: $*" >&2
exit 99
SH
chmod +x "$fake_bin/swift"

cat >"$fake_bin/swiftc" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    output="${2:-}"
    shift 2
  else
    shift
  fi
done
if [[ -z "$output" ]]; then
  echo "fake swiftc missing -o" >&2
  exit 99
fi
mkdir -p "$(dirname "$output")"
cat >"$output" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$output"
SH
chmod +x "$fake_bin/swiftc"

cat >"$fake_bin/codesign" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$PRESSTALK_TEST_CODESIGN_LOG"
exit 0
SH
chmod +x "$fake_bin/codesign"

cat >"$fake_bin/security" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  unlock-keychain|set-keychain-settings|set-key-partition-list)
    exit 0
    ;;
  list-keychains)
    if [[ "${2:-}" == "-d" && "${3:-}" == "user" ]]; then
      exit 0
    fi
    exit 0
    ;;
  find-identity)
    if [[ "${PRESSTALK_TEST_EXISTING_IDENTITY:-missing}" == "ready" ]]; then
      printf '  1) TESTHASH "PressTalk Local Development Code Signing"\n'
    fi
    exit 0
    ;;
esac

echo "unexpected fake security invocation: $*" >&2
exit 99
SH
chmod +x "$fake_bin/security"

keychain="$home_dir/Library/Keychains/presstalk-local-dev.keychain-db"
mkdir -p "$(dirname "$keychain")"
touch "$keychain"
printf 'test-password\n' >"$home_dir/Library/Application Support/PressTalk/local-codesign-keychain-password"

run_build() {
  local output_file="$1"
  shift
  HOME="$home_dir" \
  PATH="$fake_bin:$PATH" \
  PRESSTALK_APP_BUNDLE="$app_bundle" \
  PRESSTALK_TEST_SWIFT_BIN_DIR="$swift_bin_dir" \
  PRESSTALK_TEST_CODESIGN_LOG="$codesign_log" \
  PRESSTALK_BUILD_STABLE_SIGNING=existing \
  PRESSTALK_BUILD_REQUIRE_STABLE_SIGNING=1 \
  PRESSTALK_LOCAL_CODESIGN_KEYCHAIN="$keychain" \
    "$@" >"$output_file" 2>&1
}

ready_output="$TEST_TMPDIR/ready.txt"
PRESSTALK_TEST_EXISTING_IDENTITY=ready run_build "$ready_output" bash "$ROOT/scripts/build_jarvistap.sh"
grep -Fq "Code signing identity: TESTHASH" "$ready_output"
grep -Fq -- "--sign TESTHASH" "$codesign_log"
test -x "$app_bundle/Contents/MacOS/jarvistap"
test -x "$app_bundle/Contents/Resources/PressTalkInputMethod.app/Contents/MacOS/presstalk-input-method"

rm -rf "$app_bundle" "$swift_bin_dir" "$codesign_log"
mkdir -p "$swift_bin_dir"
missing_output="$TEST_TMPDIR/missing.txt"
if PRESSTALK_TEST_EXISTING_IDENTITY=missing run_build "$missing_output" bash "$ROOT/scripts/build_jarvistap.sh"; then
  echo "FAIL: existing-signing build unexpectedly succeeded without a trusted identity" >&2
  exit 1
fi
grep -Fq "no existing trusted PressTalk identity is available without a trust prompt" "$missing_output"
if [[ -f "$codesign_log" ]] && grep -Fq -- "--sign -" "$codesign_log"; then
  echo "FAIL: existing-signing build fell back to ad-hoc signing" >&2
  exit 1
fi

echo "PASS build_existing_signing"
