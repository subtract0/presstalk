#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER="$SCRIPT_DIR/presstalk_verify_repair_result.sh"

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-verify-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

write_status_json() {
  local path="$1"
  local ad_hoc_signed="$2"
  local input_method_fallback="$3"
  local accessibility_status="$4"
  local active_ready="$5"
  local active_status="$6"
  local code_signature_authority="${7:-unknown}"

  cat >"$path" <<EOF
{
  "permissions": {
    "accessibilityStatus": "$accessibility_status",
    "inputMethodFallbackStatus": "$input_method_fallback",
    "inputMonitoringEffective": true,
    "microphoneAuthorizationStatus": "authorized"
  },
  "runtime": {
    "activeFieldInsertionReady": $active_ready,
    "activeFieldInsertionStatus": "$active_status",
    "inputListener": "hid:listen_only"
  },
  "status": {
    "adHocSigned": $ad_hoc_signed,
    "codeSignatureAuthority": "$code_signature_authority",
    "speechModel": "Ready"
  }
}
EOF
}

write_probe_json() {
  local path="$1"
  local success="$2"
  local target_success="$3"
  local trace_method="$4"
  local paste_command_posted="$5"
  local copy_fallback="$6"
  local enable_no_effect="$7"

  cat >"$path" <<EOF
{
  "generatedAt": "2026-06-07T00:00:00Z",
  "success": $success,
  "reason": "payload_inserted",
  "targetCaptureSuccess": $target_success,
  "targetCaptureFailureHint": null,
  "traceProductionMethod": $trace_method,
  "tracePasteCommandPosted": $paste_command_posted,
  "traceCopyFallback": $copy_fallback,
  "traceInputMethodEnableNoEffect": $enable_no_effect
}
EOF
}

run_case() {
  local name="$1"
  local expected_status="$2"
  local expected_text="$3"
  local case_dir="$TEST_TMPDIR/$name"
  local output_file="$case_dir/output.txt"
  mkdir -p "$case_dir/Diagnostics"

  shift 3
  "$@" "$case_dir/runtime-status.json" "$case_dir/Diagnostics/production-insertion-probe-2026-06-07T00-00-00Z.json"

  set +e
  PRESSTALK_STATUS_JSON="$case_dir/runtime-status.json" \
    PRESSTALK_DIAGNOSTICS_DIR="$case_dir/Diagnostics" \
    "$VERIFIER" >"$output_file" 2>&1
  local actual_status="$?"
  set -e

  if [[ "$actual_status" != "$expected_status" ]]; then
    echo "FAIL $name: expected exit $expected_status, got $actual_status"
    cat "$output_file"
    exit 1
  fi
  if ! grep -Fq "$expected_text" "$output_file"; then
    echo "FAIL $name: expected output containing: $expected_text"
    cat "$output_file"
    exit 1
  fi
  echo "PASS $name"
}

input_method_success_fixture() {
  write_status_json "$1" false ready ax_false_input_method_fallback_ready true ready_input_method
  write_probe_json "$2" true true '"input_method_notification"' false false false
}

accessibility_success_fixture() {
  write_status_json "$1" true recognized_disabled ax_trusted true ready_accessibility
  write_probe_json "$2" true true '"ax_selected_text"' false false false
}

paste_command_success_fixture() {
  write_status_json "$1" false not_installed ax_trusted true ready_accessibility
  write_probe_json "$2" true true null true false false
}

signing_repair_blocked_fixture() {
  write_status_json "$1" true recognized_disabled ax_false_input_method_recognized_disabled false needs_signing_repair
  write_probe_json "$2" true true '"input_method_notification"' false false false
}

post_repair_disabled_fixture() {
  write_status_json "$1" false recognized_disabled ax_false_input_method_recognized_disabled false blocked_recognized_disabled "PressTalk Local Development Code Signing"
  write_probe_json "$2" true true '"input_method_notification"' false false false
}

client_unavailable_fixture() {
  write_status_json "$1" false client_unavailable ax_false_input_method_client_unavailable false blocked_client_unavailable "PressTalk Local Development Code Signing"
  write_probe_json "$2" false false null false true false
}

run_case input_method_success 0 "Result: proven" input_method_success_fixture
run_case accessibility_success 0 "Result: proven" accessibility_success_fixture
run_case paste_command_success 0 "Result: proven" paste_command_success_fixture
run_case signing_repair_blocked 1 "Reason: active-field insertion needs signing repair" signing_repair_blocked_fixture
run_case post_repair_disabled 1 "Reason: active-field insertion is blocked because the PressTalk input method is recognized but disabled" post_repair_disabled_fixture
run_case client_unavailable 1 "Reason: active-field insertion is blocked because the PressTalk input method could not attach to the focused text field" client_unavailable_fixture
