# Owner offline dictation — 2026-09-09

The owner dictated into TextEdit with the Fn key using installed PressTalk
0.1.23/build 23.3 and confirmed that the document contained live speech-to-text
results. The whole app was running under `sandbox-exec` with network operations
denied. This establishes real offline dictation on this Mac, including the
original Shure-with-AirPods-connected route. One AirPods attempt failed, so this
session does not establish release acceptance or capture reliability.

## Observed results

The offline app was process 82854, ready at 21:54:21 UTC on September 8. Its
receipts and completion markers record these eight Fn sessions:

| Session | Requested route | Capture receipt | App completion |
| --- | --- | --- | --- |
| 1 | System default, resolved to Shure MV7i | Complete | Dictation inserted |
| 2 | Explicit Shure MV7i, AirPods were system default | Complete | Dictation inserted |
| 3 | System default, resolved to AirPods | Failed, timestamp discontinuity | Interrupted; nothing inserted |
| 4 | System default, resolved to AirPods | Complete | Dictation inserted |
| 5 | System default, resolved to AirPods | Complete | Dictation inserted |
| 6 | System default, resolved to AirPods | Complete | Dictation inserted |
| 7 | System default, resolved to AirPods | Complete | Dictation inserted |
| 8 | System default, resolved to AirPods | Complete | No speech; no backend error |

There were six inserted dictations, one interrupted capture, and one no-speech
completion.

The live TextEdit document contains three dictated paragraphs describing the
Shure with the AirPods in their case, the Shure with the AirPods connected, and
direct AirPods input. The later completed sessions cannot all be assigned to
that document; no claim is made that all six appeared there. The exact spoken
words were not independently recorded. Apparent proper-name errors include
AirPods rendered as “airports” and possible PressTalk substitutions. This is
evidence of delivered sentences, not word-perfect recognition.

In session 2, the actual bound device remained the Shure at 48 kHz/stereo while
the default input was the AirPods. That receipt accounts for 907,264 native
frames consumed and 302,421 converted frames. Before/after default-input values
match within every session; PressTalk did not promote its chosen microphone.
Device IDs are local measurements, not durable device identities.

## Unresolved AirPods interruption

The first AirPods attempt began at 21:57:04 UTC and failed roughly 0.58 seconds
after the press. It retained 3,360 frames at 24 kHz before capture failed with
`PT_DISCONTINUITY` (reason 6, OSStatus 0). The C transport sets this sticky fault
when the next callback sample timestamp differs from the expected next frame by
more than half a frame. Zero queue-overflow frames do not establish continuity.

The installed receipt does not contain the expected and observed timestamps.
It therefore cannot establish the size or cause of the jump, or distinguish a
timestamp reset from actual missing audio. The continuity requirement remains
unchanged; later successful presses do not erase the interrupted attempt.

A private probe compiled the same C transport with two diagnostic timestamp
fields and unchanged validation. Eight later, two-second AirPods captures
delivered nonempty PCM without a continuity fault; consumed frames matched
retained frames and the default input stayed unchanged. This did not reproduce
the owner's first transition and is only transport evidence. It is not another
eight end-to-end acceptance passes. Two earlier probe setup errors produced no
capture and are excluded: a stale numeric device ID and an incorrectly formed
UID-translation query. The corrected probe resolves the stable UID through the
CoreAudio property's qualifier, as documented in the installed SDK.

## Restored state and remaining work

The offline app was quit gracefully after checking that Fn was released and
processing had completed. The same installed app was launched normally as
process 85707, with its model Ready and the Fn trigger selected. The owner chose
system-default input during this test; that preference was preserved. The saved
licence matches both its pre-install fingerprint and the downloaded licence.
The owner's TextEdit contents were read without editing them; a private snapshot
and structured acceptance receipt preserve the evidence.

Private evidence is under `.local/commerce/owner-offline-check/`: `start.json`,
`acceptance.json`, `owner-test-document.txt`, `capture-markers.log`, and the
timestamp probe source/results. No production capture code or installed build
was changed in this observation pass.

Before public release, investigate the transition interruption and obtain a
focused live retest of the resulting fix. Settings staying behind the target
window was arranged but not independently established by this document. The
production purchase deployment and public release remain pending. Existing
live checkout remains active.
