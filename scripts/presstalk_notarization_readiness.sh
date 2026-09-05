#!/usr/bin/env bash
# Checks an app bundle for the defects that make notarization fail, or that make
# a notarized build fail silently once installed. Runs without a Developer ID
# certificate, so it can gate every build rather than only release day.
#
# The two defects this exists for, both found on 2026-09-05:
#   1. The build shipped no entitlements at all. Apple requires
#      com.apple.security.device.audio-input for a hardened process to use the
#      microphone, and a hardened build without it can notarize and pass
#      Gatekeeper regardless -- the cost only shows up when a user with no prior
#      TCC grant tries to approve the microphone.
#   2. A Mach-O in Contents/Resources left linker-signed, because `codesign` on
#      the bundle hashes it as a resource instead of signing it as code.
#      `codesign --verify --deep --strict` passes; the notary service does not.
set -euo pipefail

APP_BUNDLE=""
REQUIRE_DEVELOPER_ID=0
REQUIRE_HARDENED=1
JSON_OUTPUT=""

usage() {
  cat <<'USAGE'
Usage: presstalk_notarization_readiness.sh --app <PressTalk.app> [options]

Options:
  --app <path>              App bundle to inspect (required)
  --require-developer-id    Also require Developer ID Application authority and a team identifier
  --allow-unhardened        Do not require the hardened runtime flag (local dev builds)
  --json-output <path>      Write a machine-readable result
  -h, --help                Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP_BUNDLE="${2:-}"; shift 2 ;;
    --require-developer-id) REQUIRE_DEVELOPER_ID=1; shift ;;
    --allow-unhardened) REQUIRE_HARDENED=0; shift ;;
    --json-output) JSON_OUTPUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$APP_BUNDLE" ]]; then
  echo "Missing --app" >&2
  usage >&2
  exit 2
fi
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Not an app bundle: $APP_BUNDLE" >&2
  exit 2
fi

FAILURES=()
CHECKS=()
WORK_PLIST="$(mktemp "${TMPDIR:-/tmp}/presstalk-entitlements.XXXXXX")"
trap 'rm -f "$WORK_PLIST"' EXIT

record() {
  # record <name> <ok|fail> <detail>
  CHECKS+=("$1|$2|$3")
  if [[ "$2" == "fail" ]]; then
    FAILURES+=("$1: $3")
    printf 'FAIL  %-34s %s\n' "$1" "$3"
  else
    printf 'ok    %-34s %s\n' "$1" "$3"
  fi
}

MAIN_BINARY="$APP_BUNDLE/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || echo jarvistap)"

# --- Info.plist ------------------------------------------------------------
plist_string() {
  /usr/libexec/PlistBuddy -c "Print $1" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
}

for key in NSMicrophoneUsageDescription NSInputMonitoringUsageDescription NSAccessibilityUsageDescription; do
  value="$(plist_string "$key")"
  if [[ -n "$value" ]]; then
    record "plist.$key" ok "present"
  else
    record "plist.$key" fail "missing; macOS will refuse the permission prompt"
  fi
done

for key in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion; do
  value="$(plist_string "$key")"
  if [[ -n "$value" ]]; then
    record "plist.$key" ok "$value"
  else
    record "plist.$key" fail "missing"
  fi
done

# --- Signature integrity ---------------------------------------------------
if codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
  record "codesign.verify" ok "valid on disk, deep and strict"
else
  record "codesign.verify" fail "codesign --verify --deep --strict rejected the bundle"
fi

# codesign writes its report to stderr. Capture it once per binary and parse the
# captured text; piping into `awk ... exit` closes the pipe early and kills the
# script with SIGPIPE under `set -o pipefail`.
codesign_report() {
  codesign -dv --verbose=4 "$1" 2>&1 || true
}
main_authority() {
  codesign_report "$1" | grep '^Authority=' | head -1 | cut -d= -f2- || true
}
main_flags() {
  codesign_report "$1" | grep -o 'flags=0x[0-9a-f]*([^)]*)' | head -1 || true
}
main_team() {
  codesign_report "$1" | grep '^TeamIdentifier=' | head -1 | cut -d= -f2- || true
}

EXPECTED_AUTHORITY="$(main_authority "$MAIN_BINARY")"
if [[ -z "$EXPECTED_AUTHORITY" ]]; then
  EXPECTED_AUTHORITY="(ad-hoc)"
fi
record "codesign.authority" ok "$EXPECTED_AUTHORITY"

# --- Every Mach-O, not just the main executable ----------------------------
# This is the check that the built-in tooling does not give you. A Mach-O under
# Contents/Resources is signed as a *resource* by a bundle-level codesign call,
# so it keeps whatever signature the compiler gave it.
MACHO_TOTAL=0
MACHO_BAD_FLAGS=()
MACHO_BAD_AUTHORITY=()

# Classify by file content, not by the executable bit. A dylib or a bundled
# binary shipped without +x is still code the notary service inspects, and
# filtering on permissions would walk straight past it.
while IFS= read -r candidate; do
  file "$candidate" 2>/dev/null | grep -q 'Mach-O' || continue
  MACHO_TOTAL=$((MACHO_TOTAL + 1))
  relative="${candidate#$APP_BUNDLE/}"

  flags="$(main_flags "$candidate")"
  if [[ "$REQUIRE_HARDENED" == "1" && "$flags" != *runtime* ]]; then
    MACHO_BAD_FLAGS+=("$relative [${flags:-unsigned}]")
  fi
  if [[ "$flags" == *linker-signed* ]]; then
    MACHO_BAD_FLAGS+=("$relative [linker-signed; never re-signed by the build]")
  fi

  authority="$(main_authority "$candidate")"
  authority="${authority:-(ad-hoc)}"
  if [[ "$authority" != "$EXPECTED_AUTHORITY" ]]; then
    MACHO_BAD_AUTHORITY+=("$relative signed by ${authority}")
  fi
