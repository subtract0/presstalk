#!/usr/bin/env python3
"""Fails if a download or checkout link on the site does not resolve.

A broken download button is invisible from inside the repository. The HTML is
valid, the gates pass, the page deploys -- and the first person to find out is
a stranger who wanted the app, which is the one visitor we cannot afford to
lose.

The specific trap this exists for: GitHub's /releases/latest/download/<name>
alias only resolves while <name> belongs to the newest release. The site links
to PressTalk-0.1.11-macos-arm64.zip through that alias, so publishing 0.1.12
turns the live download button into a 404 without touching a single file here.
Nothing else in this repository would notice.

Checks only links that must work for a purchase to complete: the release
download and the checkout. Ordinary reading links are not worth failing a
deploy over.
"""
from __future__ import annotations

import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
MUST_RESOLVE = (
    re.compile(r"https://github\.com/[^\"'\s]+/releases/[^\"'\s]+"),
    re.compile(r"https://buy\.stripe\.com/[^\"'\s]+"),
)
UA = "PressTalk-link-gate (+https://presstalk.app)"


def status(url: str) -> tuple[int, str]:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, ""
    except urllib.error.HTTPError as e:
        return e.code, e.reason
    except Exception as e:                      # DNS, TLS, timeout
        return 0, str(e)


def main() -> int:
    urls: dict[str, set[str]] = {}
    for page in sorted(SITE.rglob("*.html")):
        text = page.read_text(encoding="utf-8")
        for pattern in MUST_RESOLVE:
            for m in pattern.finditer(text):
                urls.setdefault(m.group(0).rstrip('"\'')  , set()).add(
                    str(page.relative_to(ROOT)))

    if not urls:
        print("No download or checkout links found on the site.", file=sys.stderr)
        print("That is not a pass: a page with no way to get the app is broken.",
              file=sys.stderr)
        return 1

    failures = 0
    for url, pages in sorted(urls.items()):
        code, detail = status(url)
        where = ", ".join(sorted(pages))
        if code == 200:
            print(f"ok    {code}  {url}")
        else:
            print(f"FAIL  {code or 'no response'}  {url}")
            print(f"        linked from {where}"
                  + (f"\n        {detail}" if detail else ""))
            failures += 1

    print()
    if failures:
        print(f"{failures} link(s) a buyer needs do not resolve.")
        return 1
    print(f"All {len(urls)} download and checkout link(s) resolve.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
