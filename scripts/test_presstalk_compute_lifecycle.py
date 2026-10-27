#!/usr/bin/env python3
"""Exercise actual app lifecycle functions with a controlled model loader.

No app startup, microphone, model, network, defaults or permissions are used.
Method bodies are extracted verbatim; only external service types are mocked.
Three compiled negative controls prove that regressions are observable.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(os.environ.get("PRESSTALK_TEST_APP_SOURCE", ROOT / "Sources/JarvisTap/main.swift"))
DECLARATIONS = (
    "private enum WhisperLoadState",
    "private func withStateLock<T>",
    "private func requestComputeChange()",
    "private func startWhisperWarmupIfNeeded()",
    "private func startReservedSpeechModelWarmup(",
    "private func loadParakeetV3(",
    "private func markSpeechModelReady()",
)


def extract(source, declaration):
    lines = source.splitlines()
    starts = [i for i, line in enumerate(lines) if line.startswith("    " + declaration)]
    assert len(starts) == 1, f"Expected one production declaration: {declaration}"
    start = starts[0]
    # Production members close at the class member indentation. Nested Swift
    # statements are more deeply indented; do not parse braces inside strings.
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "    }")
    return "\n".join(lines[start:end + 1])


def compile_and_run(scratch, name, source):
    driver = scratch / "main.swift"
    driver.write_text(source)
    binary = scratch / name
    built = subprocess.run([
        "swiftc", "-module-cache-path", str(scratch / "module-cache"),
        str(ROOT / "Sources/PressTalkCore/TranscriptionComputePolicy.swift"),
        str(driver), "-o", str(binary),
    ], capture_output=True, text=True, timeout=90)
    if built.returncode:
        raise AssertionError(built.stderr)
    return subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)


def main():
    production = SOURCE.read_text()
    methods = {declaration: extract(production, declaration) for declaration in DECLARATIONS}
    template = (ROOT / "Tests/Fixtures/TranscriptionComputeLifecycle/main.swift.in").read_text()
    marker = "    // PRODUCTION_DECLARATIONS"
    assert template.count(marker) == 1

    def render(parts):
        return template.replace(marker, "\n\n".join(parts.values()))

    with tempfile.TemporaryDirectory(prefix="presstalk-compute-lifecycle-") as directory:
        scratch = Path(directory)
        result = compile_and_run(scratch, "lifecycle", render(methods))
        assert result.returncode == 0, result.stdout + result.stderr
        print(result.stdout.strip())
        mutants = [
            ("reservation", "private func requestComputeChange()",
             "whisperLoadState = .loading", "whisperLoadState = .idle",
             "Idle-to-loading reservation was lost"),
            ("stale-success", "private func loadParakeetV3(",
             "device: device, requestedDevice: settingsStore.transcriptionComputeDevice)",
             "device: device, requestedDevice: device)",
             "A superseded successful load replaced the active processor"),
            ("stale-failure", "private func startReservedSpeechModelWarmup(",
             "guard requestedDevice == settingsStore.transcriptionComputeDevice else {",
             "guard true else {",
             "Superseded failure rolled back the latest setting or displayed a stale error"),
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
