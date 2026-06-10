#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_SCRIPT="$SCRIPT_DIR/package_presstalk_release.sh"
PUBLISH_HOMEBREW_SCRIPT="$SCRIPT_DIR/publish_presstalk_homebrew.sh"
PUBLISH_PRERELEASE_SCRIPT="$SCRIPT_DIR/publish_presstalk_prerelease.sh"
ARTIFACT_AUDIT_SCRIPT="$SCRIPT_DIR/presstalk_release_artifact_audit.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-distribution-package-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

proof_gate_json="$TEST_TMPDIR/proof-gate.json"
cat >"$proof_gate_json" <<'JSON'
{
  "schemaVersion": "1",
  "proven": true,
  "failureCount": 0,
  "targets": [
    {
      "required": "local",
      "target": "local",
      "machineHost": "studio1",
      "asrBackend": "parakeet-v3-ane",
      "asrMode": "parakeet_v3_ane_final_pass",
      "realtimePartialTranscriptionEnabled": false,
      "status": "ready_reported",
      "reachable": true,
      "physicalSTTSmokeReady": true,
      "activeFieldSmokeReady": true,
      "passed": true,
      "failures": []
    }
  ]
}
JSON

build_ad_hoc_test_zip() {
  local app="$TEST_TMPDIR/PressTalk.app"
  local zip="$TEST_TMPDIR/PressTalk-0.0-test-macos-arm64.zip"
  mkdir -p "$app/Contents/MacOS"

  plutil -create xml1 "$app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string com.am.presstalk "$app/Contents/Info.plist"
  plutil -insert CFBundleShortVersionString -string 0.0-test "$app/Contents/Info.plist"
  plutil -insert CFBundleVersion -string 1 "$app/Contents/Info.plist"
  plutil -insert CFBundleExecutable -string PressTalk "$app/Contents/Info.plist"

  printf '#!/usr/bin/env bash\necho fake PressTalk\n' >"$app/Contents/MacOS/PressTalk"
  chmod +x "$app/Contents/MacOS/PressTalk"
  codesign --force --sign - "$app" >/dev/null
  ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
  printf '%s\n' "$zip"
}

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
grep -Fq "presstalk_release_artifact_audit.sh" "$PUBLISH_HOMEBREW_SCRIPT"
grep -Fq "artifact-audit.json" "$PUBLISH_HOMEBREW_SCRIPT"
grep -Fq -- "--require-distribution" "$PUBLISH_HOMEBREW_SCRIPT"
grep -Fq -- "--require-notarized" "$PUBLISH_HOMEBREW_SCRIPT"
grep -Fq 'REQUIRED_PROOF_TARGETS="studio1,mbp1"' "$PUBLISH_HOMEBREW_SCRIPT"
grep -Fq 'REQUIRE_STREAMING_RELEASE=1' "$PUBLISH_HOMEBREW_SCRIPT"
grep -Fq 'EXPECTED_ASR_MODE="any"' "$PUBLISH_HOMEBREW_SCRIPT"
grep -Fq 'PRESSTALK_STREAMING_BENCH_QUALITY_JSON' "$PUBLISH_HOMEBREW_SCRIPT"
grep -Fq 'PRESSTALK_HYBRID_STREAMING_QUALITY_JSON' "$PUBLISH_HOMEBREW_SCRIPT"
grep -Fq -- "--require-streaming-bench-quality" "$PUBLISH_HOMEBREW_SCRIPT"
grep -Fq -- "--require-hybrid-streaming-quality" "$PUBLISH_HOMEBREW_SCRIPT"
grep -Fq -- "--require-streaming" "$PUBLISH_HOMEBREW_SCRIPT"
grep -Fq -- "--require-proof-target" "$PUBLISH_HOMEBREW_SCRIPT"

stable_publish_without_proof_output="$TEST_TMPDIR/stable-publish-without-proof.txt"
set +e
env -u PRESSTALK_CODESIGN_IDENTITY -u CODESIGN_IDENTITY \
  PRESSTALK_DISTRIBUTION_SIGNING=1 \
  PRESSTALK_NOTARIZE=1 \
  "$PUBLISH_HOMEBREW_SCRIPT" 0.1.6 >"$stable_publish_without_proof_output" 2>&1
