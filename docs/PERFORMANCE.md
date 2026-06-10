# Performance Notes

These numbers were measured locally on `mbaM4`, a MacBook Air with Apple Silicon M4 and `16 GB` RAM, on `2026-03-13`.

They are not marketing numbers. They are point-in-time measurements from an
older `0.1.5` PressTalk baseline running as a LaunchAgent with:

- `JARVISTAP_AGENT_MODE=dictation`
- `JARVISTAP_WHISPERKIT_MODEL=openai_whisper-large-v3-v20240930_turbo_632MB`
- local WhisperKit/CoreML decoding
- compact listening light enabled

## What Was Measured

The measurements below came from:

- `top`
- `ps`
- the live `jarvistap_trace.log`
- on-disk bundle sizes via `du -sh`

macOS does not expose per-process ANE wattage from an unprivileged shell. `powermetrics` is the correct tool for that, but it requires `sudo`.

## Current Fallback Release

The current fallback release is `v0.1.6-test4`. It keeps local compute only and
uses Parakeet v3 on ANE as the fast first-pass final-text backend, with local
WhisperKit large-v3-turbo retained as quality fallback when Parakeet confidence
or punctuation looks weak.

This is not yet true streaming partial text in the Monologue/Wispr Flow sense:
the release baseline still captures while the trigger is held, finalizes on
release, then pastes. The ANE backend makes that finalization feel close to
instant on tested M4-class machines, while the fallback path protects quality
when the fast pass is not good enough.

## PressTalk 0.1.5 Baseline

### Install Footprint

- App bundle size: `5.5 MB`
- Local speech model used by the app:
  `~/Library/Application Support/JarvisTap/Models/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo_632MB`

### Launch / Ready Time

Latest measured startup from the trace log:

- startup to `PressTalk armed`: `0.11 s`
- startup to `WhisperKit ready`: `1.12 s`

This means the agent becomes present almost immediately and the local speech model is ready about one second later on this machine.

### Runtime Memory / CPU

Measured process: `~/Applications/PressTalk.app/Contents/MacOS/jarvistap`

Ready and idle:

- resident memory settled around `109 MB`
- CPU usage returned to `0.0%`

Listening hold (configured trigger held, no real speech payload):

- resident memory around `158 MB`
- CPU roughly `6.4%` to `7.0%`
- `top` power score roughly `7.3` to `8.2`

Short finalize / post-release window:

- resident memory briefly reached about `205 MB`
- then dropped back toward idle after processing finished

These numbers are encouraging for a local always-available dictation agent. The app is not free, but it is materially lighter than Electron-style speech clients.

## Streaming V1 Branch

Measured locally on `studio1` / M4 Max on `2026-06-09`, branch
`feature/streaming-whisper-tail`, installed as
`~/Applications/PressTalk.app` with:

- `PRESSTALK_ENABLE_STREAMING_TRANSCRIPTION=1`
- `JARVISTAP_RELEASE_TAIL_PADDING_SECONDS=0.50`
- `JARVISTAP_WHISPER_LANGUAGE=de`
- `JARVISTAP_WHISPERKIT_MODEL=openai_whisper-large-v3-v20240930_turbo_632MB`
- `PRESSTALK_WHISPER_COMPUTE=cpu-gpu-no-ane`
- Shure MV7i selected as the input device

This branch is a UX bridge, not the final ASR architecture. It runs repeated
realtime WhisperKit passes over the accumulated held audio, keeps the latest
fresh candidate, waits after release for `0.10 s` of silence or up to `0.50 s`,
and only uses realtime text as final when it is within `0.65 s` of the frozen
audio. Offline Whisper remains the fallback.

Observed long-dictation traces:

- `24.2 s` German dictation: realtime was `1.50 s` behind the frozen audio, so
  the app correctly used offline fallback; release-to-paste was about `1.80 s`.
- `27.3 s` German dictation: realtime final was used with `0.30 s` lag;
  release-to-paste was about `1.59 s`.

The remaining latency is dominated by the last full-buffer Whisper pass, which
took `1.72 s` on the `27.3 s` sample. Further large latency gains should come
from a true incremental/tail-only decoder or a separate ANE/CoreML backend
targeted at base M-series machines such as MacBook Air, not from repeatedly
tuning full-buffer Whisper passes on M4 Max.

## CoreML ASR Backend Benchmark Branch

