#!/usr/bin/env bash
set -euo pipefail

CANDIDATE_JSON=""
PROOF_GATE_JSON=""
HOST_DISCOVERY_JSON=""
JSON_OUTPUT=""

usage() {
  cat <<'EOF'
Usage: presstalk_release_target_handoff.sh --candidate-preflight PATH [options]

Reads existing PressTalk release-candidate receipts and prints the manual target
actions needed to complete proof. This script is read-only: it does not SSH,
install PressTalk, open System Settings, or touch excluded machines.

Options:
  --candidate-preflight PATH  Candidate wrapper JSON.
  --proof-gate PATH           Override proof-gate JSON path.
  --host-discovery PATH       Override host-discovery JSON path.
  --json-output PATH          Write a compact machine-readable handoff JSON.
  -h, --help                  Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --candidate-preflight)
      CANDIDATE_JSON="${2:-}"
      if [[ -z "$CANDIDATE_JSON" ]]; then
        echo "Missing value for --candidate-preflight" >&2
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
    --host-discovery)
      HOST_DISCOVERY_JSON="${2:-}"
      if [[ -z "$HOST_DISCOVERY_JSON" ]]; then
        echo "Missing value for --host-discovery" >&2
        exit 2
      fi
      shift 2
      ;;
    --json-output)
      JSON_OUTPUT="${2:-}"
      if [[ -z "$JSON_OUTPUT" ]]; then
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

if [[ -z "$CANDIDATE_JSON" && -z "$PROOF_GATE_JSON" ]]; then
  echo "Provide --candidate-preflight or --proof-gate" >&2
  exit 2
fi
if [[ -n "$CANDIDATE_JSON" && ! -f "$CANDIDATE_JSON" ]]; then
  echo "Missing candidate preflight JSON: $CANDIDATE_JSON" >&2
  exit 2
fi

extract_raw() {
  local file="$1"
  local key="$2"
  local value
  if [[ -f "$file" ]] && value="$(plutil -extract "$key" raw -o - "$file" 2>/dev/null)"; then
    printf '%s' "$value"
  fi
}

append_required_target() {
  local target="$1"
  local existing
  [[ -z "$target" ]] && return 0
  if [[ "${#REQUIRED_TARGETS[@]}" -gt 0 ]]; then
    for existing in "${REQUIRED_TARGETS[@]}"; do
      [[ "$existing" == "$target" ]] && return 0
    done
  fi
  REQUIRED_TARGETS+=("$target")
}

append_host_target() {
  local target="$1"
  local existing
  [[ -z "$target" || "$target" == "local" ]] && return 0
  if [[ "${#HOST_TARGETS[@]}" -gt 0 ]]; then
    for existing in "${HOST_TARGETS[@]}"; do
      [[ "$existing" == "$target" ]] && return 0
    done
  fi
  HOST_TARGETS+=("$target")
}

append_excluded_target() {
  local target="$1"
  local existing
  [[ -z "$target" ]] && return 0
  if [[ "${#EXCLUDED_TARGETS[@]}" -gt 0 ]]; then
    for existing in "${EXCLUDED_TARGETS[@]}"; do
      [[ "$existing" == "$target" ]] && return 0
    done
  fi
  EXCLUDED_TARGETS+=("$target")
}

append_blocked_target() {
  local label="$1"
  [[ -z "$label" ]] && return 0
  BLOCKED_TARGETS+=("$label")
}

find_host_probe_error() {
  local target="$1"
  local idx=0
  local item_target error
  [[ -z "$HOST_DISCOVERY_JSON" || ! -f "$HOST_DISCOVERY_JSON" ]] && return 0
  while item_target="$(extract_raw "$HOST_DISCOVERY_JSON" "targets.$idx.target")"; [[ -n "$item_target" ]]; do
    if [[ "$item_target" == "$target" ]]; then
      error="$(extract_raw "$HOST_DISCOVERY_JSON" "targets.$idx.sshProbe.error")"
      if [[ -n "$error" ]]; then
        printf '%s' "$error"
      fi
      return 0
    fi
    idx=$((idx + 1))
  done
}

join_command() {
  local part
  local rendered=""
  for part in "$@"; do
    if [[ -n "$rendered" ]]; then
      rendered+=" "
    fi
    rendered+="$(printf '%q' "$part")"
  done
  printf '%s' "$rendered"
}

if [[ -n "$CANDIDATE_JSON" ]]; then
  PROOF_GATE_JSON="${PROOF_GATE_JSON:-$(extract_raw "$CANDIDATE_JSON" proofGateJSON)}"
  HOST_DISCOVERY_JSON="${HOST_DISCOVERY_JSON:-$(extract_raw "$CANDIDATE_JSON" hostDiscoveryJSON)}"
