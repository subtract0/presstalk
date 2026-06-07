#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT"
OUT_DIR="$PKG_DIR/bin"
OUT_BIN="$OUT_DIR/jarvistap"
APP_BUNDLE="$HOME/Applications/PressTalk.app"
LEGACY_APP_BUNDLE="$HOME/Applications/JarvisTap.app"
APP_CONTENTS_DIR="$APP_BUNDLE/Contents"
APP_MACOS_DIR="$APP_CONTENTS_DIR/MacOS"
APP_RESOURCES_DIR="$APP_CONTENTS_DIR/Resources"
APP_INFO_PLIST="$APP_CONTENTS_DIR/Info.plist"
LOCAL_CODESIGN_HELPER="$PKG_DIR/scripts/create_presstalk_local_codesign_identity.sh"

current_bundle_identifier() {
  if [[ -f "$APP_INFO_PLIST" ]]; then
    /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_INFO_PLIST" 2>/dev/null || true
  fi
}

DEFAULT_BUNDLE_IDENTIFIER="$(current_bundle_identifier)"
DEFAULT_BUNDLE_IDENTIFIER="${DEFAULT_BUNDLE_IDENTIFIER:-com.am.presstalk}"
APP_BUNDLE_IDENTIFIER="${PRESSTALK_BUNDLE_IDENTIFIER:-${PRESSTALK_APP_BUNDLE_IDENTIFIER:-$DEFAULT_BUNDLE_IDENTIFIER}}"

if [[ ! "$APP_BUNDLE_IDENTIFIER" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+$ ]]; then
  echo "Invalid PRESSTALK_BUNDLE_IDENTIFIER: $APP_BUNDLE_IDENTIFIER" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
rm -rf "$APP_BUNDLE"

pushd "$PKG_DIR" >/dev/null
swift package clean
swift build -c release
BINARY_DIR="$(swift build -c release --show-bin-path)"
popd >/dev/null

cp "$BINARY_DIR/jarvistap" "$OUT_BIN"
chmod 755 "$OUT_BIN"

mkdir -p "$APP_MACOS_DIR"
mkdir -p "$APP_RESOURCES_DIR"
cp "$BINARY_DIR/jarvistap" "$APP_MACOS_DIR/jarvistap"
chmod 755 "$APP_MACOS_DIR/jarvistap"
cp "$PKG_DIR/scripts/presstalk_bootstrap.sh" "$APP_RESOURCES_DIR/presstalk-bootstrap.sh"
chmod 755 "$APP_RESOURCES_DIR/presstalk-bootstrap.sh"
cp "$PKG_DIR/scripts/presstalk_disable_system_dictation.sh" "$APP_RESOURCES_DIR/presstalk-disable-system-dictation.sh"
chmod 755 "$APP_RESOURCES_DIR/presstalk-disable-system-dictation.sh"
cp "$PKG_DIR/scripts/presstalk_karabiner_fallback.sh" "$APP_RESOURCES_DIR/presstalk-karabiner-fallback.sh"
chmod 755 "$APP_RESOURCES_DIR/presstalk-karabiner-fallback.sh"
cp "$PKG_DIR/scripts/create_presstalk_local_codesign_identity.sh" "$APP_RESOURCES_DIR/create-presstalk-local-codesign-identity.sh"
chmod 755 "$APP_RESOURCES_DIR/create-presstalk-local-codesign-identity.sh"
cp "$PKG_DIR/scripts/presstalk_repair_local_signing.sh" "$APP_RESOURCES_DIR/presstalk-repair-local-signing.sh"
chmod 755 "$APP_RESOURCES_DIR/presstalk-repair-local-signing.sh"
cp "$PKG_DIR/scripts/presstalk_collect_smoke_status.sh" "$APP_RESOURCES_DIR/presstalk-collect-smoke-status.sh"
chmod 755 "$APP_RESOURCES_DIR/presstalk-collect-smoke-status.sh"
cp "$PKG_DIR/scripts/presstalk_accessibility_identity_probe.sh" "$APP_RESOURCES_DIR/presstalk-accessibility-identity-probe.sh"
chmod 755 "$APP_RESOURCES_DIR/presstalk-accessibility-identity-probe.sh"
cp "$PKG_DIR/scripts/presstalk_actual_accessibility_probe.sh" "$APP_RESOURCES_DIR/presstalk-actual-accessibility-probe.sh"
chmod 755 "$APP_RESOURCES_DIR/presstalk-actual-accessibility-probe.sh"
cp "$PKG_DIR/scripts/presstalk_manual_fn_smoke.swift" "$APP_RESOURCES_DIR/presstalk-manual-fn-smoke.swift"
chmod 755 "$APP_RESOURCES_DIR/presstalk-manual-fn-smoke.swift"
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
  <string>PressTalk</string>
  <key>CFBundleExecutable</key>
  <string>jarvistap</string>
  <key>CFBundleIdentifier</key>
  <string>$APP_BUNDLE_IDENTIFIER</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>PressTalk</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.5</string>
  <key>CFBundleVersion</key>
  <string>6</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>PressTalk needs microphone access to capture your voice commands.</string>
  <key>NSAccessibilityUsageDescription</key>
  <string>PressTalk needs accessibility access to paste transcribed text into the focused app.</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>PressTalk needs input monitoring access to detect the push-to-talk trigger key.</string>
</dict>
</plist>
PLIST

resolve_signing_identity() {
  if [[ -n "${PRESSTALK_CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "$PRESSTALK_CODESIGN_IDENTITY"
    return
  fi
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "$CODESIGN_IDENTITY"
    return
  fi
  if [[ "${PRESSTALK_BUILD_STABLE_SIGNING:-1}" == "1" && -x "$LOCAL_CODESIGN_HELPER" ]]; then
    local output identity_hash
    if output="$("$LOCAL_CODESIGN_HELPER" 2>&1)"; then
      identity_hash="$(printf '%s\n' "$output" | awk '/^Hash: / { print $2; exit }')"
      if [[ -n "$identity_hash" ]]; then
        printf '%s' "$identity_hash"
        return
      fi
    else
      printf '%s\n' "$output" >&2
      printf '%s\n' "Stable local signing skipped: could not prepare local code-signing identity." >&2
    fi
  fi
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

codesign_args=(--force --sign "$SIGN_IDENTITY" --timestamp=none)
if [[ -n "$SIGN_KEYCHAIN" ]]; then
  codesign_args+=(--keychain "$SIGN_KEYCHAIN")
fi

codesign "${codesign_args[@]}" --identifier "$APP_BUNDLE_IDENTIFIER" "$APP_MACOS_DIR/jarvistap"
codesign "${codesign_args[@]}" "$APP_BUNDLE"

if [[ -d "$LEGACY_APP_BUNDLE" && "$LEGACY_APP_BUNDLE" != "$APP_BUNDLE" ]]; then
  rm -rf "$LEGACY_APP_BUNDLE"
fi

echo "Built: $OUT_BIN"
echo "App:   $APP_BUNDLE"
echo "Bundle identifier: $APP_BUNDLE_IDENTIFIER"
