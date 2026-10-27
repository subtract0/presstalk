#!/usr/bin/env python3
"""Prepare/verify PressTalk's signed Sparkle feed. Never publishes anything.

Cryptographic signing and verification are delegated to pinned Sparkle tools;
private keys stay in Keychain. A local generation receipt is not a public gate.
"""
from __future__ import annotations

import argparse
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import posixpath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

FEED_URL = "https://presstalk.app/appcast.xml"
REPOSITORY = "subtract0/presstalk"
SPARKLE_VERSION = "2.10.1"
NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
PUBLIC_DR = ('identifier "com.am.presstalk" and anchor apple generic and '
             'certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and '
             'certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and '
             'certificate leaf[subject.OU] = "5HUC5LA94B"')
MAX_FEED_BYTES = 2 * 1024 * 1024


class ReleaseError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ReleaseError(message)


def version(value: str) -> tuple[int, int, int]:
    require(isinstance(value, str) and re.fullmatch(r"(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){0,2}", value) is not None,
            f"Expected an increasing numeric build/OS version, got {value!r}")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def public_key(value: str) -> str:
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, TypeError) as error:
        raise ReleaseError("Public updater key is not valid base64") from error
    require(len(decoded) == 32, "Public updater key must decode to 32 bytes")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run(args: list[str | Path], timeout: int = 180) -> str:
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True, timeout=timeout)
    require(result.returncode == 0,
            f"{Path(args[0]).name} failed ({result.returncode}): {(result.stderr or result.stdout).strip()}")
    return result.stdout.strip()


class SparkleTools:
    def __init__(self, directory: Path, account: str, expected_key: str):
        self.directory = directory.resolve()
        self.account = account
        require(bool(account) and account != "ed25519", "Use PressTalk's explicit Keychain account, not Sparkle's shared default")
        for name in ("generate_appcast", "generate_keys", "sign_update"):
            require((self.directory / name).is_file(), f"Missing official Sparkle tool: {name}")
        framework = self.directory.parent / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Resources/Info.plist"
        if not framework.exists():
            framework = self.directory.parent / "Sparkle.framework/Resources/Info.plist"
        require(framework.is_file(), "Cannot identify the Sparkle distribution containing these tools")
        metadata = plistlib.loads(framework.read_bytes())
        require(metadata.get("CFBundleShortVersionString") == SPARKLE_VERSION,
                f"Expected pinned Sparkle {SPARKLE_VERSION} tools")
        # -p only looks up the existing public key. It never creates or exports a key.
        found = public_key(run([self.directory / "generate_keys", "--account", account, "-p"]))
        require(found == public_key(expected_key), "Keychain signing account does not match the approved public key")
        self.public_key = found

    def verify(self, path: Path, signature: str | None = None) -> None:
        args = [self.directory / "sign_update", "--account", self.account, "--verify", path]
        if signature is not None:
            args.append(signature)
        run(args)

    def provenance(self) -> dict:
        return {"version": SPARKLE_VERSION, "directory": str(self.directory),
                "tool_sha256": {name: sha256(self.directory / name) for name in
                                ("generate_appcast", "generate_keys", "sign_update")}}


def archive_paths_safe(archive: Path) -> None:
    with zipfile.ZipFile(archive) as zipped:
        require(sum(info.file_size for info in zipped.infolist()) <= 2 * 1024 ** 3,
                "Archive unexpectedly expands beyond 2 GiB")
        for info in zipped.infolist():
            path = PurePosixPath(info.filename)
            require(not path.is_absolute() and ".." not in path.parts and "\\" not in info.filename,
                    "Unsafe path in update archive")
            require(path.parts and path.parts[0] in ("PressTalk.app", "__MACOSX"),
                    "Archive must contain only PressTalk.app and macOS archive metadata")
            if stat.S_ISLNK(info.external_attr >> 16):
                target = zipped.read(info).decode("utf-8")
                resolved = posixpath.normpath(str(path.parent / target))
                require(not target.startswith("/") and resolved.startswith("PressTalk.app/"),
                        "Archive contains a symlink escaping the app bundle")


