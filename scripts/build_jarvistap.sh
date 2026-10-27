#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT"
OUT_DIR="$PKG_DIR/bin"
OUT_BIN="$OUT_DIR/jarvistap"
truthy() { case "${1:-}" in 1|true|TRUE|yes|YES) return 0 ;; *) return 1 ;; esac; }
DISTRIBUTION_SIGNING="${PRESSTALK_DISTRIBUTION_SIGNING:-0}"
if truthy "$DISTRIBUTION_SIGNING"; then
  DEFAULT_APP_BUNDLE="$ROOT/dist/PressTalk.app"
  DEFAULT_BUNDLE_IDENTIFIER="com.am.presstalk"
  APP_DISPLAY_NAME="PressTalk"
  APP_URL_SCHEME="presstalk"
  APP_LICENSE_EXTENSION="presstalk-license"
else
  DEFAULT_APP_BUNDLE="$HOME/Applications/PressTalk Dev.app"
  DEFAULT_BUNDLE_IDENTIFIER="com.am.presstalk.dev"
  APP_DISPLAY_NAME="PressTalk Dev"
  APP_URL_SCHEME="presstalk-dev"
  APP_LICENSE_EXTENSION="presstalk-dev-license"
fi
APP_BUNDLE="${PRESSTALK_APP_BUNDLE:-$DEFAULT_APP_BUNDLE}"
set_app_paths() {
  APP_CONTENTS_DIR="$APP_BUNDLE/Contents"
  APP_MACOS_DIR="$APP_CONTENTS_DIR/MacOS"
  APP_RESOURCES_DIR="$APP_CONTENTS_DIR/Resources"
  APP_INFO_PLIST="$APP_CONTENTS_DIR/Info.plist"
}
set_app_paths
LOCAL_CODESIGN_HELPER="$PKG_DIR/scripts/create_presstalk_local_codesign_identity.sh"
ENTITLEMENTS_PLIST="${PRESSTALK_ENTITLEMENTS:-$PKG_DIR/resources/PressTalk.entitlements}"
# Developer probes and smoke helpers are useful locally and are a liability in a
# shipped app: the compiled smoke binary is a second Mach-O that the notary
# service checks, and the signing-repair helpers exist to re-sign the app, which
# would throw away a stapled notarization ticket. Distribution packaging sets
# this to 0.
INCLUDE_DEV_TOOLS="${PRESSTALK_INCLUDE_DEV_TOOLS:-1}"
if truthy "$DISTRIBUTION_SIGNING"; then INCLUDE_DEV_TOOLS=0; fi