Measured locally on `studio1` / M4 Max and `mba1` / M4 MacBook Air on
`2026-06-09`, branch `feature/ane-parakeet-backend`, release build product
`presstalk-asr-bench`. Fixtures were generated with:

```bash
/bin/bash scripts/make_presstalk_asr_bench_fixtures.sh
```

The English fixture was about `17.2 s`; the German fixture was `17.71 s`.
These are synthetic TTS fixtures, so they are useful for repeatable speed
comparisons and basic transcription sanity, not final product-quality WER
claims. WER/CER below are normalized scores: lowercased, diacritic-insensitive,
and punctuation-insensitive. That intentionally tests recognized words more
than dictation formatting.

The `stock-v1-gpu` row is the frozen PressTalk v1 route:
WhisperKit `openai_whisper-large-v3-v20240930_turbo_632MB` with
`cpu-gpu-no-ane` compute placement.

Studio1 warmed-cache results:

| Backend | Fixture | Median Processing | Finalize | RTFx | WER | CER | Notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Stock v1 WhisperKit large-v3-turbo, CPU+GPU, no ANE | English | `3.362 s` | `3.362 s` | `5.12x` | `4.26%` | `0.35%` | Frozen v1 quality baseline |
| Parakeet v3 0.6B, CPU+ANE encoder | English | `0.166 s` | `0.166 s` | `103.71x` | `4.26%` | `0.35%` | Same normalized English score as stock; about `20x` faster final pass |
| Parakeet v3 0.6B, CPU+GPU encoder | English | `0.290 s` | `0.290 s` | `59.31x` | `4.26%` | `0.35%` | Slower than ANE on studio1 |
| Parakeet EOU 120M true streaming, 160ms | English | `1.153 s` | `0.003 s` | `14.92x` | `10.64%` | `3.48%` | Fast partials; weaker accuracy |
| Parakeet EOU 120M true streaming, 320ms | English | `0.682 s` | `0.004 s` | `25.21x` | `6.38%` | `3.14%` | Best EOU tier so far; no casing/punctuation |
| Parakeet EOU 120M true streaming, 1280ms | English | `0.533 s` | `0.006 s` | `32.26x` | `14.89%` | `19.16%` | Faster but unacceptable transcription degradation |
| Nemotron 0.6B English true streaming, 560ms | English | `0.871 s` | `0.013 s` | `19.76x` | `4.26%` | `0.35%` | Accurate fixture text; CoreML emitted slice-by-index warning |
| Nemotron 0.6B English true streaming, 1120ms | English | `0.678 s` | `0.014 s` | `25.36x` | `4.26%` | `0.35%` | Accurate fixture text; optional tier |
| Nemotron 0.6B English true streaming, 2240ms | English | `0.607 s` | `0.022 s` | `28.32x` | `4.26%` | `0.35%` | Accurate fixture text; optional tier |
| Stock v1 WhisperKit large-v3-turbo, CPU+GPU, no ANE | German | `3.484 s` | `3.484 s` | `5.08x` | `13.51%` | `1.22%` | Better German CER than Parakeet on payment terms |
| Parakeet v3 0.6B, CPU+ANE encoder | German | `0.168 s` | `0.168 s` | `105.21x` | `13.51%` | `3.25%` | Same normalized German WER as stock; higher CER on payment terms |
| Parakeet v3 0.6B, CPU+GPU encoder | German | `0.278 s` | `0.278 s` | `63.76x` | `13.51%` | `3.25%` | Slower than ANE on studio1 |

Mba1 warmed-cache results on a base M4 MacBook Air / macOS 26.3:

