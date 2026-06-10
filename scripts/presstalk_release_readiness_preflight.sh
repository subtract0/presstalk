#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_AUDIT_JSON=""
PROOF_GATE_JSON=""
STREAMING_BENCH_QUALITY_JSON="${PRESSTALK_STREAMING_BENCH_QUALITY_JSON:-}"
JSON_OUTPUT_PATH=""
EXPECTED_ASR_MODE="${PRESSTALK_EXPECTED_ASR_MODE:-parakeet_v3_ane_final_pass}"
REQUIRE_PRODUCTION=0
REQUIRE_STREAMING=0
REQUIRE_STREAMING_BENCH_QUALITY=0
REQUIRED_PROOF_TARGETS=()
REQUIRED_PROOF_TARGET_COUNT=0

usage() {
  cat <<'EOF'
Usage: presstalk_release_readiness_preflight.sh --artifact-audit PATH --proof-gate PATH [options]

Combines the packaged artifact audit and cross-machine release proof gate into
one machine-readable readiness verdict. By default, this can pass for a valid
test/prerelease artifact. With --require-production it also requires Developer
ID signing, hardened runtime, and stapled notarization evidence.

Options:
  --artifact-audit PATH   JSON from presstalk_release_artifact_audit.sh.
  --proof-gate PATH       JSON from presstalk_release_proof_gate.sh.
  --expected-asr-mode M   Required ASR mode for every proof target.
                          Use "any" to allow any non-missing ASR mode.
                          Default: parakeet_v3_ane_final_pass.
  --require-proof-target T
                          Require proof coverage for target alias, host, or
                          machineHost. May be repeated.
  --require-production    Fail unless the artifact is production distribution
                          ready and notarized.
  --require-streaming     Fail unless every proof target reports realtime
                          partial transcription enabled.
  --streaming-bench-quality PATH
                          JSON from presstalk_streaming_bench_quality_gate.sh.
  --require-streaming-bench-quality
                          Fail unless streaming bench quality JSON is present
                          and passed.
  --json-output PATH      Write machine-readable readiness JSON.
  -h, --help              Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-audit)
      ARTIFACT_AUDIT_JSON="${2:-}"
      if [[ -z "$ARTIFACT_AUDIT_JSON" ]]; then
        echo "Missing value for --artifact-audit" >&2
        exit 2
      fi
      shift 2
      ;;
    --proof-gate)
      PROOF_GATE_JSON="${2:-}"
      if [[ -z "$PROOF_GATE_JSON" ]]; then
        echo "Missing value for --proof-gate" >&2
        exit 2
      fi
      shift 2
      ;;
    --expected-asr-mode)
      EXPECTED_ASR_MODE="${2:-}"
      if [[ -z "$EXPECTED_ASR_MODE" ]]; then
        echo "Missing value for --expected-asr-mode" >&2
        exit 2
      fi
      shift 2
      ;;
    --require-proof-target)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --require-proof-target" >&2
        exit 2
      fi
      REQUIRED_PROOF_TARGETS+=("$2")
      REQUIRED_PROOF_TARGET_COUNT=$((REQUIRED_PROOF_TARGET_COUNT + 1))
      shift 2
      ;;
    --require-production)
      REQUIRE_PRODUCTION=1
      shift
      ;;
    --require-streaming)
      REQUIRE_STREAMING=1
      shift
      ;;
    --streaming-bench-quality)
      STREAMING_BENCH_QUALITY_JSON="${2:-}"
      if [[ -z "$STREAMING_BENCH_QUALITY_JSON" ]]; then
        echo "Missing value for --streaming-bench-quality" >&2
        exit 2
      fi
      shift 2
      ;;
    --require-streaming-bench-quality)
      REQUIRE_STREAMING_BENCH_QUALITY=1
      shift
      ;;
    --json-output)
      JSON_OUTPUT_PATH="${2:-}"
      if [[ -z "$JSON_OUTPUT_PATH" ]]; then
        echo "Missing value for --json-output" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$ARTIFACT_AUDIT_JSON" || -z "$PROOF_GATE_JSON" ]]; then
  usage >&2
  exit 2
