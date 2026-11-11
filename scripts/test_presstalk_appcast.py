#!/usr/bin/env python3
"""Release refusal tests; optional real Sparkle signature tests use Keychain only."""
import base64
import copy
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
import zipfile
import xml.etree.ElementTree as ET

import presstalk_appcast as appcast


def metadata():
    return {"build": "26.3", "version": "0.1.26", "minimum_macos": "14.0.0",
            "archive_name": "PressTalk-0.1.26-macos-arm64.zip", "archive_bytes": 123,
            "archive_sha256": "a" * 64, "tag": "v0.1.26",
            "download_url": "https://github.com/subtract0/presstalk/releases/download/v0.1.26/PressTalk-0.1.26-macos-arm64.zip"}


def feed():
    root = ET.Element("rss", version="2.0")
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "PressTalk"
    item = ET.SubElement(channel, "item")
    for key, value in (("version", "26.3"), ("shortVersionString", "0.1.26"),
                       ("minimumSystemVersion", "14.0.0"), ("hardwareRequirements", "arm64")):
        ET.SubElement(item, appcast.NS + key).text = value
    ET.SubElement(item, "enclosure", {"url": metadata()["download_url"], "length": "123",
                                      appcast.NS + "edSignature": base64.b64encode(b"s" * 64).decode()})
    return root


def feed_bytes(root):
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


class ReleasePolicyTests(unittest.TestCase):
    def test_numeric_build_order_handles_two_digit_components(self):
        self.assertGreater(appcast.version("26.10"), appcast.version("26.9"))
        self.assertEqual(appcast.version("26.3"), appcast.version("26.3.0"))
        for invalid in ("26.3-rc1", "v26.3", "", "26.03", "26.3.1.1"):
            with self.subTest(invalid=invalid), self.assertRaises(appcast.ReleaseError):
                appcast.version(invalid)

    def test_valid_candidate_structure(self):
        self.assertEqual(appcast.validate_feed_structure(feed_bytes(feed()), metadata(), "25.1"),
                         base64.b64encode(b"s" * 64).decode())

    def test_equal_or_downgrade_build_is_rejected(self):
        for previous in ("26.3", "26.3.0", "26.4", "27"):
            with self.subTest(previous=previous), self.assertRaises(appcast.ReleaseError):
                appcast.validate_feed_structure(feed_bytes(feed()), metadata(), previous)

    def test_mutable_or_changed_enclosures_are_rejected(self):
        for url in (metadata()["download_url"].replace("/download/v0.1.26/", "/latest/download/"),
                    metadata()["download_url"] + "?download=1", metadata()["download_url"].replace("https:", "http:"),
                    metadata()["download_url"].replace("v0.1.26/", "v0.1.25/")):
            root = feed()
            root.find("channel/item/enclosure").set("url", url)
            with self.subTest(url=url), self.assertRaises(appcast.ReleaseError):
                appcast.validate_feed_structure(feed_bytes(root), metadata(), "25.1")

    def test_unsigned_length_changed_or_incompatible_item_is_rejected(self):
        for change in ("unsigned", "length", "hardware", "minimum", "channel", "notes", "duplicate"):
            root = feed()
            item = root.find("channel/item")
            if change == "unsigned":
                del item.find("enclosure").attrib[appcast.NS + "edSignature"]
            elif change == "length":
                item.find("enclosure").set("length", "124")
            elif change == "hardware":
                item.remove(item.find(appcast.NS + "hardwareRequirements"))
            elif change == "minimum":
                item.find(appcast.NS + "minimumSystemVersion").text = "13.0.0"
            elif change == "duplicate":
                root.find("channel").append(copy.deepcopy(item))
            else:
                ET.SubElement(item, appcast.NS + ("channel" if change == "channel" else "releaseNotesLink")).text = "beta"
            with self.subTest(change=change), self.assertRaises(appcast.ReleaseError):
                appcast.validate_feed_structure(feed_bytes(root), metadata(), "25.1")

    def test_public_asset_must_be_published_stable_and_match(self):
        data = metadata()
        release = {"id": 1, "tag_name": data["tag"], "draft": False, "prerelease": False,
                   "published_at": "2026-10-27T12:00:00Z", "assets": [{"id": 2, "name": data["archive_name"],
                   "state": "uploaded", "size": data["archive_bytes"], "browser_download_url": data["download_url"],
                   "digest": "sha256:" + data["archive_sha256"]}]}
        self.assertEqual(appcast.validate_public_metadata(release, data)["id"], 2)
        for field in ("draft", "prerelease", "digest", "size", "missing"):
            bad = copy.deepcopy(release)
            if field in ("draft", "prerelease"):
                bad[field] = True
            elif field == "missing":
                bad["assets"] = []
            elif field == "digest":
                bad["assets"][0]["digest"] = "sha256:" + "b" * 64
            else:
                bad["assets"][0]["size"] += 1
            with self.subTest(field=field), self.assertRaises(appcast.ReleaseError):
                appcast.validate_public_metadata(bad, data)

    def test_archive_extraction_guard_preserves_framework_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.zip"
            link = zipfile.ZipInfo("PressTalk.app/Contents/Frameworks/Sparkle.framework/Versions/Current")
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o755) << 16
            with zipfile.ZipFile(path, "w") as stream:
                stream.writestr(link, "B")
            appcast.archive_paths_safe(path)
            for unsafe in ("../../../../../../escape", "/etc/passwd"):
                with zipfile.ZipFile(path, "w") as stream:
                    stream.writestr(link, unsafe)
                with self.subTest(target=unsafe), self.assertRaises(appcast.ReleaseError):
                    appcast.archive_paths_safe(path)
            with zipfile.ZipFile(path, "w") as stream:
                stream.writestr("../escape", "blocked")
            with self.assertRaises(appcast.ReleaseError):
                appcast.archive_paths_safe(path)


