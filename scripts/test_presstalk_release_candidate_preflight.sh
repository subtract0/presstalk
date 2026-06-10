#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$SCRIPT_DIR/presstalk_release_candidate_preflight.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-candidate-preflight-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

fake_matrix="$TEST_TMPDIR/fake-readiness-matrix.sh"
fake_publish="$TEST_TMPDIR/fake-publish-homebrew.sh"
fake_host_discovery="$TEST_TMPDIR/fake-host-discovery.sh"

cat >"$fake_matrix" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

json_output=""
include_local=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json-output)
      json_output="${2:-}"
      shift 2
      ;;
    --local)
      include_local=1
      shift
      ;;
    --host|--exclude-host)
      shift 2
      ;;
    *)
      echo "Unexpected fake matrix argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$json_output" ]]; then
  echo "Missing fake matrix JSON output" >&2
  exit 2
fi
if [[ "$include_local" -ne 1 ]]; then
  echo "Fake matrix expected --local" >&2
  exit 2
fi

mkdir -p "$(dirname "$json_output")"
cat >"$json_output" <<'JSON'
{
  "schemaVersion": "1",
  "targets": [
    {
      "target": "local",
      "status": "ready_reported",
      "reachable": true,
      "summary": {
        "machineHost": "studio1",
        "asrBackend": "parakeet-v3-ane",
        "streamingASRBackend": "parakeet-eou-320",
        "asrMode": "parakeet_v3_ane_final_pass_with_parakeet_eou_320_true_streaming_partials",
        "realtimePartialTranscriptionEnabled": true,
        "physicalSTTSmokeReady": true,
        "activeFieldSmokeReady": true,
        "realFieldSmokeSuccess": true,
        "realFieldTargetCaptureSuccess": true,
        "realFieldReleaseToInsertMs": "1345",
        "realFieldFinalizer": "offline_whisper",
        "realFieldInsertionMethod": "ax_menu_paste",
        "nextAction": "ready"
      }
    }
  ]
}
JSON
echo "Fake readiness matrix wrote $json_output"
SH
chmod +x "$fake_matrix"

cat >"$fake_publish" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
if [[ -z "$version" ]]; then
  echo "Missing fake publish version" >&2
  exit 2
fi
if [[ "${PRESSTALK_PUBLISH_DRY_RUN:-}" != "1" ]]; then
  echo "Fake publish expected PRESSTALK_PUBLISH_DRY_RUN=1" >&2
  exit 2
fi
if [[ "${PRESSTALK_REQUIRE_RELEASE_READINESS:-}" != "1" ]]; then
  echo "Fake publish expected PRESSTALK_REQUIRE_RELEASE_READINESS=1" >&2
  exit 2
fi
if [[ ! -f "${PRESSTALK_RELEASE_PROOF_GATE_JSON:-}" ]]; then
  echo "Fake publish expected proof gate JSON" >&2
  exit 2
fi
if [[ "${PRESSTALK_REQUIRED_PROOF_TARGETS:-}" != "local" ]]; then
  echo "Fake publish expected PRESSTALK_REQUIRED_PROOF_TARGETS=local, got ${PRESSTALK_REQUIRED_PROOF_TARGETS:-unset}" >&2
  exit 2
fi
if [[ "${PRESSTALK_REQUIRE_STREAMING_BENCH_QUALITY:-0}" == "1" &&
      ! -f "${PRESSTALK_STREAMING_BENCH_QUALITY_JSON:-}" ]]; then
  echo "Fake publish expected streaming bench quality JSON" >&2
  exit 2
fi
if [[ "${PRESSTALK_REQUIRE_HYBRID_STREAMING_QUALITY:-0}" == "1" &&
      ! -f "${PRESSTALK_HYBRID_STREAMING_QUALITY_JSON:-}" ]]; then
  echo "Fake publish expected hybrid streaming quality JSON" >&2
  exit 2
fi

