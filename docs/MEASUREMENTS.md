# What has actually been measured

Every number PressTalk publishes has to come from here, with its method attached.
The two ways to get this wrong are quoting a throughput figure as a latency
figure, and averaging over the runs that worked.

Last run: 2026-09-05, studio1 (M4 Max, 128 GB, macOS 26.6), PressTalk 0.1.7.

## End to end, 144 German clips

Run with `scripts/presstalk_fallback_sweep.sh`, which replays audio in place of
the microphone and drives the trigger headlessly, so the whole shipped path runs:
trigger, capture, freeze, recognition, cleanup, vocabulary repair, delivery.

| | |
|---|---|
| Clips attempted | 144 |
| Produced text | 144 |
| Produced nothing | 0 |
| Word error rate | **11.25 %** |

Scored with `scripts/presstalk_score_fallback_sweep.py` against the written
references in `~/presstalk-de-eval/eval_set.tsv`, using the text the app finally
settled on rather than any intermediate candidate. The denominator is every clip
attempted, taken from the results file: an earlier version built it from trace
blocks that contained a recogniser candidate, which dropped failed clips entirely
and then reported "0 produced nothing" over the survivors.

**"Produced text" is not "delivered text".** The harness suppresses insertion so
a test run cannot type into whatever window is focused, so these runs prove
recognition reached the end of the pipeline, not that words arrived in another
app. That distinction is why the fresh-Mac run in
[LAUNCH_GATES.md](LAUNCH_GATES.md) is still the top open gate.

## Latency

| Span | p50 | p95 | max | n |
|---|---|---|---|---|
| Key release → transcript | 0.95 s | 1.45 s | 3.06 s | 144 |
| Final inference | 0.07 s | 0.10 s | — | 10 |
| Key release → audio frozen | 0.50 s | 0.51 s | — | 10 |

**The 0.50 s is a fixture artifact, not a product measurement.** The release tail
waits for silence before freezing audio, up to a configured maximum. Replayed
clips end mid-speech, so silence never arrives and the tail runs to its cap on
every run. Real dictation ends in silence and exits early. The honest reading:
0.95 s p50 is an *upper* bound on this fixture, and live speech has not been
measured.

Percentiles are over every attempted run. A success-only percentile would have
hidden the reliability finding below.

## What the harness found

Before the readiness ordering was fixed, startup waited for both the primary
recognizer and the optional fallback, and a trigger pressed inside that window
was refused.

| | Text delivered |
|---|---|
| Ready after both models | 4 / 5 |
| Ready after the primary recognizer | 8 / 8, then 10 / 10, then 144 / 144 |

Capture engine startup is now 0.001 s, because it no longer loads a model.

## Recognition throughput

Realtime factor: seconds of audio processed per second of wall clock. Best of 3,
byte-identical fixtures, English.

| Backend | M4 Max | M1 Ultra | M1 Max |
|---|---|---|---|
| Parakeet v3 (Neural Engine) | 115.2× | 61.9× | 56.6× |
| WhisperKit large-v3-turbo (GPU) | 5.5× | 3.7× | 3.2× |

**This is not a latency number and must never be quoted as one.** 115× means a
minute of audio is recognised in about half a second. It says nothing about how
long a user waits after releasing a key, which is the table above and is roughly
ten times larger.

## Does the quality fallback earn its cost?

The fallback re-runs low-confidence Parakeet output through a larger WhisperKit
model, costing roughly a second when it fires.

| | |
|---|---|
| Clips where it fired | 54 of 144 (38 %) |
| Parakeet candidate alone, those clips | 18.98 % WER |
| As delivered, with the fallback | 15.15 % WER |
| Difference | 3.83 points better |
| Per clip | better on 18, worse on 15, tied on 21 |

By category, on the clips where it fired:

| Category | n | Parakeet | Delivered | Δ |
|---|---|---|---|---|
| umlauts | 4 | 28.9 % | 0.0 % | −28.9 |
| compounds | 3 | 17.4 % | 0.0 % | −17.4 |
| anglicisms | 14 | 19.4 % | 15.0 % | −4.4 |
| brands | 15 | 14.5 % | 10.5 % | −3.9 |
| names | 8 | 12.0 % | 12.0 % | 0.0 |
| numbers | 3 | 72.7 % | 75.8 % | +3.0 |
| dictation | 4 | 4.3 % | 8.7 % | +4.3 |
| coaching | 3 | 4.8 % | 23.8 % | +19.0 |

**This does not settle the default.** Aggregate WER improves, but per clip it is
close to even, and fewer word errors can still mean a worse mistake in a name or
a number. Most category counts are three or four clips. The `numbers` row is
measuring the reference style, not the models: both engines emit numerals while
the references spell digits out, which is why both sit near 73 %.

Note also that a fresh install does not have the fallback model at all, since it
is never downloaded implicitly. A warmed development machine therefore does not
describe what a new buyer experiences.

**To settle it:** roughly 60 natural dictations from three German speakers on
real microphones, run through both configurations with the output labels blinded,
measuring corrections made and meaning changed rather than word distance. Freeze
the current threshold first. Repeating the same sentence in three synthetic
voices is not three independent observations.

## Caveats that apply to everything above

- The audio is macOS `say` output in three synthetic voices. It is a regression
  baseline, not a claim about anyone's voice in a real room.
- One machine, one microphone, one acoustic environment.
- No comparison against any other dictation app has been run, so no claim about
  being quicker or more accurate than one can be made.
- Insertion into a third-party app under a real physical keypress is **not**
  covered. The harness suppresses insertion by default so it cannot type into
  the operator's windows. That path still needs a human.

## Reproducing

```bash
# One fixture, many runs, every attempt counted
bash scripts/presstalk_e2e_harness.sh --fixture <audio> --runs 10 --label warm

# A whole corpus in one app session
bash scripts/presstalk_fallback_sweep.sh --fixtures <dir> --out <dir>
python3 scripts/presstalk_score_fallback_sweep.py --sweep <dir> --eval-set <tsv>
```