fi
if [[ -z "$PROOF_GATE_JSON" || ! -f "$PROOF_GATE_JSON" ]]; then
  echo "Missing proof gate JSON: ${PROOF_GATE_JSON:-unset}" >&2
  exit 2
fi
if [[ -n "$HOST_DISCOVERY_JSON" && ! -f "$HOST_DISCOVERY_JSON" ]]; then
  HOST_DISCOVERY_JSON=""
fi

VERSION="$(extract_raw "$CANDIDATE_JSON" version)"
CANDIDATE_PASSED="$(extract_raw "$CANDIDATE_JSON" passed)"
FAILURE_STEP="$(extract_raw "$CANDIDATE_JSON" failureStep)"
FAILURE_STATUS="$(extract_raw "$CANDIDATE_JSON" failureStatus)"
PROOF_PROVEN="$(extract_raw "$PROOF_GATE_JSON" proven)"

REQUIRED_TARGETS=()
HOST_TARGETS=()
EXCLUDED_TARGETS=()
BLOCKED_TARGETS=()
RERUN_ARGS=()
LOCAL_SELECTED=0
READY_COUNT=0
BLOCKED_COUNT=0

required_idx=0
while required_value="$(extract_raw "$CANDIDATE_JSON" "requiredTargets.$required_idx")"; [[ -n "$required_value" ]]; do
  append_required_target "$required_value"
  required_idx=$((required_idx + 1))
done

excluded_idx=0
while excluded_value="$(extract_raw "$PROOF_GATE_JSON" "excludedTargets.$excluded_idx")"; [[ -n "$excluded_value" ]]; do
  append_excluded_target "$excluded_value"
  excluded_idx=$((excluded_idx + 1))
done

echo "PressTalk release target handoff"
if [[ -n "$VERSION" ]]; then
  echo "Version: $VERSION"
fi
if [[ -n "$CANDIDATE_JSON" ]]; then
  echo "CandidatePreflightJSON: $CANDIDATE_JSON"
fi
echo "ProofGateJSON: $PROOF_GATE_JSON"
if [[ -n "$HOST_DISCOVERY_JSON" ]]; then
  echo "HostDiscoveryJSON: $HOST_DISCOVERY_JSON"
fi
if [[ -n "$CANDIDATE_PASSED" ]]; then
  echo "Candidate passed: $CANDIDATE_PASSED"
fi
if [[ -n "$FAILURE_STEP" ]]; then
  echo "Failure: $FAILURE_STEP status=${FAILURE_STATUS:-unknown}"
fi
if [[ -n "$PROOF_PROVEN" ]]; then
  echo "Proof proven: $PROOF_PROVEN"
fi
echo

echo "Targets"
target_idx=0
while target_value="$(extract_raw "$PROOF_GATE_JSON" "targets.$target_idx.target")"; [[ -n "$target_value" ]]; do
  required_value="$(extract_raw "$PROOF_GATE_JSON" "targets.$target_idx.required")"
  machine_value="$(extract_raw "$PROOF_GATE_JSON" "targets.$target_idx.machineHost")"
  status_value="$(extract_raw "$PROOF_GATE_JSON" "targets.$target_idx.status")"
  passed_value="$(extract_raw "$PROOF_GATE_JSON" "targets.$target_idx.passed")"
  reachable_value="$(extract_raw "$PROOF_GATE_JSON" "targets.$target_idx.reachable")"
  streaming_asr_backend="$(extract_raw "$PROOF_GATE_JSON" "targets.$target_idx.streamingASRBackend")"
  asr_mode="$(extract_raw "$PROOF_GATE_JSON" "targets.$target_idx.asrMode")"
  next_action="$(extract_raw "$PROOF_GATE_JSON" "targets.$target_idx.nextAction")"
  ssh_error="$(find_host_probe_error "$target_value")"

  append_required_target "$required_value"
  if [[ "$target_value" == "local" ]]; then
    LOCAL_SELECTED=1
  else
    append_host_target "$target_value"
  fi

  if [[ "$passed_value" == "true" ]]; then
    READY_COUNT=$((READY_COUNT + 1))
    echo "- READY ${required_value:-$target_value}: target=$target_value machine=${machine_value:-unknown} streamingASRBackend=${streaming_asr_backend:-unknown} asrMode=${asr_mode:-unknown}"
  else
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
    append_blocked_target "${required_value:-$target_value}: target=$target_value status=${status_value:-unknown} reachable=${reachable_value:-unknown}"
    echo "- BLOCKED ${required_value:-$target_value}: target=$target_value machine=${machine_value:-unknown} status=${status_value:-unknown} reachable=${reachable_value:-unknown}"
    if [[ -n "$ssh_error" ]]; then
      echo "  ssh error: $ssh_error"
    fi
    if [[ -n "$next_action" ]]; then
      echo "  tool next action: $next_action"
    fi
    echo "  manual action: wake and unlock this Mac, ensure it is on the expected network or Tailscale, ensure Remote Login is enabled, then rerun the candidate preflight."
  fi

  target_idx=$((target_idx + 1))
