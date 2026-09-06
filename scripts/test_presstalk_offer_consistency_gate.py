#!/usr/bin/env python3
"""Proves the offer-consistency gate catches the mistake that created it.

On 2026-09-06 a search and replace shortening the trial from 14 days to 3 also
shortened the stated refund window to 3 days in the German pages, where 14 is
statutory. Every gate in the repository passed. These cases are that bug and
its neighbours, plus the true sentences an over-eager version flagged.
"""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GATE = ROOT / "scripts" / "presstalk_offer_consistency_gate.py"
POLICY_DAYS = int(re.search(
    r"public init\(trialDays: Int = (\d+)\)",
    (ROOT / "Sources/PressTalkCore/EntitlementPolicy.swift").read_text()).group(1))

MUST_FAIL = {
    "the actual bug: refund shortened to the trial length": (
        "de/index.html",
        "<p>Du kannst innerhalb von 3 Tagen eine Erstattung anfordern.</p>"),
    "English refund shortened": (
        "index.html", "<p>A 3-day refund is available after purchase.</p>"),
    "refund of zero days": (
        "index.html", "<p>Refund within 0 days of purchase.</p>"),
    "trial copy left at the old length": (
        "index.html", "<p>Try it free for 14 days. No card.</p>"),
    "German trial left at the old length": (
        "de/index.html", "<p>14 Tage kostenlos testen, ohne Karte.</p>"),
    "trial longer than the code grants": (
        "index.html", "<p>Free trial: 30 days, no account.</p>"),
}

MUST_PASS = {
    "correct trial and correct refund in one clause": (
        "index.html",
        f"<p>{POLICY_DAYS} days. No card. No account.</p>"
        "<p>A 14-day refund is available after purchase.</p>"),
    "correct German pair": (
        "de/index.html",
        f"<p>{POLICY_DAYS} Tage. Keine Kreditkarte.</p>"
        "<p>Innerhalb von 14 Tagen eine Erstattung anfordern.</p>"),
    "a usage record, not an offer": (
        "index.html", "<p>174 dictations across 26 days of real use.</p>"),
    "an ad measurement window": (
        "index.html", "<p>Read paid sales 21 days after the last click.</p>"),
    "a refund longer than statutory": (
        "index.html", "<p>A 30-day refund is available after purchase.</p>"),
    "a version number that is not a day count": (
        "index.html", "<p>Requires macOS 14 or later.</p>"),
}


def run(filename: str, body: str) -> int:
    with tempfile.TemporaryDirectory() as d:
        site = Path(d) / "site"
        (site / "de").mkdir(parents=True)
        (site / filename).write_text(f"<title>t</title>{body}", encoding="utf-8")
        (Path(d) / "docs" / "launch").mkdir(parents=True)
        (Path(d) / "Sources" / "PressTalkCore").mkdir(parents=True)
        (Path(d) / "Sources/PressTalkCore/EntitlementPolicy.swift").write_text(
            f"public init(trialDays: Int = {POLICY_DAYS}) {{}}")
        patched = GATE.read_text().replace(
            "ROOT = Path(__file__).resolve().parent.parent",
            f"ROOT = Path({str(d)!r})")
        gate = Path(d) / "gate.py"
        gate.write_text(patched)
        return subprocess.run([sys.executable, str(gate)],
                              capture_output=True, text=True).returncode


def main() -> int:
    failures = 0
    for label, (name, body) in MUST_FAIL.items():
        if run(name, body) != 0:
            print(f"ok    caught: {label}")
        else:
            print(f"FAIL  missed: {label}\n        {body}")
            failures += 1
    for label, (name, body) in MUST_PASS.items():
        if run(name, body) == 0:
            print(f"ok    allowed: {label}")
        else:
            print(f"FAIL  wrongly flagged: {label}\n        {body}")
            failures += 1
    print()
    if failures:
        print(f"FAILED: {failures} case(s)")
        return 1
    print(f"PASS: {len(MUST_FAIL)} defects caught, {len(MUST_PASS)} true "
          f"statements allowed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
