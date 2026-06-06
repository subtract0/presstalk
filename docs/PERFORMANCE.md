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
  `~/Library/Application Support/JarvisTap/Models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo_632MB`

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