done

if [[ "${#EXCLUDED_TARGETS[@]}" -gt 0 ]]; then
  echo
  echo "Excluded"
  for excluded_value in "${EXCLUDED_TARGETS[@]}"; do
    echo "- $excluded_value"
  done
fi

RERUN_ARGS=(bash scripts/presstalk_release_candidate_preflight.sh)
if [[ -n "$VERSION" ]]; then
  RERUN_ARGS+=("$VERSION")
fi
if [[ "$LOCAL_SELECTED" -eq 1 ]]; then
  RERUN_ARGS+=(--local)
fi
if [[ "${#HOST_TARGETS[@]}" -gt 0 ]]; then
  for host_value in "${HOST_TARGETS[@]}"; do
    RERUN_ARGS+=(--host "$host_value")
  done
fi
if [[ "${#REQUIRED_TARGETS[@]}" -gt 0 ]]; then
  for required_value in "${REQUIRED_TARGETS[@]}"; do
    RERUN_ARGS+=(--require "$required_value")
  done
fi
if [[ "${#EXCLUDED_TARGETS[@]}" -gt 0 ]]; then
  for excluded_value in "${EXCLUDED_TARGETS[@]}"; do
    RERUN_ARGS+=(--exclude-host "$excluded_value")
  done
fi
RERUN_COMMAND="$(join_command "${RERUN_ARGS[@]}")"

echo
echo "Rerun when targets are awake:"
echo "$RERUN_COMMAND"

if [[ -n "$JSON_OUTPUT" ]]; then
  result_plist="$(mktemp "${TMPDIR:-/tmp}/presstalk-release-target-handoff.XXXXXX.plist")"
  plutil -create xml1 "$result_plist" >/dev/null
  plutil -insert schemaVersion -string "1" "$result_plist" >/dev/null
  if [[ -n "$VERSION" ]]; then
    plutil -insert version -string "$VERSION" "$result_plist" >/dev/null
  fi
  if [[ -n "$CANDIDATE_JSON" ]]; then
    plutil -insert candidatePreflightJSON -string "$CANDIDATE_JSON" "$result_plist" >/dev/null
  fi
  plutil -insert proofGateJSON -string "$PROOF_GATE_JSON" "$result_plist" >/dev/null
  if [[ -n "$HOST_DISCOVERY_JSON" ]]; then
    plutil -insert hostDiscoveryJSON -string "$HOST_DISCOVERY_JSON" "$result_plist" >/dev/null
  fi
  if [[ "$CANDIDATE_PASSED" == "true" ]]; then
    plutil -insert candidatePassed -bool true "$result_plist" >/dev/null
  elif [[ "$CANDIDATE_PASSED" == "false" ]]; then
    plutil -insert candidatePassed -bool false "$result_plist" >/dev/null
  fi
  if [[ "$PROOF_PROVEN" == "true" ]]; then
    plutil -insert proofProven -bool true "$result_plist" >/dev/null
  elif [[ "$PROOF_PROVEN" == "false" ]]; then
    plutil -insert proofProven -bool false "$result_plist" >/dev/null
  fi
  plutil -insert readyTargetCount -integer "$READY_COUNT" "$result_plist" >/dev/null
  plutil -insert blockedTargetCount -integer "$BLOCKED_COUNT" "$result_plist" >/dev/null
  if [[ -n "$FAILURE_STEP" ]]; then
    plutil -insert failureStep -string "$FAILURE_STEP" "$result_plist" >/dev/null
  fi
  plutil -insert rerunCommand -string "$RERUN_COMMAND" "$result_plist" >/dev/null
  plutil -insert blockedTargets -array "$result_plist" >/dev/null
  if [[ "${#BLOCKED_TARGETS[@]}" -gt 0 ]]; then
    for blocked_value in "${BLOCKED_TARGETS[@]}"; do
      plutil -insert blockedTargets -string "$blocked_value" -append "$result_plist" >/dev/null
    done
  fi
  plutil -insert excludedTargets -array "$result_plist" >/dev/null
  if [[ "${#EXCLUDED_TARGETS[@]}" -gt 0 ]]; then
    for excluded_value in "${EXCLUDED_TARGETS[@]}"; do
      plutil -insert excludedTargets -string "$excluded_value" -append "$result_plist" >/dev/null
    done
  fi
  mkdir -p "$(dirname "$JSON_OUTPUT")"
  plutil -convert json -r -o "$JSON_OUTPUT" "$result_plist"
  rm -f "$result_plist"
  echo
  echo "TargetHandoffJSON: $JSON_OUTPUT"
fi

if [[ "$BLOCKED_COUNT" -gt 0 ]]; then
  exit 1
fi