fi
if [[ ! -f "$ARTIFACT_AUDIT_JSON" ]]; then
  echo "Missing artifact audit JSON: $ARTIFACT_AUDIT_JSON" >&2
  exit 1
fi
if [[ ! -f "$PROOF_GATE_JSON" ]]; then
  echo "Missing proof gate JSON: $PROOF_GATE_JSON" >&2
  exit 1
fi

if [[ "$REQUIRED_PROOF_TARGET_COUNT" -eq 0 && -n "${PRESSTALK_REQUIRED_PROOF_TARGETS:-}" ]]; then
  IFS=',' read -r -a parsed_required_targets <<<"$PRESSTALK_REQUIRED_PROOF_TARGETS"
  for parsed_required_target in "${parsed_required_targets[@]}"; do
    parsed_required_target="${parsed_required_target#"${parsed_required_target%%[![:space:]]*}"}"
    parsed_required_target="${parsed_required_target%"${parsed_required_target##*[![:space:]]}"}"
    [[ -z "$parsed_required_target" ]] && continue
    REQUIRED_PROOF_TARGETS+=("$parsed_required_target")
    REQUIRED_PROOF_TARGET_COUNT=$((REQUIRED_PROOF_TARGET_COUNT + 1))
  done
fi

case "${PRESSTALK_REQUIRE_STREAMING_RELEASE:-}" in
  1|true|TRUE|yes|YES) REQUIRE_STREAMING=1 ;;
esac
case "${PRESSTALK_REQUIRE_STREAMING_BENCH_QUALITY:-}" in
  1|true|TRUE|yes|YES) REQUIRE_STREAMING_BENCH_QUALITY=1 ;;
esac

json_value() {
  local file="$1"
  local key_path="$2"
  plutil -extract "$key_path" raw -o - "$file" 2>/dev/null || true
}

bool_ready() {
  case "${1:-}" in
    true|1) return 0 ;;
    *) return 1 ;;
  esac
}

plist_insert_string() {
  local plist="$1"
  local key="$2"
  local value="${3:-}"
  plutil -insert "$key" -string "${value:-unknown}" "$plist" >/dev/null
}

plist_insert_bool() {
  local plist="$1"
  local key="$2"
  local value="${3:-false}"
  case "$value" in
    true|1) plutil -insert "$key" -bool true "$plist" >/dev/null ;;
    *) plutil -insert "$key" -bool false "$plist" >/dev/null ;;
  esac
}

append_failure() {
  local failure="$1"
  failures+=("$failure")
}

safe_failure_suffix() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_'
}

RUN_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-release-readiness.XXXXXX")"
RESULT_PLIST="$RUN_TMPDIR/result.plist"
trap 'rm -rf "$RUN_TMPDIR"' EXIT
plutil -create xml1 "$RESULT_PLIST" >/dev/null

artifact_passed="$(json_value "$ARTIFACT_AUDIT_JSON" passed)"
bundle_identifier_matches="$(json_value "$ARTIFACT_AUDIT_JSON" bundleIdentifierMatches)"
version_matches="$(json_value "$ARTIFACT_AUDIT_JSON" versionMatches)"
code_sign_verify_passed="$(json_value "$ARTIFACT_AUDIT_JSON" codeSignVerifyPassed)"
distribution_ready="$(json_value "$ARTIFACT_AUDIT_JSON" distributionReady)"
notarized="$(json_value "$ARTIFACT_AUDIT_JSON" notarized)"
bundle_version="$(json_value "$ARTIFACT_AUDIT_JSON" bundleVersion)"
zip_sha256="$(json_value "$ARTIFACT_AUDIT_JSON" zipSHA256)"

