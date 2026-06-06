#!/usr/bin/env bash
set -euo pipefail

SUPPORT_DIR="$HOME/Library/Application Support/JarvisTap"
DIAGNOSTICS_DIR="$SUPPORT_DIR/Diagnostics"
TIMESTAMP="$(date -u '+%Y-%m-%dT%H-%M-%SZ')"
RUN_ID="$TIMESTAMP-$$"
OUTPUT_JSON="$DIAGNOSTICS_DIR/accessibility-actual-bundle-probe-$RUN_ID.json"

mkdir -p "$DIAGNOSTICS_DIR"

json_string() {
  local escaped
  escaped="$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '"%s"' "$escaped"
}

json_raw_value() {
  local path="$1"
  local key="$2"
  if [[ -f "$path" ]]; then
    plutil -extract "$key" raw -o - "$path" 2>/dev/null || true
  fi
}

plist_value() {
  local app_path="$1"
  local key="$2"
  if [[ -f "$app_path/Contents/Info.plist" ]]; then
    /usr/libexec/PlistBuddy -c "Print $key" "$app_path/Contents/Info.plist" 2>/dev/null || true
  fi
}

codesign_value() {
  local path="$1"
  local key="$2"
  if [[ -d "$path" ]]; then
    codesign -dv --verbose=4 "$path" 2>&1 |
      awk -F= -v key="$key" '$1 == key { value = $2 } END { if (value != "") print value }'
  fi
}

safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

presstalk_processes() {
  ps -axo pid=,ppid=,command= |
    awk '
      (index($0, "/PressTalk.app/Contents/MacOS/jarvistap") ||
      index($0, "/JarvisTap.app/Contents/MacOS/jarvistap")) &&
      !index($0, " awk ") {
        print
      }
    '
}

live_app_bundle() {
  printf '%s\n' "$1" |
    awk '
      {
        for (i = 3; i <= NF; i++) {
          if ($i ~ /\/(PressTalk|JarvisTap)\.app\/Contents\/MacOS\/jarvistap$/) {
            sub(/\/Contents\/MacOS\/jarvistap$/, "", $i)
            print $i
            exit
          }
        }
      }
    '
}

add_candidate() {
  local path="$1"
  [[ -n "$path" && -d "$path" ]] || return 0
  local existing
  if [[ "${#CANDIDATE_BUNDLES[@]}" -gt 0 ]]; then
    for existing in "${CANDIDATE_BUNDLES[@]}"; do
      [[ "$existing" == "$path" ]] && return 0
    done
  fi
  CANDIDATE_BUNDLES+=("$path")
}

append_result() {
  local first="$1"
  local app_path="$2"
  local status="$3"
  local open_status="$4"
  local stdout_path="$5"
  local stderr_path="$6"
  local trusted="$7"
  local prompt_requested="$8"
  local bundle_identifier="$9"
  local executable_path="${10}"
  local process_id="${11}"
  local sign_identifier="${12}"
  local sign_cdhash="${13}"
  local sign_authority="${14}"

  if [[ "$first" == "0" ]]; then
    printf ',\n' >>"$OUTPUT_JSON"
  fi
  {
    printf '    {\n'
    printf '      "appPath": %s,\n' "$(json_string "$app_path")"
    printf '      "status": %s,\n' "$(json_string "$status")"
    printf '      "openExitStatus": %s,\n' "$(json_string "$open_status")"
    printf '      "probeStdoutPath": %s,\n' "$(json_string "$stdout_path")"
    printf '      "probeStderrPath": %s,\n' "$(json_string "$stderr_path")"
    printf '      "accessibilityTrusted": %s,\n' "$trusted"
    printf '      "promptRequested": %s,\n' "$prompt_requested"
    printf '      "bundleIdentifier": %s,\n' "$(json_string "$bundle_identifier")"
    printf '      "executablePath": %s,\n' "$(json_string "$executable_path")"
    printf '      "processID": %s,\n' "$(json_string "$process_id")"
    printf '      "codeSignatureIdentifier": %s,\n' "$(json_string "$sign_identifier")"
    printf '      "codeSignatureCDHash": %s,\n' "$(json_string "$sign_cdhash")"
    printf '      "codeSignatureAuthority": %s\n' "$(json_string "$sign_authority")"
    printf '    }'
  } >>"$OUTPUT_JSON"
}