@unittest.skipUnless(os.environ.get("PRESSTALK_TEST_SPARKLE_TOOLS") and os.environ.get("PRESSTALK_TEST_SPARKLE_ACCOUNT")
                     and os.environ.get("PRESSTALK_TEST_PUBLIC_KEY_FILE"), "Set explicit official tool/account/public-key paths for real crypto checks")
class OfficialSparkleSignatureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = Path(os.environ["PRESSTALK_TEST_SPARKLE_TOOLS"])
        cls.account = os.environ["PRESSTALK_TEST_SPARKLE_ACCOUNT"]
        cls.key = Path(os.environ["PRESSTALK_TEST_PUBLIC_KEY_FILE"]).read_text().strip()
        cls.tools = appcast.SparkleTools(cls.directory, cls.account, cls.key)

    def test_official_verifier_rejects_tampered_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "noninstallable-signature-test.zip"
            with zipfile.ZipFile(archive, "w") as stream:
                stream.writestr("signature-fixture.txt", "This is a test fixture, not an app.")
            signature = appcast.run([self.directory / "sign_update", "--account", self.account, "-p", archive])
            self.tools.verify(archive, signature)
            archive.write_bytes(archive.read_bytes() + b"tampered")
            with self.assertRaises(appcast.ReleaseError):
                self.tools.verify(archive, signature)

    def test_official_verifier_rejects_unsigned_and_tampered_feed(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "appcast.xml"
            path.write_bytes(feed_bytes(feed()))
            with self.assertRaises(appcast.ReleaseError):
                self.tools.verify(path)
            appcast.run([self.directory / "sign_update", "--account", self.account, path])
            self.tools.verify(path)
            path.write_bytes(path.read_bytes().replace(b"PressTalk", b"Counterfeit", 1))
            with self.assertRaises(appcast.ReleaseError):
                self.tools.verify(path)

    def test_keychain_account_must_match_embedded_public_key(self):
        wrong = base64.b64encode(b"not-the-approved-public-key-00000"[:32]).decode()
        self.assertNotEqual(wrong, self.key)
        with self.assertRaisesRegex(appcast.ReleaseError, "does not match"):
            appcast.SparkleTools(self.directory, self.account, wrong)


if __name__ == "__main__":
    unittest.main(verbosity=2)