| Backend | Fixture | Median Processing | Finalize | RTFx | WER | CER | Notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Stock v1 WhisperKit large-v3-turbo, CPU+GPU, no ANE | English | `6.297 s` | `6.297 s` | `2.74x` | `4.26%` | `0.35%` | Frozen v1 route slows sharply on base M4 |
| Parakeet v3 0.6B, CPU+ANE encoder | English | `0.165 s` | `0.165 s` | `104.43x` | `4.26%` | `0.35%` | Same normalized English score as stock; about `38x` faster final pass |
| Parakeet v3 0.6B, CPU+GPU encoder | English | `0.420 s` | `0.420 s` | `41.03x` | `4.26%` | `0.35%` | Much slower than ANE on base M4 |
| Parakeet EOU 120M true streaming, 320ms | English | `0.692 s` | `0.005 s` | `24.88x` | `10.64%` | `3.83%` | Live partial candidate; no casing/punctuation |
| Nemotron 0.6B English true streaming, 560ms | English | `0.882 s` | `0.015 s` | `19.52x` | `4.26%` | `0.35%` | Accurate fixture text |
| Stock v1 WhisperKit large-v3-turbo, CPU+GPU, no ANE | German | `6.686 s` | `6.686 s` | `2.65x` | `13.51%` | `1.22%` | Better German CER than Parakeet on payment terms |
| Parakeet v3 0.6B, CPU+ANE encoder | German | `0.169 s` | `0.169 s` | `104.69x` | `13.51%` | `3.25%` | Same normalized German WER as stock; higher CER on payment terms |
| Parakeet v3 0.6B, CPU+GPU encoder | German | `0.427 s` | `0.427 s` | `41.50x` | `13.51%` | `3.25%` | Much slower than ANE on base M4 |

User-supplied real fixture:

- File: `/Users/am/Downloads/chirp.wav`, copied to mba1 as
  `/tmp/presstalk-asr-bench/chirp.wav`
- Duration: `21.23 s`
- Content: mixed English title plus German marketing text for "Chirp 3"
- Reference text used Alex's expected transcript, including `zehn Sekunden`
  rather than numeric `10 Sekunden`

Studio1 real-fixture results:

| Backend | Language Mode | Median Processing | Finalize | RTFx | WER | CER | Transcript Notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Stock v1 WhisperKit large-v3-turbo, CPU+GPU, no ANE | `auto` | `3.498 s` | `3.498 s` | `6.07x` | `5.13%` | `1.79%` | Output `10 Sekunden`; wrote `Medias Studio` |
| Parakeet v3 0.6B, CPU+ANE encoder | `auto` | `0.214 s` | `0.214 s` | `99.39x` | `12.82%` | `2.15%` | Output `Chirp3`, `10 Sekunden`, `Mediastudio` |
| Parakeet v3 0.6B, CPU+GPU encoder | `auto` | `0.334 s` | `0.334 s` | `63.56x` | `12.82%` | `2.15%` | Same transcript as ANE auto; slower than ANE |

Mba1 real-fixture results:

| Backend | Language Mode | Median Processing | Finalize | RTFx | WER | CER | Transcript Notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Stock v1 WhisperKit large-v3-turbo, CPU+GPU, no ANE | `auto` | `7.181 s` | `7.181 s` | `2.96x` | `5.13%` | `1.79%` | Same transcript as studio1 stock |
| Parakeet v3 0.6B, CPU+ANE encoder | `auto` | `0.236 s` | `0.236 s` | `90.14x` | `12.82%` | `2.15%` | Same transcript as studio1 Parakeet auto |
| Parakeet v3 0.6B, CPU+GPU encoder | `auto` | `0.506 s` | `0.506 s` | `42.00x` | `12.82%` | `2.15%` | Much slower than ANE on base M4 |

First-load timings include one-time Hugging Face download and CoreML compile,
so they are not included in the warmed-cache table. The largest first loads
observed here were about `61 s` for current Parakeet v3, `48 s` for each EOU
tier, and `70 s` for Nemotron 560ms on studio1. On mba1, first-load timings
were much longer because it was a fresh checkout and fresh model cache: about
`251 s` for Parakeet v3, `247 s` for EOU 320ms, and `230 s` for Nemotron 560ms.

Current interpretation:

- The frozen stock v1 WhisperKit route remains the quality baseline, but it is
  too slow for near-instant release on longer dictations, especially on the base
  M4 Air class: `6.297 s` for a `17.2 s` English fixture.
- For release-on-key final dictation, Parakeet v3 on ANE is the leading local
  CoreML candidate. It is batch/sliding-window rather than true streaming, but
  the final pass is already far below the current WhisperKit final-pass cost:
  about `20x` faster on studio1 and `38x` faster on mba1 for the English
  fixture, with the same normalized English WER/CER.
- Accuracy is not solved by speed alone. On the German TTS fixture, stock
  WhisperKit and Parakeet v3 tied on normalized WER, but stock had lower CER
  because Parakeet misheard parts of the payment-term phrase. Real recorded
  user fixtures should decide whether Parakeet needs a cleanup pass, domain
  dictionary, or fallback language route. The first real user fixture,
  `chirp.wav`, confirms this caution: Parakeet v3 ANE is about `30x` faster
  than stock on mba1, but stock WhisperKit has lower WER/CER on the mixed
  English/German marketing copy.