proof_proven="$(json_value "$PROOF_GATE_JSON" proven)"
proof_failures="$(json_value "$PROOF_GATE_JSON" failureCount)"
target_count="$(json_value "$PROOF_GATE_JSON" targets)"
streaming_bench_quality_ready=true
streaming_bench_quality_passed=""
if [[ -n "$STREAMING_BENCH_QUALITY_JSON" ]]; then
  if [[ -f "$STREAMING_BENCH_QUALITY_JSON" ]]; then
    streaming_bench_quality_passed="$(json_value "$STREAMING_BENCH_QUALITY_JSON" passed)"
  else
    streaming_bench_quality_ready=false
  fi
elif [[ "$REQUIRE_STREAMING_BENCH_QUALITY" -eq 1 ]]; then
  streaming_bench_quality_ready=false
fi

failures=()
if ! bool_ready "$artifact_passed"; then
  append_failure "artifact_audit_not_passed"
fi
if ! bool_ready "$bundle_identifier_matches"; then
  append_failure "artifact_bundle_id_mismatch"
fi
if ! bool_ready "$version_matches"; then
  append_failure "artifact_version_mismatch"
fi
if ! bool_ready "$code_sign_verify_passed"; then
  append_failure "artifact_codesign_not_verified"
fi
if ! bool_ready "$proof_proven"; then
  append_failure "release_proof_not_proven"
fi
if [[ -z "$target_count" || ! "$target_count" =~ ^[0-9]+$ || "$target_count" -eq 0 ]]; then
  append_failure "proof_targets_missing"
  target_count=0
fi
if [[ "$REQUIRE_STREAMING_BENCH_QUALITY" -eq 1 ]]; then
  if [[ -z "$STREAMING_BENCH_QUALITY_JSON" ]]; then
    append_failure "streaming_bench_quality_json_missing"
  elif [[ ! -f "$STREAMING_BENCH_QUALITY_JSON" ]]; then
    append_failure "streaming_bench_quality_json_not_found"
  elif ! bool_ready "$streaming_bench_quality_passed"; then
    append_failure "streaming_bench_quality_not_passed"
    streaming_bench_quality_ready=false
  fi
elif [[ -n "$STREAMING_BENCH_QUALITY_JSON" ]]; then
  if [[ ! -f "$STREAMING_BENCH_QUALITY_JSON" ]]; then
    append_failure "streaming_bench_quality_json_not_found"
    streaming_bench_quality_ready=false
  elif ! bool_ready "$streaming_bench_quality_passed"; then
    append_failure "streaming_bench_quality_not_passed"
    streaming_bench_quality_ready=false
  fi
fi

asr_mode_ready=true
streaming_ready=true
for ((i = 0; i < target_count; i++)); do
  target_passed="$(json_value "$PROOF_GATE_JSON" "targets.$i.passed")"
  target_asr_mode="$(json_value "$PROOF_GATE_JSON" "targets.$i.asrMode")"
  target_realtime_partials="$(json_value "$PROOF_GATE_JSON" "targets.$i.realtimePartialTranscriptionEnabled")"
  if ! bool_ready "$target_passed"; then
    append_failure "proof_target_${i}_not_passed"
  fi
  if [[ -z "$target_asr_mode" || "$target_asr_mode" == "unknown" ]]; then
    append_failure "proof_target_${i}_asr_mode_missing"
    asr_mode_ready=false
  elif [[ "$EXPECTED_ASR_MODE" != "any" && "$target_asr_mode" != "$EXPECTED_ASR_MODE" ]]; then
    append_failure "proof_target_${i}_asr_mode_mismatch"
    asr_mode_ready=false
  fi
  if [[ -z "$target_realtime_partials" || "$target_realtime_partials" == "unknown" ]]; then
    append_failure "proof_target_${i}_realtime_partials_state_missing"
    streaming_ready=false
  elif [[ "$REQUIRE_STREAMING" -eq 1 ]]; then
    if ! bool_ready "$target_realtime_partials"; then
      append_failure "proof_target_${i}_realtime_partials_disabled"
      streaming_ready=false
    fi
  elif bool_ready "$target_realtime_partials"; then
    append_failure "proof_target_${i}_realtime_partials_enabled"
    asr_mode_ready=false
  fi
