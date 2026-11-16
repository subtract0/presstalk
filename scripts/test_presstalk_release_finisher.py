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
                         'sparkleBundleScript': {'path': str(self.helper), 'sha256': finisher.sha(self.helper)},
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

    def framework(self):
        framework = self.app / 'Contents/Frameworks/Sparkle.framework'
        (framework / 'Versions/B/Resources').mkdir(parents=True)
        (framework / 'Versions/B/Sparkle').write_bytes(b'framework code')
        (framework / 'Versions/Current').symlink_to('B')
        (framework / 'Sparkle').symlink_to('Versions/Current/Sparkle')
        (framework / 'Resources').symlink_to('Versions/Current/Resources')
        return framework

    def test_contained_framework_links_are_recorded_and_verified(self):
        framework = self.framework()
        self.manifest['files'] = finisher.inventory(self.app)
        self.assertEqual(self.manifest['files']['Contents/Frameworks/Sparkle.framework/Sparkle'],
                         {'symlink': 'Versions/Current/Sparkle'})
        self.assertEqual(finisher.verify_prepared(self.manifest), self.app)
        (framework / 'Versions/B/Sparkle').write_bytes(b'changed framework')
        with self.assertRaisesRegex(RuntimeError, 'differs'):
            finisher.verify_prepared(self.manifest)

    def test_retargeted_framework_link_changes_inventory(self):
        framework = self.framework()
        self.manifest['files'] = finisher.inventory(self.app)
        (framework / 'Sparkle').unlink()
        (framework / 'Sparkle').symlink_to('Versions/B/Sparkle')
        with self.assertRaisesRegex(RuntimeError, 'differs'):
            finisher.verify_prepared(self.manifest)

    def test_relative_escaping_framework_link_is_rejected(self):
        framework = self.framework()
        (framework / 'escape').symlink_to('../../MacOS/jarvistap')
        with self.assertRaisesRegex(RuntimeError, 'Unsafe symbolic link'):
            finisher.inventory(self.app)

    def test_absolute_contained_framework_link_is_rejected(self):
        framework = self.framework()
        (framework / 'absolute').symlink_to(framework / 'Versions/B/Sparkle')
        with self.assertRaisesRegex(RuntimeError, 'Unexpected symbolic link'):
            finisher.inventory(self.app)

    def test_broken_framework_link_is_rejected(self):
        framework = self.framework()
        (framework / 'missing').symlink_to('Versions/Z')
        with self.assertRaisesRegex(RuntimeError, 'Unsafe symbolic link'):
            finisher.inventory(self.app)

    def test_links_outside_framework_remain_rejected(self):
        (self.app / 'Contents/inside').symlink_to('MacOS/jarvistap')
        with self.assertRaisesRegex(RuntimeError, 'Unexpected symbolic link'):
            finisher.inventory(self.app)

    def test_framework_requires_hash_bound_verifier(self):
        self.framework()
        self.manifest['files'] = finisher.inventory(self.app)
        del self.manifest['sparkleBundleScript']
        with self.assertRaisesRegex(RuntimeError, 'Sparkle bundle verifier'):
            finisher.verify_prepared(self.manifest)

    def test_framework_signing_order_preserves_only_downloader_entitlements(self):
        framework = self.framework()
        sign = ['codesign', '--force', '--sign', 'fixture', '--options', 'runtime']
        with patch.object(finisher, 'run') as run:
            finisher.sign_sparkle(self.app, sign, self.root)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual([Path(command[-1]).name for command in commands],
                         ['Installer.xpc', 'Downloader.xpc', 'Autoupdate', 'Updater.app', 'Sparkle.framework'])
        self.assertEqual([i for i, command in enumerate(commands) if '--preserve-metadata=entitlements' in command], [1])
        self.assertTrue(all('--entitlements' not in command and '--deep' not in command for command in commands))

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
