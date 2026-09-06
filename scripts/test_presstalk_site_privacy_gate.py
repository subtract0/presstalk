#!/usr/bin/env python3
"""Proves the site privacy gate fails on every shape of third-party request.

A gate that reports success over a broken thing is worse than no gate. Each
case below plants one real defect and asserts the shipping gate rejects it;
the last cases assert it does NOT reject things that are fine, because a gate
nobody can satisfy gets switched off.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GATE = ROOT / "scripts" / "presstalk_site_privacy_gate.py"

MUST_FAIL = {
    "google fonts stylesheet": (
        'index.html',
        '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo">'
    ),
    "preconnect to a third party": (
        'index.html', '<link rel="preconnect" href="https://fonts.gstatic.com">'
    ),
    "cdn script": (
        'index.html', '<script src="https://cdn.jsdelivr.net/npm/thing.js"></script>'
    ),
    "remote image": (
        'index.html', '<img src="https://example.com/hero.png" alt="hero">'
    ),
    "protocol-relative url": (
        'index.html', '<script src="//evil.example.com/t.js"></script>'
    ),
    "iframe embed": (
        'index.html', '<iframe src="https://www.youtube.com/embed/x"></iframe>'
    ),
    "favicon from a third party": (
        'index.html', '<link rel="icon" href="https://example.com/f.ico">'
    ),
    "css url() in a stylesheet": (
        'style.css', '@font-face { src: url(https://fonts.gstatic.com/a.woff2); }'
    ),
    "css @import": (
        'style.css', '@import url("https://fonts.googleapis.com/css2?family=X");'
    ),
    "inline style background": (
        'index.html', '<div style="background:url(https://example.com/bg.png)">x</div>'
    ),
    "srcset with a remote candidate": (
        'index.html', '<img srcset="local.png 1x, https://example.com/2x.png 2x">'
    ),
    "single-quoted attribute": (
        'index.html', "<script src='https://example.com/a.js'></script>"
    ),
    "unquoted attribute": (
        'index.html', '<script src=https://example.com/a.js></script>'
    ),
}

MUST_PASS = {
    "a link the reader clicks": (
        'index.html', '<a href="https://github.com/subtract0/presstalk">Source</a>'
    ),
    "local stylesheet": ('index.html', '<link rel="stylesheet" href="fonts/fonts.css">'),
    "local font file": ('style.css', '@font-face { src: url(fonts/a.woff2); }'),
    "rel=canonical to another origin": (
        'index.html', '<link rel="canonical" href="https://presstalk.app/">'
    ),
    "hostname mentioned only in a comment": (
        'index.html', '<!-- we deliberately do not load fonts.googleapis.com -->'
    ),
    "mailto link": ('index.html', '<a href="mailto:x@example.com">mail</a>'),
}


def run_gate(body: str, filename: str) -> int:
    with tempfile.TemporaryDirectory() as d:
        (Path(d) / filename).write_text(
            body if filename.endswith(".css")
            else f"<title>t</title>\n{body}\n", encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(GATE), d],
            capture_output=True, text=True).returncode


def main() -> int:
    failures = 0
    for label, (filename, body) in MUST_FAIL.items():
        if run_gate(body, filename) != 0:
            print(f"ok    caught: {label}")
        else:
            print(f"FAIL  missed: {label}\n        {body}")
            failures += 1

    for label, (filename, body) in MUST_PASS.items():
        if run_gate(body, filename) == 0:
            print(f"ok    allowed: {label}")
        else:
            print(f"FAIL  wrongly blocked: {label}\n        {body}")
            failures += 1

    print()
    if failures:
        print(f"FAILED: {failures} case(s)")
        return 1
    print(f"PASS: {len(MUST_FAIL)} defects caught, {len(MUST_PASS)} legitimate "
          f"patterns allowed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
