#!/usr/bin/env bash
set -euo pipefail

ZIP_PATH=""
JSON_OUTPUT_PATH=""
EXPECTED_BUNDLE_ID="${PRESSTALK_EXPECTED_BUNDLE_ID:-com.am.presstalk}"
EXPECTED_VERSION="${PRESSTALK_EXPECTED_VERSION:-}"
REQUIRE_DISTRIBUTION=0
REQUIRE_NOTARIZED=0

usage() {
  cat <<'EOF'
Usage: presstalk_release_artifact_audit.sh --zip PATH [options]

Audits a packaged PressTalk zip without installing it. The audit extracts the
zip into a temporary directory, finds PressTalk.app, verifies the bundle
signature, records bundle metadata, checks whether the first signing authority
is Developer ID Application, checks for hardened runtime, and optionally
requires a stapled notarization ticket.

Options:
  --zip PATH               Packaged PressTalk zip to audit.
  --expected-bundle-id ID  Expected CFBundleIdentifier. Default: com.am.presstalk.
  --expected-version VER   Expected CFBundleShortVersionString.
  --require-distribution   Fail unless Developer ID, hardened runtime, and
                           strict codesign verification are present.
  --require-notarized      Also fail unless stapler validates the extracted app.
                           Implies --require-distribution.
  --json-output PATH       Write machine-readable JSON audit result.
  -h, --help               Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zip)
      ZIP_PATH="${2:-}"
      if [[ -z "$ZIP_PATH" ]]; then
        echo "Missing value for --zip" >&2
        exit 2
      fi
      shift 2
      ;;
    --expected-bundle-id)
      EXPECTED_BUNDLE_ID="${2:-}"
      if [[ -z "$EXPECTED_BUNDLE_ID" ]]; then
        echo "Missing value for --expected-bundle-id" >&2
        exit 2
      fi
      shift 2
      ;;
    --expected-version)
      EXPECTED_VERSION="${2:-}"
      if [[ -z "$EXPECTED_VERSION" ]]; then
        echo "Missing value for --expected-version" >&2
        exit 2
      fi
      shift 2
      ;;
    --require-distribution)
      REQUIRE_DISTRIBUTION=1
      shift
      ;;
    --require-notarized)
      REQUIRE_DISTRIBUTION=1
      REQUIRE_NOTARIZED=1
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

if [[ -z "$ZIP_PATH" ]]; then
  echo "Missing --zip PATH" >&2
  usage >&2
  exit 2
fi
if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Missing zip: $ZIP_PATH" >&2
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
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

single_line_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    tr '\n' ' ' <"$file" | sed 's/[[:space:]][[:space:]]*/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//' | cut -c 1-800
  fi
}

plist_value() {
  local plist="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true
}

require_cmd codesign
require_cmd ditto
require_cmd plutil
require_cmd shasum

RUN_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-artifact-audit.XXXXXX")"
trap 'rm -rf "$RUN_TMPDIR"' EXIT
EXTRACT_DIR="$RUN_TMPDIR/extracted"
RESULT_PLIST="$RUN_TMPDIR/audit.plist"
mkdir -p "$EXTRACT_DIR"
plutil -create xml1 "$RESULT_PLIST" >/dev/null

ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"

APP_BUNDLE="$(find "$EXTRACT_DIR" -maxdepth 3 -type d -name 'PressTalk.app' -print -quit)"
if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  echo "Missing PressTalk.app inside zip: $ZIP_PATH" >&2
  exit 1
fi

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
BUNDLE_ID="$(plist_value "$INFO_PLIST" CFBundleIdentifier)"
BUNDLE_VERSION="$(plist_value "$INFO_PLIST" CFBundleShortVersionString)"
BUNDLE_BUILD="$(plist_value "$INFO_PLIST" CFBundleVersion)"
ZIP_SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{ print $1 }')"

codesign_stdout="$RUN_TMPDIR/codesign-verify.out"
codesign_stderr="$RUN_TMPDIR/codesign-verify.err"
set +e
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" >"$codesign_stdout" 2>"$codesign_stderr"
codesign_status=$?
set -e
codesign_error="$(single_line_file "$codesign_stderr")"

codesign_details="$RUN_TMPDIR/codesign-details.txt"
set +e
codesign -dv --verbose=4 "$APP_BUNDLE" >"$RUN_TMPDIR/codesign-details.out" 2>"$codesign_details"
details_status=$?
set -e
authority="$(awk -F= '/^Authority=/ { print $2; exit }' "$codesign_details")"
cdhash="$(awk -F= '/^CDHash=/ { print $2; exit }' "$codesign_details")"
identifier="$(awk -F= '/^Identifier=/ { print $2; exit }' "$codesign_details")"
flags="$(awk -F= '/^flags=/ { print $2; exit }' "$codesign_details")"
timestamp="$(awk -F= '/^Timestamp=/ { print $2; exit }' "$codesign_details")"
developer_id=false
hardened_runtime=false
[[ "$authority" == Developer\ ID\ Application* ]] && developer_id=true
[[ "$flags" == *runtime* ]] && hardened_runtime=true

stapler_status=0
stapler_error="not_checked"
notarized="unknown"
if command -v xcrun >/dev/null 2>&1; then
  stapler_stdout="$RUN_TMPDIR/stapler.out"
  stapler_stderr="$RUN_TMPDIR/stapler.err"
  set +e
  xcrun stapler validate "$APP_BUNDLE" >"$stapler_stdout" 2>"$stapler_stderr"
  stapler_status=$?
  set -e
  if [[ "$stapler_status" -eq 0 ]]; then
    notarized=true
    stapler_error="$(single_line_file "$stapler_stdout")"
  else
    notarized=false
    stapler_error="$(single_line_file "$stapler_stderr")"
    if [[ -z "$stapler_error" ]]; then
      stapler_error="$(single_line_file "$stapler_stdout")"
    fi
  fi
