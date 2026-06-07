#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_READINESS_HELPER="$SCRIPT_DIR/presstalk_machine_readiness.sh"
if [[ ! -f "$DEFAULT_READINESS_HELPER" && -f "$SCRIPT_DIR/presstalk-machine-readiness.sh" ]]; then
  DEFAULT_READINESS_HELPER="$SCRIPT_DIR/presstalk-machine-readiness.sh"
fi
READINESS_HELPER="${PRESSTALK_READINESS_HELPER:-$DEFAULT_READINESS_HELPER}"
OUTPUT_FORMAT="text"
JSON_OUTPUT_PATH=""
SSH_CONNECT_TIMEOUT="${PRESSTALK_SSH_CONNECT_TIMEOUT:-5}"
RUN_LOCAL=0
HOSTS=()

usage() {
  cat <<'EOF'
Usage: presstalk-readiness-matrix.sh [--local] [--host HOST] [--hosts a,b,c] [--json] [--json-output PATH]

Collects PressTalk machine-readiness reports locally and/or over SSH. Remote
collection is read-only: the script pipes presstalk-machine-readiness.sh to the
remote host with --json. It uses BatchMode SSH with strict host-key checking and
does not open System Settings, bootstrap PressTalk, or run signing repair.

Options:
  --local             Include this Mac.
  --host HOST         Include one SSH host. May be repeated.
  --hosts LIST        Include comma-separated SSH hosts.
  --timeout SECONDS   SSH ConnectTimeout. Default: 5.
  --json              Write only machine-readable JSON to stdout.
  --json-output PATH  Also write the machine-readable JSON matrix to PATH.
  -h, --help          Show this help.

If no target is provided, --local is implied.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      RUN_LOCAL=1
      ;;
    --host)
      shift
      if [[ $# -eq 0 || -z "$1" ]]; then
        echo "Missing value for --host" >&2
        exit 2
      fi
      HOSTS+=("$1")
      ;;
    --hosts)
      shift
      if [[ $# -eq 0 || -z "$1" ]]; then
        echo "Missing value for --hosts" >&2
        exit 2
      fi
      IFS=',' read -r -a parsed_hosts <<<"$1"
      for parsed_host in "${parsed_hosts[@]}"; do
        parsed_host="${parsed_host#"${parsed_host%%[![:space:]]*}"}"
        parsed_host="${parsed_host%"${parsed_host##*[![:space:]]}"}"
        [[ -z "$parsed_host" ]] && continue
        HOSTS+=("$parsed_host")
      done
      ;;
    --timeout)
      shift
      if [[ $# -eq 0 || ! "$1" =~ ^[0-9]+$ || "$1" -eq 0 ]]; then
        echo "Invalid value for --timeout" >&2
        exit 2
      fi
      SSH_CONNECT_TIMEOUT="$1"
      ;;
    --json)
      OUTPUT_FORMAT="json"
      ;;
    --json-output)
      shift
      if [[ $# -eq 0 || -z "$1" ]]; then
        echo "Missing value for --json-output" >&2
        exit 2
      fi
      JSON_OUTPUT_PATH="$1"
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
  shift
done

if [[ "$RUN_LOCAL" -eq 0 && "${#HOSTS[@]}" -eq 0 ]]; then
  RUN_LOCAL=1
fi

if [[ ! -f "$READINESS_HELPER" ]]; then
  echo "Missing readiness helper: $READINESS_HELPER" >&2
  exit 2
fi

RUN_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-readiness-matrix.XXXXXX")"
trap 'rm -rf "$RUN_TMPDIR"' EXIT

MATRIX_PLIST="$RUN_TMPDIR/matrix.plist"
plutil -create xml1 "$MATRIX_PLIST" >/dev/null

plist_insert_string() {
  local plist="$1"
  local key="$2"
  local value="${3:-}"
  plutil -insert "$key" -string "${value:-unknown}" "$plist" >/dev/null
}

plist_insert_bool_or_string() {
  local plist="$1"
  local key="$2"
  local value="${3:-}"
  case "$value" in
    true|false)
      plutil -insert "$key" -bool "$value" "$plist" >/dev/null
      ;;
    *)
      plutil -insert "$key" -string "${value:-unknown}" "$plist" >/dev/null
      ;;
  esac
}

plist_insert_int() {
  local plist="$1"
  local key="$2"
  local value="${3:-0}"
  if [[ "$value" =~ ^-?[0-9]+$ ]]; then
    plutil -insert "$key" -integer "$value" "$plist" >/dev/null
  else
    plutil -insert "$key" -integer 0 "$plist" >/dev/null
  fi
}

json_file_value() {
  local file="$1"
  local key_path="$2"
  if [[ -f "$file" ]]; then
    plutil -extract "$key_path" raw -o - "$file" 2>/dev/null || true
  fi
}

json_file_extract_json() {
  local file="$1"
  local key_path="$2"
  if [[ -f "$file" ]]; then
    plutil -extract "$key_path" json -o - "$file" 2>/dev/null || true
  fi
}

single_line_error() {
  local file="$1"
  if [[ -f "$file" ]]; then
    tr '\n' ' ' <"$file" | sed 's/[[:space:]][[:space:]]*/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//' | cut -c 1-500
  fi
}

plutil -insert schemaVersion -string "1" "$MATRIX_PLIST" >/dev/null
plist_insert_string "$MATRIX_PLIST" "generatedAt" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
plist_insert_string "$MATRIX_PLIST" "readinessHelper" "$READINESS_HELPER"
plist_insert_int "$MATRIX_PLIST" "sshConnectTimeoutSeconds" "$SSH_CONNECT_TIMEOUT"
plutil -insert targets -array "$MATRIX_PLIST" >/dev/null

TEXT_SUMMARY=()

append_target_result() {
  local target="$1"
  local kind="$2"
  local exit_status="$3"
  local stdout_file="$4"
  local stderr_file="$5"

  local target_plist target_json readiness_json schema_version status error_text reachable
  local microphone physical active next_action machine_host
  target_plist="$RUN_TMPDIR/target-$RANDOM.plist"
  plutil -create xml1 "$target_plist" >/dev/null

  plist_insert_string "$target_plist" "target" "$target"
  plist_insert_string "$target_plist" "kind" "$kind"
  plist_insert_int "$target_plist" "exitStatus" "$exit_status"

  schema_version="$(json_file_value "$stdout_file" schemaVersion)"
  if [[ "$exit_status" -eq 0 && "$schema_version" == "1" ]]; then
    status="ready_reported"
    reachable="true"
    error_text=""
    readiness_json="$(cat "$stdout_file")"
    plutil -insert readiness -json "$readiness_json" "$target_plist" >/dev/null

    machine_host="$(json_file_value "$stdout_file" machine.host)"
    microphone="$(json_file_value "$stdout_file" audio.microphoneHardwareDetected)"
    physical="$(json_file_value "$stdout_file" eligibility.physicalSTTSmokeReady)"
    active="$(json_file_value "$stdout_file" eligibility.activeFieldSmokeReady)"
    next_action="$(json_file_value "$stdout_file" nextAction)"
  else
    status="failed"
    reachable="false"
    error_text="$(single_line_error "$stderr_file")"
    if [[ -z "$error_text" ]]; then
      error_text="$(single_line_error "$stdout_file")"
    fi
    if [[ -z "$error_text" ]]; then
      error_text="readiness helper did not produce schemaVersion=1 JSON"
    fi
    machine_host=""
    microphone=""
    physical=""
    active=""
    next_action="Fix host/readiness collection error, then rerun matrix."
  fi

  plist_insert_string "$target_plist" "status" "$status"
  plist_insert_bool_or_string "$target_plist" "reachable" "$reachable"
  plist_insert_string "$target_plist" "error" "$error_text"

  plutil -insert summary -dictionary "$target_plist" >/dev/null
  plist_insert_string "$target_plist" "summary.machineHost" "$machine_host"
  plist_insert_bool_or_string "$target_plist" "summary.microphoneHardwareDetected" "$microphone"
  plist_insert_bool_or_string "$target_plist" "summary.physicalSTTSmokeReady" "$physical"
  plist_insert_bool_or_string "$target_plist" "summary.activeFieldSmokeReady" "$active"
  plist_insert_string "$target_plist" "summary.nextAction" "$next_action"

  target_json="$(plutil -convert json -r -o - "$target_plist")"
  plutil -insert targets -json "$target_json" -append "$MATRIX_PLIST" >/dev/null
  rm -f "$target_plist"

  if [[ "$status" == "ready_reported" ]]; then
    TEXT_SUMMARY+=("$target [$kind]: microphone=${microphone:-unknown} physical=${physical:-unknown} active=${active:-unknown} next=${next_action:-unknown}")
  else
    TEXT_SUMMARY+=("$target [$kind]: failed exit=$exit_status error=${error_text:-unknown}")
  fi
}

collect_local() {
  local stdout_file="$RUN_TMPDIR/local.stdout"
  local stderr_file="$RUN_TMPDIR/local.stderr"
  set +e
  /bin/bash "$READINESS_HELPER" --json >"$stdout_file" 2>"$stderr_file"
  local exit_status="$?"
  set -e
  append_target_result "local" "local" "$exit_status" "$stdout_file" "$stderr_file"
}

collect_remote() {
  local host="$1"
  local stdout_file="$RUN_TMPDIR/ssh-$host.stdout"
  local stderr_file="$RUN_TMPDIR/ssh-$host.stderr"
  set +e
  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
    -o StrictHostKeyChecking=yes \
    "$host" \
    'bash -s -- --json' <"$READINESS_HELPER" >"$stdout_file" 2>"$stderr_file"
  local exit_status="$?"
  set -e
  append_target_result "$host" "ssh" "$exit_status" "$stdout_file" "$stderr_file"
}

if [[ "$RUN_LOCAL" -eq 1 ]]; then
  collect_local
fi

if [[ "${#HOSTS[@]}" -gt 0 ]]; then
  for host in "${HOSTS[@]}"; do
    collect_remote "$host"
  done
fi

write_matrix_json() {
  local output_path="$1"
  plutil -convert json -r -o "$output_path" "$MATRIX_PLIST"
}

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  write_matrix_json "-"
else
  echo "PressTalk readiness matrix"
  echo
  for line in "${TEXT_SUMMARY[@]}"; do
    echo "- $line"
  done
fi

if [[ -n "$JSON_OUTPUT_PATH" ]]; then
  write_matrix_json "$JSON_OUTPUT_PATH"
  if [[ "$OUTPUT_FORMAT" != "json" ]]; then
    echo
    echo "ReadinessMatrixJSON: $JSON_OUTPUT_PATH"
  fi
fi
