#!/usr/bin/env python3
"""Turns one harness run into a report that counts failures.

Percentiles over successful runs only will tell you dictation is fast right up
until the day half of it stops working, so the denominator here is every
attempted run.
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
from pathlib import Path

SPAN = re.compile(r"latency span=(?P<name>[a-z_]+) seconds=(?P<seconds>[0-9.]+)")


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = fraction * (len(ordered) - 1)
    low = int(position)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", required=True)
    parser.add_argument("--trace", required=True)
    parser.add_argument("--label", default="unlabelled")
    parser.add_argument("--fixture", default="")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    records = []
    for line in Path(args.results).read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            records.append({"transcript": "", "outcome": "unparseable"})

    attempted = len(records)
    produced = [r for r in records if r.get("transcript")]
    empty = attempted - len(produced)

    spans: dict[str, list[float]] = {}
    for line in Path(args.trace).read_text(errors="replace").splitlines():
        for match in SPAN.finditer(line):
            spans.setdefault(match.group("name"), []).append(float(match.group("seconds")))

    span_summary = {}
    for name, values in sorted(spans.items()):
        span_summary[name] = {
            "count": len(values),
            "min": round(min(values), 3),
            "p50": round(percentile(values, 0.50) or 0, 3),
            "p95": round(percentile(values, 0.95) or 0, 3),
            "max": round(max(values), 3),
        }

    end_to_end = [r["keyupToTranscriptSeconds"] for r in produced if "keyupToTranscriptSeconds" in r]

    report = {
        "label": args.label,
        "fixture": args.fixture,
        "runsAttempted": attempted,
        "runsProducingText": len(produced),
        "runsProducingNothing": empty,
        # Recognition, not delivery. The harness suppresses insertion by default so
        # it cannot type into the operator's windows, which means it cannot prove
        # text reached another app. Naming it "delivery" would claim exactly the
        # thing this harness is unable to check.
        "textProducedRate": round(len(produced) / attempted, 3) if attempted else None,
        "insertionExercised": False,
        "keyupToTranscriptSeconds": {
            "count": len(end_to_end),
            "min": round(min(end_to_end), 3) if end_to_end else None,
            "p50": round(percentile(end_to_end, 0.50) or 0, 3) if end_to_end else None,
            "p95": round(percentile(end_to_end, 0.95) or 0, 3) if end_to_end else None,
            "max": round(max(end_to_end), 3) if end_to_end else None,
        },
        "traceSpans": span_summary,
        "transcripts": [r.get("transcript", "") for r in records],
        "qualityFallbackStatus": next(
            (r.get("qualityFallbackStatus") for r in produced if r.get("qualityFallbackStatus")), None
        ),
    }

    Path(args.out).write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")

    print()
    print(f"label                {report['label']}")
    print(f"runs attempted       {attempted}")
    print(f"produced text        {len(produced)}")
    print(f"produced nothing     {empty}")
    if report["textProducedRate"] is not None:
        print(f"produced-text rate   {report['textProducedRate']:.1%}  (insertion not exercised)")
    if end_to_end:
        k = report["keyupToTranscriptSeconds"]
        print(f"keyup -> transcript  p50 {k['p50']}s  p95 {k['p95']}s  max {k['max']}s")
    for name, stats in span_summary.items():
        print(f"  span {name:<26} n={stats['count']:<3} p50 {stats['p50']}s  p95 {stats['p95']}s")
    if report["qualityFallbackStatus"]:
        print(f"quality fallback     {report['qualityFallbackStatus']}")
    print(f"report               {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
