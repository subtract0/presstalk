#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATRIX_HELPER="$SCRIPT_DIR/presstalk_readiness_matrix.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-matrix-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

local_json="$TEST_TMPDIR/local-matrix.json"
blocked_json="$TEST_TMPDIR/blocked-matrix.json"
excluded_json="$TEST_TMPDIR/excluded-matrix.json"
bundle_json="$TEST_TMPDIR/bundle-matrix.json"

"$MATRIX_HELPER" --local --json >"$local_json"

extract_required() {
  local file="$1"
  local key_path="$2"
  local value
  value="$(plutil -extract "$key_path" raw -o - "$file" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    echo "FAIL: missing JSON key $key_path in $file"
    exit 1
  fi
  printf '%s\n' "$value"
}

schema_version="$(extract_required "$local_json" schemaVersion)"
if [[ "$schema_version" != "1" ]]; then
  echo "FAIL: unexpected matrix schemaVersion $schema_version"
  exit 1
fi
local_count="$(extract_required "$local_json" targets)"
if [[ "$local_count" != "1" ]]; then
  echo "FAIL: expected one local target, got $local_count"
  exit 1
fi
local_status="$(extract_required "$local_json" targets.0.status)"
if [[ "$local_status" != "ready_reported" ]]; then
  echo "FAIL: expected local ready_reported, got $local_status"
  exit 1
fi
extract_required "$local_json" targets.0.readiness.schemaVersion >/dev/null
extract_required "$local_json" targets.0.summary.asrBackend >/dev/null
extract_required "$local_json" targets.0.summary.streamingASRBackend >/dev/null
extract_required "$local_json" targets.0.summary.asrMode >/dev/null
extract_required "$local_json" targets.0.summary.realtimePartialTranscriptionEnabled >/dev/null
extract_required "$local_json" targets.0.summary.activeFieldSmokeReady >/dev/null
extract_required "$local_json" targets.0.summary.realFieldSmokeSuccess >/dev/null

"$MATRIX_HELPER" --host presstalk-invalid-host.invalid --timeout 1 --json >"$blocked_json"
blocked_status="$(extract_required "$blocked_json" targets.0.status)"
blocked_reachable="$(extract_required "$blocked_json" targets.0.reachable)"
if [[ "$blocked_status" != "failed" || "$blocked_reachable" != "false" ]]; then
  echo "FAIL: expected blocked host to be recorded as failed/reachable=false"
  plutil -convert json -r -o - "$blocked_json"
  exit 1
fi

"$MATRIX_HELPER" \
  --host presstalk-invalid-host.invalid \
  --exclude-host presstalk-invalid-host.invalid=no-attached-microphone \
  --timeout 1 \
  --json >"$excluded_json"
excluded_status="$(extract_required "$excluded_json" targets.0.status)"
excluded_kind="$(extract_required "$excluded_json" targets.0.kind)"
excluded_reason="$(extract_required "$excluded_json" targets.0.error)"
if [[ "$excluded_status" != "excluded" || "$excluded_kind" != "excluded" || "$excluded_reason" != "no-attached-microphone" ]]; then
  echo "FAIL: expected excluded host to be recorded without SSH probing"
  plutil -convert json -r -o - "$excluded_json"
  exit 1
fi

bundle_dir="$TEST_TMPDIR/bundle-resources"
mkdir -p "$bundle_dir"
cp "$MATRIX_HELPER" "$bundle_dir/presstalk-readiness-matrix.sh"
cp "$SCRIPT_DIR/presstalk_machine_readiness.sh" "$bundle_dir/presstalk-machine-readiness.sh"
chmod +x "$bundle_dir/presstalk-readiness-matrix.sh" "$bundle_dir/presstalk-machine-readiness.sh"
"$bundle_dir/presstalk-readiness-matrix.sh" --local --json >"$bundle_json"
bundle_status="$(extract_required "$bundle_json" targets.0.status)"
if [[ "$bundle_status" != "ready_reported" ]]; then
  echo "FAIL: expected bundled-name helper layout to work"
  plutil -convert json -r -o - "$bundle_json"
  exit 1
fi

echo "PASS readiness_matrix_json"
