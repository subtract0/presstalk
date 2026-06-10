#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_SCRIPT="$SCRIPT_DIR/package_presstalk_release.sh"
PUBLISH_HOMEBREW_SCRIPT="$SCRIPT_DIR/publish_presstalk_homebrew.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-distribution-package-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

missing_identity_output="$TEST_TMPDIR/missing-identity.txt"
set +e
env -u PRESSTALK_CODESIGN_IDENTITY -u CODESIGN_IDENTITY \
  PRESSTALK_DISTRIBUTION_SIGNING=1 \
  "$PACKAGE_SCRIPT" 0.0-test >"$missing_identity_output" 2>&1
missing_identity_status=$?
set -e
if [[ "$missing_identity_status" -ne 2 ]]; then
  echo "FAIL: expected missing distribution identity to exit 2, got $missing_identity_status"
  cat "$missing_identity_output"
  exit 1
fi
grep -Fq "requires a Developer ID signing identity" "$missing_identity_output"

notarize_without_signing_output="$TEST_TMPDIR/notarize-without-signing.txt"
set +e
env -u PRESSTALK_CODESIGN_IDENTITY -u CODESIGN_IDENTITY \
  PRESSTALK_NOTARIZE=1 \
  PRESSTALK_DISTRIBUTION_SIGNING=0 \
  "$PACKAGE_SCRIPT" 0.0-test >"$notarize_without_signing_output" 2>&1
notarize_without_signing_status=$?
set -e
if [[ "$notarize_without_signing_status" -ne 2 ]]; then
  echo "FAIL: expected notarization without distribution signing to exit 2, got $notarize_without_signing_status"
  cat "$notarize_without_signing_output"
  exit 1
fi
grep -Fq "PRESSTALK_NOTARIZE=1 requires PRESSTALK_DISTRIBUTION_SIGNING=1" "$notarize_without_signing_output"

stable_publish_without_signing_output="$TEST_TMPDIR/stable-publish-without-signing.txt"
set +e
env -u PRESSTALK_CODESIGN_IDENTITY -u CODESIGN_IDENTITY \
  PRESSTALK_DISTRIBUTION_SIGNING=0 \
  PRESSTALK_NOTARIZE=0 \
  "$PUBLISH_HOMEBREW_SCRIPT" 0.1.6 >"$stable_publish_without_signing_output" 2>&1
stable_publish_without_signing_status=$?
set -e
if [[ "$stable_publish_without_signing_status" -ne 2 ]]; then
  echo "FAIL: expected stable Homebrew publish without distribution signing to exit 2, got $stable_publish_without_signing_status"
  cat "$stable_publish_without_signing_output"
  exit 1
fi
grep -Fq "Refusing to publish a stable PressTalk Homebrew release without production" "$stable_publish_without_signing_output"

stable_publish_without_notary_output="$TEST_TMPDIR/stable-publish-without-notary.txt"
set +e
env -u PRESSTALK_CODESIGN_IDENTITY -u CODESIGN_IDENTITY \
  PRESSTALK_DISTRIBUTION_SIGNING=1 \
  PRESSTALK_NOTARIZE=0 \
  "$PUBLISH_HOMEBREW_SCRIPT" 0.1.6 >"$stable_publish_without_notary_output" 2>&1
stable_publish_without_notary_status=$?
set -e
if [[ "$stable_publish_without_notary_status" -ne 2 ]]; then
  echo "FAIL: expected stable Homebrew publish without notarization to exit 2, got $stable_publish_without_notary_status"
  cat "$stable_publish_without_notary_output"
  exit 1
fi
grep -Fq "Refusing to publish a stable PressTalk Homebrew release without notarization" "$stable_publish_without_notary_output"

echo "PASS distribution_packaging"
