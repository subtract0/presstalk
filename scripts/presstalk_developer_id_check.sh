#!/usr/bin/env bash
# Checks the two things a Developer ID release needs that this repo cannot create:
# a Developer ID Application identity, and a notarytool credential profile.
# Everything else in the release path is already scripted.
#
# Run after the two owner steps in docs/DEVELOPER_ID_SETUP.md.
# Exit 0 means scripts/package_presstalk_release.sh can sign and notarize.
#
# Deliberately does NOT test-sign anything. A test signature makes the Security
# framework touch the private key, and on a freshly created certificate that
# raises a modal keychain prompt and blocks forever in a non-interactive shell.
# Measured on studio1 2026-09-06: it hung until killed. The listing below is
# sufficient anyway - `find-identity` enumerates identities, which by definition
# are a certificate paired with its private key. A bare .cer never appears here.
set -uo pipefail

TEAM_ID="${PRESSTALK_TEAM_ID:-5HUC5LA94B}"
PROFILE="${PRESSTALK_NOTARYTOOL_PROFILE:-presstalk-notary}"
failures=0

fail() { printf '  FAIL  %s\n' "$*"; failures=$((failures + 1)); }
pass() { printf '  ok    %s\n' "$*"; }
note() { printf '        %s\n' "$*"; }

echo "== 1. Developer ID Application identity =="
identities="$(security find-identity -v -p codesigning 2>/dev/null)"
devid_line="$(printf '%s\n' "$identities" | grep 'Developer ID Application' | head -1)"

if [[ -z "$devid_line" ]]; then
  fail "no Developer ID Application identity in any keychain"
  note ""
  note "What is here instead:"
  printf '%s\n' "$identities" | sed 's/^/          /'
  note ""
  note "Fix: Xcode > Settings > Accounts > Manage Certificates > + >"
  note "     Developer ID Application.  See docs/DEVELOPER_ID_SETUP.md"
else
  pass "$(printf '%s' "$devid_line" | sed 's/^ *[0-9]*) [0-9A-F]* //')"
  note "listed by find-identity, so the private key is paired and unexpired"
  if printf '%s' "$devid_line" | grep -q "$TEAM_ID"; then
    pass "team $TEAM_ID matches the enrolled account"
  else
    fail "identity is not for team $TEAM_ID"
  fi
fi

echo
echo "== 2. notarytool credentials =="
if ! xcrun --find notarytool >/dev/null 2>&1; then
  fail "notarytool not found (needs full Xcode, not Command Line Tools alone)"
elif xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  pass "keychain profile '$PROFILE' authenticates against Apple"
else
  fail "keychain profile '$PROFILE' missing, or Apple rejected it"
  note "Fix, run by the owner so the password is never seen by an agent:"
  note "  xcrun notarytool store-credentials \"$PROFILE\" \\"
  note "      --apple-id <apple-id> --team-id $TEAM_ID"
  note "It prompts for an app-specific password from appleid.apple.com."
fi

echo
if (( failures == 0 )); then
  cat <<'READY'
READY.

First signing run may raise one keychain prompt for the new private key.
Click "Always Allow", not "Allow", or every later build stops on the same
dialog. Run the release in a terminal you are watching the first time.

Next:
  PRESSTALK_DISTRIBUTION_SIGNING=1 PRESSTALK_NOTARIZE=1 \
  PRESSTALK_NOTARYTOOL_PROFILE=presstalk-notary \
  PRESSTALK_CODESIGN_IDENTITY="Developer ID Application" \
  scripts/package_presstalk_release.sh 0.1.9
READY
else
  echo "NOT READY: $failures check(s) failed. Nothing was signed."
fi
exit $(( failures > 0 ))
