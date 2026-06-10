#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT/scripts"
VERSION="${PRESSTALK_RELEASE_VERSION:-0.1.6-test-local}"
PUBLIC_NAME="${PUBLIC_NAME:-PressTalk}"
ARCH="${ARCH:-arm64}"
DIST_DIR=""
RUN_LOCAL=0
HOSTS=()
HOST_COUNT=0
REQUIRED_TARGETS=()
REQUIRED_TARGET_COUNT=0
EXCLUDED_HOSTS=()
EXCLUDED_HOST_COUNT=0
JSON_OUTPUT_PATH=""
REQUIRE_PRODUCTION=0

PUBLISH_SCRIPT="${PRESSTALK_PUBLISH_HOMEBREW_SCRIPT:-$SCRIPT_DIR/publish_presstalk_homebrew.sh}"
MATRIX_SCRIPT="${PRESSTALK_READINESS_MATRIX_SCRIPT:-$SCRIPT_DIR/presstalk_readiness_matrix.sh}"
PROOF_GATE_SCRIPT="${PRESSTALK_RELEASE_PROOF_GATE_SCRIPT:-$SCRIPT_DIR/presstalk_release_proof_gate.sh}"
READINESS_PREFLIGHT_SCRIPT="${PRESSTALK_RELEASE_READINESS_PREFLIGHT_SCRIPT:-$SCRIPT_DIR/presstalk_release_readiness_preflight.sh}"

usage() {
  cat <<'EOF'
Usage: presstalk_release_candidate_preflight.sh [version] [options]

Runs a no-publish release-candidate evidence pass:
  1. collect readiness matrix
  2. run release proof gate
  3. package via Homebrew publish dry-run
  4. run/record release-readiness JSON

This does not install PressTalk, open System Settings, or publish to GitHub. It
only SSHes when --host/--hosts are supplied.

Options:
  --version VERSION       Release/prerelease version to package.
  --dist-dir PATH         Directory for generated evidence.
  --local                 Include this Mac in the readiness matrix.
  --host HOST             Include one SSH host. May be repeated.
  --hosts LIST            Include comma-separated SSH hosts.
  --exclude-host HOST=WHY Record an intentionally excluded host.
  --require TARGET        Required target alias, host, or machineHost for proof.
                          May be repeated. Defaults to selected targets.
  --require-production    Require production signing/notarization in final
                          readiness preflight.
  --json-output PATH      Write machine-readable wrapper summary.
  -h, --help              Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      if [[ -z "$VERSION" ]]; then
        echo "Missing value for --version" >&2
        exit 2
      fi
      shift 2
      ;;
    --dist-dir)
      DIST_DIR="${2:-}"
      if [[ -z "$DIST_DIR" ]]; then
        echo "Missing value for --dist-dir" >&2
        exit 2
      fi
      shift 2
      ;;
    --local)
      RUN_LOCAL=1
      shift
      ;;
    --host)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --host" >&2
        exit 2
      fi
      HOSTS+=("$2")
      HOST_COUNT=$((HOST_COUNT + 1))
      shift 2
      ;;
    --hosts)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --hosts" >&2
        exit 2
      fi
      IFS=',' read -r -a parsed_hosts <<<"$2"
      for parsed_host in "${parsed_hosts[@]}"; do
        parsed_host="${parsed_host#"${parsed_host%%[![:space:]]*}"}"
        parsed_host="${parsed_host%"${parsed_host##*[![:space:]]}"}"
        [[ -z "$parsed_host" ]] && continue
        HOSTS+=("$parsed_host")
        HOST_COUNT=$((HOST_COUNT + 1))
      done
      shift 2
      ;;
    --exclude-host)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --exclude-host" >&2
        exit 2
      fi
      EXCLUDED_HOSTS+=("$2")
      EXCLUDED_HOST_COUNT=$((EXCLUDED_HOST_COUNT + 1))
      shift 2
      ;;
    --require)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --require" >&2
        exit 2
      fi
      REQUIRED_TARGETS+=("$2")
      REQUIRED_TARGET_COUNT=$((REQUIRED_TARGET_COUNT + 1))
      shift 2
      ;;
    --require-production)
      REQUIRE_PRODUCTION=1
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
      if [[ "$1" == -* ]]; then
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 2
      fi
      VERSION="$1"
      shift
      ;;
  esac
