#!/usr/bin/env bash
set -euo pipefail

MATRIX_JSON=""
REQUIRED_TARGETS=()
EXCLUDED_TARGETS=()

usage() {
  cat <<EOF
Usage: presstalk-release-proof-gate.sh --matrix PATH --require TARGET [options]

Checks a presstalk-readiness-matrix JSON file and exits 0 only when every
required target is reachable, reports readiness, has physical STT smoke ready,
and has active-field smoke ready.

Options:
  --matrix PATH        Matrix JSON from presstalk-readiness-matrix.sh.
  --require TARGET     Required target alias or machine host. Repeatable.
  --exclude TARGET=WHY Record an intentionally excluded target and reason.
                       This is informational and does not make release proof.
  -h, --help           Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --matrix)
      MATRIX_JSON="${2:-}"
      if [[ -z "$MATRIX_JSON" ]]; then
        echo "Missing value for --matrix" >&2
        exit 2
      fi
      shift 2
      ;;
    --require)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --require" >&2
        exit 2
      fi
      REQUIRED_TARGETS+=("$2")
      shift 2
      ;;
    --exclude)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --exclude" >&2
        exit 2
      fi
      EXCLUDED_TARGETS+=("$2")
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

if [[ -z "$MATRIX_JSON" ]]; then
  echo "Missing --matrix PATH" >&2
  usage >&2
  exit 2
fi
if [[ ! -f "$MATRIX_JSON" ]]; then
  echo "Missing matrix JSON: $MATRIX_JSON" >&2
  exit 1
fi
if [[ "${#REQUIRED_TARGETS[@]}" -eq 0 ]]; then
  echo "At least one --require TARGET is required" >&2
  usage >&2
  exit 2
fi

json_value() {
  local key_path="$1"
  plutil -extract "$key_path" raw -o - "$MATRIX_JSON" 2>/dev/null || true
}

bool_ready() {
  case "$1" in
    true|1) return 0 ;;
    *) return 1 ;;
  esac
}

target_count="$(json_value targets)"
if [[ -z "$target_count" || ! "$target_count" =~ ^[0-9]+$ ]]; then
  echo "Result: not proven"
  echo "Reason: matrix does not contain a targets array"
  exit 1
fi

find_target_index() {
  local wanted="$1"
  local i target machine_host
  for ((i = 0; i < target_count; i++)); do
    target="$(json_value "targets.$i.target")"
    machine_host="$(json_value "targets.$i.summary.machineHost")"
    if [[ "$target" == "$wanted" || "$machine_host" == "$wanted" ]]; then
      printf '%s\n' "$i"
      return 0
    fi
  done
  return 1
}

echo "PressTalk release proof gate"
echo "Matrix: $MATRIX_JSON"
echo

if [[ "${#EXCLUDED_TARGETS[@]}" -gt 0 ]]; then
  echo "Excluded targets"
  for excluded in "${EXCLUDED_TARGETS[@]}"; do
    echo "- $excluded"
  done
  echo
fi

failures=0
for required in "${REQUIRED_TARGETS[@]}"; do
  if ! index="$(find_target_index "$required")"; then
    echo "FAIL $required: missing from matrix"
    failures=$((failures + 1))
    continue
  fi

  target="$(json_value "targets.$index.target")"
  machine_host="$(json_value "targets.$index.summary.machineHost")"
  status="$(json_value "targets.$index.status")"
  reachable="$(json_value "targets.$index.reachable")"
  physical="$(json_value "targets.$index.summary.physicalSTTSmokeReady")"
  active="$(json_value "targets.$index.summary.activeFieldSmokeReady")"
  next_action="$(json_value "targets.$index.summary.nextAction")"

  target_failures=0
  if [[ "$status" != "ready_reported" ]]; then
    echo "FAIL $required: status=$status target=${target:-unknown} machine=${machine_host:-unknown}"
    target_failures=$((target_failures + 1))
  fi
  if ! bool_ready "$reachable"; then
    echo "FAIL $required: reachable=${reachable:-unknown} target=${target:-unknown} machine=${machine_host:-unknown}"
    target_failures=$((target_failures + 1))
  fi
  if ! bool_ready "$physical"; then
    echo "FAIL $required: physicalSTTSmokeReady=${physical:-unknown} target=${target:-unknown} machine=${machine_host:-unknown}"
    target_failures=$((target_failures + 1))
  fi
  if ! bool_ready "$active"; then
    echo "FAIL $required: activeFieldSmokeReady=${active:-unknown} target=${target:-unknown} machine=${machine_host:-unknown}"
    if [[ -n "$next_action" ]]; then
      echo "  nextAction: $next_action"
    fi
    target_failures=$((target_failures + 1))
  fi

  if [[ "$target_failures" -eq 0 ]]; then
    echo "PASS $required: target=${target:-unknown} machine=${machine_host:-unknown}"
  else
    failures=$((failures + target_failures))
  fi
done

echo
if [[ "$failures" -eq 0 ]]; then
  echo "Result: proven"
  exit 0
fi

echo "Result: not proven"
echo "Failures: $failures"
exit 1
