#!/usr/bin/env python3
"""Isolated real Sparkle installer acceptance; never targets the daily app.

Uses unchanged pinned sparkle-cli source, an ephemeral TEST Keychain key,
loopback-only feeds, unique synthetic bundle IDs, and user-writable fixture apps.
No --interactive, sudo, microphone, production signing key, or publication.
"""
import argparse
import datetime
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import threading
import time
import uuid
import xml.etree.ElementTree as ET

NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
ET.register_namespace("sparkle", NS[1:-1])


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest(app):
    return {str(p.relative_to(app)): digest(p) for p in app.rglob("*") if p.is_file() and not p.is_symlink()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sdk", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    root = args.output.resolve()
    root.mkdir(mode=0o700, parents=True, exist_ok=False)
    token = uuid.uuid4().hex
    prefix = "com.am.presstalk.updaterfixture." + token
    account = prefix + ".test-key"
    tools = repo / ".build/artifacts/sparkle/Sparkle/bin"
    framework = tools.parent / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    source = repo / ".build/checkouts/Sparkle/sparkle-cli"
    domains = [prefix + suffix for suffix in (".cli", ".valid", ".tampered")]
    receipt = {"started_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "fixture_root": str(root), "test_domains": domains, "test_key_account": account,
               "production_key_used": False, "daily_app_touched": False, "microphone_capture": False,
               "commands": [], "scenarios": {}, "cleanup": []}
    server = None
    key_created = False
    home_dir = Path.home()

    def save():
        (root / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")

    def run(command, label, timeout=90, check=True):
        completed = subprocess.run([str(x) for x in command], capture_output=True, text=True, timeout=timeout)
        (root / (label + ".log")).write_text(completed.stdout + completed.stderr)
        receipt["commands"].append({"label": label, "command": [str(x) for x in command], "exit_code": completed.returncode})
        save()
        if check and completed.returncode:
            raise RuntimeError(f"{label} failed ({completed.returncode}); see {label}.log")
        return completed

    try:
        assert os.getuid() != 0
        assert args.sdk.is_dir() and framework.is_dir()
        for domain in domains:
            assert not (home_dir / "Library/Preferences" / (domain + ".plist")).exists()
            assert not (home_dir / "Library/Caches" / domain).exists()
            exists = subprocess.run(["/usr/bin/defaults", "read", domain], capture_output=True).returncode == 0
            assert not exists, "Refusing to touch an existing preference domain"
        receipt["preflight_test_domains_absent"] = True
        receipt["official_cli_source_sha256"] = {name: digest(source / name) for name in
                                                ("main.m", "SPUCommandLineDriver.m", "SPUCommandLineUserDriver.m")}
        cli = root / "TestUpdater.app"
        (cli / "Contents/MacOS").mkdir(parents=True)
        (cli / "Contents/Frameworks").mkdir()
        run(["/usr/bin/ditto", framework, cli / "Contents/Frameworks/Sparkle.framework"], "copy-pinned-framework")
        info = {"CFBundleIdentifier": domains[0], "CFBundleExecutable": "sparkle-fixture-updater",
                "CFBundleName": "PressTalk Fixture Updater", "CFBundlePackageType": "APPL", "LSUIElement": True,
                "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "LSMinimumSystemVersion": "14.0.0",
                "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True}}
        (cli / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        executable = cli / "Contents/MacOS/sparkle-fixture-updater"
        compile_args = ["/usr/bin/xcrun", "clang", "-isysroot", args.sdk, "-arch", "arm64", "-mmacosx-version-min=14.0",
                        "-fobjc-arc", "-fblocks", "-DSPU_OBJC_DIRECT=__attribute__((objc_direct))",
                        "-DSPU_OBJC_DIRECT_MEMBERS=__attribute__((objc_direct_members))", "-F", framework.parent,
                        "-framework", "Cocoa", "-framework", "Sparkle", "-Wl,-rpath,@executable_path/../Frameworks",
                        "-o", executable] + [source / name for name in receipt["official_cli_source_sha256"]]
        run(compile_args, "build-official-cli")
        run(["/usr/bin/codesign", "--force", "--sign", "-", cli], "sign-test-cli-adhoc")
        run([tools / "generate_keys", "--account", account], "create-ephemeral-test-key")
        key_created = True
        public = run([tools / "generate_keys", "--account", account, "-p"], "read-test-public-key").stdout.strip()
        receipt["test_public_key"] = public

        server_root = root / "server"
        server_root.mkdir()
        requests = []

        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, format_string, *values):
                requests.append(format_string % values)

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=str(server_root)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        base_url = f"http://127.0.0.1:{server.server_address[1]}"
        receipt["network_scope"] = base_url + " (loopback only)"
        fixture_source = root / "fixture.c"
        fixture_source.write_text('#include <stdio.h>\nint main(void) { puts(FIXTURE_VERSION); return 0; }\n')
        binaries = {}
        for build in ("1", "2"):
            binary = root / ("fixture-v" + build)
            run(["/usr/bin/xcrun", "clang", "-isysroot", args.sdk, "-arch", "arm64", "-mmacosx-version-min=14.0",
                 '-DFIXTURE_VERSION="' + build + '"', fixture_source, "-o", binary], "build-fixture-v" + build)
            binaries[build] = binary

        for scenario, domain in zip(("valid", "tampered"), domains[1:]):
            directory = root / scenario
            installed = directory / "installed/Fixture.app"
            update = directory / "update/Fixture.app"
            feed_dir = server_root / scenario
            feed_dir.mkdir()
            feed_url = base_url + f"/{scenario}/appcast.xml"
            for app, build in ((installed, "1"), (update, "2")):
                (app / "Contents/MacOS").mkdir(parents=True)
                shutil.copy2(binaries[build], app / "Contents/MacOS/fixture")
                info = {"CFBundleIdentifier": domain, "CFBundleExecutable": "fixture", "CFBundleName": "Updater Fixture",
                        "CFBundlePackageType": "APPL", "CFBundleVersion": build, "CFBundleShortVersionString": build + ".0",
                        "LSMinimumSystemVersion": "14.0.0", "SUFeedURL": feed_url, "SUPublicEDKey": public,
                        "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
                        "SUSignedFeedFailureExpirationInterval": 0, "SUEnableAutomaticChecks": False,
                        "SUSendProfileInfo": False, "LSUIElement": True}
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
                run(["/usr/bin/codesign", "--force", "--sign", "-", app], scenario + "-sign-v" + build)
            settings = directory / "application-support/settings.json"
            settings.parent.mkdir()
            settings.write_text('{"sentinel":"keep-my-settings","compute":"ane","shortcut":"fn"}\n')
            before = manifest(installed)
            expected = manifest(update)
            settings_hash = digest(settings)
            archive = feed_dir / "Fixture-2.zip"
            run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", update, archive], scenario + "-archive")
            signature = run([tools / "sign_update", "--account", account, "-p", archive], scenario + "-sign-archive").stdout.strip()
            tree = ET.Element("rss", version="2.0")
            channel = ET.SubElement(tree, "channel")
            ET.SubElement(channel, "title").text = "Local updater fixture"
            item = ET.SubElement(channel, "item")
            for key, value in (("version", "2"), ("shortVersionString", "2.0"),
                               ("minimumSystemVersion", "14.0.0"), ("hardwareRequirements", "arm64")):
                ET.SubElement(item, NS + key).text = value
            ET.SubElement(item, "enclosure", {"url": base_url + f"/{scenario}/Fixture-2.zip", "type": "application/octet-stream",
                                             "length": str(archive.stat().st_size), NS + "edSignature": signature})
            feed = feed_dir / "appcast.xml"
            feed.write_bytes(ET.tostring(tree, encoding="utf-8", xml_declaration=True))
            run([tools / "sign_update", "--account", account, feed], scenario + "-sign-feed")
            if scenario == "tampered":
                data = bytearray(archive.read_bytes())
                # Same-length mutation after signing, preserving metadata length.
                data[len(data) // 2] ^= 1
                archive.write_bytes(data)
            start = time.monotonic()
            result = run([executable, installed, "--check-immediately", "--user-agent-name", "PressTalk-Isolated-Acceptance",
                          "--verbose"], scenario + "-real-updater", timeout=90, check=False)
            after = manifest(installed)
            built_version = plistlib.loads((installed / "Contents/Info.plist").read_bytes())["CFBundleVersion"]
            passed = (result.returncode == 0 and after == expected and built_version == "2") if scenario == "valid" else (
                result.returncode != 0 and after == before and built_version == "1" and
                "error 4005 (SUSparkleErrorDomain)" in result.stderr and "improperly signed" in result.stderr)
            settings_unchanged = digest(settings) == settings_hash
            receipt["scenarios"][scenario] = {"passed": passed and settings_unchanged, "exit_code": result.returncode,
                 "duration_seconds": round(time.monotonic() - start, 3), "bundle_version_after": built_version,
                 "old_app_intact": after == before, "new_app_installed_exactly": after == expected,
                 "settings_file_unchanged": settings_unchanged, "before_manifest": before, "after_manifest": after,
                 "log": scenario + "-real-updater.log"}
            save()
        receipt["requests"] = requests
        receipt["state"] = "passed" if all(x["passed"] for x in receipt["scenarios"].values()) else "acceptance_failed"
        receipt["limits"] = ["Synthetic ad-hoc-signed apps, not notarized production PressTalk",
                             "Target app was closed; installer replacement tested, app relaunch not exercised",
                             "No claim about preserving real PressTalk TCC grants from this isolated fixture"]
    except Exception as error:
        receipt.update(state="blocked_or_failed", error=str(error))
    finally:
        if server:
            server.shutdown()
            server.server_close()
        if key_created:
            result = subprocess.run(["/usr/bin/security", "delete-generic-password", "-s", "https://sparkle-project.org", "-a", account], capture_output=True)
            receipt["cleanup"].append({"ephemeral_test_key_deleted": result.returncode == 0, "exit_code": result.returncode})
        if receipt.get("preflight_test_domains_absent"):
            for domain in domains:
                # Only UUID domains proven absent before this run are touched.
                result = subprocess.run(["/usr/bin/defaults", "delete", domain], capture_output=True)
                preference = home_dir / "Library/Preferences" / (domain + ".plist")
                if preference.exists():
                    preserved = root / "preserved-test-preferences" / preference.name
                    preserved.parent.mkdir(exist_ok=True)
                    shutil.move(str(preference), str(preserved))
                cache = home_dir / "Library/Caches" / domain
                if cache.exists():
                    preserved = root / "preserved-test-caches" / domain
                    preserved.parent.mkdir(exist_ok=True)
                    shutil.move(str(cache), str(preserved))
                receipt["cleanup"].append({"test_preference_domain": domain, "delete_exit_code": result.returncode,
                                           "test_preference_file_removed": not preference.exists(),
                                           "cache_removed_from_active_namespace": not cache.exists()})
        receipt["completed_at_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        save()
    print(json.dumps({"state": receipt["state"], "receipt": str(root / "receipt.json"),
                      "scenarios": {key: {k: v for k, v in value.items() if "manifest" not in k}
                                    for key, value in receipt["scenarios"].items()}, "error": receipt.get("error")}, indent=2))
    return 0 if receipt["state"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