done

if [[ -z "$DIST_DIR" ]]; then
  DIST_DIR="${PRESSTALK_DIST_DIR:-$ROOT/dist/release-candidate-$VERSION}"
fi

if [[ "$RUN_LOCAL" -eq 0 && "$HOST_COUNT" -eq 0 ]]; then
  RUN_LOCAL=1
fi

if [[ "$REQUIRED_TARGET_COUNT" -eq 0 ]]; then
  if [[ -n "${PRESSTALK_REQUIRED_PROOF_TARGETS:-}" ]]; then
    IFS=',' read -r -a parsed_required_targets <<<"$PRESSTALK_REQUIRED_PROOF_TARGETS"
    for parsed_required_target in "${parsed_required_targets[@]}"; do
      parsed_required_target="${parsed_required_target#"${parsed_required_target%%[![:space:]]*}"}"
      parsed_required_target="${parsed_required_target%"${parsed_required_target##*[![:space:]]}"}"
      [[ -z "$parsed_required_target" ]] && continue
      REQUIRED_TARGETS+=("$parsed_required_target")
      REQUIRED_TARGET_COUNT=$((REQUIRED_TARGET_COUNT + 1))
    done
  else
    if [[ "$RUN_LOCAL" -eq 1 ]]; then
      REQUIRED_TARGETS+=("local")
      REQUIRED_TARGET_COUNT=$((REQUIRED_TARGET_COUNT + 1))
    fi
    if [[ "$HOST_COUNT" -gt 0 ]]; then
      for host in "${HOSTS[@]}"; do
        REQUIRED_TARGETS+=("$host")
        REQUIRED_TARGET_COUNT=$((REQUIRED_TARGET_COUNT + 1))
      done
    fi
  fi
fi

required_targets_csv() {
  local joined="" target
  if [[ "$REQUIRED_TARGET_COUNT" -gt 0 ]]; then
    for target in "${REQUIRED_TARGETS[@]}"; do
      if [[ -n "$joined" ]]; then
        joined+=","
      fi
      joined+="$target"
    done
  fi
  printf '%s\n' "$joined"
}

mkdir -p "$DIST_DIR"

MATRIX_JSON="$DIST_DIR/${PUBLIC_NAME}-${VERSION}-readiness-matrix.json"
PROOF_GATE_JSON="$DIST_DIR/${PUBLIC_NAME}-${VERSION}-proof-gate.json"
ARTIFACT_AUDIT_JSON="$DIST_DIR/${PUBLIC_NAME}-${VERSION}-macos-${ARCH}-artifact-audit.json"
RELEASE_READINESS_JSON="$DIST_DIR/${PUBLIC_NAME}-${VERSION}-macos-${ARCH}-release-readiness.json"
WRAPPER_JSON="${JSON_OUTPUT_PATH:-$DIST_DIR/${PUBLIC_NAME}-${VERSION}-candidate-preflight.json}"

matrix_args=(--json-output "$MATRIX_JSON")
if [[ "$RUN_LOCAL" -eq 1 ]]; then
  matrix_args+=(--local)
fi
if [[ "$HOST_COUNT" -gt 0 ]]; then
  for host in "${HOSTS[@]}"; do
    matrix_args+=(--host "$host")
  done
fi
if [[ "$EXCLUDED_HOST_COUNT" -gt 0 ]]; then
  for excluded in "${EXCLUDED_HOSTS[@]}"; do
    matrix_args+=(--exclude-host "$excluded")
  done
fi

echo "PressTalk release candidate preflight"
echo "Version: $VERSION"
echo "DistDir: $DIST_DIR"
echo

echo "Collecting readiness matrix..."
"/bin/bash" "$MATRIX_SCRIPT" "${matrix_args[@]}"

proof_args=(--matrix "$MATRIX_JSON" --json-output "$PROOF_GATE_JSON")
if [[ "$REQUIRED_TARGET_COUNT" -gt 0 ]]; then
  for required in "${REQUIRED_TARGETS[@]}"; do
    proof_args+=(--require "$required")
  done
fi
if [[ "$EXCLUDED_HOST_COUNT" -gt 0 ]]; then
  for excluded in "${EXCLUDED_HOSTS[@]}"; do
    proof_args+=(--exclude "$excluded")
  done
fi

echo
echo "Running proof gate..."
"/bin/bash" "$PROOF_GATE_SCRIPT" "${proof_args[@]}"

echo
echo "Packaging and auditing with publish dry-run..."
PRESSTALK_PUBLISH_DRY_RUN=1 \
PRESSTALK_REQUIRE_RELEASE_READINESS=1 \
PRESSTALK_RELEASE_PROOF_GATE_JSON="$PROOF_GATE_JSON" \
PRESSTALK_REQUIRED_PROOF_TARGETS="$(required_targets_csv)" \
PRESSTALK_DIST_DIR="$DIST_DIR" \
ARCH="$ARCH" \
PUBLIC_NAME="$PUBLIC_NAME" \
  "/bin/bash" "$PUBLISH_SCRIPT" "$VERSION"

if [[ "$REQUIRE_PRODUCTION" -eq 1 ]]; then
  echo
  echo "Requiring production release readiness..."
  readiness_args=(
    --artifact-audit "$ARTIFACT_AUDIT_JSON"
    --proof-gate "$PROOF_GATE_JSON"
    --expected-asr-mode "${PRESSTALK_EXPECTED_ASR_MODE:-parakeet_v3_ane_final_pass}"
    --require-production
    --json-output "$RELEASE_READINESS_JSON"
  )
  if [[ "$REQUIRED_TARGET_COUNT" -gt 0 ]]; then
    for required in "${REQUIRED_TARGETS[@]}"; do
      readiness_args+=(--require-proof-target "$required")
    done
  fi
  "/bin/bash" "$READINESS_PREFLIGHT_SCRIPT" "${readiness_args[@]}"
fi

RESULT_PLIST="$(mktemp "${TMPDIR:-/tmp}/presstalk-candidate-preflight.XXXXXX.plist")"
trap 'rm -f "$RESULT_PLIST"' EXIT
plutil -create xml1 "$RESULT_PLIST" >/dev/null
plutil -insert schemaVersion -string "1" "$RESULT_PLIST" >/dev/null
plutil -insert version -string "$VERSION" "$RESULT_PLIST" >/dev/null
plutil -insert distDir -string "$DIST_DIR" "$RESULT_PLIST" >/dev/null
plutil -insert readinessMatrixJSON -string "$MATRIX_JSON" "$RESULT_PLIST" >/dev/null
plutil -insert proofGateJSON -string "$PROOF_GATE_JSON" "$RESULT_PLIST" >/dev/null
plutil -insert artifactAuditJSON -string "$ARTIFACT_AUDIT_JSON" "$RESULT_PLIST" >/dev/null
plutil -insert releaseReadinessJSON -string "$RELEASE_READINESS_JSON" "$RESULT_PLIST" >/dev/null
plutil -insert requiredTargets -array "$RESULT_PLIST" >/dev/null
if [[ "$REQUIRED_TARGET_COUNT" -gt 0 ]]; then
  for required in "${REQUIRED_TARGETS[@]}"; do
    plutil -insert requiredTargets -string "$required" -append "$RESULT_PLIST" >/dev/null
  done
fi
plutil -insert passed -bool true "$RESULT_PLIST" >/dev/null
mkdir -p "$(dirname "$WRAPPER_JSON")"
plutil -convert json -r -o "$WRAPPER_JSON" "$RESULT_PLIST"

echo
echo "CandidatePreflightJSON: $WRAPPER_JSON"
echo "Result: pass"