include_dev_tools() {
  case "$INCLUDE_DEV_TOOLS" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

current_bundle_identifier() {
  if [[ -f "$APP_INFO_PLIST" ]]; then
    /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_INFO_PLIST" 2>/dev/null || true
  fi
}

APP_BUNDLE_IDENTIFIER="${PRESSTALK_BUNDLE_IDENTIFIER:-${PRESSTALK_APP_BUNDLE_IDENTIFIER:-$DEFAULT_BUNDLE_IDENTIFIER}}"
APP_VERSION="${PRESSTALK_VERSION:-0.1.5}"
APP_BUILD="${PRESSTALK_BUILD_NUMBER:-6}"

if [[ ! "$APP_BUNDLE_IDENTIFIER" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+$ ]]; then
  echo "Invalid PRESSTALK_BUNDLE_IDENTIFIER: $APP_BUNDLE_IDENTIFIER" >&2
  exit 2
fi

if [[ -z "$APP_VERSION" ]]; then
  echo "Invalid PRESSTALK_VERSION: must not be empty" >&2
  exit 2
fi

if [[ -z "$APP_BUILD" ]]; then
  echo "Invalid PRESSTALK_BUILD_NUMBER: must not be empty" >&2
  exit 2
fi

# Reserve the customer identity for explicit distribution builds. Never infer
# it from an existing app: that used to re-sign the daily app with a local
# certificate and leave a checked but unusable macOS permission entry behind.
if truthy "$DISTRIBUTION_SIGNING"; then
  if [[ "$APP_BUNDLE_IDENTIFIER" != "com.am.presstalk" ]]; then
    echo "Distribution builds require the official com.am.presstalk identity." >&2
    exit 2
  fi
  requested_identity="${PRESSTALK_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}"
  if [[ -z "$requested_identity" || "$requested_identity" == "-" ]]; then
    echo "Distribution builds require an explicit Developer ID Application signing identity." >&2
    exit 2
  fi
  identity_search_args=(find-identity -v -p codesigning)
  if [[ -n "${PRESSTALK_CODESIGN_KEYCHAIN:-}" ]]; then identity_search_args+=("$PRESSTALK_CODESIGN_KEYCHAIN"); fi
  identities="$(security "${identity_search_args[@]}" 2>/dev/null)" || {
    echo "Cannot verify the requested Developer ID signing identity." >&2; exit 2;
  }
  selected_identity=""
  identity_matches=0
  while IFS= read -r identity_line; do
    [[ "$identity_line" == *'"Developer ID Application:'*' (5HUC5LA94B)"'* ]] || continue
    identity_hash="$(printf '%s\n' "$identity_line" | awk '{print $2}')"
    identity_name="$(printf '%s\n' "$identity_line" | sed -E 's/^[^"]*"([^"]+)".*$/\1/')"
    if [[ "$requested_identity" == "$identity_hash" || "$requested_identity" == "$identity_name" ||
          "$requested_identity" == "Developer ID Application" ]]; then
      selected_identity="$identity_hash"
      identity_matches=$((identity_matches + 1))
    fi
  done <<<"$identities"
  if [[ "$identity_matches" != "1" ]]; then
    echo "Choose exactly one valid Developer ID Application identity for PressTalk team 5HUC5LA94B." >&2
    exit 2
  fi
  export PRESSTALK_CODESIGN_IDENTITY="$selected_identity"
  export PRESSTALK_CODESIGN_HARDENED_RUNTIME=1
  export PRESSTALK_CODESIGN_TIMESTAMP=1
elif [[ "$APP_BUNDLE_IDENTIFIER" != *.dev ]]; then
  echo "Development builds require a distinct .dev bundle identifier; production identity is distribution-only." >&2
  exit 2
fi

TARGET_APP_BUNDLE="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$APP_BUNDLE")"
PRODUCTION_USER_APP="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$HOME/Applications/PressTalk.app")"
if [[ "$TARGET_APP_BUNDLE" != *.app || "$TARGET_APP_BUNDLE" == "$PRODUCTION_USER_APP" ||
      "$TARGET_APP_BUNDLE" == "/Applications/PressTalk.app" ]]; then
  echo "Refusing to build over the daily PressTalk app. Build a development app or a staged distribution artifact." >&2
  exit 2
fi
existing_identifier="$(current_bundle_identifier)"
if [[ "$existing_identifier" == "com.am.presstalk" ]]; then
  echo "Refusing to overwrite an existing production app. Choose an empty staging destination." >&2
  exit 2
fi
if truthy "${PRESSTALK_BUILD_PLAN_ONLY:-0}"; then
  printf 'App: %s\nBundleIdentifier: %s\nDistributionSigning: %s\n' \
    "$TARGET_APP_BUNDLE" "$APP_BUNDLE_IDENTIFIER" "$DISTRIBUTION_SIGNING"
  exit 0
fi

pushd "$PKG_DIR" >/dev/null
if truthy "${PRESSTALK_BUILD_CLEAN:-0}"; then swift package clean; fi
swift build -c release --product jarvistap
BINARY_DIR="$(swift build -c release --show-bin-path)"
popd >/dev/null

BUILD_STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-build.XXXXXX")"
trap 'rm -rf "$BUILD_STAGING_ROOT"' EXIT
APP_BUNDLE="$BUILD_STAGING_ROOT/$(basename "$TARGET_APP_BUNDLE")"
set_app_paths
mkdir -p "$OUT_DIR"
cp "$BINARY_DIR/jarvistap" "$OUT_BIN"
chmod 755 "$OUT_BIN"

