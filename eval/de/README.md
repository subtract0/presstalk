# The German test set behind PressTalk's published word error rate

PressTalk claims 12.71 % word error rate on German against Apple's 19.38 % on
the same audio. This directory is the whole basis of that claim: the sentences,
the audio, the references, the runner and the scorer. Run it yourself and
disagree with a number, not with an assertion.

    ./run_eval.sh /path/to/PressTalkAsrBench "$PWD" results.tsv
    ./analyze.py results.tsv

`PressTalkAsrBench` builds from this repository:

    swift build -c release --product PressTalkAsrBench

## What is here

| | |
|---|---|
| `eval_set.tsv` | 48 German sentences, 8 categories of 6 |
| `audio/` | 144 clips: every sentence spoken by three German voices |
| `ref/` | the reference text for each clip, one file per clip |
| `gen_audio.sh` | regenerates `audio/` and `ref/` from `eval_set.tsv` |
| `run_eval.sh` | scores every clip on every backend, one TSV row per clip |
| `analyze.py` | slices the results by category, voice and backend |
| `results.tsv` | the run that produced the published figure |
| `MANIFEST.sha256` | checksums, so you can prove your audio is byte-identical |

The eight categories are `anglicisms`, `brands`, `coaching`, `compounds`,
`dictation`, `names`, `numbers` and `umlauts` — chosen because they are where a
German speaker actually watches dictation fail, not because they are where
PressTalk does well.

## Two traps this set already fell into

Both were hit for real on 2026-09-04 and both are now guarded in `gen_audio.sh`.

**`say -v Reed` is the English Reed.** The German voice is
`Reed (Deutsch (Deutschland))`. Ask for the short name and German text gets
spoken by an English voice — and `say` exits 0, so the first run silently scored
96 nonsense clips above 100 % WER and blamed the recognizer. `gen_audio.sh` now
transcribes one probe clip per voice and refuses to build the set if any voice
scores worse than 30 % WER on a sentence it should find easy. A fixture has to
prove itself before anything measured on it is allowed to mean something.

**Umlauts do not survive the shell.** Text reaches `say` through `-f` and a
file, never as an argument, so the reference matches what was spoken byte for
byte.

## What this set does not show

Read this before quoting the number anywhere.

- **The voices are synthetic.** Three macOS TTS voices — Anna, Sandy and Rocko.
  Synthetic speech has no hesitation, no room, no accent and no breath. This
  measures how a recognizer handles German *text as spoken*, and it is not
  evidence about your voice.
- **Substantial vocabulary overlap.** 68 of the 70 terms in PressTalk's German
  repair lexicon appear somewhere in these references. The set and the lexicon
  were built by the same person in the same week. Both engines get the same
  vocabulary pass so the comparison stays fair, but a set with no overlap would
  score both engines worse.
- **Six clips per category.** Any per-category figure rests on six sentences
  times three voices. Category differences here are suggestive, not established.
- **One machine.** studio1, an M4 Max. Recognition quality should not vary by
  machine; latency certainly does.
- **This compares recognition engines, not products.** Apple Dictation as a
  whole has behaviour this harness never touches — its own endpointing, its own
  insertion path, its own punctuation handling.

## Reproducing the audio rather than trusting ours

    ./gen_audio.sh eval_set.tsv "$PWD" /path/to/PressTalkAsrBench

This overwrites `audio/` and `ref/`. Regenerated clips will not be byte-identical
to the committed ones across different macOS releases, because Apple revises its
voices. If your scores differ from `results.tsv`, check `MANIFEST.sha256` first
— it distinguishes "the recognizer behaved differently" from "you are scoring
different audio".
