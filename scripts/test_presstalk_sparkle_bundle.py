#!/usr/bin/env python3
"""Verify the real pinned Sparkle framework in a temporary compiled app bundle.

This executable only locates Sparkle's bundle; it never starts an updater or
connects to the production feed. Negative controls mutate only temporary copies.
"""
import base64
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('sparkle_bundle', Path(__file__).with_name('presstalk_sparkle_bundle.py'))
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)
finisher_spec = importlib.util.spec_from_file_location('finisher', Path(__file__).with_name('finish_presstalk_release.py'))
finisher = importlib.util.module_from_spec(finisher_spec)
finisher_spec.loader.exec_module(finisher)


class SparkleBundleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='presstalk-sparkle-fixture-')
        cls.addClassCleanup(cls.directory.cleanup)
        cls.root = Path(cls.directory.name)
        cls.source = ROOT / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
        if not cls.source.is_dir():
            raise RuntimeError('Resolve the pinned Sparkle package before running this integration fixture')
        driver = cls.root / 'main.swift'
        driver.write_text('import Foundation\nimport Sparkle\nprint(Bundle(for: SPUUpdater.self).bundleURL.path)\n')
        cls.executable = cls.root / 'probe'
        subprocess.run(['swiftc', '-module-cache-path', str(cls.root / 'modules'),
                        '-F', str(cls.source.parent), '-framework', 'Sparkle',
                        '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
                        str(driver), '-o', str(cls.executable)], check=True, capture_output=True, text=True)

    def setUp(self):
        self.scratch = Path(tempfile.mkdtemp(dir=self.root))
        self.app = self.scratch / 'Relocated PressTalk.app'
        (self.app / 'Contents/MacOS').mkdir(parents=True)
        (self.app / 'Contents/Resources').mkdir()
        self.licence = ROOT / '.build/artifacts/sparkle/Sparkle/LICENSE'
        shutil.copy2(self.licence, self.app / 'Contents/Resources/Sparkle-LICENSE')
        self.framework = self.app / 'Contents/Frameworks/Sparkle.framework'
        subprocess.run(['ditto', str(self.source), str(self.framework)], check=True)
        shutil.copy2(self.executable, self.app / 'Contents/MacOS/probe')
        self.plist = self.app / 'Contents/Info.plist'
        self.plist.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.am.presstalk',
                                              'CFBundleExecutable': 'probe'}))
        self.key = self.scratch / 'fixture-public-key.txt'
        self.key.write_text(base64.b64encode(bytes(range(32))).decode())
        bundle.configure(self.app, True, self.key)

    def mutate_info(self, **changes):
        info = plistlib.loads(self.plist.read_bytes())
        info.update(changes)
        self.plist.write_bytes(plistlib.dumps(info))

    def test_packaged_executable_loads_its_own_framework(self):
        bundle.verify(self.app)
        environment = {key: value for key, value in os.environ.items() if not key.startswith('DYLD_')}
        loaded = subprocess.check_output([str(self.app / 'Contents/MacOS/probe')], env=environment, text=True).strip()
        self.assertEqual(Path(loaded).resolve(), self.framework.resolve())

    def test_inside_out_signatures_remain_valid_and_preserve_downloader_entitlements(self):
        downloader = self.framework / 'Versions/B/XPCServices/Downloader.xpc'
        def entitlements():
            return plistlib.loads(subprocess.check_output(
                ['codesign', '-d', '--entitlements', '-', '--xml', str(downloader)], stderr=subprocess.DEVNULL))
        before = entitlements()
        finisher.sign_sparkle(self.app, ['codesign', '--force', '--sign', '-', '--timestamp=none', '--options', 'runtime'], self.scratch)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(self.framework)], check=True, capture_output=True)
        self.assertEqual(entitlements(), before)

    def test_release_zip_roundtrip_preserves_framework_links_and_loads(self):
        archive = self.scratch / 'release.zip'
        extracted = self.scratch / 'extracted'
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(self.app), str(archive)], check=True)
        subprocess.run(['ditto', '-x', '-k', str(archive), str(extracted)], check=True)
        restored = extracted / self.app.name
        self.assertEqual(finisher.inventory(self.app), finisher.inventory(restored))
        self.assertEqual(self.licence.read_bytes(), (restored / 'Contents/Resources/Sparkle-LICENSE').read_bytes())
        bundle.verify(restored)
        environment = {key: value for key, value in os.environ.items() if not key.startswith('DYLD_')}
        loaded = subprocess.check_output([str(restored / 'Contents/MacOS/probe')], env=environment, text=True).strip()
        self.assertEqual(Path(loaded).resolve(), (restored / 'Contents/Frameworks/Sparkle.framework').resolve())

    def test_missing_redistribution_notices_are_rejected(self):
        (self.app / 'Contents/Resources/Sparkle-LICENSE').unlink()
        with self.assertRaisesRegex(ValueError, 'redistribution licence'):
            bundle.verify(self.app)

    def test_development_app_has_no_production_feed(self):
        self.mutate_info(CFBundleIdentifier='com.am.presstalk.dev')
        bundle.configure(self.app, False)
        bundle.verify(self.app)
        info = plistlib.loads(self.plist.read_bytes())
        self.assertNotIn('SUFeedURL', info)
        self.assertNotIn('SUPublicEDKey', info)
        self.assertFalse(info['SUEnableAutomaticChecks'])
        self.assertFalse(info['SUAutomaticallyUpdate'])
        self.mutate_info(SUFeedURL=bundle.FEED_URL)
        with self.assertRaisesRegex(ValueError, 'Development app'):
            bundle.verify(self.app)

    def test_missing_framework_helper_is_rejected(self):
        (self.framework / 'Versions/B/Autoupdate').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing Sparkle helper'):
            bundle.verify(self.app)

    def test_missing_framework_links_are_rejected(self):
        (self.framework / 'Versions/Current').unlink()
        with self.assertRaisesRegex(ValueError, 'links were not preserved'):
            bundle.verify(self.app)

    def test_signed_feed_cannot_be_disabled_or_expire(self):
        self.mutate_info(SURequireSignedFeed=False)
        with self.assertRaisesRegex(ValueError, 'SURequireSignedFeed'):
            bundle.verify(self.app)
        self.mutate_info(SURequireSignedFeed=True, SUSignedFeedFailureExpirationInterval=1728000)
        with self.assertRaisesRegex(ValueError, 'must not expire'):
            bundle.verify(self.app)

    def test_plain_http_or_different_feed_is_rejected(self):
        self.mutate_info(SUFeedURL='http://presstalk.app/appcast.xml')
        with self.assertRaisesRegex(ValueError, 'fixed HTTPS feed'):
            bundle.verify(self.app)

    def test_missing_framework_runpath_is_rejected(self):
        subprocess.run(['install_name_tool', '-delete_rpath', '@executable_path/../Frameworks',
                        str(self.app / 'Contents/MacOS/probe')], check=True, capture_output=True)
        with self.assertRaisesRegex(ValueError, 'runpath'):
            bundle.verify(self.app)


if __name__ == '__main__':
    unittest.main()
