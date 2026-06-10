#!/usr/bin/env bash
set -euo pipefail

JSON_OUTPUT=""
REQUIRE_NOTARIZATION=0
IDENTITY_OVERRIDE=""
NOTARY_PROFILE_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage: presstalk_distribution_signing_preflight.sh [options]

Checks whether this Mac is ready to produce a production PressTalk distribution
artifact. This is read-only: it does not build, sign, notarize, upload, open
System Settings, or print secrets.

Options:
  --require-notarization       Require notarytool credentials for a stable build.
  --identity VALUE             Developer ID identity name or hash to check.
  --notary-profile NAME        notarytool keychain profile name to use.
  --json-output PATH           Write machine-readable preflight JSON.
  -h, --help                   Show this help.
EOF
}

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

append_failure() {
  FAILURES+=("$1")
}

append_action() {
  NEXT_ACTIONS+=("$1")
}

insert_bool() {
  local plist="$1"
  local key="$2"
  local value="$3"
  case "$value" in
    true) plutil -insert "$key" -bool true "$plist" >/dev/null ;;
    *) plutil -insert "$key" -bool false "$plist" >/dev/null ;;
  esac
}

insert_string() {
  local plist="$1"
  local key="$2"
  local value="$3"
  [[ -z "$value" ]] && return 0
  plutil -insert "$key" -string "$value" "$plist" >/dev/null
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-notarization)
      REQUIRE_NOTARIZATION=1
      shift
      ;;
    --identity)
      IDENTITY_OVERRIDE="${2:-}"
      if [[ -z "$IDENTITY_OVERRIDE" ]]; then
        echo "Missing value for --identity" >&2
        exit 2
      fi
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE_OVERRIDE="${2:-}"
      if [[ -z "$NOTARY_PROFILE_OVERRIDE" ]]; then
        echo "Missing value for --notary-profile" >&2
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

if truthy "${PRESSTALK_NOTARIZE:-0}"; then
  REQUIRE_NOTARIZATION=1
fi

FAILURES=()
NEXT_ACTIONS=()
IDENTITY_REQUESTED="${IDENTITY_OVERRIDE:-${PRESSTALK_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}}"
NOTARY_PROFILE="${NOTARY_PROFILE_OVERRIDE:-${PRESSTALK_NOTARYTOOL_PROFILE:-}}"
SECURITY_CMD="${PRESSTALK_SECURITY_CMD:-security}"
XCRUN_CMD="${PRESSTALK_XCRUN_CMD:-xcrun}"

security_available=false
xcrun_available=false
identity_ready=false
developer_id_identity_available=false
requested_identity_found=false
requested_identity_is_developer_id=false
identity_source="none"
selected_identity=""
selected_identity_hash=""
identity_listing=""
identity_listing_status=0
notary_credentials_ready=false
notary_mode="not_required"

if command -v "$SECURITY_CMD" >/dev/null 2>&1; then
  security_available=true
  set +e
  identity_listing="$("$SECURITY_CMD" find-identity -v -p codesigning 2>/dev/null)"
  identity_listing_status=$?
  set -e
else
  append_failure "security_command_missing"
fi

if [[ "$security_available" == "true" && "$identity_listing_status" -eq 0 ]]; then
  while IFS= read -r line; do
    [[ "$line" != *"Developer ID Application"* ]] && continue
    developer_id_identity_available=true
    if [[ -z "$selected_identity" ]]; then
      selected_identity="$(printf '%s\n' "$line" | sed -E 's/^ *[0-9]+\) +[A-Fa-f0-9]+ +"(.*)"$/\1/')"
      selected_identity_hash="$(printf '%s\n' "$line" | awk '{ print $2; exit }')"
      identity_source="discovered"
    fi
  done <<<"$identity_listing"

  if [[ -n "$IDENTITY_REQUESTED" ]]; then
    identity_source="requested"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ "$line" == *"$IDENTITY_REQUESTED"* ]]; then
        requested_identity_found=true
        selected_identity="$(printf '%s\n' "$line" | sed -E 's/^ *[0-9]+\) +[A-Fa-f0-9]+ +"(.*)"$/\1/')"
        selected_identity_hash="$(printf '%s\n' "$line" | awk '{ print $2; exit }')"
        if [[ "$line" == *"Developer ID Application"* ]]; then
          requested_identity_is_developer_id=true
        fi
        break
      fi
    done <<<"$identity_listing"
  fi
elif [[ "$security_available" == "true" ]]; then
  append_failure "codesigning_identity_listing_failed"
fi

if [[ -n "$IDENTITY_REQUESTED" ]]; then
  if [[ "$requested_identity_found" != "true" ]]; then
    append_failure "requested_developer_id_identity_not_found"
  elif [[ "$requested_identity_is_developer_id" != "true" ]]; then
    append_failure "requested_identity_is_not_developer_id_application"
  else
    identity_ready=true
  fi
else
  if [[ "$developer_id_identity_available" == "true" ]]; then
    identity_ready=true
  else
    append_failure "developer_id_application_identity_missing"
  fi
fi

if [[ "$identity_ready" != "true" ]]; then
  append_action "Install a Developer ID Application certificate into this user's login keychain, or set PRESSTALK_CODESIGN_IDENTITY to a valid Developer ID Application name/hash."
fi

