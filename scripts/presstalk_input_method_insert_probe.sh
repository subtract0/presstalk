#!/usr/bin/env bash
set -euo pipefail

TEXT="${1:-PressTalk input method probe}"
SUPPORT_DIR="$HOME/Library/Application Support/JarvisTap"
PAYLOAD_FILE="$SUPPORT_DIR/input-method-insert.txt"
NOTIFICATION="com.am.presstalk.inputmethod.insert"

mkdir -p "$SUPPORT_DIR"
printf '%s' "$TEXT" >"$PAYLOAD_FILE"
/usr/bin/notifyutil -p "$NOTIFICATION"

cat <<EOF
Posted PressTalk input-method insertion probe.

Notification: $NOTIFICATION
Payload file: $PAYLOAD_FILE
Payload: $TEXT

Inspect:
  tail -n 40 "$HOME/Library/Logs/presstalk_input_method.log"
EOF
