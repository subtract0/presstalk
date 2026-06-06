#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
if [[ "$MODE" != "--enable" && "$MODE" != "--disable" ]]; then
  echo "Usage: $0 --enable | --disable" >&2
  exit 2
fi

KARABINER_CONFIG="$HOME/.config/karabiner/karabiner.json"
KARABINER_ASSET_DIR="$HOME/.config/karabiner/assets/complex_modifications"
KARABINER_ASSET_FILE="$KARABINER_ASSET_DIR/presstalk_f5_notify.json"
RULE_DESCRIPTION="Send PressTalk press and release notifications from the F5 / microphone key"
LEGACY_RULE_DESCRIPTION="Map the F5 / microphone key to Fn+F5 for PressTalk"
LEGACY_RULE_DESCRIPTION_2="Send JarvisTap press and release notifications from the F5 / microphone key"

mkdir -p "$KARABINER_ASSET_DIR"

if [[ "$MODE" == "--enable" ]]; then
  cat >"$KARABINER_ASSET_FILE" <<'JSON'
{
  "title": "PressTalk",
  "rules": [
    {
      "description": "Send PressTalk press and release notifications from the F5 / microphone key",
      "manipulators": [
        {
          "type": "basic",
          "from": {
            "key_code": "f5",
            "modifiers": { "optional": ["any"] }
          },
          "to": [
            {
              "repeat": false,
              "shell_command": "/usr/bin/notifyutil -p com.am.jarvistap.trigger.press"
            },
            {
              "key_code": "vk_none"
            }
          ],
          "to_after_key_up": [
            {
              "shell_command": "/usr/bin/notifyutil -p com.am.jarvistap.trigger.release"
            }
          ]
        },
        {
          "type": "basic",
          "from": {
            "consumer_key_code": "microphone",
            "modifiers": { "optional": ["any"] }
          },
          "to": [
            {
              "repeat": false,
              "shell_command": "/usr/bin/notifyutil -p com.am.jarvistap.trigger.press"
            },
            {
              "key_code": "vk_none"
            }
          ],
          "to_after_key_up": [
            {
              "shell_command": "/usr/bin/notifyutil -p com.am.jarvistap.trigger.release"
            }
          ]
        },
        {
          "type": "basic",
          "from": {
            "consumer_key_code": "dictation",
            "modifiers": { "optional": ["any"] }
          },
          "to": [
            {
              "repeat": false,
              "shell_command": "/usr/bin/notifyutil -p com.am.jarvistap.trigger.press"
            },
            {
              "key_code": "vk_none"
            }
          ],
          "to_after_key_up": [
            {
              "shell_command": "/usr/bin/notifyutil -p com.am.jarvistap.trigger.release"
            }
          ]
        }
      ]
    }
  ]
}
JSON
fi

python3 - "$KARABINER_CONFIG" "$KARABINER_ASSET_FILE" "$RULE_DESCRIPTION" "$LEGACY_RULE_DESCRIPTION" "$LEGACY_RULE_DESCRIPTION_2" "$MODE" <<'PY'
import json
import pathlib
import sys

config_path = pathlib.Path(sys.argv[1]).expanduser()
asset_path = pathlib.Path(sys.argv[2]).expanduser()
rule_description = sys.argv[3]
legacy_rule_description = sys.argv[4]
legacy_rule_description_2 = sys.argv[5]
mode = sys.argv[6]

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
rules = [
    existing for existing in rules
    if existing.get("description") not in {
        rule_description,
        legacy_rule_description,
        legacy_rule_description_2,
    }
]

fn_function_keys = selected_profile.get("fn_function_keys")
if not isinstance(fn_function_keys, list):
    fn_function_keys = []
fn_function_keys = [
    existing for existing in fn_function_keys
    if not (
        isinstance(existing.get("from"), dict) and
        existing.get("from", {}).get("key_code") == "f5" and
        isinstance(existing.get("to"), list) and
        any(
            isinstance(item, dict) and
            (
                item.get("key_code") in {"f20", "f5"}
            )
            for item in existing.get("to", [])
        )
    )
]

if mode == "--enable":
    rule = json.loads(asset_path.read_text())["rules"][0]
    rules.append(rule)
else:
    if asset_path.exists():
        asset_path.unlink()

complex_modifications["rules"] = rules
if fn_function_keys:
    selected_profile["fn_function_keys"] = fn_function_keys
else:
    selected_profile.pop("fn_function_keys", None)
config_path.parent.mkdir(parents=True, exist_ok=True)
config_path.write_text(json.dumps(config, indent=2) + "\n")
PY

if [[ "$MODE" == "--enable" ]]; then
  open -g -a "Karabiner-Elements" >/dev/null 2>&1 || true
  echo "Enabled PressTalk Karabiner fallback."
  echo "Approve Karabiner-Elements input monitoring / driver extension if macOS asks."
else
  echo "Disabled PressTalk Karabiner fallback."
fi