dist_dir="${PRESSTALK_DIST_DIR:?}"
public_name="${PUBLIC_NAME:-PressTalk}"
arch="${ARCH:-arm64}"
mkdir -p "$dist_dir"
printf 'fake zip\n' >"$dist_dir/${public_name}-${version}-macos-${arch}.zip"
printf 'fake sha\n' >"$dist_dir/${public_name}-${version}-macos-${arch}.zip.sha256"
printf 'ran\n' >"$dist_dir/fake-publish-ran.txt"
printf '%s\n' "${PRESSTALK_REQUIRE_STREAMING_RELEASE:-unset}" >"$dist_dir/fake-publish-streaming-env.txt"
printf '%s\n' "${PRESSTALK_EXPECTED_ASR_MODE:-unset}" >"$dist_dir/fake-publish-expected-asr-mode.txt"
printf '%s\n' "${PRESSTALK_REQUIRE_STREAMING_BENCH_QUALITY:-unset}" >"$dist_dir/fake-publish-streaming-bench-env.txt"
printf '%s\n' "${PRESSTALK_STREAMING_BENCH_QUALITY_JSON:-unset}" >"$dist_dir/fake-publish-streaming-bench-json.txt"
printf '%s\n' "${PRESSTALK_REQUIRE_HYBRID_STREAMING_QUALITY:-unset}" >"$dist_dir/fake-publish-hybrid-streaming-env.txt"
printf '%s\n' "${PRESSTALK_HYBRID_STREAMING_QUALITY_JSON:-unset}" >"$dist_dir/fake-publish-hybrid-streaming-json.txt"
cat >"$dist_dir/${public_name}-${version}-macos-${arch}-artifact-audit.json" <<JSON
{
  "schemaVersion": "1",
  "zipPath": "$dist_dir/${public_name}-${version}-macos-${arch}.zip",
  "zipSHA256": "fake",
  "bundleIdentifier": "com.am.presstalk",
  "bundleIdentifierMatches": true,
  "bundleVersion": "$version",
  "versionMatches": true,
  "codeSignVerifyPassed": true,
  "developerIDApplication": false,
  "hardenedRuntime": false,
  "distributionReady": false,
  "notarized": false,
  "passed": true,
  "failureCount": 0,
  "failures": []
}
JSON
cat >"$dist_dir/${public_name}-${version}-macos-${arch}-release-readiness.json" <<'JSON'
{
  "schemaVersion": "1",
  "testArtifactReady": true,
  "productionReady": false,
  "requiredProofTargetsReady": true,
  "passed": true,
  "failures": []
}
JSON
echo "PressTalk publish dry run complete"
echo "ReadinessJSON: $dist_dir/${public_name}-${version}-macos-${arch}-release-readiness.json"
SH
chmod +x "$fake_publish"

cat >"$fake_host_discovery" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

targets=""
json_output=""
probe_ssh=0
no_arp=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --targets)
      targets="${2:-}"
      shift 2
      ;;
    --probe-ssh)
      probe_ssh=1
      shift
      ;;
    --timeout)
      shift 2
      ;;
    --no-arp)
      no_arp=1
      shift
      ;;
    --json-output)
      json_output="${2:-}"
      shift 2
      ;;
    *)
      echo "Unexpected fake host discovery argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$targets" || -z "$json_output" ]]; then
  echo "Fake host discovery expected targets and JSON output" >&2
  exit 2
fi
if [[ "$probe_ssh" -ne 1 || "$no_arp" -ne 1 ]]; then
  echo "Fake host discovery expected probe SSH with ARP disabled" >&2
  exit 2
fi

mkdir -p "$(dirname "$json_output")"
cat >"$json_output" <<JSON
{
  "schemaVersion": "1",
  "targets": [
    {
      "target": "$targets",
      "sshProbe": {
        "enabled": true,
        "success": true
      }
    }
  ],
  "arpEnabled": false
}
JSON
echo "Fake host discovery wrote $json_output"
SH
chmod +x "$fake_host_discovery"