done < <(find "$APP_BUNDLE" -type f)

record "macho.count" ok "$MACHO_TOTAL Mach-O binaries in the bundle"

if [[ ${#MACHO_BAD_FLAGS[@]} -eq 0 ]]; then
  record "macho.hardened_runtime" ok "every Mach-O carries the runtime flag"
else
  record "macho.hardened_runtime" fail "$(printf '%s; ' "${MACHO_BAD_FLAGS[@]}")"
fi

if [[ ${#MACHO_BAD_AUTHORITY[@]} -eq 0 ]]; then
  record "macho.single_authority" ok "every Mach-O shares the main authority"
else
  record "macho.single_authority" fail "$(printf '%s; ' "${MACHO_BAD_AUTHORITY[@]}")"
fi

# --- Entitlements ----------------------------------------------------------
ENTITLEMENTS_PLIST="$WORK_PLIST"
codesign -d --entitlements - --xml "$MAIN_BINARY" >"$ENTITLEMENTS_PLIST" 2>/dev/null || true

# Read the value, not just the key. `grep` for the entitlement name is satisfied
# by `<false/>`, which is the same as not having it.
audio_input_value=""
if [[ -s "$ENTITLEMENTS_PLIST" ]]; then
  audio_input_value="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.audio-input' \
    "$ENTITLEMENTS_PLIST" 2>/dev/null || true)"
fi

if [[ "$audio_input_value" == "true" ]]; then
  record "entitlements.audio_input" ok "com.apple.security.device.audio-input = true"
elif [[ -n "$audio_input_value" ]]; then
  record "entitlements.audio_input" fail \
    "com.apple.security.device.audio-input is present but set to ${audio_input_value}"
elif [[ "$REQUIRE_HARDENED" == "0" ]]; then
  record "entitlements.audio_input" ok "not required for an unhardened dev build"
else
  record "entitlements.audio_input" fail \
    "hardened runtime without com.apple.security.device.audio-input; Apple requires it for microphone access"
fi

# --- Developer ID specifics ------------------------------------------------
if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
  if [[ "$EXPECTED_AUTHORITY" == Developer\ ID\ Application* ]]; then
    record "developer_id.authority" ok "$EXPECTED_AUTHORITY"
  else
    record "developer_id.authority" fail "expected Developer ID Application authority, got ${EXPECTED_AUTHORITY}"
  fi

  team="$(main_team "$MAIN_BINARY")"
  if [[ -n "$team" && "$team" != "not set" ]]; then
    record "developer_id.team" ok "$team"
  else
    record "developer_id.team" fail "TeamIdentifier not set"
  fi

  # Notarization rejects signatures without a secure timestamp, and the local
  # build default is --timestamp=none, so this is easy to ship by accident.
  if codesign_report "$MAIN_BINARY" | grep -q '^Timestamp='; then
    record "developer_id.secure_timestamp" ok "signature carries a secure timestamp"
  else
    record "developer_id.secure_timestamp" fail \
      "no secure timestamp; sign with --timestamp (PRESSTALK_CODESIGN_TIMESTAMP=1)"
  fi

  if xcrun stapler validate "$APP_BUNDLE" >/dev/null 2>&1; then
    record "developer_id.stapled" ok "notarization ticket stapled"
  else
    record "developer_id.stapled" fail "no stapled notarization ticket"
  fi

  # spctl is the thing the user's Mac actually runs on first launch.
  if spctl --assess --type execute "$APP_BUNDLE" >/dev/null 2>&1; then
    record "developer_id.gatekeeper" ok "spctl accepts the bundle"
  else
    record "developer_id.gatekeeper" fail "spctl rejects the bundle"
  fi
fi

# --- Result ----------------------------------------------------------------
echo
if [[ -n "$JSON_OUTPUT" ]]; then
  mkdir -p "$(dirname "$JSON_OUTPUT")"
  {
    printf '{\n  "app": "%s",\n  "requireDeveloperId": %s,\n  "checks": [\n' \
      "$APP_BUNDLE" "$([[ "$REQUIRE_DEVELOPER_ID" == 1 ]] && echo true || echo false)"
    local_first=1
    for entry in "${CHECKS[@]}"; do
      name="${entry%%|*}"; rest="${entry#*|}"
      state="${rest%%|*}"; detail="${rest#*|}"
      detail="${detail//\\/\\\\}"; detail="${detail//\"/\\\"}"
      [[ $local_first == 1 ]] || printf ',\n'
      local_first=0
      printf '    {"name": "%s", "state": "%s", "detail": "%s"}' "$name" "$state" "$detail"
    done
    printf '\n  ],\n  "failures": %d,\n  "ready": %s\n}\n' \
      "${#FAILURES[@]}" "$([[ ${#FAILURES[@]} -eq 0 ]] && echo true || echo false)"
  } > "$JSON_OUTPUT"
  echo "Wrote $JSON_OUTPUT"
fi

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo "NOT READY: ${#FAILURES[@]} blocking problem(s)" >&2
  exit 1
fi
echo "READY"
