#!/usr/bin/env python3
"""Exercise the audit against controlled codesign/stapler output, not a real signature."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class ArtifactAuditTests(unittest.TestCase):
    def audit(self, flags, verify=0, staple=0):
        with tempfile.TemporaryDirectory(prefix="presstalk-audit-test-") as temp:
            folder = Path(temp)
            fake_bin = folder / "bin"
            fake_bin.mkdir()
            scripts = {
                "codesign": '''#!/bin/bash
if [[ "$1" == "--verify" ]]; then exit "$AUDIT_TEST_VERIFY"; fi
cat "$AUDIT_TEST_REPORT" >&2
''',
                "xcrun": '#!/bin/bash\nexit "$AUDIT_TEST_STAPLE"\n',
            }
            for name, content in scripts.items():
                p = fake_bin / name
                p.write_text(content)
                p.chmod(0o755)
            report = folder / "codesign.txt"
            report.write_text(
                "Executable=/fixture/PressTalk.app/Contents/MacOS/jarvistap\n"
                "Identifier=com.am.presstalk\n"
                + flags + "\n"
                "Authority=Developer ID Application: Fixture (TEAM)\n"
                "TeamIdentifier=TEAM\n"
                "CDHash=abcdef\n"
                "Timestamp=8 Sep 2026\n"
            )
            archive = folder / "fixture.zip"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("PressTalk.app/Contents/Info.plist", plistlib.dumps({
                    "CFBundleIdentifier": "com.am.presstalk",
                    "CFBundleShortVersionString": "0.1.22",
                    "CFBundleVersion": "22.2",
                }))
            output = folder / "audit.json"
            result = subprocess.run([
                "bash", str(ROOT / "scripts/presstalk_release_artifact_audit.sh"),
                "--zip", str(archive), "--expected-version", "0.1.22",
                "--require-notarized", "--json-output", str(output),
            ], env=dict(os.environ, PATH=str(fake_bin) + os.pathsep + os.environ["PATH"],
                        AUDIT_TEST_REPORT=str(report), AUDIT_TEST_VERIFY=str(verify),
                        AUDIT_TEST_STAPLE=str(staple)), capture_output=True, text=True)
            self.assertTrue(output.exists(), result.stdout + result.stderr)
            return result.returncode, json.loads(output.read_text())

    def test_actual_codesign_codedirectory_runtime_format(self):
        status, report = self.audit("CodeDirectory v=20500 size=28124 flags=0x10000(runtime) hashes=868+7 location=embedded")
        self.assertEqual(status, 0, report)
        self.assertTrue(report["hardenedRuntime"])

    def test_standalone_flags_format(self):
        status, report = self.audit("flags=0x10000(runtime)")
        self.assertEqual(status, 0, report)

    def test_unhardened_signature_fails(self):
        status, report = self.audit("CodeDirectory v=20500 flags=0x0(none) hashes=868+7")
        self.assertNotEqual(status, 0)
        self.assertFalse(report["hardenedRuntime"])

    def test_missing_flags_fail(self):
        status, report = self.audit("Runtime Version=26.5.0")
        self.assertNotEqual(status, 0)
        self.assertFalse(report["hardenedRuntime"])

    def test_unrelated_runtime_text_is_not_evidence(self):
        status, report = self.audit("Comment=flags=0x10000(runtime)")
        self.assertNotEqual(status, 0)
        self.assertFalse(report["hardenedRuntime"])

    def test_invalid_signature_fails_even_with_runtime_flag(self):
        status, report = self.audit("flags=0x10000(runtime)", verify=1)
        self.assertNotEqual(status, 0)
        self.assertFalse(report["codeSignVerifyPassed"])

    def test_missing_notarization_fails(self):
        status, report = self.audit("flags=0x10000(runtime)", staple=1)
        self.assertNotEqual(status, 0)
        self.assertEqual(report["notarized"], "false")


if __name__ == "__main__":
    unittest.main()
