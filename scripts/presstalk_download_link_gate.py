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

Checks external release, checkout and recovery links, plus local page links.
The stable checkout page opened by the Mac app must exist and contain an actual
purchase-service link. A commented-out button or a successful redirect to a
missing destination cannot satisfy the gate.
"""
from __future__ import annotations

import re
import subprocess
import sys
from html.parser import HTMLParser
from urllib.parse import urlsplit, unquote
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
MUST_RESOLVE = (
    re.compile(r"https://github\.com/[^\"'\s]+/releases/[^\"'\s]+"),
    re.compile(r"https://buy\.stripe\.com/[^\"'\s]+"),
    re.compile(r"https://presstalk-licenses\.presstalk\.workers\.dev/(?:buy|recover)$"),
)
CHECKOUT_SERVICE = 'https://presstalk-licenses.presstalk.workers.dev/buy'
UA = "PressTalk-link-gate (+https://presstalk.app)"


def status(url: str) -> tuple[int, str]:
    # Exercise redirects too. Cloudflare rejects urllib's TLS client here;
    # curl reaches the same public endpoint without credentials or cookies.
    try:
        result = subprocess.run(['curl', '--silent', '--show-error', '--location',
            '--proto', '=http,https', '--proto-redir', '=http,https', '--max-redirs', '5',
            '--max-time', '30', '--output', '/dev/null', '--write-out', '%{http_code}',
            '--user-agent', UA, url], capture_output=True, text=True, timeout=35)
        if result.returncode:
            return 0, result.stderr.strip()
        return int(result.stdout), ''
    except (OSError, ValueError, subprocess.TimeoutExpired) as e:
        return 0, str(e)


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []

    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            href = dict(attrs).get('href')
            if href:
                self.hrefs.append(href)


def main() -> int:
    urls: dict[str, set[str]] = {}
    local_failures = []
    parsed_pages = {}
    for page in sorted(SITE.rglob("*.html")):
        links = Links()
        links.feed(page.read_text(encoding='utf-8'))
        parsed_pages[page.resolve()] = links.hrefs
        for href in links.hrefs:
            if any(pattern.fullmatch(href) for pattern in MUST_RESOLVE):
                urls.setdefault(href, set()).add(str(page.relative_to(ROOT)))
            parts = urlsplit(href)
            if parts.scheme or parts.netloc or not parts.path:
                continue
            path = unquote(parts.path)
            if not (path.endswith('.html') or path.endswith('/')):
                continue
            if path.endswith('/'):
                path += 'index.html'
            target = ((SITE / path.lstrip('/')) if path.startswith('/') else page.parent / path).resolve()
            if not target.is_relative_to(SITE.resolve()) or not target.is_file():
                local_failures.append(f'{page.relative_to(ROOT)} links missing local page {href}')

    policy = (ROOT / 'Sources/PressTalkCore/EntitlementPolicy.swift').read_text()
    match = re.search(r'public static let checkoutURLString\s*=\s*"([^"]*)"', policy)
    if not match:
        local_failures.append('Cannot read the checkout URL used by the Mac app')
    elif urlsplit(match[1]).hostname == 'presstalk.app':
        target = (SITE / urlsplit(match[1]).path.lstrip('/')).resolve()
        if target not in parsed_pages:
            local_failures.append('The checkout page opened by the Mac app does not exist')
        elif CHECKOUT_SERVICE not in parsed_pages[target]:
            local_failures.append('The Mac checkout page has no link to the purchase service')

    if not any(urlsplit(url).path.endswith('.zip') for url in urls):
        local_failures.append('No direct app download link found on the site')
    if local_failures:
        for failure in local_failures:
            print('FAIL ', failure, file=sys.stderr)
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