done

required_targets_ready=true
if [[ "$REQUIRED_PROOF_TARGET_COUNT" -gt 0 ]]; then
  for required_target in "${REQUIRED_PROOF_TARGETS[@]}"; do
    required_target_found=false
    for ((i = 0; i < target_count; i++)); do
      proof_required="$(json_value "$PROOF_GATE_JSON" "targets.$i.required")"
      proof_target="$(json_value "$PROOF_GATE_JSON" "targets.$i.target")"
      proof_machine_host="$(json_value "$PROOF_GATE_JSON" "targets.$i.machineHost")"
      if [[ "$proof_required" == "$required_target" ||
            "$proof_target" == "$required_target" ||
            "$proof_machine_host" == "$required_target" ]]; then
        required_target_found=true
        break
      fi
    done
    if [[ "$required_target_found" != "true" ]]; then
      append_failure "required_proof_target_$(safe_failure_suffix "$required_target")_missing"
      required_targets_ready=false
    fi
  done
fi

production_ready=false
if bool_ready "$artifact_passed" &&
   bool_ready "$distribution_ready" &&
   bool_ready "$notarized" &&
   bool_ready "$proof_proven" &&
   [[ "$asr_mode_ready" == "true" ]] &&
   [[ "$streaming_ready" == "true" ]] &&
   [[ "$streaming_bench_quality_ready" == "true" ]] &&
   [[ "$required_targets_ready" == "true" ]]; then
  production_ready=true
fi

test_artifact_ready=false
if bool_ready "$artifact_passed" &&
   bool_ready "$proof_proven" &&
   [[ "$asr_mode_ready" == "true" ]] &&
   [[ "$streaming_ready" == "true" ]] &&
   [[ "$streaming_bench_quality_ready" == "true" ]] &&
   [[ "$required_targets_ready" == "true" ]]; then
  test_artifact_ready=true
fi

if [[ "$REQUIRE_PRODUCTION" -eq 1 && "$production_ready" != "true" ]]; then
  append_failure "production_distribution_required"
fi

passed=false
if [[ "$REQUIRE_PRODUCTION" -eq 1 ]]; then
  [[ "$production_ready" == "true" ]] && passed=true
else
  [[ "$test_artifact_ready" == "true" ]] && passed=true
fi

plist_insert_string "$RESULT_PLIST" schemaVersion "1"
plist_insert_string "$RESULT_PLIST" artifactAudit "$ARTIFACT_AUDIT_JSON"
plist_insert_string "$RESULT_PLIST" proofGate "$PROOF_GATE_JSON"
if [[ -n "$STREAMING_BENCH_QUALITY_JSON" ]]; then
  plist_insert_string "$RESULT_PLIST" streamingBenchQuality "$STREAMING_BENCH_QUALITY_JSON"
fi
plist_insert_string "$RESULT_PLIST" expectedASRMode "$EXPECTED_ASR_MODE"
plist_insert_string "$RESULT_PLIST" bundleVersion "$bundle_version"
plist_insert_string "$RESULT_PLIST" zipSHA256 "$zip_sha256"
plist_insert_bool "$RESULT_PLIST" artifactPassed "$artifact_passed"
plist_insert_bool "$RESULT_PLIST" bundleIdentifierMatches "$bundle_identifier_matches"
plist_insert_bool "$RESULT_PLIST" versionMatches "$version_matches"
plist_insert_bool "$RESULT_PLIST" codeSignVerifyPassed "$code_sign_verify_passed"
plist_insert_bool "$RESULT_PLIST" distributionReady "$distribution_ready"
plist_insert_bool "$RESULT_PLIST" notarized "$notarized"
plist_insert_bool "$RESULT_PLIST" proofProven "$proof_proven"
plutil -insert proofFailureCount -integer "${proof_failures:-0}" "$RESULT_PLIST" >/dev/null
plutil -insert proofTargetCount -integer "$target_count" "$RESULT_PLIST" >/dev/null
plutil -insert requiredProofTargets -array "$RESULT_PLIST" >/dev/null
if [[ "$REQUIRED_PROOF_TARGET_COUNT" -gt 0 ]]; then
  for required_target in "${REQUIRED_PROOF_TARGETS[@]}"; do
    plutil -insert requiredProofTargets -string "$required_target" -append "$RESULT_PLIST" >/dev/null
  done
