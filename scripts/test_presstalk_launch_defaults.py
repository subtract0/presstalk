#!/usr/bin/env python3
"""Compare real app config with launcher defaults without installing or recording.

Only the two scalar assignments under test are evaluated from each launcher.
The full app configuration is compiled with inert UI type stubs; no app starts.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FLAGS = ("ENABLE_STREAMING_TRANSCRIPTION", "PARAKEET_QUALITY_FALLBACK")


class LaunchDefaultsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="presstalk-launch-defaults-")
        cls.addClassCleanup(cls.scratch.cleanup)
        scratch = Path(cls.scratch.name)
        driver = scratch / "main.swift"
        driver.write_text('''import Foundation
enum JarvisTapSettingsStore {
    enum TriggerKeyOption: String { case fn }
}
extension String { var nonEmpty: String? { isEmpty ? nil : self } }
let config = JarvisTapConfig.load()
let data = try JSONSerialization.data(withJSONObject: [
    "ENABLE_STREAMING_TRANSCRIPTION": config.streamingTranscriptionEnabled,
    "PARAKEET_QUALITY_FALLBACK": config.parakeetQualityFallbackEnabled
], options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
''')
        cls.executable = scratch / "config-probe"
        subprocess.run([
            "swiftc", "-module-cache-path", str(scratch / "module-cache"),
            str(ROOT / "Sources/JarvisTap/JarvisTapConfig.swift"), str(driver),
            "-o", str(cls.executable)
        ], check=True, capture_output=True, text=True)
        cls.base_env = {
            k: v for k, v in os.environ.items()
            if not k.startswith(("PRESSTALK_", "JARVISTAP_"))
        }

    def config(self, overrides):
        result = subprocess.run(
            [str(self.executable)], env={**self.base_env, **overrides},
            check=True, capture_output=True, text=True)
        return json.loads(result.stdout)

    def launch_config(self, launcher, overrides):
        lines = (ROOT / "scripts" / launcher).read_text().splitlines()
        assignments = []
        for flag in FLAGS:
            found = [line for line in lines if line.startswith("PRESSTALK_" + flag + "=")]
            self.assertEqual(len(found), 1, (launcher, flag))
            assignments.extend(found)
        shell = "\n".join(assignments)
        shell += '\nprintf "%s\\n" "$PRESSTALK_ENABLE_STREAMING_TRANSCRIPTION" "$PRESSTALK_PARAKEET_QUALITY_FALLBACK"\n'
        result = subprocess.run(
            ["/bin/bash", "-c", shell], env={**self.base_env, **overrides},
            check=True, capture_output=True, text=True)
        resolved = dict(zip(("PRESSTALK_" + x for x in FLAGS), result.stdout.splitlines()))
        self.assertEqual(len(resolved), len(FLAGS))
        return self.config({**overrides, **resolved})

    def test_finder_defaults_keep_optional_recognizers_off(self):
        self.assertEqual(self.config({}), {flag: False for flag in FLAGS})

    def test_both_launchers_match_finder_defaults(self):
        expected = self.config({})
        for launcher in ("presstalk_bootstrap.sh", "install_jarvistap_launchd.sh"):
            with self.subTest(launcher=launcher):
                self.assertEqual(self.launch_config(launcher, {}), expected)

    def test_explicit_opt_in_opt_out_and_legacy_precedence(self):
        for launcher in ("presstalk_bootstrap.sh", "install_jarvistap_launchd.sh"):
            for flag in FLAGS:
                primary = "PRESSTALK_" + flag
                legacy = "JARVISTAP_" + flag
                cases = [
                    ({primary: "1"}, True),
                    ({primary: "0"}, False),
                    ({primary: "false"}, False),
                    ({legacy: "1"}, True),
                    ({legacy: "0"}, False),
                    ({primary: "0", legacy: "1"}, False),
                    ({primary: "1", legacy: "0"}, True),
                ]
                for overrides, enabled in cases:
                    with self.subTest(launcher=launcher, flag=flag, overrides=overrides):
                        expected = self.config(overrides)
                        self.assertEqual(expected[flag], enabled)
                        self.assertEqual(self.launch_config(launcher, overrides), expected)


if __name__ == "__main__":
    unittest.main()
