# Performance Notes

These numbers were measured locally on `mbaM4`, a MacBook Air with Apple Silicon M4 and `16 GB` RAM, on `2026-03-13`.

They are not marketing numbers. They are point-in-time measurements from the current `0.1.5` build of PressTalk running as a LaunchAgent with:

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

## PressTalk 0.1.5

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

Measured locally on `studio1` / M4 Max on `2026-06-09`, branch
`feature/ane-parakeet-backend`, release build product
`presstalk-asr-bench`. Fixtures were generated with:

```bash
/bin/bash scripts/make_presstalk_asr_bench_fixtures.sh
```

The English fixture was `17.18 s`; the German fixture was `17.71 s`. These are
synthetic TTS fixtures, so they are useful for repeatable speed comparisons and
basic transcription sanity, not final product-quality WER claims.

Studio1 warmed-cache results:

| Backend | Fixture | Median Processing | Finalize | RTFx | Notes |
| --- | --- | ---: | ---: | ---: | --- |
| Parakeet v3 0.6B, CPU+ANE encoder | English | `0.161 s` | `0.161 s` | `106.5x` | Accurate on fixture |
| Parakeet v3 0.6B, CPU+ANE encoder | German | `0.154 s` | `0.154 s` | `114.8x` | Mostly good; TTS payment terms misheard |
| Parakeet v3 0.6B, CPU+GPU encoder | English | `0.285 s` | `0.285 s` | `60.2x` | Slower than ANE on studio1 |
| Parakeet EOU 120M true streaming, 160ms | English | `1.138 s` | `0.003 s` | `15.1x` | Fast partials; weaker accuracy |
| Parakeet EOU 120M true streaming, 320ms | English | `0.688 s` | `0.005 s` | `25.0x` | Best EOU tier so far; correct words, no casing/punctuation |
| Parakeet EOU 120M true streaming, 1280ms | English | `0.516 s` | `0.006 s` | `33.3x` | Faster but unacceptable transcription degradation |
| Nemotron 0.6B English true streaming, 560ms | English | `0.828 s` | `0.013 s` | `20.8x` | Accurate fixture text; CoreML emitted slice-by-index warning |

First-load timings include one-time Hugging Face download and CoreML compile,
so they are not included in the warmed-cache table. The largest first loads
observed here were about `61 s` for current Parakeet v3, `48 s` for each EOU
tier, and `70 s` for Nemotron 560ms.

Current interpretation:

- For release-on-key final dictation, Parakeet v3 on ANE is the leading local
  CoreML candidate. It is batch/sliding-window rather than true streaming, but
  the final pass is already far below the current WhisperKit final-pass cost.
- For live partial text, Parakeet EOU 320ms is the most promising true
  streaming candidate tested so far. It needs capitalization, punctuation, and
  quality validation before it can replace final text.
- Nemotron 560ms remains a benchmark contender, but the observed CoreML shape
  warning makes it a higher-risk production dependency until reproduced and
  understood.
- On this M4 Max, FluidAudio's GPU encoder placement for Parakeet v3 was slower
  than ANE on the PressTalk fixture. This reinforces the ANE-first target for
  base M-series Macs such as M4 MacBook Air.

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