fi
plutil -insert requiredProofTargetCount -integer "$REQUIRED_PROOF_TARGET_COUNT" "$RESULT_PLIST" >/dev/null
plist_insert_bool "$RESULT_PLIST" requiredProofTargetsReady "$required_targets_ready"
plist_insert_bool "$RESULT_PLIST" asrModeReady "$asr_mode_ready"
plist_insert_bool "$RESULT_PLIST" streamingReady "$streaming_ready"
plist_insert_bool "$RESULT_PLIST" streamingBenchQualityReady "$streaming_bench_quality_ready"
plist_insert_bool "$RESULT_PLIST" testArtifactReady "$test_artifact_ready"
plist_insert_bool "$RESULT_PLIST" productionReady "$production_ready"
plist_insert_bool "$RESULT_PLIST" requireProduction "$([[ "$REQUIRE_PRODUCTION" -eq 1 ]] && echo true || echo false)"
plist_insert_bool "$RESULT_PLIST" requireStreaming "$([[ "$REQUIRE_STREAMING" -eq 1 ]] && echo true || echo false)"
plist_insert_bool "$RESULT_PLIST" requireStreamingBenchQuality "$([[ "$REQUIRE_STREAMING_BENCH_QUALITY" -eq 1 ]] && echo true || echo false)"
plist_insert_bool "$RESULT_PLIST" passed "$passed"
failure_count="${#failures[@]}"
plutil -insert failureCount -integer "$failure_count" "$RESULT_PLIST" >/dev/null
plutil -insert failures -array "$RESULT_PLIST" >/dev/null
if [[ "$failure_count" -gt 0 ]]; then
  for failure in "${failures[@]}"; do
    plutil -insert failures -string "$failure" -append "$RESULT_PLIST" >/dev/null
  done
fi

if [[ -n "$JSON_OUTPUT_PATH" ]]; then
  mkdir -p "$(dirname "$JSON_OUTPUT_PATH")"
  plutil -convert json -r -o "$JSON_OUTPUT_PATH" "$RESULT_PLIST"
fi

echo "PressTalk release readiness preflight"
echo "ArtifactAudit: $ARTIFACT_AUDIT_JSON"
echo "ProofGate: $PROOF_GATE_JSON"
echo "ExpectedASRMode: $EXPECTED_ASR_MODE"
echo "ArtifactPassed: ${artifact_passed:-unknown}"
echo "ProofProven: ${proof_proven:-unknown}"
echo "ASRModeReady: $asr_mode_ready"
echo "StreamingReady: $streaming_ready"
echo "RequireStreaming: $([[ "$REQUIRE_STREAMING" -eq 1 ]] && echo true || echo false)"
echo "StreamingBenchQualityReady: $streaming_bench_quality_ready"
echo "RequireStreamingBenchQuality: $([[ "$REQUIRE_STREAMING_BENCH_QUALITY" -eq 1 ]] && echo true || echo false)"
echo "RequiredProofTargetsReady: $required_targets_ready"
echo "TestArtifactReady: $test_artifact_ready"
echo "ProductionReady: $production_ready"
if [[ -n "$JSON_OUTPUT_PATH" ]]; then
  echo "ReadinessJSON: $JSON_OUTPUT_PATH"
fi

if [[ "$passed" == "true" ]]; then
  echo "Result: pass"
  exit 0
fi

echo "Result: fail"
if [[ "$failure_count" -gt 0 ]]; then
  printf 'Failures: %s\n' "${failures[*]}"
else
  printf 'Failures: unknown\n'
fi
exit 1
