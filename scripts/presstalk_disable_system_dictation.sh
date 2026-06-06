#!/usr/bin/env bash
set -euo pipefail

SYMBOLIC_HOTKEYS_PLIST="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"

/usr/bin/defaults write com.apple.HIToolbox AppleDictationAutoEnable -bool false
/usr/bin/defaults write com.apple.HIToolbox DictationIMIntroMessagePresented -bool true
/usr/bin/defaults write com.apple.HIToolbox NSDisabledDictationMenuItem -bool true
/usr/bin/defaults write -g DictationIMIntroMessagePresented -bool true
/usr/bin/defaults write -g NSDisabledDictationMenuItem -bool true
/usr/bin/defaults write com.apple.speech.recognition.AppleSpeechRecognition.prefs DictationIMIntroMessagePresented -bool true

python3 - "$SYMBOLIC_HOTKEYS_PLIST" <<'PY'
import plistlib
import sys
from pathlib import Path

plist_path = Path(sys.argv[1]).expanduser()
data = {}
if plist_path.exists():
    try:
        with plist_path.open("rb") as fh:
            data = plistlib.load(fh)
    except Exception:
        data = {}

hotkeys = data.get("AppleSymbolicHotKeys")
if not isinstance(hotkeys, dict):
    hotkeys = {}

entry = hotkeys.get("162")
if not isinstance(entry, dict):
    entry = {
        "enabled": False,
        "value": {
            "type": "standard",
            "parameters": [65535, 96, 1572864],
        },
    }

entry["enabled"] = False
if "value" not in entry:
    entry["value"] = {
        "type": "standard",
        "parameters": [65535, 96, 1572864],
    }

hotkeys["162"] = entry
data["AppleSymbolicHotKeys"] = hotkeys
plist_path.parent.mkdir(parents=True, exist_ok=True)
with plist_path.open("wb") as fh:
    plistlib.dump(data, fh)
PY

/usr/bin/killall cfprefsd >/dev/null 2>&1 || true
/usr/bin/killall SystemUIServer >/dev/null 2>&1 || true

echo "Disabled Apple Dictation F5 hotkey for PressTalk."