stable_publish_without_proof_status=$?
set -e
if [[ "$stable_publish_without_proof_status" -ne 2 ]]; then
  echo "FAIL: expected stable Homebrew publish without proof gate JSON to exit 2, got $stable_publish_without_proof_status"
  cat "$stable_publish_without_proof_output"
  exit 1
fi
grep -Fq "without machine proof" "$stable_publish_without_proof_output"
grep -Fq "PRESSTALK_RELEASE_PROOF_GATE_JSON" "$stable_publish_without_proof_output"

stable_publish_without_streaming_quality_output="$TEST_TMPDIR/stable-publish-without-streaming-quality.txt"
set +e
env -u PRESSTALK_CODESIGN_IDENTITY -u CODESIGN_IDENTITY \
  PRESSTALK_DISTRIBUTION_SIGNING=1 \
  PRESSTALK_NOTARIZE=1 \
  PRESSTALK_RELEASE_PROOF_GATE_JSON="$proof_gate_json" \
  "$PUBLISH_HOMEBREW_SCRIPT" 0.1.6 >"$stable_publish_without_streaming_quality_output" 2>&1
stable_publish_without_streaming_quality_status=$?
set -e
if [[ "$stable_publish_without_streaming_quality_status" -ne 2 ]]; then
  echo "FAIL: expected stable Homebrew publish without streaming quality JSON to exit 2, got $stable_publish_without_streaming_quality_status"
  cat "$stable_publish_without_streaming_quality_output"
  exit 1
fi
grep -Fq "without streaming ASR" "$stable_publish_without_streaming_quality_output"
grep -Fq "PRESSTALK_STREAMING_BENCH_QUALITY_JSON" "$stable_publish_without_streaming_quality_output"
grep -Fq "PRESSTALK_HYBRID_STREAMING_QUALITY_JSON" "$stable_publish_without_streaming_quality_output"

stable_prerelease_tag_output="$TEST_TMPDIR/stable-prerelease-tag.txt"
set +e
PRESSTALK_ALLOW_STABLE_PRERELEASE_TAG=0 \
  "$PUBLISH_PRERELEASE_SCRIPT" 0.1.6 >"$stable_prerelease_tag_output" 2>&1
stable_prerelease_tag_status=$?
set -e
if [[ "$stable_prerelease_tag_status" -ne 2 ]]; then
  echo "FAIL: expected stable-looking prerelease tag to exit 2, got $stable_prerelease_tag_status"
  cat "$stable_prerelease_tag_output"
  exit 1
fi
grep -Fq "Refusing to publish a prerelease smoke artifact with a stable-looking version" "$stable_prerelease_tag_output"
if grep -Fq "studio2/s2 only" "$PUBLISH_PRERELEASE_SCRIPT"; then
  echo "FAIL: prerelease notes must not list studio2/s2 as an active-only smoke target"
  exit 1
fi
grep -Fq "studio2/s2" "$PUBLISH_PRERELEASE_SCRIPT"
grep -Fq "is excluded from microphone/STT smoke" "$PUBLISH_PRERELEASE_SCRIPT"
grep -Fq "presstalk_release_artifact_audit.sh" "$PUBLISH_PRERELEASE_SCRIPT"
grep -Fq "artifact-audit.json" "$PUBLISH_PRERELEASE_SCRIPT"

homebrew_dry_run_dist="$TEST_TMPDIR/homebrew-dry-run-dist"
homebrew_dry_run_output="$TEST_TMPDIR/homebrew-dry-run.txt"
PRESSTALK_PUBLISH_DRY_RUN=1 \
PRESSTALK_REQUIRE_RELEASE_READINESS=1 \
PRESSTALK_RELEASE_PROOF_GATE_JSON="$proof_gate_json" \
PRESSTALK_REQUIRED_PROOF_TARGETS=studio1 \
PRESSTALK_DIST_DIR="$homebrew_dry_run_dist" \
  "$PUBLISH_HOMEBREW_SCRIPT" 0.0-homebrew-dryrun >"$homebrew_dry_run_output" 2>&1
