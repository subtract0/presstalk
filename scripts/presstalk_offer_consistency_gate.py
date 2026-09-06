#!/usr/bin/env python3
"""Keeps the offer the page states identical to the offer the app enforces.

Two numbers on this page mean completely different things and both are written
as a count of days, which is how they got swapped. On 2026-09-06 a search and
replace that shortened the trial from 14 days to 3 also shortened the refund
window to 3 -- in the German pages, where 14 days of withdrawal is statutory
under BGB 355 and not the seller's to shorten. Every gate we had passed.

So this checks the two independently:

  trial   -- must equal EntitlementPolicy.trialDays, because a page promising
             more days than the code grants produces a support ticket, and one
             promising fewer wastes the trial.
  refund  -- must never be stated as fewer than 14 days anywhere.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POLICY = ROOT / "Sources" / "PressTalkCore" / "EntitlementPolicy.swift"
STATUTORY_REFUND_DAYS = 14

# Every "N days" / "N Tage", classified by what surrounds it rather than by
# one clever pattern. The first attempt matched any day count not followed by a
# refund word, and flagged "26 days" (the founder's usage record) and "21 days"
# (an ad measurement window) as broken trial copy. A gate that cries wolf on
# true sentences gets switched off, so proximity to explicit trial or refund
# vocabulary is required before anything is judged.
DAYS = re.compile(r"(\d+)[\s-]*(?:days?|Tagen?|Tage)\b", re.IGNORECASE)
TRIAL_WORDS = ("trial", "testen", "kostenlos", "free", "no card", "ohne karte",
               "keine kreditkarte", "no account", "ohne konto", "gratis")
REFUND_WORDS = ("refund", "erstattung", "widerruf", "money back", "geld zurück")
# Classification is by *nearest* keyword, not by presence within a window.
# A fixed window failed on the real page, where "3 days. No card. No account."
# and "14-day refund" sit one clause apart: the refund word landed inside the
# trial number's window and the gate reported a 3-day refund that was never
# written. Nearest-wins reads both correctly, and a day count with no trial or
# refund word within reach is neither -- an ad measurement window, a usage
# record -- so it is left alone.
NEAREST = 45

# German pages are charged in euros, and euros and dollars are not conversions
# of one another here: EUR is tax-inclusive while USD and CAD have tax added at
# checkout, so 20 EUR and 20 USD are deliberately different amounts. Printing
# "$20" to a German who is then charged 20 EUR advertises a price that is not
# charged, which the Preisangabenverordnung does not permit. The claims gate
# saw nothing, because 20 is 20 in both.
PRICE_IN_DOLLARS = re.compile(r"(?:US-?Dollar|\$\s?\d)", re.IGNORECASE)

TAG = re.compile(r"<[^>]+>")


def policy_trial_days() -> int:
    m = re.search(r"public init\(trialDays: Int = (\d+)\)", POLICY.read_text())
    if not m:
        print(f"FAIL  could not read trialDays from {POLICY.relative_to(ROOT)}",
              file=sys.stderr)
        raise SystemExit(2)
    return int(m.group(1))


def main() -> int:
    expected = policy_trial_days()
    failures = []
    targets = sorted((ROOT / "site").rglob("*.html")) + \
              sorted((ROOT / "docs" / "launch").glob("*.md"))

    for path in targets:
        text = TAG.sub(" ", path.read_text(encoding="utf-8"))
        text = re.sub(r"\s+", " ", text)
        rel = path.relative_to(ROOT)

        for m in DAYS.finditer(text):
            days = int(m.group(1))
            lowered = text.lower()
            here = m.start()

            def nearest(words: tuple[str, ...]) -> int | None:
                best = None
                for word in words:
                    start = 0
                    while (found := lowered.find(word, start)) != -1:
                        distance = abs(found - here)
                        if best is None or distance < best:
                            best = distance
                        start = found + 1
                return best

            trial_at = nearest(TRIAL_WORDS)
            refund_at = nearest(REFUND_WORDS)
            quote = text[max(0, here - 45):m.end() + 45].strip()

            in_reach = [d for d in (trial_at, refund_at) if d is not None and d <= NEAREST]
            if not in_reach:
                continue
            is_refund = refund_at is not None and refund_at <= NEAREST and \
                (trial_at is None or refund_at <= trial_at)

            if is_refund:
                if days < STATUTORY_REFUND_DAYS:
                    failures.append(
                        f"{rel}: states a {days}-day refund window; "
                        f"{STATUTORY_REFUND_DAYS} is statutory and not ours to "
                        f"shorten\n        …{quote}…")
            elif days != expected:
                failures.append(
                    f"{rel}: offers {days} days where the app grants {expected}"
                    f"\n        …{quote}…")

    # Currency, per page language.
    for path in targets:
        if path.suffix != ".html":
            continue
        raw = path.read_text(encoding="utf-8")
        # Only pages served to German readers. The document's own language,
        # not any occurrence of lang="de" -- the English pages carry a language
        # switcher that links to the German ones, and matching that flagged
        # every correct dollar price on the English site.
        html_lang = re.search(r"<html[^>]*\blang=[\"']([a-zA-Z-]+)", raw)
        page_is_german = (path.parent.name == "de"
                          or (html_lang and html_lang.group(1).lower().startswith("de")))
        if not page_is_german:
            continue
        text = TAG.sub(" ", raw)
        for m in PRICE_IN_DOLLARS.finditer(text):
            quote = text[max(0, m.start() - 45):m.end() + 45].strip()
            quote = re.sub(r"\s+", " ", quote)
            failures.append(
                f"{path.relative_to(ROOT)}: quotes a dollar price on a German "
                f"page, which is charged in euros\n        …{quote}…")

    for f in failures:
        print(f"FAIL  {f}")
    print()
    print(f"trial in code: {expected} days · statutory refund: "
          f"{STATUTORY_REFUND_DAYS} days · {len(targets)} file(s) checked")
    if failures:
        print(f"{len(failures)} inconsistency(ies) between the stated and the "
              f"enforced offer.")
        return 1
    print("The offer the page states matches the offer the app enforces.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
