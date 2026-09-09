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
  rails   -- a payment method named on the page must be one the app can
             actually open. PressTalk gained a second checkout on 2026-09-07,
             and the failure this prevents is a page offering "Pay with PayPal"
             months before, or after, the app has a PayPal URL. The website and
             the binary are edited in different places by different people and
             nothing else makes them agree.
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

# Payment rails, and the words that constitute OFFERING one on a page. Naming a
# rail while explaining that purchases are paused is not an offer; a button or a
# "pay with" phrase is. The distinction matters because the page currently
# explains the paused state and must be allowed to keep doing so.
RAIL_OFFER_WORDS = {
    "paypal": (re.compile(r"(?:pay|bezahl\w*|zahl\w*)[^.<]{0,24}paypal", re.IGNORECASE),
               re.compile(r"paypal[^.<]{0,24}(?:checkout|button|kasse)", re.IGNORECASE)),
}


def policy_rail_urls() -> dict[str, str]:
    """The checkout URL the BINARY holds for each rail, keyed by rail name."""
    text = POLICY.read_text()
    urls: dict[str, str] = {}
    for rail, const in (("stripe", "checkoutURLString"),
                        ("paypal", "paypalCheckoutURLString")):
        m = re.search(
            r"public static let " + const + r"\s*=\s*\"([^\"]*)\"", text)
        if m is None:
            print(f"FAIL  could not read {const} from {POLICY.relative_to(ROOT)}")
            raise SystemExit(1)
        urls[rail] = m.group(1).strip()
    return urls


# HOUSE CONVENTION, not a statement of law. BGB 312j Abs. 3 requires the
# ordering control to be labelled "zahlungspflichtig bestellen" *or equivalent
# unambiguous wording*; CJEU C-249/21 (Fuhrmann-2) holds that the label on the
# control is what counts, and does NOT mandate one literal string or require the
# click to happen on our own domain. An earlier version of this comment claimed
# both, and claimed every PayPal SDK label is insufficient -- none of that is
# supported by the judgment.
#
# What the gate can honestly do is hold us to ONE agreed wording so the question
# is settled once with a lawyer rather than re-litigated per page. Widening the
# accepted set is a legal decision, not a code decision.
ORDER_BUTTON_REQUIRED = "zahlungspflichtig bestellen"

# An ordering CONTROL, not prose. The first version matched any occurrence of
# "kaufen"/"bestellen" anywhere on the page, which failed the sentence
# "Du kannst derzeit nicht kaufen." -- a true statement, flagged as a missing
# order button. A gate that cries wolf on correct copy gets switched off.
ORDER_CONTROL = re.compile(
    r"<(?:a|button)\b[^>]*>(?P<label>(?:(?!</(?:a|button)>).)*?"
    r"(?:kaufen|bestellen|checkout|bezahlen)"
    r"(?:(?!</(?:a|button)>).)*?)</(?:a|button)>",
    re.IGNORECASE | re.DOTALL)

# The control the page itself nominates as contract-concluding.
ORDER_BUTTON_MARKED = re.compile(
    r"<(?:a|button|input)\b[^>]*\bdata-order-button\b[^>]*>"
    r"((?:(?!</(?:a|button)>).)*?)</(?:a|button)>",
    re.IGNORECASE | re.DOTALL)

HTML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
GERMAN_PAGE = re.compile(r'lang\s*=\s*"de"', re.IGNORECASE)

# While Stripe Managed Payments is the only rail, "the contract is with Stripe"
# is a claim about every sale. It stops being one the moment a PayPal order can
# happen, and a buyer must be able to tell which entity they are contracting
# with BEFORE ordering (Art. 246a EGBGB, UWG 5a).
#
# This does NOT establish that the sentence is correct today -- who the
# contracting seller is depends on Stripe's customer terms, and Stripe's own
# Managed Payments terms say it is "not the seller of record" and is deemed
# supplier "for Indirect Tax purposes only". That is docs/launch/DAY1_CHECKS.md
# work, not something a regex settles. All this catches is the sentence
# surviving unqualified once a second rail exists.
CONTRACT_WITH_STRIPE = re.compile(
    r"Kaufvertrag kommt mit\s+Stripe zustande", re.IGNORECASE)