pass_dist="$TEST_TMPDIR/pass-dist"
pass_summary="$TEST_TMPDIR/pass-summary.json"
pass_output="$TEST_TMPDIR/pass-output.txt"
PRESSTALK_READINESS_MATRIX_SCRIPT="$fake_matrix" \
PRESSTALK_PUBLISH_HOMEBREW_SCRIPT="$fake_publish" \
  "$WRAPPER" --version 0.0-candidate --dist-dir "$pass_dist" --local \
    --require local --json-output "$pass_summary" >"$pass_output"
grep -Fq "PressTalk release candidate preflight" "$pass_output"
grep -Fq "Result: pass" "$pass_output"
grep -Fq "CandidatePreflightJSON: $pass_summary" "$pass_output"
test -f "$pass_dist/PressTalk-0.0-candidate-readiness-matrix.json"
test -f "$pass_dist/PressTalk-0.0-candidate-proof-gate.json"
test -f "$pass_dist/PressTalk-0.0-candidate-macos-arm64-artifact-audit.json"
test -f "$pass_dist/PressTalk-0.0-candidate-macos-arm64-release-readiness.json"
test -f "$pass_dist/fake-publish-ran.txt"
if [[ "$(cat "$pass_dist/fake-publish-streaming-env.txt")" != "unset" ]]; then
  echo "FAIL: candidate preflight should not force streaming env by default"
  cat "$pass_dist/fake-publish-streaming-env.txt"
  exit 1
fi
if [[ -f "$pass_dist/PressTalk-0.0-candidate-host-discovery.json" ]]; then
  echo "FAIL: host discovery should not run when no hosts are supplied"
  exit 1
fi
if [[ "$(plutil -extract passed raw -o - "$pass_summary")" != "true" ||
      "$(plutil -extract version raw -o - "$pass_summary")" != "0.0-candidate" ]]; then
  echo "FAIL: candidate preflight summary mismatch"
  plutil -p "$pass_summary"
  exit 1
fi
if [[ "$(plutil -extract proven raw -o - "$pass_dist/PressTalk-0.0-candidate-proof-gate.json")" != "true" ]]; then
  echo "FAIL: proof gate should be proven"
  plutil -p "$pass_dist/PressTalk-0.0-candidate-proof-gate.json"
  exit 1
fi

real_field_dist="$TEST_TMPDIR/real-field-dist"
real_field_summary="$TEST_TMPDIR/real-field-summary.json"
real_field_output="$TEST_TMPDIR/real-field-output.txt"
PRESSTALK_READINESS_MATRIX_SCRIPT="$fake_matrix" \
PRESSTALK_PUBLISH_HOMEBREW_SCRIPT="$fake_publish" \
  "$WRAPPER" --version 0.0-realfield --dist-dir "$real_field_dist" --local \
    --require local --require-real-field-smoke \
    --json-output "$real_field_summary" >"$real_field_output"
grep -Fq "Result: pass" "$real_field_output"
if [[ "$(plutil -extract requireRealFieldSmoke raw -o - "$real_field_summary")" != "true" ||
      "$(plutil -extract requireRealFieldSmoke raw -o - "$real_field_dist/PressTalk-0.0-realfield-proof-gate.json")" != "true" ||
      "$(plutil -extract targets.0.realFieldSmokeSuccess raw -o - "$real_field_dist/PressTalk-0.0-realfield-proof-gate.json")" != "true" ||
      "$(plutil -extract targets.0.realFieldReleaseToInsertMs raw -o - "$real_field_dist/PressTalk-0.0-realfield-proof-gate.json")" != "1345" ]]; then
  echo "FAIL: strict real-field candidate preflight evidence mismatch"
  plutil -p "$real_field_summary"
  plutil -p "$real_field_dist/PressTalk-0.0-realfield-proof-gate.json"
  exit 1
fi

