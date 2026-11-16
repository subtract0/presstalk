#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-identity-guard.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
mkdir -p "$TEST_TMPDIR/bin"
cat >"$TEST_TMPDIR/bin/security" <<'SH'
#!/usr/bin/env bash
printf '  1) OFFICIALHASH "Developer ID Application: PressTalk (5HUC5LA94B)"\n'
printf '  2) LOCALHASH "PressTalk Local Development Code Signing"\n'
printf '  3) WRONGTEAMHASH "Developer ID Application: Someone (OTHERTEAM)"\n'
SH
cat >"$TEST_TMPDIR/bin/swift" <<'SH'
#!/usr/bin/env bash
echo "Build must not begin during preflight" >&2
exit 99
SH
chmod +x "$TEST_TMPDIR/bin/"*

plan() {
  env -u PRESSTALK_APP_BUNDLE -u PRESSTALK_BUNDLE_IDENTIFIER -u PRESSTALK_APP_BUNDLE_IDENTIFIER \
    -u PRESSTALK_CODESIGN_IDENTITY -u CODESIGN_IDENTITY \
    PATH="$TEST_TMPDIR/bin:$PATH" PRESSTALK_DISTRIBUTION_SIGNING=0 PRESSTALK_BUILD_PLAN_ONLY=1 \
    "$@" bash "$SCRIPT_DIR/build_jarvistap.sh"
}
reject() {
  local label="$1"; shift
  if plan "$@" >"$TEST_TMPDIR/$label.log" 2>&1; then
    echo "FAIL: $label was allowed" >&2; exit 1
  fi
  if grep -Fq 'Build must not begin' "$TEST_TMPDIR/$label.log"; then
    echo "FAIL: $label reached build before rejection" >&2; exit 1
  fi
}
plan >"$TEST_TMPDIR/default.log"
grep -Fq '/Applications/PressTalk Dev.app' "$TEST_TMPDIR/default.log"
grep -Fq 'BundleIdentifier: com.am.presstalk.dev' "$TEST_TMPDIR/default.log"
reject production-id PRESSTALK_BUNDLE_IDENTIFIER=com.am.presstalk
reject legacy-id PRESSTALK_BUNDLE_IDENTIFIER=com.am.jarvistap
reject daily-destination PRESSTALK_APP_BUNDLE="$HOME/Applications/PressTalk.app"
reject system-destination PRESSTALK_APP_BUNDLE=/Applications/PressTalk.app
ln -s "$HOME/Applications/PressTalk.app" "$TEST_TMPDIR/alias.app"
reject symlink-destination PRESSTALK_APP_BUNDLE="$TEST_TMPDIR/alias.app"
reject unsigned-production PRESSTALK_DISTRIBUTION_SIGNING=1
reject adhoc-production PRESSTALK_DISTRIBUTION_SIGNING=1 PRESSTALK_CODESIGN_IDENTITY=-
reject local-production PRESSTALK_DISTRIBUTION_SIGNING=1 PRESSTALK_CODESIGN_IDENTITY=LOCALHASH
reject other-team PRESSTALK_DISTRIBUTION_SIGNING=1 PRESSTALK_CODESIGN_IDENTITY=WRONGTEAMHASH
plan PRESSTALK_DISTRIBUTION_SIGNING=1 PRESSTALK_CODESIGN_IDENTITY=OFFICIALHASH \
  PRESSTALK_APP_BUNDLE="$TEST_TMPDIR/staging/PressTalk.app" >"$TEST_TMPDIR/official.log"
grep -Fq 'BundleIdentifier: com.am.presstalk' "$TEST_TMPDIR/official.log"

existing="$TEST_TMPDIR/renamed.app"
mkdir -p "$existing/Contents"
plutil -create xml1 "$existing/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.am.presstalk "$existing/Contents/Info.plist"
printf 'production-sentinel\n' >"$existing/sentinel"
reject renamed-production PRESSTALK_APP_BUNDLE="$existing"
reject official-existing PRESSTALK_DISTRIBUTION_SIGNING=1 PRESSTALK_CODESIGN_IDENTITY=OFFICIALHASH PRESSTALK_APP_BUNDLE="$existing"
test "$(cat "$existing/sentinel")" = production-sentinel

# An identity override must be rejected by the shipped bootstrap before it
# can touch preferences, services, metadata, or the signature.
mkdir -p "$existing/Contents/Resources"
cp "$SCRIPT_DIR/presstalk_bootstrap.sh" "$existing/Contents/Resources/presstalk-bootstrap.sh"
if PRESSTALK_BUNDLE_IDENTIFIER=com.am.presstalk.dev bash "$existing/Contents/Resources/presstalk-bootstrap.sh" >"$TEST_TMPDIR/bootstrap.log" 2>&1; then
  echo 'FAIL: bootstrap changed production identity' >&2; exit 1
fi
grep -Fq 'Bootstrap cannot change an app identity' "$TEST_TMPDIR/bootstrap.log"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$existing/Contents/Info.plist")" = com.am.presstalk
if PRESSTALK_APP_BUNDLE="$existing" bash "$SCRIPT_DIR/presstalk_repair_local_signing.sh" --preflight >"$TEST_TMPDIR/repair.log" 2>&1; then
  echo 'FAIL: repair accepted production identity' >&2; exit 1
fi
grep -Fq 'Local signing repair is only for .dev apps' "$TEST_TMPDIR/repair.log"
echo 'PASS build_identity_guard'
