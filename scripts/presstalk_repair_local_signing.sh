#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_APP_BUNDLE="$HOME/Applications/PressTalk.app"
STATUS_JSON="$HOME/Library/Application Support/JarvisTap/runtime-status.json"
RUN_PROBE=0
PREFLIGHT=0
APP_BUNDLE="${PRESSTALK_APP_BUNDLE:-}"
TRIGGER_KEY="${PRESSTALK_TRIGGER_KEY:-}"
ALLOW_SSH="${PRESSTALK_REPAIR_ALLOW_SSH:-0}"

usage() {
  cat <<EOF
Usage: presstalk-repair-local-signing.sh [options]

Repairs PressTalk local development signing without opening macOS privacy panes.
macOS may ask for your Mac login password to trust the local signing
certificate. That prompt is for signing trust, not Microphone/Input Monitoring/
Accessibility.

Options:
  --app-bundle PATH   PressTalk.app path. Defaults to the bundled app or
                      $DEFAULT_APP_BUNDLE.
  --trigger-key KEY   Trigger to preserve while restarting. Default: current
                      runtime status, then fn.
  --preflight         Report whether repair is needed and whether a signing
                      trust password prompt would be required. Does not repair,
                      create, sign, bootstrap, probe, or open any panes.
  --probe             Run the production insertion probe after repair.
  --allow-ssh         Permit running the signing trust flow from SSH.
  -h, --help          Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-bundle)
      APP_BUNDLE="${2:-}"
      if [[ -z "$APP_BUNDLE" ]]; then
        echo "Missing value for --app-bundle" >&2
        exit 2
      fi
      shift 2
      ;;
    --trigger-key)
      TRIGGER_KEY="${2:-}"
      if [[ -z "$TRIGGER_KEY" ]]; then
        echo "Missing value for --trigger-key" >&2
        exit 2
      fi
      shift 2
      ;;
    --probe)
      RUN_PROBE=1
      shift
      ;;
    --preflight)
      PREFLIGHT=1
      shift
      ;;
    --allow-ssh)
      ALLOW_SSH=1
      shift
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

if [[ -z "$APP_BUNDLE" ]]; then
  if [[ -f "$SCRIPT_DIR/../Info.plist" && -d "$SCRIPT_DIR/../MacOS" ]]; then
    APP_BUNDLE="$(cd "$SCRIPT_DIR/../.." && pwd)"
  else
    APP_BUNDLE="$DEFAULT_APP_BUNDLE"
  fi
fi

APP_CONTENTS_DIR="$APP_BUNDLE/Contents"
APP_RESOURCES_DIR="$APP_CONTENTS_DIR/Resources"
BOOTSTRAP="$APP_RESOURCES_DIR/presstalk-bootstrap.sh"
LOCAL_CODESIGN_HELPER="$APP_RESOURCES_DIR/create-presstalk-local-codesign-identity.sh"
PROBE_RUNNER="$APP_RESOURCES_DIR/presstalk-run-production-insertion-probe.sh"
SMOKE_COLLECTOR="$APP_RESOURCES_DIR/presstalk-collect-smoke-status.sh"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing PressTalk app bundle: $APP_BUNDLE" >&2
  exit 1
fi
if [[ ! -x "$BOOTSTRAP" ]]; then
  echo "Missing bundled bootstrap helper: $BOOTSTRAP" >&2
  exit 1
fi
if [[ ! -x "$LOCAL_CODESIGN_HELPER" ]]; then
  echo "Missing bundled local signing helper: $LOCAL_CODESIGN_HELPER" >&2
  exit 1
fi

if [[ -z "$TRIGGER_KEY" && -f "$STATUS_JSON" ]]; then
  TRIGGER_KEY="$(plutil -extract runtime.triggerKey raw -o - "$STATUS_JSON" 2>/dev/null || true)"
fi
TRIGGER_KEY="${TRIGGER_KEY:-fn}"