LIVE_PROCESSES="$(presstalk_processes || true)"
LIVE_APP_BUNDLE="$(live_app_bundle "$LIVE_PROCESSES")"
CANDIDATE_BUNDLES=()

if [[ -n "${PRESSTALK_ACTUAL_AX_PROBE_APP_BUNDLES:-}" ]]; then
  IFS=':' read -r -a override_bundles <<<"$PRESSTALK_ACTUAL_AX_PROBE_APP_BUNDLES"
  for override_bundle in "${override_bundles[@]}"; do
    add_candidate "$override_bundle"
  done
else
  add_candidate "$LIVE_APP_BUNDLE"
  add_candidate "$HOME/Applications/PressTalk.app"
  add_candidate "/Applications/PressTalk.app"
  add_candidate "$HOME/Applications/JarvisTap.app"
  add_candidate "/Applications/JarvisTap.app"
fi

cat >"$OUTPUT_JSON" <<EOF
{
  "generatedAt": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "probeKind": "actual_bundle_accessibility_trust",
  "promptRequested": false,
  "liveAppBundle": $(json_string "$LIVE_APP_BUNDLE"),
  "candidates": [
EOF

first=1
if [[ "${#CANDIDATE_BUNDLES[@]}" -gt 0 ]]; then
  for app_path in "${CANDIDATE_BUNDLES[@]}"; do
    name="$(safe_name "$app_path")"
    stdout_path="$DIAGNOSTICS_DIR/accessibility-actual-bundle-$name-$RUN_ID.stdout.json"
    stderr_path="$DIAGNOSTICS_DIR/accessibility-actual-bundle-$name-$RUN_ID.stderr.txt"
    open_status=0
    if /usr/bin/open \
      -n \
      -g \
      -j \
      -W \
      --stdout "$stdout_path" \
      --stderr "$stderr_path" \
      --env PRESSTALK_ACCESSIBILITY_TRUST_PROBE=1 \
      --env PRESSTALK_OPEN_PERMISSION_PANES=0 \
      --env PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
      "$app_path" >/dev/null 2>&1; then
      open_status=0
    else
      open_status=$?
    fi

    if [[ "$open_status" == "0" ]] && plutil -extract probeKind raw -o - "$stdout_path" >/dev/null 2>&1; then
      status="ran"
      trusted="$(json_raw_value "$stdout_path" accessibilityTrusted)"
      prompt_requested="$(json_raw_value "$stdout_path" promptRequested)"
      bundle_identifier="$(json_raw_value "$stdout_path" bundleIdentifier)"
      executable_path="$(json_raw_value "$stdout_path" executablePath)"
      process_id="$(json_raw_value "$stdout_path" processID)"
      sign_identifier="$(json_raw_value "$stdout_path" codeSignatureIdentifier)"
      sign_cdhash="$(json_raw_value "$stdout_path" codeSignatureCDHash)"
      sign_authority="$(json_raw_value "$stdout_path" codeSignatureAuthority)"
    else
      status="launch_or_result_failed"
      trusted="false"
      prompt_requested="false"
      bundle_identifier="$(plist_value "$app_path" CFBundleIdentifier)"
      executable_path="$app_path/Contents/MacOS/$(plist_value "$app_path" CFBundleExecutable)"
      process_id=""
      sign_identifier="$(codesign_value "$app_path" Identifier)"
      sign_cdhash="$(codesign_value "$app_path" CDHash)"
      sign_authority="$(codesign_value "$app_path" Authority)"
    fi

    trusted="${trusted:-false}"
    prompt_requested="${prompt_requested:-false}"
    append_result \
      "$first" \
      "$app_path" \
      "$status" \
      "$open_status" \
      "$stdout_path" \
      "$stderr_path" \
      "$trusted" \
      "$prompt_requested" \
      "$bundle_identifier" \
      "$executable_path" \
      "$process_id" \
      "$sign_identifier" \
      "$sign_cdhash" \
      "$sign_authority"
    first=0
  done
fi

cat >>"$OUTPUT_JSON" <<'EOF'

  ]
}
EOF

plutil -extract generatedAt raw -o - "$OUTPUT_JSON" >/dev/null
cat "$OUTPUT_JSON"
echo
echo "Actual bundle Accessibility probe written to: $OUTPUT_JSON"