def inspect_archive(archive: Path, key: str) -> dict:
    require(archive.is_file() and archive.suffix == ".zip", "Expected the final signed/notarized ZIP")
    archive_paths_safe(archive)
    with tempfile.TemporaryDirectory(prefix="presstalk-update-inspect-") as temporary:
        run(["/usr/bin/ditto", "-x", "-k", archive, temporary])
        app = Path(temporary) / "PressTalk.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        require(info.get("CFBundleIdentifier") == "com.am.presstalk", "Development/other app cannot enter the public feed")
        build = info.get("CFBundleVersion", "")
        short = info.get("CFBundleShortVersionString", "")
        version(build)
        require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", short) is not None,
                "Stable appcast requires a three-part public version without prerelease suffix")
        minimum = info.get("LSMinimumSystemVersion", "")
        version(minimum)
        require(info.get("SUFeedURL") == FEED_URL, "App must use the canonical HTTPS appcast URL")
        require(info.get("SUPublicEDKey") == key, "Archive embeds the wrong updater public key")
        for setting in ("SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"):
            require(info.get(setting) is True, f"Archive must enable {setting}")
        require(info.get("SUSignedFeedFailureExpirationInterval") == 0,
                "Signed-feed failures must not expire into unsigned-feed fallback")
        executable = info.get("CFBundleExecutable", "")
        require(executable and PurePosixPath(executable).name == executable, "Invalid app executable name")
        architectures = run(["/usr/bin/lipo", "-archs", app / "Contents/MacOS" / executable]).split()
        require(architectures == ["arm64"], "This release channel is for arm64 app archives")
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
        run(["/usr/bin/codesign", "--verify", "-R=" + PUBLIC_DR, app])
        run(["/usr/bin/xcrun", "stapler", "validate", app])
        run(["/usr/sbin/spctl", "--assess", "--type", "execute", app])
    expected_name = f"PressTalk-{short}-macos-arm64.zip"
    require(archive.name == expected_name, f"Archive must retain its immutable release name: {expected_name}")
    return {"build": build, "version": short, "minimum_macos": minimum, "architecture": "arm64",
            "archive_name": archive.name, "archive_bytes": archive.stat().st_size,
            "archive_sha256": sha256(archive), "tag": "v" + short,
            "download_url": f"https://github.com/{REPOSITORY}/releases/download/v{short}/{archive.name}"}


def parse_feed(data: bytes) -> ET.Element:
    require(len(data) <= MAX_FEED_BYTES, "Appcast exceeds the expected size limit")
    require(b"<!DOCTYPE" not in data.upper() and b"<!ENTITY" not in data.upper(), "Appcast cannot declare external entities")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as error:
        raise ReleaseError(f"Invalid appcast XML: {error}") from error
    require(root.tag == "rss" and len(root.findall("channel")) == 1, "Expected a single RSS appcast channel")
    return root


def feed_builds(root: ET.Element) -> list[str]:
    builds = [item.findtext(NS + "version", "") for item in root.findall("channel/item")]
    for build in builds:
        version(build)
    require(len({version(build) for build in builds}) == len(builds), "Appcast contains duplicate build versions")
    return builds


def immutable_url(url: str, short: str) -> None:
    expected = f"https://github.com/{REPOSITORY}/releases/download/v{short}/PressTalk-{short}-macos-arm64.zip"
    require(url == expected, "Enclosure must be an exact versioned GitHub ZIP URL, without latest/draft/query redirects")


def validate_feed_structure(data: bytes, metadata: dict, previous_build: str) -> str:
    root = parse_feed(data)
    builds = feed_builds(root)
    require(builds, "Appcast must contain the candidate release")
    require(version(metadata["build"]) > version(previous_build), "Candidate build must be newer than the previous public build")
    require(max(map(version, builds)) == version(metadata["build"]), "Candidate must be the highest build in this feed")
    selected = []
    for item in root.findall("channel/item"):
        build = item.findtext(NS + "version", "")
        short = item.findtext(NS + "shortVersionString", "")
        require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", short) is not None, "Feed item is not a stable public version")
        enclosures = item.findall("enclosure")
        require(len(enclosures) == 1, "Each appcast item needs one full update archive")
        enclosure = enclosures[0]
        immutable_url(enclosure.get("url", ""), short)
        signature = enclosure.get(NS + "edSignature", "")
        try:
            require(len(base64.b64decode(signature, validate=True)) == 64, "Missing/invalid archive EdDSA signature")
        except ValueError as error:
            raise ReleaseError("Invalid archive signature base64") from error
        require(item.findtext(NS + "hardwareRequirements") == "arm64", "Feed item must explicitly require Apple silicon")
        minimum = item.findtext(NS + "minimumSystemVersion", "")
        version(minimum)
        require(item.find(NS + "channel") is None, "Prerelease channels cannot enter the stable feed")
        require(item.find(NS + "deltas") is None, "Delta updates are not enabled for this release workflow")
        require(item.find(NS + "releaseNotesLink") is None, "Embed release notes inside the signed feed")
        if version(build) == version(metadata["build"]):
            require(short == metadata["version"], "Feed public version differs from the signed app")
            require(enclosure.get("url") == metadata["download_url"], "Candidate enclosure URL mismatch")
            require(enclosure.get("length") == str(metadata["archive_bytes"]), "Archive length differs from enclosure")
            require(version(minimum) == version(metadata["minimum_macos"]), "Feed minimum macOS differs from the signed app")
            selected.append(signature)
    require(len(selected) == 1, "Candidate build is missing from the feed")
    return selected[0]