status_value() {
  local key_path="$1"
  if [[ -f "$STATUS_JSON" ]]; then
    plutil -extract "$key_path" raw -o - "$STATUS_JSON" 2>/dev/null || true
  fi
}

running_over_ssh() {
  [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]
}

existing_identity_status() {
  local existing_output existing_hash
  if existing_output="$(
    PRESSTALK_LOCAL_CODESIGN_EXISTING_ONLY=1 "$LOCAL_CODESIGN_HELPER" 2>&1
  )"; then
    existing_hash="$(printf '%s\n' "$existing_output" | awk '/^Hash: / { print $2; exit }')"
    printf 'ready:%s\n' "${existing_hash:-unknown}"
  else
    existing_hash="$(printf '%s\n' "$existing_output" | awk '/^Hash: / { print $2; exit }')"
    if [[ -n "$existing_hash" ]] &&
       printf '%s\n' "$existing_output" | grep -Eiq 'present but not trusted|remains untrusted'; then
      printf 'untrusted:%s\n' "$existing_hash"
      return 0
    fi
    printf 'missing:%s\n' "$(printf '%s\n' "$existing_output" | tail -1)"
  fi
}

print_preflight() {
  local ad_hoc input_method active_status code_signature_authority speech_model input_listener microphone_status input_monitoring_effective
  local existing_status existing_state existing_detail repair_needed prompt_needed repair_allowed would_run next_action

  ad_hoc="$(status_value status.adHocSigned)"
  input_method="$(status_value permissions.inputMethodFallbackStatus)"
  active_status="$(status_value runtime.activeFieldInsertionStatus)"
  code_signature_authority="$(status_value status.codeSignatureAuthority)"
  speech_model="$(status_value status.speechModel)"
  input_listener="$(status_value runtime.inputListener)"
  microphone_status="$(status_value permissions.microphoneAuthorizationStatus)"
  input_monitoring_effective="$(status_value permissions.inputMonitoringEffective)"
  existing_status="$(existing_identity_status)"
  existing_state="${existing_status%%:*}"
  existing_detail="${existing_status#*:}"

  repair_needed=false
  if [[ "$input_method" == "recognized_disabled" &&
        ( "$ad_hoc" == "true" || "$code_signature_authority" == "PressTalk Local Development Code Signing" ) ]]; then
    repair_needed=true
  elif [[ "$active_status" == "needs_signing_repair" ]]; then
    repair_needed=true
  fi

  prompt_needed=false
  if [[ "$repair_needed" == "true" && "$existing_state" != "ready" ]]; then
    prompt_needed=true
  fi

  repair_allowed=true
  if running_over_ssh && [[ "$ALLOW_SSH" != "1" ]]; then
    repair_allowed=false
  fi

  would_run=false
  if [[ "$repair_needed" == "true" && "$repair_allowed" == "true" ]]; then
    would_run=true
  fi

  if [[ "$repair_needed" != "true" ]]; then
    next_action="No signing repair needed for the current runtime status."
  elif [[ "$repair_allowed" != "true" ]]; then
    next_action="Run Repair Signing from the logged-in desktop session; SSH repair is refused unless --allow-ssh is passed deliberately."
  elif [[ "$prompt_needed" == "true" ]]; then
    next_action="Run Repair Signing from the logged-in desktop session and approve only the PressTalk local signing trust password prompt."
  else
    next_action="Run Repair Signing; an existing trusted PressTalk local signing identity can be reused."
  fi

  cat <<EOF
PressTalk local signing repair preflight

App: $APP_BUNDLE
Trigger: $TRIGGER_KEY
RuntimeStatus: ${STATUS_JSON}
RunningOverSSH: $(running_over_ssh && echo true || echo false)
AllowSSH: $([[ "$ALLOW_SSH" == "1" ]] && echo true || echo false)
RepairNeeded: $repair_needed
RepairAllowedHere: $repair_allowed
WouldRunRepair: $would_run
SigningTrustPromptNeeded: $prompt_needed
ExistingSigningIdentity: $existing_state
ExistingSigningIdentityDetail: $existing_detail
AdHocSigned: ${ad_hoc:-unknown}
CodeSignatureAuthority: ${code_signature_authority:-unknown}
InputMethodFallbackStatus: ${input_method:-unknown}
ActiveFieldInsertionStatus: ${active_status:-unknown}
SpeechModel: ${speech_model:-unknown}
InputListener: ${input_listener:-unknown}
MicrophoneAuthorizationStatus: ${microphone_status:-unknown}
InputMonitoringEffective: ${input_monitoring_effective:-unknown}
NextAction: $next_action

This preflight did not create or trust a certificate, did not sign or restart
PressTalk, did not run an insertion probe, and did not open System Settings.
EOF
}

