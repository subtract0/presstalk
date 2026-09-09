#!/usr/bin/env python3
"""Exercise release integrity failures and ambiguous process detection safely."""
import copy
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('finisher', Path(__file__).with_name('finish_presstalk_release.py'))
finisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(finisher)


class ReleaseIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.app = self.root / 'PressTalk.app'
        (self.app / 'Contents/MacOS').mkdir(parents=True)
        (self.app / 'Contents/MacOS/jarvistap').write_bytes(b'reviewed executable')
        self.metadata = {'CFBundleIdentifier': 'com.am.presstalk', 'CFBundleVersion': '23.2'}
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps(self.metadata))
        self.helper = self.root / 'helper'
        self.helper.write_text('reviewed helper')
        self.manifest = {'app': str(self.app), 'files': finisher.inventory(self.app), 'metadata': self.metadata,
                         'entitlements': {'path': str(self.helper), 'sha256': finisher.sha(self.helper)},
                         'readinessScript': {'path': str(self.helper), 'sha256': finisher.sha(self.helper)}}

    def test_exact_prepared_artifact_and_helper_pass(self):
        self.assertEqual(finisher.verify_prepared(self.manifest), self.app)

    def test_changed_code_is_rejected_before_signing(self):
        (self.app / 'Contents/MacOS/jarvistap').write_bytes(b'changed executable')
        with self.assertRaisesRegex(RuntimeError, 'differs'):
            finisher.verify_prepared(self.manifest)

    def test_extra_bundled_code_is_rejected(self):
        (self.app / 'Contents/MacOS/unreviewed').write_bytes(b'new helper')
        with self.assertRaisesRegex(RuntimeError, 'differs'):
            finisher.verify_prepared(self.manifest)

    def test_symlink_outside_bundle_is_rejected(self):
        (self.app / 'Contents/link').symlink_to(self.helper)
        with self.assertRaisesRegex(RuntimeError, 'symbolic link'):
            finisher.verify_prepared(self.manifest)

    def test_changed_signing_inputs_are_rejected(self):
        self.helper.write_text('changed entitlements')
        with self.assertRaisesRegex(RuntimeError, 'changed'):
            finisher.verify_prepared(self.manifest)

    def test_wrong_version_is_rejected_even_if_hash_list_matches(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['metadata']['CFBundleVersion'] = '23.1'
        with self.assertRaisesRegex(RuntimeError, 'metadata'):
            finisher.verify_prepared(manifest)

    def test_only_explicit_no_process_result_allows_install(self):
        for code in (0, 1, 2, -9):
            with self.subTest(exit_code=code), patch.object(finisher.subprocess, 'run', return_value=subprocess.CompletedProcess([], code, '', '')):
                if code == 1:
                    finisher.require_stopped()
                else:
                    with self.assertRaises(RuntimeError):
                        finisher.require_stopped()


if __name__ == '__main__':
    unittest.main()