def check_rail_legal_wording(pages: list[Path]) -> list[str]:
    """Wording that must change once we are the seller on SOME transactions."""
    problems: list[str] = []
    urls = policy_rail_urls()
    if not urls.get("paypal"):
        return problems

    for page in pages:
        raw = page.read_text()
        # Comments are not shown to a buyer, so they can neither make a claim
        # nor satisfy one. A commented-out order button used to pass.
        visible = HTML_COMMENT.sub(" ", raw)
        flat = re.sub(r"\s+", " ", visible)

        if CONTRACT_WITH_STRIPE.search(flat):
            problems.append(
                f"{page.relative_to(ROOT)} states the contract is with Stripe, "
                f"unqualified, while a PayPal rail is live -- those orders do "
                f"not contract with Stripe (Art. 246a EGBGB, UWG 5a)")

        german = "/de/" in str(page).replace("\\", "/") or GERMAN_PAGE.search(visible)
        if not german:
            continue

        # A page that links a payment rail must DECLARE which control concludes
        # the contract, with data-order-button. Nothing in static HTML
        # distinguishes a final submit labelled "Weiter" from an ordinary
        # navigation button -- that case passed every keyword rule -- so the
        # page has to say which one it is rather than the gate guessing.
        links_a_rail = any(url and url in visible for url in urls.values())
        if links_a_rail:
            declared = ORDER_BUTTON_MARKED.findall(visible)
            if not declared:
                problems.append(
                    f"{page.relative_to(ROOT)} links a payment rail but marks "
                    f"no ordering control; add data-order-button to the control "
                    f"that concludes the contract so its label can be checked")
            for label in declared:
                text = re.sub(r"\s+", " ", TAG.sub(" ", label)).strip()
                if ORDER_BUTTON_REQUIRED not in text.lower():
                    problems.append(
                        f"{page.relative_to(ROOT)} marks an ordering control "
                        f"labelled {text!r}; house wording is "
                        f"'{ORDER_BUTTON_REQUIRED}'")

        for m in ORDER_CONTROL.finditer(visible):
            label = TAG.sub(" ", m.group("label"))
            label = re.sub(r"\s+", " ", label).strip()
            if ORDER_BUTTON_REQUIRED not in label.lower():
                problems.append(
                    f"{page.relative_to(ROOT)} has a German ordering control "
                    f"labelled {label!r}; house wording is "
                    f"'{ORDER_BUTTON_REQUIRED}' (BGB 312j Abs. 3 allows "
                    f"equivalent wording -- changing it is a lawyer's call)")
    return problems


def check_rails(pages: list[Path]) -> list[str]:
    """A page may only offer a rail the app can actually open."""
    problems: list[str] = []
    urls = policy_rail_urls()
    for page in pages:
        raw = page.read_text()
        for rail, patterns in RAIL_OFFER_WORDS.items():
            offered = any(pat.search(raw) for pat in patterns)
            configured = bool(urls.get(rail))
            if offered and not configured:
                problems.append(
                    f"{page.relative_to(ROOT)} offers {rail} but "
                    f"PressTalkOffer has no {rail} checkout URL")
            if configured and urls[rail] not in raw and offered:
                problems.append(
                    f"{page.relative_to(ROOT)} offers {rail} but does not link "
                    f"the configured {rail} URL")
    # Relative links and service redirects can reach checkout without embedding
    # its absolute URL. The link gate follows the actual customer path.
    for rail, url in urls.items():
        if url and not any(url in p.read_text() for p in pages):
            print(f"note  configured {rail} checkout URL is not written verbatim "
                  "on a page; the download/checkout link gate checks reachability")
    return problems

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

    # The Impressum's service address cannot be written by anyone but the
    # owner: section 5 DDG wants a ladungsfähige Anschrift, a real street
    # address where post can be served. A placeholder shipped to production
    # reads as a complete Impressum to everyone except a regulator.
    imp = ROOT / "site" / "impressum.html"
    if imp.exists():
        text = imp.read_text(encoding="utf-8")
        for marker in ("[Straße und Hausnummer]", "[PLZ Ort]", "[Stra"):
            if marker in text:
                failures.append(
                    "site/impressum.html: service address is still a placeholder; "
                    "an Impressum without a real postal address is not an Impressum")
                break

    # Wired here, not merely defined above. Adding a check function and
    # forgetting to call it is how this repo produced three fail-open gates in
    # one afternoon, and the suite reports green either way.
    html_pages = [p for p in targets if p.suffix == ".html"]
    failures.extend(check_rails(html_pages))
    failures.extend(check_rail_legal_wording(html_pages))

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