mkdir -p "$APP_MACOS_DIR"
mkdir -p "$APP_RESOURCES_DIR"
cp "$BINARY_DIR/jarvistap" "$APP_MACOS_DIR/jarvistap"
chmod 755 "$APP_MACOS_DIR/jarvistap"
cp "$PKG_DIR/resources/PressTalk.icns" "$APP_RESOURCES_DIR/PressTalk.icns"
cp "$PKG_DIR/scripts/presstalk_bootstrap.sh" "$APP_RESOURCES_DIR/presstalk-bootstrap.sh"
chmod 755 "$APP_RESOURCES_DIR/presstalk-bootstrap.sh"
cp "$PKG_DIR/scripts/presstalk_disable_system_dictation.sh" "$APP_RESOURCES_DIR/presstalk-disable-system-dictation.sh"
chmod 755 "$APP_RESOURCES_DIR/presstalk-disable-system-dictation.sh"
cp "$PKG_DIR/scripts/presstalk_karabiner_fallback.sh" "$APP_RESOURCES_DIR/presstalk-karabiner-fallback.sh"
chmod 755 "$APP_RESOURCES_DIR/presstalk-karabiner-fallback.sh"
# SwiftPM emits target resources as a side-by-side .bundle. Without copying it
# the app runs with Bundle.module empty -- which for the German vocabulary guard
# list means the corrector loses its safety net. Copy every resource bundle the
# build produced.
for _resource_bundle in "$PKG_DIR"/.build/*/release/*.bundle "$PKG_DIR"/.build/release/*.bundle; do
  [[ -d "$_resource_bundle" ]] || continue
  echo "Bundling resources: $(basename "$_resource_bundle")"
  rm -rf "$APP_RESOURCES_DIR/$(basename "$_resource_bundle")"
  ditto "$_resource_bundle" "$APP_RESOURCES_DIR/$(basename "$_resource_bundle")"
done

cp "$PKG_DIR/scripts/presstalk_accessibility_handoff.sh" "$APP_RESOURCES_DIR/presstalk-accessibility-handoff.sh"
chmod 755 "$APP_RESOURCES_DIR/presstalk-accessibility-handoff.sh"
cp "$PKG_DIR/scripts/presstalk_machine_readiness.sh" "$APP_RESOURCES_DIR/presstalk-machine-readiness.sh"
chmod 755 "$APP_RESOURCES_DIR/presstalk-machine-readiness.sh"

if include_dev_tools; then
  cp "$PKG_DIR/scripts/create_presstalk_local_codesign_identity.sh" "$APP_RESOURCES_DIR/create-presstalk-local-codesign-identity.sh"
  chmod 755 "$APP_RESOURCES_DIR/create-presstalk-local-codesign-identity.sh"
  cp "$PKG_DIR/scripts/presstalk_repair_local_signing.sh" "$APP_RESOURCES_DIR/presstalk-repair-local-signing.sh"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-repair-local-signing.sh"
  cp "$PKG_DIR/scripts/presstalk_collect_smoke_status.sh" "$APP_RESOURCES_DIR/presstalk-collect-smoke-status.sh"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-collect-smoke-status.sh"
  cp "$PKG_DIR/scripts/presstalk_collect_real_field_smoke.sh" "$APP_RESOURCES_DIR/presstalk-collect-real-field-smoke.sh"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-collect-real-field-smoke.sh"
  cp "$PKG_DIR/scripts/presstalk_readiness_matrix.sh" "$APP_RESOURCES_DIR/presstalk-readiness-matrix.sh"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-readiness-matrix.sh"
  cp "$PKG_DIR/scripts/presstalk_host_discovery.sh" "$APP_RESOURCES_DIR/presstalk-host-discovery.sh"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-host-discovery.sh"
  cp "$PKG_DIR/scripts/presstalk_release_proof_gate.sh" "$APP_RESOURCES_DIR/presstalk-release-proof-gate.sh"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-release-proof-gate.sh"
  cp "$PKG_DIR/scripts/presstalk_verify_repair_result.sh" "$APP_RESOURCES_DIR/presstalk-verify-repair-result.sh"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-verify-repair-result.sh"
  cp "$PKG_DIR/scripts/presstalk_accessibility_identity_probe.sh" "$APP_RESOURCES_DIR/presstalk-accessibility-identity-probe.sh"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-accessibility-identity-probe.sh"
  cp "$PKG_DIR/scripts/presstalk_actual_accessibility_probe.sh" "$APP_RESOURCES_DIR/presstalk-actual-accessibility-probe.sh"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-actual-accessibility-probe.sh"
  cp "$PKG_DIR/scripts/presstalk_manual_fn_smoke.swift" "$APP_RESOURCES_DIR/presstalk-manual-fn-smoke.swift"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-manual-fn-smoke.swift"
  swiftc "$PKG_DIR/scripts/presstalk_manual_fn_smoke.swift" -o "$APP_RESOURCES_DIR/presstalk-manual-fn-smoke"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-manual-fn-smoke"
  cp "$PKG_DIR/scripts/presstalk_automated_f5_smoke.swift" "$APP_RESOURCES_DIR/presstalk-automated-f5-smoke.swift"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-automated-f5-smoke.swift"
  cp "$PKG_DIR/scripts/presstalk_production_insertion_probe.swift" "$APP_RESOURCES_DIR/presstalk-production-insertion-probe.swift"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-production-insertion-probe.swift"
  cp "$PKG_DIR/scripts/presstalk_run_production_insertion_probe.sh" "$APP_RESOURCES_DIR/presstalk-run-production-insertion-probe.sh"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-run-production-insertion-probe.sh"
  cp "$PKG_DIR/scripts/presstalk_input_method_insert_probe.sh" "$APP_RESOURCES_DIR/presstalk-input-method-insert-probe.sh"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-input-method-insert-probe.sh"
  cp "$PKG_DIR/scripts/presstalk_input_method_status.swift" "$APP_RESOURCES_DIR/presstalk-input-method-status.swift"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-input-method-status.swift"
  cp "$PKG_DIR/scripts/presstalk_input_method_client_probe.swift" "$APP_RESOURCES_DIR/presstalk-input-method-client-probe.swift"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-input-method-client-probe.swift"
  cp "$PKG_DIR/scripts/presstalk_unicode_event_insert_probe.swift" "$APP_RESOURCES_DIR/presstalk-unicode-event-insert-probe.swift"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-unicode-event-insert-probe.swift"
  cp "$PKG_DIR/scripts/presstalk_virtual_hid_paste_probe.swift" "$APP_RESOURCES_DIR/presstalk-virtual-hid-paste-probe.swift"
  chmod 755 "$APP_RESOURCES_DIR/presstalk-virtual-hid-paste-probe.swift"
else
  echo "Developer probes and smoke helpers: excluded (PRESSTALK_INCLUDE_DEV_TOOLS=$INCLUDE_DEV_TOOLS)"
fi
cp "$PKG_DIR/scripts/presstalk_install_input_method.sh" "$APP_RESOURCES_DIR/presstalk-install-input-method.sh"
chmod 755 "$APP_RESOURCES_DIR/presstalk-install-input-method.sh"
bash "$PKG_DIR/scripts/build_presstalk_input_method.sh" \
  --app-bundle "$APP_RESOURCES_DIR/PressTalkInputMethod.app" >/dev/null

cat >"$APP_INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>jarvistap</string>
  <key>CFBundleIdentifier</key>
  <string>$APP_BUNDLE_IDENTIFIER</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>PressTalk.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSUIElement</key>
  <true/>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>$APP_BUNDLE_IDENTIFIER.activation</string>
    <key>CFBundleURLSchemes</key><array><string>$APP_URL_SCHEME</string></array>
    <key>CFBundleTypeRole</key><string>Viewer</string>
  </dict></array>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>PressTalk Licence</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Owner</string>
    <key>LSItemContentTypes</key><array><string>$APP_BUNDLE_IDENTIFIER.license</string></array>
  </dict></array>
  <key>UTExportedTypeDeclarations</key>
  <array><dict>
    <key>UTTypeIdentifier</key><string>$APP_BUNDLE_IDENTIFIER.license</string>
    <key>UTTypeDescription</key><string>PressTalk Licence</string>
    <key>UTTypeConformsTo</key><array><string>public.plain-text</string></array>
    <key>UTTypeTagSpecification</key><dict>
      <key>public.filename-extension</key><array><string>$APP_LICENSE_EXTENSION</string></array>
    </dict>
  </dict></array>
  <key>NSMicrophoneUsageDescription</key>
  <string>PressTalk needs microphone access to capture your voice commands.</string>
  <key>NSAccessibilityUsageDescription</key>
  <string>PressTalk needs accessibility access to paste transcribed text into the focused app.</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>PressTalk needs input monitoring access to detect the push-to-talk trigger key.</string>
</dict>
</plist>
PLIST

swift "$PKG_DIR/scripts/presstalk_bundle_icon_gate.swift" "$APP_BUNDLE"

resolve_signing_identity() {
  if [[ -n "${PRESSTALK_CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "$PRESSTALK_CODESIGN_IDENTITY"
    return
  fi
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "$CODESIGN_IDENTITY"
    return
  fi

  local stable_mode require_stable output identity_hash
  stable_mode="${PRESSTALK_BUILD_STABLE_SIGNING:-1}"
  require_stable="${PRESSTALK_BUILD_REQUIRE_STABLE_SIGNING:-0}"
  case "$stable_mode" in
    1|true|TRUE|yes|YES)
      if [[ -x "$LOCAL_CODESIGN_HELPER" ]]; then
        if output="$("$LOCAL_CODESIGN_HELPER" 2>&1)"; then
          identity_hash="$(printf '%s\n' "$output" | awk '/^Hash: / { print $2; exit }')"
          if [[ -n "$identity_hash" ]]; then
            printf '%s' "$identity_hash"
            return
          fi
          printf '%s\n' "$output" >&2
          printf '%s\n' "Stable local signing skipped: helper did not report an identity hash." >&2
        else
          printf '%s\n' "$output" >&2
          printf '%s\n' "Stable local signing skipped: could not prepare local code-signing identity." >&2
        fi
      else
        printf '%s\n' "Stable local signing skipped: helper missing at $LOCAL_CODESIGN_HELPER." >&2
      fi
      if [[ "$require_stable" == "1" || "$require_stable" == "true" || "$require_stable" == "TRUE" ||
            "$require_stable" == "yes" || "$require_stable" == "YES" ]]; then
        printf '%s\n' "Stable local signing is required; refusing to build an ad-hoc PressTalk.app." >&2
        return 1
      fi
      ;;
    existing)
      if [[ ! -x "$LOCAL_CODESIGN_HELPER" ]]; then
        printf '%s\n' "Stable local signing required: helper missing at $LOCAL_CODESIGN_HELPER." >&2
        return 1
      fi
      if output="$(PRESSTALK_LOCAL_CODESIGN_EXISTING_ONLY=1 "$LOCAL_CODESIGN_HELPER" 2>&1)"; then
        identity_hash="$(printf '%s\n' "$output" | awk '/^Hash: / { print $2; exit }')"
        if [[ -n "$identity_hash" ]]; then
          printf '%s' "$identity_hash"
          return
        fi
        printf '%s\n' "$output" >&2
        printf '%s\n' "Stable local signing required: existing identity check did not report an identity hash." >&2
      else
        printf '%s\n' "$output" >&2
        printf '%s\n' "Stable local signing required: no existing trusted PressTalk identity is available without a trust prompt." >&2
      fi
      return 1
      ;;
    0|false|FALSE|no|NO|none|NONE)
      ;;
    *)
      printf '%s\n' "Invalid PRESSTALK_BUILD_STABLE_SIGNING=$stable_mode; expected 1, 0, or existing." >&2
      return 2
      ;;
  esac
  printf '%s' "-"
}

SIGN_IDENTITY="$(resolve_signing_identity)"
SIGN_KEYCHAIN="${PRESSTALK_CODESIGN_KEYCHAIN:-}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Code signing: ad-hoc"
else
  echo "Code signing identity: $SIGN_IDENTITY"
  if [[ -n "$SIGN_KEYCHAIN" ]]; then
    echo "Code signing keychain: $SIGN_KEYCHAIN"
  fi
fi

codesign_args=(--force --sign "$SIGN_IDENTITY")
if [[ -n "$SIGN_KEYCHAIN" ]]; then
  codesign_args+=(--keychain "$SIGN_KEYCHAIN")
fi
TIMESTAMP_MODE="${PRESSTALK_CODESIGN_TIMESTAMP:-none}"
TIMESTAMP_MODE_NORMALIZED="$(printf '%s' "$TIMESTAMP_MODE" | tr '[:upper:]' '[:lower:]')"
case "$TIMESTAMP_MODE_NORMALIZED" in
  1|true|yes)
    codesign_args+=(--timestamp)
    ;;
  ""|0|false|no|none)
    codesign_args+=(--timestamp=none)
    ;;
  *)
    codesign_args+=(--timestamp="$TIMESTAMP_MODE")
    ;;
esac
HARDENED_RUNTIME="${PRESSTALK_CODESIGN_HARDENED_RUNTIME:-0}"
if [[ "$HARDENED_RUNTIME" == "1" ]]; then
  codesign_args+=(--options runtime)
fi

# A hardened process is denied microphone input unless it carries
# com.apple.security.device.audio-input, and the denial is silent: the
# authorization status still reads .authorized while the input tap delivers zero
# frames. Sign with the entitlements in every mode so a local build exercises
# the same signature shape the release build ships.
if [[ ! -f "$ENTITLEMENTS_PLIST" ]]; then
  echo "Missing entitlements plist: $ENTITLEMENTS_PLIST" >&2
  exit 1
fi
codesign_args+=(--entitlements "$ENTITLEMENTS_PLIST")

# codesign on a bundle hashes a Mach-O under Contents/Resources as a *resource*
# rather than signing it as code, so anything compiled into Resources keeps its
# linker-signed signature. `codesign --verify --deep --strict` accepts that; the
# notary service rejects it. Sign every Mach-O in the bundle inside-out.
sign_nested_machos() {
  local found=0
  while IFS= read -r candidate; do
    file "$candidate" 2>/dev/null | grep -q 'Mach-O' || continue
    [[ "$candidate" == "$APP_MACOS_DIR/jarvistap" ]] && continue
    # The nested input method app signs itself in its own build script.
    [[ "$candidate" == *"/PressTalkInputMethod.app/"* ]] && continue
    echo "Signing nested Mach-O: ${candidate#$APP_BUNDLE/}"
    codesign "${codesign_args[@]}" "$candidate"
    found=$((found + 1))
  done < <(find "$APP_BUNDLE" -type f -perm +111)
  echo "Nested Mach-O binaries signed: $found"
}

sign_nested_machos
codesign "${codesign_args[@]}" --identifier "$APP_BUNDLE_IDENTIFIER" "$APP_MACOS_DIR/jarvistap"
codesign "${codesign_args[@]}" "$APP_BUNDLE"

codesign --verify --deep --strict "$APP_BUNDLE"
if truthy "$DISTRIBUTION_SIGNING"; then
  signature_report="$(codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1)"
  if [[ "$signature_report" != *"Authority=Developer ID Application:"* ||
        "$signature_report" != *"TeamIdentifier=5HUC5LA94B"* ]]; then
    echo "Built app did not retain PressTalk's production signing identity; destination is untouched." >&2
    exit 1
  fi
fi

# Install only the fully built and verified artifact. Keep any earlier dev
# build instead of destroying it before compilation or signing can fail.
mkdir -p "$(dirname "$TARGET_APP_BUNDLE")"
PREVIOUS_APP=""
if [[ -e "$TARGET_APP_BUNDLE" ]]; then
  final_existing_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$TARGET_APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$final_existing_id" == "com.am.presstalk" ]]; then
    echo "Destination became a production app during the build; refusing to replace it." >&2
    exit 2
  fi
  PREVIOUS_APP="$TARGET_APP_BUNDLE.previous-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  mv "$TARGET_APP_BUNDLE" "$PREVIOUS_APP"
fi
if ! mv "$APP_BUNDLE" "$TARGET_APP_BUNDLE"; then
  if [[ -n "$PREVIOUS_APP" && ! -e "$TARGET_APP_BUNDLE" ]]; then mv "$PREVIOUS_APP" "$TARGET_APP_BUNDLE"; fi
  echo "Could not move the staged app into place; previous build preserved at $PREVIOUS_APP." >&2
  exit 1
fi

echo "Built: $OUT_BIN"
echo "App:   $TARGET_APP_BUNDLE"
echo "Bundle identifier: $APP_BUNDLE_IDENTIFIER"
