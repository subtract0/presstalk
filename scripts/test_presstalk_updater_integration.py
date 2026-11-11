#!/usr/bin/env python3
"""Compile production update/termination decisions with inert OS services.

No real app termination, microphone, clipboard, updater, preferences or network.
Function and closure bodies under test are extracted verbatim from main.swift.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(os.environ.get("PRESSTALK_TEST_APP_SOURCE", ROOT / "Sources/JarvisTap/main.swift"))


def declaration(source, marker, indentation=4):
    lines = source.splitlines()
    prefix = " " * indentation
    starts = [i for i, line in enumerate(lines) if line.startswith(prefix + marker)]
    assert len(starts) == 1, f"Production declaration changed: {marker}"
    start = starts[0]
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == prefix + "}")
    return "\n".join(lines[start:end + 1])


def extract(source):
    markers = [
        "private func withStateLock<T>", "private var updateActivityIsBusy:",
        "func applicationShouldTerminate(_", "private func notifyUpdateActivityChanged()",
        "private func startNativeTriggerCalibration()", "private func restorePasteboardAfterInsertion(",
    ]
    methods = "\n\n".join(declaration(source, marker) for marker in markers)
    probe = declaration(source, "controller.onVerifyMicrophone =", 8)
    press = declaration(source, "private func handlePress(")
    begin = press.index("        enum PressDecision {")
    end = press.index("        let captureSessionID: UInt64", begin)
    admission = press[begin:end].rstrip()
    return methods, probe, admission


def run(scratch, name, source):
    template = (ROOT / "Tests/Fixtures/UpdaterIntegration/main.swift.in").read_text()
    methods, probe, admission = extract(source)
    for marker, value in [
        ("    // PRODUCTION_DECLARATIONS", methods),
        ("        // PRODUCTION_PROBE_CALLBACK", probe),
        ("        // PRODUCTION_CAPTURE_ADMISSION", admission),
    ]:
        assert template.count(marker) == 1
        template = template.replace(marker, value)
    driver = scratch / "main.swift"
    driver.write_text(template)
    binary = scratch / name
    build = subprocess.run([
        "swiftc", "-module-cache-path", str(scratch / "module-cache"),
        str(ROOT / "Sources/PressTalkCore/UpdateSafetyPolicy.swift"), str(driver), "-o", str(binary),
    ], capture_output=True, text=True, timeout=90)
    assert build.returncode == 0, build.stderr
    try:
        return subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired as error:
        def decoded(value):
            return value.decode(errors="replace") if isinstance(value, bytes) else (value or "")
        raise AssertionError(
            f"{name}: fixture exceeded its 20-second safety bound; timeout is NOT a passing negative control.\n"
            + decoded(error.stdout) + decoded(error.stderr)
        ) from error


def main():
    production = SOURCE.read_text()
    with tempfile.TemporaryDirectory(prefix="presstalk-updater-integration-") as directory:
        scratch = Path(directory)
        result = run(scratch, "integration", production)
        assert result.returncode == 0, result.stdout + result.stderr
        print(result.stdout.strip())
        mutants = [
            ("missing-observer", "if becameIdle { notifyUpdateActivityChanged() }", "if becameIdle {}",
             "Busy-to-idle observer did not resume termination"),
            ("capture-during-termination", "if updateInstallationReserved || terminationPending { return .ignoreTermination }",
             "if false { return .ignoreTermination }", "New capture began while termination was pending"),
            ("probe-during-termination", "!self.permissionRenewalInFlight, !self.updateInstallationReserved,\n                      !self.terminationPending else { return false }",
             "!self.permissionRenewalInFlight else { return false }",
             "New microphone probe began while termination was pending"),
            ("repeat-termination-reply", "self.terminationPending = false\n                self.updateInstallationReserved = true",
             "self.terminationPending = true\n                self.updateInstallationReserved = true",
             "Termination reply ran before an idle installation reservation"),
        ]
        for name, before, after, expected in mutants:
            assert production.count(before) == 1, f"Negative-control anchor changed: {name}"
            result = run(scratch, name, production.replace(before, after))
            assert result.returncode != 0 and expected in result.stdout, (
                f"Negative control failed: {name}\n" + result.stdout + result.stderr)
            print(f"PASS: negative control rejects {name} regression")


if __name__ == "__main__":
    main()