def previous_floor(args, tools: SparkleTools) -> str:
    floor = args.previous_build
    version(floor)
    if args.previous_appcast:
        tools.verify(args.previous_appcast)
        builds = feed_builds(parse_feed(args.previous_appcast.read_bytes()))
        floor = max([floor] + builds, key=version)
    return floor


def validate_local(args, tools: SparkleTools, metadata: dict, feed: Path, floor: str) -> dict:
    # Authenticate feed before parsing release metadata, and archive before publication.
    tools.verify(feed)
    signature = validate_feed_structure(feed.read_bytes(), metadata, floor)
    tools.verify(args.archive, signature)
    return {"status": "local_signatures_and_release_metadata_verified", "published": False,
            "feed_url": FEED_URL, "feed_sha256": sha256(feed), "previous_build": floor,
            "release": metadata, "sparkle": tools.provenance()}


def generate(args, tools: SparkleTools, metadata: dict, floor: str) -> dict:
    require(version(metadata["build"]) > version(floor), "Refusing a duplicate/downgrade build")
    output = args.output.resolve()
    if output.exists():
        # Re-running the exact preparation preserves signed bytes and timestamps.
        return validate_local(args, tools, metadata, output / "appcast.xml", floor)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".presstalk-feed-", dir=output.parent) as temporary:
        stage = Path(temporary)
        shutil.copy2(args.archive, stage / args.archive.name)
        if args.previous_appcast:
            shutil.copy2(args.previous_appcast, stage / "appcast.xml")
        if args.release_notes:
            require(args.release_notes.suffix in (".md", ".txt"), "Use plain text/Markdown embedded release notes")
            shutil.copy2(args.release_notes, stage / (args.archive.stem + args.release_notes.suffix))
        run([tools.directory / "generate_appcast", "--account", tools.account,
             "--download-url-prefix", metadata["download_url"].rsplit("/", 1)[0] + "/",
             "--maximum-deltas", "0", "--maximum-versions", "3", "--embed-release-notes",
             "--link", "https://presstalk.app/", stage], timeout=300)
        feed = stage / "appcast.xml"
        receipt = validate_local(args, tools, metadata, feed, floor)
        require(sha256(stage / args.archive.name) == metadata["archive_sha256"], "Generation changed the final archive")
        # Only export the signed XML and receipt. Release archives stay at their original path.
        output.mkdir()
        shutil.copy2(feed, output / "appcast.xml")
        (output / "generation-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


class HTTPSOnlyRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        require(urllib.parse.urlsplit(new_url).scheme == "https", "Refusing an insecure HTTP redirect")
        return super().redirect_request(request, response, code, message, headers, new_url)


def fetch(url: str, maximum: int) -> bytes:
    require(urllib.parse.urlsplit(url).scheme == "https", "Only HTTPS is allowed")
    request = urllib.request.Request(url, headers={"User-Agent": "PressTalk-release-verifier", "Accept": "application/vnd.github+json" if "api.github.com" in url else "*/*"})
    with urllib.request.build_opener(HTTPSOnlyRedirect()).open(request, timeout=60) as response:
        data = response.read(maximum + 1)
    require(len(data) <= maximum, "Remote response exceeds its expected size")
    return data


def validate_public_metadata(release: dict, metadata: dict) -> dict:
    require(release.get("tag_name") == metadata["tag"], "GitHub release tag mismatch")
    require(release.get("draft") is False and release.get("prerelease") is False and release.get("published_at"),
            "Public feed cannot reference a draft, prerelease, or unpublished GitHub release")
    assets = [asset for asset in release.get("assets", []) if asset.get("name") == metadata["archive_name"]]
    require(len(assets) == 1, "Published ZIP asset missing or duplicated")
    asset = assets[0]
    require(isinstance(release.get("id"), int) and isinstance(asset.get("id"), int), "GitHub release/asset identity is missing")
    require(asset.get("state") == "uploaded" and asset.get("size") == metadata["archive_bytes"], "GitHub asset is incomplete or has the wrong size")
    require(asset.get("browser_download_url") == metadata["download_url"], "GitHub asset URL differs from signed feed")
    digest = asset.get("digest")
    if digest:
        require(digest == "sha256:" + metadata["archive_sha256"], "GitHub asset digest differs from signed archive")
    return asset


def verify_public(args, tools: SparkleTools, metadata: dict, floor: str) -> dict:
    receipt = validate_local(args, tools, metadata, args.appcast, floor)
    url = f"https://api.github.com/repos/{REPOSITORY}/releases/tags/{metadata['tag']}"
    release = json.loads(fetch(url, MAX_FEED_BYTES))
    asset = validate_public_metadata(release, metadata)
    downloaded = fetch(metadata["download_url"], metadata["archive_bytes"])
    require(len(downloaded) == metadata["archive_bytes"] and hashlib.sha256(downloaded).hexdigest() == metadata["archive_sha256"],
            "Public download bytes differ from the signed release archive")
    try:
        live_feed = fetch(FEED_URL, MAX_FEED_BYTES)
    except urllib.error.HTTPError as error:
        require(error.code == 404 and args.allow_initial_feed, "Current feed unavailable; cannot establish safe publication order")
        receipt["current_feed"] = "404; explicitly preparing first updater feed"
    else:
        with tempfile.TemporaryDirectory(prefix="presstalk-live-feed-") as temporary:
            path = Path(temporary) / "appcast.xml"
            path.write_bytes(live_feed)
            tools.verify(path)
        live_builds = feed_builds(parse_feed(live_feed))
        require(live_feed == args.appcast.read_bytes() or not live_builds or max(map(version, live_builds)) < version(metadata["build"]),
                "Public feed already has this build or a newer one; refusing overwrite/downgrade")
        receipt["current_feed_builds"] = live_builds
        receipt["public_feed_already_matches"] = live_feed == args.appcast.read_bytes()
    receipt.update(status="public_asset_verified_ready_for_feed_publication", published=False,
                   checked_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   github_release_id=release.get("id"), github_asset_id=asset.get("id"),
                   github_immutable_release=release.get("immutable"), public_archive_sha256=metadata["archive_sha256"])
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "generate", "validate", "verify-public"),
                        help="prepare generates/reuses signed XML and verifies the already-published immutable asset; never publishes the feed")
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--tools-dir", type=Path, required=True)
    parser.add_argument("--keychain-account", required=True)
    parser.add_argument("--public-key-file", type=Path, required=True)
    parser.add_argument("--previous-build", required=True)
    parser.add_argument("--previous-appcast", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--appcast", type=Path)
    parser.add_argument("--release-notes", type=Path)
    parser.add_argument("--allow-initial-feed", action="store_true")
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    try:
        generating = args.command in ("prepare", "generate")
        require(not generating or args.output is not None, "prepare/generate require --output")
        require(generating or args.appcast is not None, "validate/verify-public require --appcast")
        key = public_key(args.public_key_file.read_text().strip())
        tools = SparkleTools(args.tools_dir, args.keychain_account, key)
        if not generating:
            # Authenticate the supplied feed and ZIP before extracting the archive.
            tools.verify(args.appcast)
            root = parse_feed(args.appcast.read_bytes())
            enclosures = [node for node in root.findall("channel/item/enclosure")
                          if node.get("url", "").rsplit("/", 1)[-1] == args.archive.name]
            require(len(enclosures) == 1, "Signed appcast must identify exactly one matching archive")
            tools.verify(args.archive, enclosures[0].get(NS + "edSignature", ""))
        metadata = inspect_archive(args.archive.resolve(), key)
        floor = previous_floor(args, tools)
        if generating:
            result = generate(args, tools, metadata, floor)
            if args.command == "prepare":
                args.appcast = args.output / "appcast.xml"
                result = verify_public(args, tools, metadata, floor)
                public_receipt = args.output / "publication-receipt.json"
                if public_receipt.exists():
                    prior = json.loads(public_receipt.read_text())
                    require(prior.get("github_asset_id") == result["github_asset_id"],
                            "Published asset was replaced since previous verification; preserve immutable asset identity")
                public_receipt.write_text(json.dumps(result, indent=2) + "\n")
        elif args.command == "validate":
            result = validate_local(args, tools, metadata, args.appcast, floor)
        else:
            result = verify_public(args, tools, metadata, floor)
        if args.receipt:
            with args.receipt.open("x") as stream:
                json.dump(result, stream, indent=2)
                stream.write("\n")
        print(json.dumps(result, indent=2))
        return 0
    except (ReleaseError, OSError, ValueError, subprocess.TimeoutExpired, zipfile.BadZipFile) as error:
        print(f"Appcast refused: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
