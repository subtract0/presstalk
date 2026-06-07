#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_APP_BUNDLE="$HOME/Applications/PressTalk.app"
STATUS_JSON="$HOME/Library/Application Support/JarvisTap/runtime-status.json"
RUN_PROBE=0
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

cat <<EOF
PressTalk local signing repair

App: $APP_BUNDLE
Trigger: $TRIGGER_KEY

This repair will not open System Settings or privacy panes. If macOS asks for
your Mac login password, approve it only for the PressTalk local signing
certificate trust prompt.
EOF

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
  PRESSTALK_TRIGGER_KEY="$TRIGGER_KEY" /bin/bash "$PROBE_RUNNER" --json --timeout 14
else
  cat <<EOF

Repair finished. To verify insertion without recording audio, run:
  /bin/bash "$PROBE_RUNNER" --json --timeout 14
EOF
fi
