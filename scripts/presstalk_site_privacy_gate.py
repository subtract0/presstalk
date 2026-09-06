#!/usr/bin/env python3
"""Fails if a page in site/ makes an automatic request to a third-party host.

The product's claim is that your voice never leaves your Mac. A landing page
that quietly fetches a stylesheet from Google contradicts that in the one place
a sceptical reader will check first, and for a German seller it is a real
DSGVO exposure: the visitor's IP reaches a third party before any consent.

The distinction this enforces is *automatic* versus *user-initiated*. A link a
reader clicks is fine -- the page does not phone anyone until they choose to
go. A stylesheet, script, image, font, iframe or CSS url() fires on load with
no choice involved, and those are what this refuses.

Exit 0 means every byte the page loads by itself comes from its own origin.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"

# Attributes that cause a fetch without the reader doing anything.
AUTO_ATTRS = {
    "script": ["src"],
    "img": ["src", "srcset"],
    "iframe": ["src"],
    "embed": ["src"],
    "object": ["data"],
    "video": ["src", "poster"],
    "audio": ["src"],
    "source": ["src", "srcset"],
    "track": ["src"],
    "input": ["src"],
    "use": ["href", "xlink:href"],
}
# <link> is conditional: a stylesheet or preload fetches, rel="canonical" does not.
FETCHING_LINK_RELS = {
    "stylesheet", "preload", "prefetch", "preconnect", "dns-prefetch",
    "icon", "shortcut icon", "apple-touch-icon", "manifest", "modulepreload",
}

TAG = re.compile(r"<\s*([a-zA-Z][\w:-]*)((?:\s+[^<>]*?)?)/?>", re.S)
ATTR = re.compile(r'([\w:-]+)\s*=\s*(?:"([^"]*)"|\'([^\']*)\'|([^\s"\'<>`]+))')
CSS_URL = re.compile(r"""url\(\s*['"]?([^'")]+)['"]?\s*\)""")
CSS_IMPORT = re.compile(r"""@import\s+(?:url\(\s*)?['"]([^'"]+)['"]""")
COMMENT = re.compile(r"<!--.*?-->", re.S)


def is_external(value: str) -> bool:
    value = value.strip()
    if not value:
        return False
    if value.startswith("//"):
        return True
    parsed = urlparse(value)
    return parsed.scheme in ("http", "https") and bool(parsed.netloc)


def attrs_of(blob: str) -> dict[str, str]:
    out = {}
    for m in ATTR.finditer(blob):
        out[m.group(1).lower()] = m.group(2) or m.group(3) or m.group(4) or ""
    return out


def scan(path: Path) -> list[str]:
    # Comments are stripped first: a documented hostname in a comment is prose,
    # not a request, and failing on it would push authors to delete the
    # explanation of why the hostname is absent.
    raw = path.read_text(encoding="utf-8")
    text = COMMENT.sub("", raw)
    findings: list[str] = []
    try:
        rel_path = path.relative_to(ROOT)
    except ValueError:
        rel_path = path.name

    def line_of(idx: int) -> int:
        return text.count("\n", 0, idx) + 1

    for m in TAG.finditer(text):
        tag = m.group(1).lower()
        attrs = attrs_of(m.group(2) or "")
        names: list[str] = []
        if tag in AUTO_ATTRS:
            names = AUTO_ATTRS[tag]
        elif tag == "link":
            rel = attrs.get("rel", "").strip().lower()
            if rel in FETCHING_LINK_RELS:
                names = ["href"]
        for name in names:
            for candidate in attrs.get(name, "").split(","):
                candidate = candidate.strip().split(" ")[0]
                if is_external(candidate):
                    findings.append(
                        f"{rel_path}:{line_of(m.start())}  <{tag} {name}> "
                        f"loads {urlparse(candidate).netloc or candidate}"
                    )
        # Inline styles can carry url() too.
        style = attrs.get("style", "")
        for u in CSS_URL.findall(style):
            if is_external(u):
                findings.append(
                    f"{rel_path}:{line_of(m.start())}  inline style url() "
                    f"loads {urlparse(u).netloc}"
                )

    for pattern, label in ((CSS_URL, "css url()"), (CSS_IMPORT, "@import")):
        for m in pattern.finditer(text):
            if is_external(m.group(1)):
                findings.append(
                    f"{rel_path}:{line_of(m.start())}  {label} "
                    f"loads {urlparse(m.group(1)).netloc}"
                )
    return sorted(set(findings))


def main() -> int:
    # An explicit directory lets the test point the real gate at planted
    # defects, so the test exercises the shipping code rather than a copy.
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else SITE
    targets = sorted(root.rglob("*.html")) + sorted(root.rglob("*.css"))
    if not targets:
        print(f"no pages found under {root}", file=sys.stderr)
        return 1

    all_findings: list[str] = []
    for path in targets:
        all_findings.extend(scan(path))

    for f in all_findings:
        print(f"FAIL  {f}")

    print()
    print(f"scanned {len(targets)} file(s) under {root}")
    if all_findings:
        print(f"{len(all_findings)} automatic third-party request(s).")
        print("Vendor the asset locally; scripts/presstalk_vendor_webfonts.py "
              "does this for webfonts.")
        return 1

    print("No automatic third-party requests. Links a reader clicks are not "
          "checked -- those are their choice, not the page's.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