host_dist="$TEST_TMPDIR/host-dist"
host_summary="$TEST_TMPDIR/host-summary.json"
host_output="$TEST_TMPDIR/host-output.txt"
PRESSTALK_HOST_DISCOVERY_SCRIPT="$fake_host_discovery" \
PRESSTALK_READINESS_MATRIX_SCRIPT="$fake_matrix" \
PRESSTALK_PUBLISH_HOMEBREW_SCRIPT="$fake_publish" \
  "$WRAPPER" --version 0.0-host --dist-dir "$host_dist" --local \
    --host mbp1-tb --exclude-host "studio2=no attached microphone" \
    --require local --json-output "$host_summary" >"$host_output"
grep -Fq "Collecting host discovery..." "$host_output"
test -f "$host_dist/PressTalk-0.0-host-host-discovery.json"
if [[ "$(plutil -extract hostDiscoveryJSON raw -o - "$host_summary")" != "$host_dist/PressTalk-0.0-host-host-discovery.json" ||
      "$(plutil -extract targets.0.target raw -o - "$host_dist/PressTalk-0.0-host-host-discovery.json")" != "mbp1-tb" ||
      "$(plutil -extract arpEnabled raw -o - "$host_dist/PressTalk-0.0-host-host-discovery.json")" != "false" ]]; then
  echo "FAIL: host discovery evidence mismatch"
  plutil -p "$host_summary"
  plutil -p "$host_dist/PressTalk-0.0-host-host-discovery.json"
  exit 1
fi

default_dist="$TEST_TMPDIR/default-dist"
default_output="$TEST_TMPDIR/default-output.txt"
PRESSTALK_RELEASE_VERSION=0.0-default \
PRESSTALK_READINESS_MATRIX_SCRIPT="$fake_matrix" \
PRESSTALK_PUBLISH_HOMEBREW_SCRIPT="$fake_publish" \
  "$WRAPPER" --dist-dir "$default_dist" --local --require local >"$default_output"
grep -Fq "Version: 0.0-default" "$default_output"
test -f "$default_dist/PressTalk-0.0-default-candidate-preflight.json"

streaming_dist="$TEST_TMPDIR/streaming-dist"
streaming_output="$TEST_TMPDIR/streaming-output.txt"
streaming_quality_json="$TEST_TMPDIR/streaming-quality.json"
cat >"$streaming_quality_json" <<'JSON'
{
  "schemaVersion": "1",
  "passed": true,
  "streamingQualityReady": true
}
JSON
PRESSTALK_READINESS_MATRIX_SCRIPT="$fake_matrix" \
PRESSTALK_PUBLISH_HOMEBREW_SCRIPT="$fake_publish" \
  "$WRAPPER" --version 0.0-streaming --dist-dir "$streaming_dist" --local \
    --require local --require-streaming \
    --streaming-bench-quality "$streaming_quality_json" \
    --require-streaming-bench-quality >"$streaming_output"
grep -Fq "Result: pass" "$streaming_output"
if [[ "$(cat "$streaming_dist/fake-publish-streaming-env.txt")" != "1" ]]; then
  echo "FAIL: --require-streaming did not reach publish dry-run"
  cat "$streaming_dist/fake-publish-streaming-env.txt"
  exit 1
fi
if [[ "$(cat "$streaming_dist/fake-publish-expected-asr-mode.txt")" != "any" ]]; then
  echo "FAIL: --require-streaming did not relax expected ASR mode for prerelease dry-run"
  cat "$streaming_dist/fake-publish-expected-asr-mode.txt"
  exit 1
fi
if [[ "$(cat "$streaming_dist/fake-publish-streaming-bench-env.txt")" != "1" ||
      "$(cat "$streaming_dist/fake-publish-streaming-bench-json.txt")" != "$streaming_quality_json" ]]; then
  echo "FAIL: streaming bench quality args did not reach publish dry-run"
  cat "$streaming_dist/fake-publish-streaming-bench-env.txt"
  cat "$streaming_dist/fake-publish-streaming-bench-json.txt"
  exit 1
