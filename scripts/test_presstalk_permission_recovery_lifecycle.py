#!/usr/bin/env python3
"""Run actual production recovery methods with in-memory system boundaries.

No application, permission reset, microphone, process launch, or user defaults
are used. Method bodies are extracted verbatim, including startup and modal
flow. Compiled negative controls must fail at the relevant behavioral check.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(os.environ.get("PRESSTALK_TEST_APP_SOURCE", ROOT / "Sources/JarvisTap/main.swift"))
DECLARATIONS = (
    "private func completeStartupIfPossible(",
    "private func clearPermissionRecoveryAfterGrant()",
    "private func recheckPermissionsAfterSettings()",
    "private func currentPermissionRecoveryState()",
    "private func restartForPermissionRecovery()",
    "private func renewAccessibilityPermission()",
)


def extract(source, declaration):
    lines = source.splitlines()
    starts = [i for i, line in enumerate(lines) if line.startswith("    " + declaration)]
    assert len(starts) == 1, f"Expected one production declaration: {declaration}"
    start = starts[0]
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "    }")
    return "\n".join(lines[start:end + 1])


def compile_and_run(scratch, name, source):
    driver = scratch / "main.swift"
    driver.write_text(source)
    binary = scratch / name
    built = subprocess.run([
        "swiftc", "-module-cache-path", str(scratch / "module-cache"),
        str(ROOT / "Sources/PressTalkCore/PermissionRecoveryPolicy.swift"),
        str(driver), "-o", str(binary),
    ], capture_output=True, text=True, timeout=90)
    assert built.returncode == 0, built.stderr
    return subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)


def main():
    methods = {name: extract(SOURCE.read_text(), name) for name in DECLARATIONS}
    template = (ROOT / "Tests/Fixtures/PermissionRecoveryLifecycle/main.swift.in").read_text()
    marker = "    // PRODUCTION_DECLARATIONS"
    assert template.count(marker) == 1

    def render(parts):
        return template.replace(marker, "\n\n".join(parts.values()))

    with tempfile.TemporaryDirectory(prefix="presstalk-permission-lifecycle-") as directory:
        scratch = Path(directory)
        result = compile_and_run(scratch, "recovery", render(methods))
        assert result.returncode == 0, result.stdout + result.stderr
        print(result.stdout.strip().splitlines()[-1])
        mutants = [
            ("episode-clear", "private func completeStartupIfPossible(",
             "            clearPermissionRecoveryAfterGrant()", "            /* regression: missing clear */",
             "Granted startup retained an earlier recovery episode"),
            ("modal-approval", "private func renewAccessibilityPermission()",
             "guard !accessibilityIsTrusted(), currentPermissionRecoveryState() == .renewPermission else {",
             "guard true else {", "Approval received during confirmation was reset"),
            ("in-flight-startup", "private func completeStartupIfPossible(",
             "        guard !withStateLock({ permissionRenewalInFlight || updateInstallationReserved || terminationPending }) else { return }", "",
             "Startup rearmed services during permission renewal"),
            ("update-startup", "private func completeStartupIfPossible(",
             "permissionRenewalInFlight || updateInstallationReserved || terminationPending",
             "permissionRenewalInFlight || terminationPending",
             "Startup rearmed services during update or termination"),
            ("termination-startup", "private func completeStartupIfPossible(",
             "permissionRenewalInFlight || updateInstallationReserved || terminationPending",
             "permissionRenewalInFlight || updateInstallationReserved",
             "Startup rearmed services during update or termination"),
            ("reserved-recheck", "private func recheckPermissionsAfterSettings()",
             "                || updateInstallationReserved || terminationPending", "",
             "Permission recheck changed listener or recovery state during update or termination"),
        ]
        for name, declaration, before, after, expected in mutants:
            mutated = methods.copy()
            assert mutated[declaration].count(before) == 1, f"Mutation anchor changed: {name}"
            mutated[declaration] = mutated[declaration].replace(before, after)
            result = compile_and_run(scratch, name, render(mutated))
            assert result.returncode != 0 and expected in result.stdout, (
                f"Negative control {name} did not detect the intended regression:\n"
                + result.stdout + result.stderr)
            print(f"PASS: negative control rejects {name} regression")


if __name__ == "__main__":
    main()
