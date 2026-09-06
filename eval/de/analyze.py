#!/usr/bin/env python3
"""Slice the German eval results by category, voice and backend."""
import csv, statistics, sys, collections

rows = []
with open(sys.argv[1] if len(sys.argv) > 1 else '/Users/am/presstalk-de-eval/results.tsv') as f:
    for r in csv.DictReader(f, delimiter='\t'):
        try: r['wer'] = float(r['wer']); r['cer'] = float(r['cer'])
        except (ValueError, TypeError): continue
        rows.append(r)

backends = sorted({r['backend'] for r in rows})
cats     = sorted({r['category'] for r in rows})

def mean(xs): return statistics.mean(xs) if xs else float('nan')

print(f"scored clips: {len(rows)}\n")
print("=== WER % by category (lower is better) ===")
print(f"  {'category':13s} " + "".join(f"{b:>21s}" for b in backends))
for c in cats:
    line = f"  {c:13s} "
    for b in backends:
        line += f"{mean([r['wer'] for r in rows if r['category']==c and r['backend']==b]):>20.1f}%"
    print(line)
print(f"  {'OVERALL':13s} " + "".join(
    f"{mean([r['wer'] for r in rows if r['backend']==b]):>20.1f}%" for b in backends))

print("\n=== WER % by voice (robustness across speakers) ===")
for v in sorted({r['voice'] for r in rows}):
    print(f"  {v:13s} " + "".join(
        f"{mean([r['wer'] for r in rows if r['voice']==v and r['backend']==b]):>20.1f}%" for b in backends))

print("\n=== worst 12 clips on the recommended backend (parakeet-v3-ane) ===")
bad = sorted([r for r in rows if r['backend']=='parakeet-v3-ane'], key=lambda r: -r['wer'])[:12]
for r in bad:
    print(f"  {r['wer']:5.1f}%  [{r['category']}/{r['id']}/{r['voice']}]")
    print(f"          got: {r['transcript'][:100]}")

print("\n=== clean clips (WER 0) per backend ===")
for b in backends:
    n = sum(1 for r in rows if r['backend']==b and r['wer']==0.0)
    t = sum(1 for r in rows if r['backend']==b)
    print(f"  {b:22s} {n:3d}/{t:3d}  ({100*n/t:.0f}%)")