else
  stapler_status=127
  notarized=unknown
  stapler_error="xcrun unavailable"
fi

bundle_id_matches=false
version_matches=true
[[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] && bundle_id_matches=true
if [[ -n "$EXPECTED_VERSION" && "$BUNDLE_VERSION" != "$EXPECTED_VERSION" ]]; then
  version_matches=false
fi

distribution_ready=false
if [[ "$codesign_status" -eq 0 && "$developer_id" == "true" && "$hardened_runtime" == "true" ]]; then
  distribution_ready=true
fi

passed=true
failure_count=0
failures=()
if [[ "$bundle_id_matches" != "true" ]]; then
  passed=false
  failure_count=$((failure_count + 1))
  failures+=("bundle_id_mismatch")
fi
if [[ "$version_matches" != "true" ]]; then
  passed=false
  failure_count=$((failure_count + 1))
  failures+=("version_mismatch")
fi
if [[ "$codesign_status" -ne 0 ]]; then
  passed=false
  failure_count=$((failure_count + 1))
  failures+=("codesign_verify_failed")
fi
if [[ "$REQUIRE_DISTRIBUTION" -eq 1 && "$distribution_ready" != "true" ]]; then
  passed=false
  failure_count=$((failure_count + 1))
  failures+=("distribution_signature_required")
fi
if [[ "$REQUIRE_NOTARIZED" -eq 1 && "$notarized" != "true" ]]; then
  passed=false
  failure_count=$((failure_count + 1))
  failures+=("notarization_required")
fi

plist_insert_string "$RESULT_PLIST" schemaVersion "1"
plist_insert_string "$RESULT_PLIST" zipPath "$ZIP_PATH"
plist_insert_string "$RESULT_PLIST" zipSHA256 "$ZIP_SHA256"
plist_insert_string "$RESULT_PLIST" appBundleInZip "$APP_BUNDLE"
plist_insert_string "$RESULT_PLIST" bundleIdentifier "$BUNDLE_ID"
plist_insert_string "$RESULT_PLIST" expectedBundleIdentifier "$EXPECTED_BUNDLE_ID"
plist_insert_bool "$RESULT_PLIST" bundleIdentifierMatches "$bundle_id_matches"
plist_insert_string "$RESULT_PLIST" bundleVersion "$BUNDLE_VERSION"
plist_insert_string "$RESULT_PLIST" expectedVersion "${EXPECTED_VERSION:-}"
plist_insert_bool "$RESULT_PLIST" versionMatches "$version_matches"
plist_insert_string "$RESULT_PLIST" bundleBuild "$BUNDLE_BUILD"
plist_insert_string "$RESULT_PLIST" codeSignatureIdentifier "$identifier"
plist_insert_string "$RESULT_PLIST" codeSignatureCDHash "$cdhash"
plist_insert_string "$RESULT_PLIST" codeSignatureAuthority "$authority"
plist_insert_string "$RESULT_PLIST" codeSignatureFlags "$flags"
plist_insert_string "$RESULT_PLIST" codeSignatureTimestamp "$timestamp"
plist_insert_bool "$RESULT_PLIST" codeSignVerifyPassed "$([[ "$codesign_status" -eq 0 ]] && echo true || echo false)"
plutil -insert codeSignVerifyExitStatus -integer "$codesign_status" "$RESULT_PLIST" >/dev/null
plutil -insert codeSignDetailsExitStatus -integer "$details_status" "$RESULT_PLIST" >/dev/null
plist_insert_string "$RESULT_PLIST" codeSignVerifyError "$codesign_error"
plist_insert_bool "$RESULT_PLIST" developerIDApplication "$developer_id"
plist_insert_bool "$RESULT_PLIST" hardenedRuntime "$hardened_runtime"
plist_insert_bool "$RESULT_PLIST" distributionReady "$distribution_ready"
plist_insert_bool "$RESULT_PLIST" requireDistribution "$([[ "$REQUIRE_DISTRIBUTION" -eq 1 ]] && echo true || echo false)"
plist_insert_bool "$RESULT_PLIST" requireNotarized "$([[ "$REQUIRE_NOTARIZED" -eq 1 ]] && echo true || echo false)"
plist_insert_string "$RESULT_PLIST" notarized "$notarized"
plutil -insert staplerExitStatus -integer "$stapler_status" "$RESULT_PLIST" >/dev/null
plist_insert_string "$RESULT_PLIST" staplerResult "$stapler_error"
plist_insert_bool "$RESULT_PLIST" passed "$passed"
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

echo "PressTalk release artifact audit"
echo "Zip: $ZIP_PATH"
echo "SHA-256: $ZIP_SHA256"
echo "Bundle ID: ${BUNDLE_ID:-unknown}"
echo "Version: ${BUNDLE_VERSION:-unknown} (${BUNDLE_BUILD:-unknown})"
echo "Codesign: $([[ "$codesign_status" -eq 0 ]] && echo pass || echo fail)"
echo "Authority: ${authority:-unknown}"
echo "Hardened runtime: $hardened_runtime"
echo "Notarized: $notarized"
echo "Distribution-ready signature: $distribution_ready"
if [[ -n "$JSON_OUTPUT_PATH" ]]; then
  echo "AuditJSON: $JSON_OUTPUT_PATH"
fi
if [[ "$passed" == "true" ]]; then
  echo "Result: pass"
  exit 0
fi

echo "Result: fail"
printf 'Failures: %s\n' "${failures[*]:-unknown}"
exit 1
