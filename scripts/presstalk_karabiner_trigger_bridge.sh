#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
if [[ "$MODE" != "--enable" && "$MODE" != "--disable" ]]; then
  echo "Usage: PRESSTALK_KARABINER_TRIGGER_KEY=right_option $0 --enable | --disable" >&2
  exit 2
fi

TRIGGER_KEY="${PRESSTALK_KARABINER_TRIGGER_KEY:-right_option}"
KARABINER_CONFIG="$HOME/.config/karabiner/karabiner.json"
KARABINER_ASSET_DIR="$HOME/.config/karabiner/assets/complex_modifications"
KARABINER_ASSET_FILE="$KARABINER_ASSET_DIR/presstalk_trigger_bridge.json"

case "$TRIGGER_KEY" in
  right_option|left_option|option|fn|caps_lock|f5)
    ;;
  *)
    echo "Unsupported PRESSTALK_KARABINER_TRIGGER_KEY: $TRIGGER_KEY" >&2
    echo "Supported: right_option, left_option, option, fn, caps_lock, f5" >&2
    exit 2
    ;;
esac

mkdir -p "$KARABINER_ASSET_DIR"

python3 - "$KARABINER_CONFIG" "$KARABINER_ASSET_FILE" "$TRIGGER_KEY" "$MODE" <<'PY'
import json
import pathlib
import sys

config_path = pathlib.Path(sys.argv[1]).expanduser()
asset_path = pathlib.Path(sys.argv[2]).expanduser()
trigger_key = sys.argv[3]
mode = sys.argv[4]

press_command = "/usr/bin/notifyutil -p com.am.jarvistap.trigger.press"
release_command = "/usr/bin/notifyutil -p com.am.jarvistap.trigger.release"

def from_entries_for_trigger(trigger):
    if trigger == "option":
        return [{"key_code": "left_option"}, {"key_code": "right_option"}]
    if trigger == "f5":
        return [
            {"key_code": "f5"},
            {"consumer_key_code": "microphone"},
            {"consumer_key_code": "dictation"},
        ]
    return [{"key_code": trigger}]

def manipulator_for_from(from_entry):
    return {
        "type": "basic",
        "from": {
            **from_entry,
            "modifiers": {"optional": ["any"]},
        },
        "to": [
            {"repeat": False, "shell_command": press_command},
            {"key_code": "vk_none"},
        ],
        "to_after_key_up": [
            {"shell_command": release_command},
        ],
    }

def command_targets(manipulator):
    targets = []
    for key in ("to", "to_after_key_up"):
        value = manipulator.get(key)
        if isinstance(value, list):
            targets.extend(item for item in value if isinstance(item, dict))
    return targets

def is_presstalk_bridge_rule(rule):
    description = str(rule.get("description", ""))
    if description.startswith("PressTalk trigger bridge"):
        return True
    if description in {
        "Send PressTalk press and release notifications from the F5 / microphone key",
        "Send JarvisTap press and release notifications from the F5 / microphone key",
        "Map the F5 / microphone key to Fn+F5 for PressTalk",
    }:
        return True
    manipulators = rule.get("manipulators")
    if not isinstance(manipulators, list):
        return False
    for manipulator in manipulators:
        if not isinstance(manipulator, dict):
            continue
        for target in command_targets(manipulator):
            command = target.get("shell_command")
            if isinstance(command, str) and "com.am.jarvistap.trigger." in command:
                return True
    return False

if config_path.exists():
    try:
        config = json.loads(config_path.read_text())
    except Exception:
        config = {}
else:
    config = {}

profiles = config.setdefault("profiles", [])
if not profiles:
    profiles.append({
        "name": "Default profile",
        "selected": True,
        "complex_modifications": {"rules": []},
    })

selected_profile = next((profile for profile in profiles if profile.get("selected")), profiles[0])
complex_modifications = selected_profile.setdefault("complex_modifications", {})
rules = complex_modifications.setdefault("rules", [])
rules = [rule for rule in rules if not is_presstalk_bridge_rule(rule)]

if mode == "--enable":
    rule = {
        "description": f"PressTalk trigger bridge ({trigger_key})",
        "manipulators": [manipulator_for_from(entry) for entry in from_entries_for_trigger(trigger_key)],
    }
    rules.append(rule)
    asset = {"title": "PressTalk", "rules": [rule]}
    asset_path.write_text(json.dumps(asset, indent=2) + "\n")
else:
    if asset_path.exists():
        asset_path.unlink()

complex_modifications["rules"] = rules
config_path.parent.mkdir(parents=True, exist_ok=True)
config_path.write_text(json.dumps(config, indent=2) + "\n")
PY

if [[ "$MODE" == "--enable" ]]; then
  echo "Enabled PressTalk Karabiner trigger bridge: $TRIGGER_KEY"
  echo "No System Settings or Karabiner window was opened."
else
  echo "Disabled PressTalk Karabiner trigger bridge."
fi