if [[ "$PREFLIGHT" == "1" ]]; then
  print_preflight
  exit 0
fi

cat <<EOF
PressTalk local signing repair

App: $APP_BUNDLE
Trigger: $TRIGGER_KEY

This repair will not open System Settings or privacy panes. If macOS asks for
your Mac login password, approve it only for the PressTalk local signing
certificate trust prompt.
EOF

echo
print_preflight

if [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" && "$ALLOW_SSH" != "1" ]]; then
  cat >&2 <<EOF

This appears to be running over SSH, so PressTalk will not start the signing
trust flow here. Run the same helper from the logged-in desktop session and
approve only the Mac login-password prompt for PressTalk local signing trust.

If you are deliberately testing SSH behavior, rerun with --allow-ssh.
EOF
  exit 2
fi

identity_output="$(
  PRESSTALK_LOCAL_CODESIGN_TRUST_TIMEOUT_SECONDS="${PRESSTALK_LOCAL_CODESIGN_TRUST_TIMEOUT_SECONDS:-180}" \
    "$LOCAL_CODESIGN_HELPER" 2>&1
)" || {
  printf '%s\n' "$identity_output" >&2
  cat >&2 <<EOF

PressTalk could not prepare a trusted local signing identity.
Do not reopen Microphone, Input Monitoring, or Accessibility panes for this.
Run this helper from the logged-in desktop session and approve the signing
trust prompt.
EOF
  exit 1
}

identity_hash="$(printf '%s\n' "$identity_output" | awk '/^Hash: / { print $2; exit }')"
if [[ -z "$identity_hash" ]]; then
  printf '%s\n' "$identity_output" >&2
  echo "Signing helper did not report an identity hash." >&2
  exit 1
fi

echo
echo "Local signing identity ready: $identity_hash"
echo "Restarting PressTalk with stable signing and no permission panes..."

PRESSTALK_CODESIGN_IDENTITY="$identity_hash" \
PRESSTALK_BOOTSTRAP_STABLE_SIGNING=1 \
PRESSTALK_BOOTSTRAP_REFRESH_INPUT_METHOD=1 \
PRESSTALK_OPEN_PERMISSION_PANES=0 \
PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
PRESSTALK_TRIGGER_KEY="$TRIGGER_KEY" \
  /bin/bash "$BOOTSTRAP"

if [[ "$RUN_PROBE" == "1" ]]; then
  if [[ ! -x "$PROBE_RUNNER" ]]; then
    echo "Production insertion probe runner missing: $PROBE_RUNNER" >&2
    exit 1
  fi
  echo
  echo "Running production insertion probe..."
  probe_status=0
  PRESSTALK_TRIGGER_KEY="$TRIGGER_KEY" /bin/bash "$PROBE_RUNNER" --json --timeout 14 || probe_status=$?

  if [[ -x "$SMOKE_COLLECTOR" ]]; then
    echo
    echo "Collecting post-repair smoke status..."
    /bin/bash "$SMOKE_COLLECTOR" || true
  else
    echo
    echo "Post-repair smoke collector missing: $SMOKE_COLLECTOR"
  fi
  exit "$probe_status"
else
  cat <<EOF

Repair finished. To verify insertion without recording audio, run:
  /bin/bash "$PROBE_RUNNER" --json --timeout 14
EOF
fi