- The packaged ANE path now treats Parakeet v3 as the fast first pass and keeps
  WhisperKit large-v3-turbo as a quality fallback. By default,
  `PRESSTALK_PARAKEET_QUALITY_FALLBACK=1` and
  `PRESSTALK_PARAKEET_MIN_CONFIDENCE=0.96`; accepted Parakeet output below
  that confidence floor, or long output with weak punctuation, is retried
  through WhisperKit before paste.
- Fallback arbitration is recall-protecting: when a WhisperKit fallback
  candidate is plausible but much shorter than the accepted Parakeet candidate
  on a long capture, PressTalk tries the relaxed/auto Whisper passes and then
  keeps the Parakeet candidate if all Whisper candidates appear truncated.
- For live partial text, Parakeet EOU 320ms is the most promising true
  streaming candidate tested so far. It needs capitalization, punctuation, and
  quality validation before it can replace final text.
- The app now has an opt-in FluidAudio true-streaming path behind
  `PRESSTALK_ASR_BACKEND=parakeet-eou-320` or
  `PRESSTALK_ASR_BACKEND=nemotron-560`. It feeds live captured chunks through
  the streaming manager, surfaces partials through the existing HUD/snapshot
  path, finalizes the streaming transcript on release, and falls back to local
  WhisperKit if the streaming result is weak. The default remains
  `parakeet-v3-ane`, which is the current measured fallback release path.
- A local offline check on `/Users/am/Downloads/chirp.wav` confirmed why this
  stays experimental: `parakeet-eou-320` loaded and streamed quickly
  (`0.897s` total processing for `21.232s` audio, `25` partial updates), but
  its mixed German transcript was unusable. On the same fixture,
  `parakeet-v3-ane` produced the accepted transcript in `0.226s` total
  processing (`RTFx 93.76`, confidence `0.988`), while `stock-v1-gpu` produced
  a good transcript in `3.508s` total processing (`RTFx 6.05`). Keep the true
  streaming backend for partial/HUD experiments only until quality improves.
- Nemotron remains a benchmark contender. It matched the normalized English
  score on the synthetic fixture, but it is English-only in the tested
  configuration and has higher production risk until model availability,
  language coverage, and CoreML warnings are understood.
- The base M4 GPU route did slow down versus M4 Max, but not linearly with GPU
  core count or memory bandwidth. This benchmark is not purely GPU-bandwidth
  bound. The stronger product signal is that ANE performance stayed nearly flat
  across M4 Max and base M4 while stock WhisperKit GPU became much slower on the
  Air.
- The ANE-first target for base M-series Macs is reinforced. The app should keep
  the frozen WhisperKit route available as a quality/fallback baseline while
  Parakeet v3 ANE gets broader real-speech accuracy validation.

## Wispr Flow Snapshot

This is not a full benchmark and it is not a quality judgment. It is only a local footprint snapshot on the same Mac, taken from a hidden launch of the installed app:

- App bundle size: `438 MB`
- Aggregate resident memory across visible Wispr Flow processes: about `1.24 GB`
- Observed process layout: multiple Electron renderer/helper processes plus a Swift helper

The point is not that Wispr Flow is "bad". It is that PressTalk is a much narrower product with a much smaller local footprint.

## UI Rendering Cost

The listening light is intentionally lightweight:

- one transparent panel
- one custom `NSView`
- a small number of filled vector paths
- no Metal renderer
- no shader pipeline

Recent tuning traded a little more draw area for smoother edges and less visible shape granularity. That is a reasonable trade on Apple Silicon because the light only appears while the user is actively holding the configured push-to-talk trigger.

## Metrics We Still Do Not Claim

We do not currently publish exact numbers for:

- per-process ANE usage
- per-process GPU watts
- per-process total package watts

Reason:

- macOS requires `sudo` for `powermetrics`
- per-process ANE attribution is limited even with root

If you want to capture system-level power counters manually, this is the right command:

```bash
sudo powermetrics -n 1 --samplers cpu_power,gpu_power,ane_power
```

## Practical Takeaway

On the current M4 Air 16 GB build, PressTalk:

- arms almost instantly
- reaches speech-ready state in about one second
- idles around `109 MB`
- stays well below Electron-class memory footprints
- keeps the UI effect small enough to be viable as a hold-to-talk overlay
