#!/usr/bin/env python3
"""Scores a fallback sweep: does the Whisper quality fallback earn its latency?

For every clip where the fallback ran, this compares the Parakeet transcript and
the Whisper transcript against the same reference, so the question stops being
"did the text change" (it usually does) and becomes "did it get better".
"""
from __future__ import annotations

import argparse
import json
import re
import unicodedata
from pathlib import Path

PARAKEET = re.compile(r"Parakeet v3 ANE transcript: (.*)")
WHISPER = re.compile(r"Primary offline Whisper transcript: (.*)")
FIXTURE = re.compile(r"Fixture audio loaded path=(\S+)")


def normalize(text: str) -> list[str]:
    text = unicodedata.normalize("NFC", text).lower()
    text = re.sub(r"[^\w\säöüß]", " ", text)
    return text.split()


def word_error_rate(reference: str, hypothesis: str) -> tuple[int, int]:
    ref, hyp = normalize(reference), normalize(hypothesis)
    if not ref:
        return 0, 0
    previous = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, start=1):
        current = [i]
        for j, h in enumerate(hyp, start=1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (r != h)))
        previous = current
    return previous[-1], len(ref)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sweep", required=True, help="sweep output directory")
    parser.add_argument("--eval-set", required=True, help="TSV of category, id, reference text")
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    references = {}
    for line in Path(args.eval_set).read_text().splitlines():
        parts = line.split("\t")
        if len(parts) >= 3:
            references[(parts[0], parts[1])] = parts[2]

    # The denominator is what was ATTEMPTED, taken from the results file, not
    # from what the trace happened to contain. Building rows only from trace
    # blocks that carry a recogniser candidate silently drops every clip that
    # failed, and then reports "0 produced nothing" over the survivors.
    attempted: list[dict] = []
    results_path = Path(args.sweep, "results.jsonl")
    if results_path.exists():
        for line in results_path.read_text().splitlines():
            if not line.strip():
                continue
            try:
                attempted.append(json.loads(line))
            except json.JSONDecodeError:
                attempted.append({"fixture": "", "transcript": "", "outcome": "unparseable"})

    trace = Path(args.sweep, "trace.log").read_text(errors="replace")

    # Transcripts are redacted in the log by default. Scoring "<redacted chars=57
    # ...>" against a reference yields a word error rate over 100% and a glowing
    # verdict for whichever engine was not redacted, which is how a privacy fix
    # silently turned into a 84-point improvement.
    if "<redacted chars=" in trace:
        raise SystemExit(
            "This trace has redacted transcripts, so nothing here can be scored.\n"
            "Re-run the sweep with PRESSTALK_LOG_TRANSCRIPTS=1 "
            "(presstalk_fallback_sweep.sh sets it)."
        )

    rows = []
    for block in trace.split("Fixture audio loaded")[1:]:
        fixture_match = FIXTURE.search("Fixture audio loaded" + block[:400])
        if not fixture_match:
            continue
        stem = Path(fixture_match.group(1)).stem
        pieces = stem.split("__")
        if len(pieces) < 2:
            continue
        key = (pieces[0], pieces[1])
        reference = references.get(key)
        if reference is None:
            continue

        parakeet = PARAKEET.search(block)
        whisper = WHISPER.search(block)
        if not parakeet:
            continue
        rows.append({
            "fixture": stem,
            "category": pieces[0],
            "id": pieces[1],
            "reference": reference,
            "parakeet": parakeet.group(1).strip(),
            "whisper": whisper.group(1).strip() if whisper else None,
        })

    def wer_over(pairs) -> float | None:
        errors = total = 0
        for reference, hypothesis in pairs:
            e, t = word_error_rate(reference, hypothesis)
            errors += e
            total += t
        return (errors / total * 100) if total else None

    # The delivered text is what the user actually got: post-cleanup,
    # post-vocabulary-repair, and after the app decided which candidate to keep.
    # Scoring the first Whisper candidate instead measures a value the app is
    # free to discard.
    delivered: dict[str, str] = {}
    results_path = Path(args.sweep, "results.jsonl")
    if results_path.exists():
        for line in results_path.read_text().splitlines():
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            fixture = Path(record.get("fixture", "")).stem
            if fixture:
                delivered[fixture] = record.get("transcript", "")
    for row in rows:
        row["delivered"] = delivered.get(row["fixture"])

    contested = [r for r in rows if r["whisper"] is not None]
    print(f"clips scored                     {len(rows)}")
    if rows:
        print(f"clips where the fallback ran     {len(contested)}  ({len(contested) / len(rows):.0%})")

    # The corpus number, including clips the fallback never touched and clips
    # that produced nothing. This is the one to quote about the product.
    # Every attempted clip counts, including the ones that produced nothing: an
    # empty transcript scores as a total miss against its reference, which is
    # what it is.
    corpus_rows = []
    rows_by_fixture = {r["fixture"]: r for r in rows}
    unscorable = 0
    for record in attempted:
        fixture = Path(record.get("fixture", "")).stem
        row = rows_by_fixture.get(fixture)
        if row is not None:
            corpus_rows.append((row["reference"], record.get("transcript", "")))
            continue
        pieces = fixture.split("__")
        reference = references.get((pieces[0], pieces[1])) if len(pieces) >= 2 else None
        if reference is None:
            # No reference to score against. Reported, never silently dropped.
            unscorable += 1
            continue
        corpus_rows.append((reference, record.get("transcript", "")))

    print()
    if corpus_rows:
        corpus = wer_over(iter(corpus_rows))
        empty = sum(1 for _, hypothesis in corpus_rows if not hypothesis.strip())
        print(f"WHOLE CORPUS, text as delivered  {corpus:.2f}% WER over {len(corpus_rows)} attempted clips"
              f" ({empty} produced nothing)")
    else:
        print("WHOLE CORPUS                     no attempted clips could be scored")
    if unscorable:
        print(f"                                 {unscorable} attempted clip(s) had no reference and were skipped")
    if attempted and len(corpus_rows) + unscorable != len(attempted):
        print(f"                                 WARNING: {len(attempted)} attempted but "
              f"{len(corpus_rows)} scored; the denominator is wrong")
    print()

    if contested:
        parakeet_wer = wer_over((r["reference"], r["parakeet"]) for r in contested)
        # Prefer the delivered text; fall back to the raw candidate only where the
        # harness did not record one.
        whisper_wer = wer_over(
            (r["reference"], r["delivered"] if r.get("delivered") else r["whisper"])
            for r in contested)
        print("On the clips where the fallback ran, scored against the same reference:")
        print(f"  Parakeet candidate alone       {parakeet_wer:.2f}% WER")
        print(f"  As delivered (with fallback)   {whisper_wer:.2f}% WER")
        delta = whisper_wer - parakeet_wer
        verdict = "worse" if delta > 0 else "better"
        print(f"  The fallback is {abs(delta):.2f} points {verdict}.")
        print()

        better = worse = same = 0
        for r in contested:
            pe, _ = word_error_rate(r["reference"], r["parakeet"])
            we, _ = word_error_rate(r["reference"], r["delivered"] if r.get("delivered") else r["whisper"])
            if we < pe:
                better += 1
            elif we > pe:
                worse += 1
            else:
                same += 1
        print(f"  per clip: fallback better on {better}, worse on {worse}, tied on {same}")
        print()

    by_category: dict[str, list[dict]] = {}
    for r in contested:
        by_category.setdefault(r["category"], []).append(r)
    if by_category:
        print(f"{'category':<16}{'n':>4}{'parakeet':>11}{'delivered':>12}{'delta':>9}")
        for category, group in sorted(by_category.items()):
            p = wer_over((r["reference"], r["parakeet"]) for r in group)
            w = wer_over(
                (r["reference"], r["delivered"] if r.get("delivered") else r["whisper"])
                for r in group)
            print(f"{category:<16}{len(group):>4}{p:>10.1f}%{w:>11.1f}%{w - p:>+9.1f}")

    if args.out:
        Path(args.out).write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")
        print(f"\nrows written to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