if [[ "$REQUIRE_NOTARIZATION" -eq 1 ]]; then
  notary_mode="missing"
  if command -v "$XCRUN_CMD" >/dev/null 2>&1; then
    xcrun_available=true
  else
    append_failure "xcrun_command_missing"
    append_action "Install the Xcode command line tools so xcrun notarytool and stapler are available."
  fi

  if [[ -n "$NOTARY_PROFILE" ]]; then
    notary_mode="profile"
    if [[ "$xcrun_available" == "true" ]]; then
      notary_credentials_ready=true
    fi
  elif [[ -n "${PRESSTALK_NOTARY_APPLE_ID:-}" &&
          -n "${PRESSTALK_NOTARY_TEAM_ID:-}" &&
          -n "${PRESSTALK_NOTARY_PASSWORD:-}" ]]; then
    notary_mode="apple_id_env"
    if [[ "$xcrun_available" == "true" ]]; then
      notary_credentials_ready=true
    fi
  else
    append_failure "notary_credentials_missing"
    append_action "Store a notarytool keychain profile, for example: xcrun notarytool store-credentials presstalk-notary --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>; then set PRESSTALK_NOTARYTOOL_PROFILE=presstalk-notary."
  fi
else
  notary_credentials_ready=true
fi

production_ready=false
if [[ "$identity_ready" == "true" && "$notary_credentials_ready" == "true" ]]; then
  production_ready=true
fi

echo "PressTalk distribution signing preflight"
echo "Developer ID identity: $([[ "$identity_ready" == "true" ]] && echo ready || echo missing)"
if [[ -n "$selected_identity" ]]; then
  echo "Selected identity: $selected_identity"
fi
if [[ "$REQUIRE_NOTARIZATION" -eq 1 ]]; then
  echo "Notarization credentials: $([[ "$notary_credentials_ready" == "true" ]] && echo ready || echo missing) ($notary_mode)"
else
  echo "Notarization credentials: not required by this preflight"
fi
echo "Production signing ready: $production_ready"

if [[ "${#FAILURES[@]}" -gt 0 ]]; then
  echo
  echo "Failures"
  for failure in "${FAILURES[@]}"; do
    echo "- $failure"
  done
fi

if [[ "${#NEXT_ACTIONS[@]}" -gt 0 ]]; then
  echo
  echo "Next actions"
  for action in "${NEXT_ACTIONS[@]}"; do
    echo "- $action"
  done
fi

if [[ "$production_ready" == "true" && "$REQUIRE_NOTARIZATION" -eq 1 ]]; then
  echo
  echo "Production package command"
  if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "PRESSTALK_DISTRIBUTION_SIGNING=1 PRESSTALK_CODESIGN_IDENTITY=\"${IDENTITY_REQUESTED:-$selected_identity}\" PRESSTALK_NOTARIZE=1 PRESSTALK_NOTARYTOOL_PROFILE=\"$NOTARY_PROFILE\" bash scripts/package_presstalk_release.sh 0.1.6"
  else
    echo "PRESSTALK_DISTRIBUTION_SIGNING=1 PRESSTALK_CODESIGN_IDENTITY=\"${IDENTITY_REQUESTED:-$selected_identity}\" PRESSTALK_NOTARIZE=1 bash scripts/package_presstalk_release.sh 0.1.6"
  fi
fi

if [[ -n "$JSON_OUTPUT" ]]; then
  result_plist="$(mktemp "${TMPDIR:-/tmp}/presstalk-distribution-signing.XXXXXX.plist")"
  plutil -create xml1 "$result_plist" >/dev/null
  plutil -insert schemaVersion -string "1" "$result_plist" >/dev/null
  insert_bool "$result_plist" securityAvailable "$security_available"
  plutil -insert identityListingExitStatus -integer "$identity_listing_status" "$result_plist" >/dev/null
  insert_bool "$result_plist" developerIDIdentityAvailable "$developer_id_identity_available"
  insert_bool "$result_plist" identityReady "$identity_ready"
  insert_string "$result_plist" identitySource "$identity_source"
  insert_string "$result_plist" selectedIdentity "$selected_identity"
  insert_string "$result_plist" selectedIdentityHash "$selected_identity_hash"
  insert_bool "$result_plist" requireNotarization "$([[ "$REQUIRE_NOTARIZATION" -eq 1 ]] && echo true || echo false)"
  insert_bool "$result_plist" xcrunAvailable "$xcrun_available"
  insert_string "$result_plist" notaryCredentialMode "$notary_mode"
  insert_bool "$result_plist" notaryCredentialsReady "$notary_credentials_ready"
  insert_bool "$result_plist" productionSigningReady "$production_ready"
  plutil -insert failures -array "$result_plist" >/dev/null
  if [[ "${#FAILURES[@]}" -gt 0 ]]; then
    for failure in "${FAILURES[@]}"; do
      plutil -insert failures -string "$failure" -append "$result_plist" >/dev/null
    done
  fi
  plutil -insert nextActions -array "$result_plist" >/dev/null
  if [[ "${#NEXT_ACTIONS[@]}" -gt 0 ]]; then
    for action in "${NEXT_ACTIONS[@]}"; do
      plutil -insert nextActions -string "$action" -append "$result_plist" >/dev/null
    done
  fi
  mkdir -p "$(dirname "$JSON_OUTPUT")"
  plutil -convert json -r -o "$JSON_OUTPUT" "$result_plist"
  rm -f "$result_plist"
  echo
  echo "DistributionSigningPreflightJSON: $JSON_OUTPUT"
fi

if [[ "$production_ready" != "true" ]]; then
  exit 1
fi
