#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPPORT_DIR="$HOME/Library/Application Support/JarvisTap"
DIAGNOSTICS_DIR="$SUPPORT_DIR/Diagnostics"
if [[ -x "$SCRIPT_DIR/create-presstalk-local-codesign-identity.sh" ]]; then
  LOCAL_CODESIGN_HELPER="$SCRIPT_DIR/create-presstalk-local-codesign-identity.sh"
else
  LOCAL_CODESIGN_HELPER="$SCRIPT_DIR/create_presstalk_local_codesign_identity.sh"
fi
TIMESTAMP="$(date -u '+%Y-%m-%dT%H-%M-%SZ')"
OUTPUT_JSON="$DIAGNOSTICS_DIR/accessibility-identity-probe-$TIMESTAMP.json"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-ax-identity.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$DIAGNOSTICS_DIR"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Missing required command: swiftc" >&2
  exit 1
fi

HELPER_SOURCE="$TMP_DIR/presstalk-ax-probe.swift"
HELPER_BINARY="$TMP_DIR/presstalk-ax-probe"
cat >"$HELPER_SOURCE" <<'SWIFT'
import ApplicationServices
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("missing output path\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let promptOptions = [
    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(promptOptions)

let payload: [String: Any] = [
    "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
    "bundlePath": Bundle.main.bundleURL.path,
    "executablePath": Bundle.main.executableURL?.path ?? "unknown",
    "processID": ProcessInfo.processInfo.processIdentifier,
    "accessibilityTrusted": trusted,
    "promptRequested": false,
]

do {
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: outputURL, options: .atomic)
} catch {
    fputs("write failed: \(error)\n", stderr)
    exit(1)
}
SWIFT

swiftc "$HELPER_SOURCE" -o "$HELPER_BINARY"

stable_identity() {
  if [[ -n "${PRESSTALK_CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "$PRESSTALK_CODESIGN_IDENTITY"
    return 0
  fi
  if [[ -x "$LOCAL_CODESIGN_HELPER" ]]; then
    local output
    output="$("$LOCAL_CODESIGN_HELPER" 2>/dev/null || true)"
    printf '%s\n' "$output" | awk '/^Hash: / { print $2; exit }'
  fi
}

SIGNING_IDENTITY="$(stable_identity || true)"

candidate_ids="${PRESSTALK_ACCESSIBILITY_PROBE_BUNDLE_IDS:-com.am.jarvistap com.am.presstalk}"
signing_modes="${PRESSTALK_ACCESSIBILITY_PROBE_SIGNING_MODES:-stable adhoc}"

json_string() {
  local escaped
  escaped="$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '"%s"' "$escaped"
}

append_result() {
  local first="$1"
  local bundle_id="$2"
  local signing="$3"
  local status="$4"
  local app_path="$5"
  local result_path="$6"
  local ax_trusted="$7"
  local sign_identifier="$8"
  local sign_cdhash="$9"
  local sign_authority="${10}"

  if [[ "$first" == "0" ]]; then
    printf ',\n' >>"$OUTPUT_JSON"
  fi
  {
    printf '    {\n'
    printf '      "bundleIdentifier": %s,\n' "$(json_string "$bundle_id")"
    printf '      "signing": %s,\n' "$(json_string "$signing")"
    printf '      "status": %s,\n' "$(json_string "$status")"
    printf '      "appPath": %s,\n' "$(json_string "$app_path")"
    printf '      "resultPath": %s,\n' "$(json_string "$result_path")"
    printf '      "accessibilityTrusted": %s,\n' "$ax_trusted"
    printf '      "codeSignatureIdentifier": %s,\n' "$(json_string "$sign_identifier")"
    printf '      "codeSignatureCDHash": %s,\n' "$(json_string "$sign_cdhash")"
    printf '      "codeSignatureAuthority": %s\n' "$(json_string "$sign_authority")"
    printf '    }'
  } >>"$OUTPUT_JSON"
}

codesign_value() {
  local path="$1"
  local key="$2"
  codesign -dv --verbose=4 "$path" 2>&1 |
    awk -F= -v key="$key" '$1 == key { value = $2 } END { print value }'
}

cat >"$OUTPUT_JSON" <<EOF
{
  "generatedAt": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "promptRequested": false,
  "installedAppBundleIdentifier": "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HOME/Applications/PressTalk.app/Contents/Info.plist" 2>/dev/null || true)",
  "installedAppPath": "$HOME/Applications/PressTalk.app",
  "candidates": [
EOF

first=1
for bundle_id in $candidate_ids; do
  for signing in $signing_modes; do
    if [[ "$signing" == "stable" && -z "$SIGNING_IDENTITY" ]]; then
      append_result "$first" "$bundle_id" "$signing" "skipped_no_stable_identity" "" "" "false" "" "" ""
      first=0
      continue
    fi

    safe_name="$(printf '%s-%s' "$bundle_id" "$signing" | tr -c 'A-Za-z0-9._-' '_')"
    app_path="$TMP_DIR/$safe_name/PressTalkAccessibilityProbe.app"
    contents="$app_path/Contents"
    macos="$contents/MacOS"
    result_path="$DIAGNOSTICS_DIR/accessibility-identity-$safe_name-$TIMESTAMP.json"
    mkdir -p "$macos"
    cp "$HELPER_BINARY" "$macos/presstalk-ax-probe"
    chmod 755 "$macos/presstalk-ax-probe"
    cat >"$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>PressTalk Accessibility Probe</string>
  <key>CFBundleExecutable</key>
  <string>presstalk-ax-probe</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>PressTalkAccessibilityProbe</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.5</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAccessibilityUsageDescription</key>
  <string>PressTalk checks whether this exact signing identity is trusted for insertion.</string>
</dict>
</plist>
PLIST

    if [[ "$signing" == "stable" ]]; then
      sign_arg="$SIGNING_IDENTITY"
    else
      sign_arg="-"
    fi
    codesign --force --sign "$sign_arg" --timestamp=none --identifier "$bundle_id" "$macos/presstalk-ax-probe" >/dev/null 2>&1
    codesign --force --sign "$sign_arg" --timestamp=none "$app_path" >/dev/null 2>&1

    if /usr/bin/open -gjW "$app_path" --args "$result_path" >/dev/null 2>&1 && [[ -f "$result_path" ]]; then
      ax_trusted="$(plutil -extract accessibilityTrusted raw -o - "$result_path" 2>/dev/null || echo false)"
      status="ran"
    else
      ax_trusted=false
      status="launch_or_result_failed"
    fi

    append_result \
      "$first" \
      "$bundle_id" \
      "$signing" \
      "$status" \
      "$app_path" \
      "$result_path" \
      "$ax_trusted" \
      "$(codesign_value "$app_path" Identifier)" \
      "$(codesign_value "$app_path" CDHash)" \
      "$(codesign_value "$app_path" Authority)"
    first=0
  done
done

cat >>"$OUTPUT_JSON" <<'EOF'

  ]
}
EOF

plutil -extract generatedAt raw -o - "$OUTPUT_JSON" >/dev/null
cat "$OUTPUT_JSON"
echo
echo "Accessibility identity probe written to: $OUTPUT_JSON"