fi

hybrid_dist="$TEST_TMPDIR/hybrid-dist"
hybrid_output="$TEST_TMPDIR/hybrid-output.txt"
hybrid_quality_json="$TEST_TMPDIR/hybrid-quality.json"
cat >"$hybrid_quality_json" <<'JSON'
{
  "schemaVersion": "1",
  "passed": true,
  "hybridQualityReady": true,
  "streamingPartialReady": true,
  "finalizerQualityReady": true
}
JSON
PRESSTALK_READINESS_MATRIX_SCRIPT="$fake_matrix" \
PRESSTALK_PUBLISH_HOMEBREW_SCRIPT="$fake_publish" \
  "$WRAPPER" --version 0.0-hybrid --dist-dir "$hybrid_dist" --local \
    --require local --require-streaming \
    --hybrid-streaming-quality "$hybrid_quality_json" \
    --require-hybrid-streaming-quality >"$hybrid_output"
grep -Fq "Result: pass" "$hybrid_output"
if [[ "$(cat "$hybrid_dist/fake-publish-streaming-env.txt")" != "1" ]]; then
  echo "FAIL: hybrid --require-streaming did not reach publish dry-run"
  cat "$hybrid_dist/fake-publish-streaming-env.txt"
  exit 1
fi
if [[ "$(cat "$hybrid_dist/fake-publish-hybrid-streaming-env.txt")" != "1" ||
      "$(cat "$hybrid_dist/fake-publish-hybrid-streaming-json.txt")" != "$hybrid_quality_json" ]]; then
  echo "FAIL: hybrid streaming quality args did not reach publish dry-run"
  cat "$hybrid_dist/fake-publish-hybrid-streaming-env.txt"
  cat "$hybrid_dist/fake-publish-hybrid-streaming-json.txt"
  exit 1
fi

fail_dist="$TEST_TMPDIR/fail-dist"
fail_output="$TEST_TMPDIR/fail-output.txt"
fail_summary="$fail_dist/PressTalk-0.0-candidate-candidate-preflight.json"
set +e
PRESSTALK_READINESS_MATRIX_SCRIPT="$fake_matrix" \
PRESSTALK_PUBLISH_HOMEBREW_SCRIPT="$fake_publish" \
  "$WRAPPER" --version 0.0-candidate --dist-dir "$fail_dist" --local \
    --require mbp1 >"$fail_output" 2>&1
fail_status=$?
set -e
if [[ "$fail_status" -eq 0 ]]; then
  echo "FAIL: candidate preflight unexpectedly passed missing proof target"
  cat "$fail_output"
  exit 1
fi
grep -Fq "FAIL mbp1: missing from matrix" "$fail_output"
grep -Fq "CandidatePreflightJSON: $fail_summary" "$fail_output"
grep -Fq "Result: fail" "$fail_output"
test -f "$fail_summary"
if [[ "$(plutil -extract passed raw -o - "$fail_summary")" != "false" ||
      "$(plutil -extract failureStep raw -o - "$fail_summary")" != "proof_gate" ||
      "$(plutil -extract failureStatus raw -o - "$fail_summary")" != "1" ]]; then
  echo "FAIL: failed proof gate did not write wrapper failure summary"
  plutil -p "$fail_summary"
  exit 1
fi
if plutil -extract artifactAuditJSON raw -o - "$fail_summary" >/dev/null 2>&1 ||
   plutil -extract releaseReadinessJSON raw -o - "$fail_summary" >/dev/null 2>&1; then
  echo "FAIL: failed proof gate should not report later-stage evidence paths"
  plutil -p "$fail_summary"
  exit 1
fi
if [[ -f "$fail_dist/fake-publish-ran.txt" ]]; then
  echo "FAIL: publish dry-run ran after failed proof gate"
  cat "$fail_output"
  exit 1
fi

echo "PASS release_candidate_preflight"