grep -Fq "PressTalk publish dry run complete" "$homebrew_dry_run_output"
grep -Fq "ReadinessJSON:" "$homebrew_dry_run_output"
test -f "$homebrew_dry_run_dist/PressTalk-0.0-homebrew-dryrun-macos-arm64.zip"
test -f "$homebrew_dry_run_dist/PressTalk-0.0-homebrew-dryrun-macos-arm64-artifact-audit.json"
test -f "$homebrew_dry_run_dist/PressTalk-0.0-homebrew-dryrun-macos-arm64-release-readiness.json"
grep -Fq '"bundleIdentifier"' "$homebrew_dry_run_dist/PressTalk-0.0-homebrew-dryrun-macos-arm64-artifact-audit.json"
grep -Fq '"testArtifactReady"' "$homebrew_dry_run_dist/PressTalk-0.0-homebrew-dryrun-macos-arm64-release-readiness.json"
grep -Fq '"requiredProofTargetsReady"' "$homebrew_dry_run_dist/PressTalk-0.0-homebrew-dryrun-macos-arm64-release-readiness.json"

prerelease_dry_run_dist="$TEST_TMPDIR/prerelease-dry-run-dist"
prerelease_dry_run_output="$TEST_TMPDIR/prerelease-dry-run.txt"
PRESSTALK_PUBLISH_DRY_RUN=1 \
PRESSTALK_REQUIRE_RELEASE_READINESS=1 \
PRESSTALK_RELEASE_PROOF_GATE_JSON="$proof_gate_json" \
PRESSTALK_REQUIRED_PROOF_TARGETS=studio1 \
PRESSTALK_DIST_DIR="$prerelease_dry_run_dist" \
  "$PUBLISH_PRERELEASE_SCRIPT" 0.0-prerelease-dryrun >"$prerelease_dry_run_output" 2>&1
grep -Fq "PressTalk prerelease publish dry run complete" "$prerelease_dry_run_output"
grep -Fq "ReadinessJSON:" "$prerelease_dry_run_output"
test -f "$prerelease_dry_run_dist/PressTalk-0.0-prerelease-dryrun-macos-$(uname -m).zip"
test -f "$prerelease_dry_run_dist/PressTalk-0.0-prerelease-dryrun-macos-$(uname -m)-artifact-audit.json"
test -f "$prerelease_dry_run_dist/PressTalk-0.0-prerelease-dryrun-macos-$(uname -m)-release-readiness.json"
grep -Fq '"bundleIdentifier"' "$prerelease_dry_run_dist/PressTalk-0.0-prerelease-dryrun-macos-$(uname -m)-artifact-audit.json"
grep -Fq '"testArtifactReady"' "$prerelease_dry_run_dist/PressTalk-0.0-prerelease-dryrun-macos-$(uname -m)-release-readiness.json"
grep -Fq '"requiredProofTargetsReady"' "$prerelease_dry_run_dist/PressTalk-0.0-prerelease-dryrun-macos-$(uname -m)-release-readiness.json"

artifact_zip="$(build_ad_hoc_test_zip)"
artifact_audit_json="$TEST_TMPDIR/artifact-audit.json"
artifact_audit_output="$TEST_TMPDIR/artifact-audit.txt"
"$ARTIFACT_AUDIT_SCRIPT" \
  --zip "$artifact_zip" \
  --expected-bundle-id com.am.presstalk \
  --expected-version 0.0-test \
  --json-output "$artifact_audit_json" >"$artifact_audit_output" 2>&1
grep -Fq "Result: pass" "$artifact_audit_output"
grep -Fq '"bundleIdentifier"' "$artifact_audit_json"
grep -Fq '"com.am.presstalk"' "$artifact_audit_json"
grep -Fq '"passed"' "$artifact_audit_json"

artifact_distribution_output="$TEST_TMPDIR/artifact-distribution-required.txt"
set +e
"$ARTIFACT_AUDIT_SCRIPT" \
  --zip "$artifact_zip" \
  --expected-bundle-id com.am.presstalk \
  --expected-version 0.0-test \
  --require-distribution >"$artifact_distribution_output" 2>&1
artifact_distribution_status=$?
set -e
if [[ "$artifact_distribution_status" -ne 1 ]]; then
  echo "FAIL: expected ad-hoc artifact with distribution requirement to exit 1, got $artifact_distribution_status"
  cat "$artifact_distribution_output"
  exit 1
fi
grep -Fq "distribution_signature_required" "$artifact_distribution_output"

echo "PASS distribution_packaging"
