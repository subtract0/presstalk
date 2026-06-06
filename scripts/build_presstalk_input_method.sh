#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL=0
APP_BUNDLE_OVERRIDE="${PRESSTALK_INPUT_METHOD_APP_BUNDLE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL=1
      shift
      ;;
    --app-bundle)
      APP_BUNDLE_OVERRIDE="${2:-}"
      if [[ -z "$APP_BUNDLE_OVERRIDE" ]]; then
        echo "Missing value for --app-bundle" >&2
        exit 2
      fi
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

PRODUCT="presstalk-input-method"
APP_NAME="PressTalkInputMethod.app"
BUILD_DIR="$ROOT/.build/presstalk-input-method"
APP_BUNDLE="${APP_BUNDLE_OVERRIDE:-$BUILD_DIR/$APP_NAME}"
APP_CONTENTS_DIR="$APP_BUNDLE/Contents"
APP_MACOS_DIR="$APP_CONTENTS_DIR/MacOS"
APP_RESOURCES_DIR="$APP_CONTENTS_DIR/Resources"
APP_INFO_PLIST="$APP_CONTENTS_DIR/Info.plist"
INSTALLED_BUNDLE="$HOME/Library/Input Methods/$APP_NAME"

pushd "$ROOT" >/dev/null
swift build -c release --product "$PRODUCT"
BINARY_DIR="$(swift build -c release --show-bin-path)"
popd >/dev/null

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS_DIR" "$APP_RESOURCES_DIR"
cp "$BINARY_DIR/$PRODUCT" "$APP_MACOS_DIR/$PRODUCT"
chmod 755 "$APP_MACOS_DIR/$PRODUCT"

cat >"$APP_INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>PressTalk Input Method</string>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT</string>
  <key>CFBundleIdentifier</key>
  <string>com.am.presstalk.inputmethod</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>PressTalkInputMethod</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleSignature</key>
  <string>????</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.5</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>CFBundleVersion</key>
  <string>3</string>
  <key>ComponentInputModeDict</key>
  <dict>
    <key>tsInputModeListKey</key>
    <dict>
      <key>com.am.presstalk.inputmethod</key>
      <dict>
        <key>TISInputSourceID</key>
        <string>com.am.presstalk.inputmethod</string>
        <key>TISIconLabels</key>
        <dict>
          <key>Primary</key>
          <string>PT</string>
        </dict>
        <key>TISIntendedLanguage</key>
        <string>en</string>
        <key>tsInputModeIsVisibleKey</key>
        <true/>
        <key>tsInputModePrimaryInScriptKey</key>
        <true/>
        <key>tsInputModeScriptKey</key>
        <string>smUnicodeScript</string>
      </dict>
    </dict>
    <key>tsVisibleInputModeOrderedArrayKey</key>
    <array>
      <string>com.am.presstalk.inputmethod</string>
    </array>
  </dict>
  <key>InputMethodConnectionName</key>
  <string>PressTalkInputMethod_1_Connection</string>
  <key>InputMethodServerControllerClass</key>
  <string>PressTalkIMController</string>
  <key>InputMethodServerDelegateClass</key>
  <string>PressTalkIMController</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsSuddenTermination</key>
  <true/>
  <key>TISIconIsTemplate</key>
  <true/>
  <key>TISInputSourceID</key>
  <string>com.am.presstalk.inputmethod</string>
  <key>TISIntendedLanguage</key>
  <string>en</string>
</dict>
</plist>
PLIST

plutil -lint "$APP_INFO_PLIST" >/dev/null
codesign --force --sign - --timestamp=none "$APP_MACOS_DIR/$PRODUCT"
codesign --force --sign - --timestamp=none "$APP_BUNDLE"

echo "Built input method prototype: $APP_BUNDLE"
echo "Notification: com.am.presstalk.inputmethod.insert"
echo "Payload file: $HOME/Library/Application Support/JarvisTap/input-method-insert.txt"

if [[ "$INSTALL" == "1" ]]; then
  mkdir -p "$HOME/Library/Input Methods"
  rm -rf "$INSTALLED_BUNDLE"
  ditto "$APP_BUNDLE" "$INSTALLED_BUNDLE"
  echo "Installed input method prototype: $INSTALLED_BUNDLE"
  echo "You may need to log out/in or manually add/select this input source before it can receive a text client."
else
  echo "Not installed. Re-run with --install to copy into ~/Library/Input Methods."
fi
