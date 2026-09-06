#!/usr/bin/env python3
"""Vendors the landing page's webfonts so the page makes no third-party request.

A German seller embedding fonts from fonts.googleapis.com transmits every
visitor's IP address to Google before the visitor has consented to anything.
German courts have treated that as an actionable privacy violation, and on a
page whose entire claim is that nothing leaves your machine it is also simply
incoherent.

All three families are SIL Open Font License 1.1, so redistribution is allowed
provided the licence travels with them.

Only the latin and latin-ext subsets are kept. The page is English and German;
the Vietnamese, Greek and Cyrillic subsets Google serves would be dead weight.
German umlauts and the eszett live in latin (U+00C4 and friends); latin-ext is
kept for the occasional borrowed name.
"""
from __future__ import annotations

import re
import sys
import urllib.request
from pathlib import Path

CSS_URL = (
    "https://fonts.googleapis.com/css2"
    "?family=Archivo:wght@500;600;800"
    "&family=IBM+Plex+Mono:wght@400;500"
    "&family=Source+Serif+4:opsz,wght@8..60,400;8..60,600"
    "&display=swap"
)
# Google serves different files per User-Agent. A modern browser UA yields woff2.
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36")
KEEP_SUBSETS = {"latin", "latin-ext"}

ROOT = Path(__file__).resolve().parent.parent
FONT_DIR = ROOT / "site" / "fonts"


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def main() -> int:
    css = fetch(CSS_URL).decode("utf-8")
    FONT_DIR.mkdir(parents=True, exist_ok=True)

    # Each @font-face is preceded by a /* subset */ comment naming its subset.
    blocks = re.split(r"/\*\s*([\w-]+)\s*\*/", css)
    # split yields ['', subset, block, subset, block, ...]
    pairs = list(zip(blocks[1::2], blocks[2::2]))
    if not pairs:
        print("no subset-annotated @font-face blocks found", file=sys.stderr)
        return 1

    out: list[str] = []
    downloaded = 0
    for subset, block in pairs:
        if subset not in KEEP_SUBSETS:
            continue
        m = re.search(r"url\((https://fonts\.gstatic\.com/[^)]+\.woff2)\)", block)
        family = re.search(r"font-family:\s*'([^']+)'", block)
        weight = re.search(r"font-weight:\s*([\d\s]+);", block)
        if not (m and family and weight):
            continue
        url = m.group(1)
        slug = family.group(1).replace(" ", "-").lower()
        w = weight.group(1).strip().replace(" ", "-")
        name = f"{slug}-{w}-{subset}.woff2"
        target = FONT_DIR / name
        if not target.exists():
            target.write_bytes(fetch(url))
            downloaded += 1
        out.append(block.strip().replace(url, f"fonts/{name}"))

    if not out:
        print("no latin/latin-ext faces survived filtering", file=sys.stderr)
        return 1

    header = (
        "/* Vendored from Google Fonts so the page makes no third-party request.\n"
        "   Archivo, IBM Plex Mono and Source Serif 4 are SIL Open Font License 1.1.\n"
        "   Regenerate with scripts/presstalk_vendor_webfonts.py -- do not hand-edit. */\n"
    )
    (FONT_DIR / "fonts.css").write_text(header + "\n" + "\n".join(out) + "\n")
    total = len(list(FONT_DIR.glob("*.woff2")))
    size = sum(f.stat().st_size for f in FONT_DIR.glob("*.woff2"))
    print(f"{len(out)} faces, {total} woff2 files "
          f"({downloaded} newly downloaded), {size // 1024} KiB total")
    print(f"wrote {FONT_DIR / 'fonts.css'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
