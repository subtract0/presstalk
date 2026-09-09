#!/usr/bin/env python3
"""Wiring guard, not a hardware or full dictation acceptance test.

Masks comments AND literals so declarations, logs and commented-out calls cannot
stand in for executable call sites. --self-test attacks each guarded boundary in
an isolated copy; it never mutates the checkout.
"""
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = ['Sources/JarvisTap/main.swift', 'Sources/JarvisTap/AudioCaptureProbe.swift',
         'Sources/PressTalkCapture/HALCapture.swift', 'Sources/PressTalkHAL/PressTalkHAL.c']

def code(text):
    return re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/',
                  lambda m: ''.join('\n' if c == '\n' else ' ' for c in m[0]), text)

def body(source, signature):
    start = source.find(signature)
    if start < 0:
        return ''
    start = source.find('{', start)
    depth = 1
    end = start + 1
    while end < len(source) and depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start + 1:end - 1]

def check(files):
    main, probe, adapter, hal = map(lambda p: code(files[p]), FILES)
    errors = []
    def need(condition, message):
        if not condition: errors.append(message)
    press = body(main, 'private func handlePress(')
    append = body(main, 'private func appendLiveCapturedAudioSamples(_ samples: [Float], sessionID: UInt64)')
    stop = body(main, 'private func safelyStopLiveAudioRecording(')
    release = body(main, 'private func handleRelease(')
    fail = body(main, 'private func captureFailed(')
    finalizers = [body(release, 'func finalizeTranscript()'),
                  body(main, 'private func finalizeTranscript(preferFallbackTranscript: Bool)')]
    for finalizer in finalizers:
        inference = finalizer.find('try await transcribeParakeetV3ANE(samples: normalizedSamples)')
        completed = finalizer.find('primaryOutcome = .completed')
        secondary = body(finalizer, 'guard let whisperKit else')
        need(inference >= 0 and completed > inference and
             finalizer.find('guard let whisperKit else') > completed,
             'primary recognition must complete before resolving an absent optional backend')
        need('primaryOutcome = .failed(error)' in finalizer,
             'primary recognizer errors must be retained for absent-secondary resolution')
        need('try TranscriptFallback.withoutSecondary(' in secondary and
             'primary: primaryOutcome' in secondary and 'return transcript' in secondary,
             'both finalizers must resolve completed empty recognition without requiring optional Whisper')
    no_speech = body(release, 'guard !transcript.isEmpty else')
    after_integrity = ''
    # Locate the end of the integrity-failure branch without relying on log text.
    integrity = body(no_speech, 'if let integrityMessage = captureVerdict.userFacingMessage,')
    if integrity:
        after_integrity = no_speech[no_speech.index(integrity) + len(integrity) + 1:]
    need(bool(integrity) and 'present(.ready)' in after_integrity and 'present(.error(' not in after_integrity,
         'valid capture with no recognized speech must return to Ready without an error card')
    need('try ownedCapture.start(session: captureSessionID' in press, 'live capture must call the owned adapter')
    need('deviceID: selectedAudioInput.id, deviceUID: selectedAudioInput.uid' in press, 'capture must bind the selected ID and UID')
    need('self?.appendLiveCapturedAudioSamples(samples, sessionID: captureSessionID)' in press, 'capture consumer must retain PCM in its session')
    need('self?.captureFailed(message, sessionID: captureSessionID)' in press, 'capture failures must reach the app')
    need('ownedCapture.stop(session: session)' in stop and '!receipt.complete' in stop, 'stop must use and check the capture receipt')
    need('activeCaptureFailure = receipt.failure' in stop, 'an incomplete receipt must block recognition')
    need('if let failure = withStateLock({ activeCaptureFailure })' in release and
         release.index('if let failure = withStateLock({ activeCaptureFailure })') < release.find('func finalizeTranscript'),
         'capture failure must stop release before recognition')
    need('activeCaptureFailure = message' in fail and 'activeCaptureEngineStarted = false' in fail,
         'a stalled stream must revoke readiness')
    need(main.count('activeCaptureEngineStarted = true') == 1 and 'activeCaptureEngineStarted = true' in append,
         'only retained PCM may establish readiness')
    need('appendLiveCapturedAudioSamples(samples)' in append and
         append.find('appendLiveCapturedAudioSamples(samples)') < append.find('activeCaptureEngineStarted = true'),
         'the ready-making buffer must be retained')
    need('try capture.start(' in probe and 'receipt?.complete == true' in probe, 'selftest must use the production capture adapter and receipt')
    for source in [main, probe]:
        need('startRecordingLive(' not in source and '.installTap(' not in source, 'live app must not use the replaced engine tap')
        need('AudioObjectSetPropertyData(' not in source, 'app must not write global audio properties')
    need('try converter.finish()' in adapter, 'converter must drain at release')
    need('onSamples?(samples)' in adapter, 'converted PCM must reach the installed consumer')
    need('frames > 0 && frames == receipt?.convertedFrames' in probe, 'selftest must verify its actual consumer received all converted PCM')
    need('stats.retainedFrames != stats.consumedFrames' in adapter, 'stop must account for all retained PCM')
    need('receipt?.recordTransportFailure(stats)' in body(adapter, 'private func finishLocked()'),
         'the actual completion path must preserve transport failure diagnostics')
    need('fail(c, PT_DISCONTINUITY, 0)' in body(hal, 'static void retain_pcm('),
         'a sample timestamp discontinuity must reject the recording')
    need('try validateDeviceLocked()' in adapter, 'device must be revalidated')
    need('AudioObjectSetPropertyData(' not in hal, 'HAL adapter must not change system settings')
    need('c->boundDevice != device' in hal, 'HAL binding must be read back and checked')
    need('CHECK(AudioUnitAddPropertyListener(' in hal and 'pt_invalidate(c)' in body(hal, 'static void unit_property_changed('), 'unit configuration changes must invalidate capture even between readbacks')
    need('frames > c->maximumFrames' in hal and 'PT_OVERFLOW' in hal and '!isfinite(pcm[i])' in hal,
         'HAL callback must reject capacity, overflow and invalid PCM')
    return errors

def self_test(files):
    mutations = [
        (FILES[0], 'primaryOutcome = .completed', '// primaryOutcome = .completed'),
        (FILES[0], 'primaryOutcome = .failed(error)', '// primaryOutcome = .failed(error)'),
        (FILES[0], 'try TranscriptFallback.withoutSecondary(', 'nil /* try TranscriptFallback.withoutSecondary( */'),
        (FILES[0], 'primary: primaryOutcome', 'primary: .notAttempted /* primary: primaryOutcome */'),
        (FILES[0], 'present(.ready)\n                    print("[PressTalk] No speech captured.")',
         'present(.error("No speech"))\n                    print("[PressTalk] No speech captured.")'),
        (FILES[0], 'try ownedCapture.start(session: captureSessionID,', '// try ownedCapture.start(session: captureSessionID,'),
        (FILES[0], 'self?.appendLiveCapturedAudioSamples(samples, sessionID: captureSessionID)', '// self?.appendLiveCapturedAudioSamples(samples, sessionID: captureSessionID)'),
        (FILES[0], 'self?.captureFailed(message, sessionID: captureSessionID)', '// self?.captureFailed(message, sessionID: captureSessionID)'),
        (FILES[0], 'guard let receipt = ownedCapture.stop(session: session) else { return }', '// guard let receipt = ownedCapture.stop(session: session) else { return }'),
        (FILES[0], 'if !receipt.complete {', 'if false { // if !receipt.complete {'),
        (FILES[0], 'if let failure = withStateLock({ activeCaptureFailure }) {', 'if false { // if let failure = withStateLock({ activeCaptureFailure }) {'),
        (FILES[0], 'appendLiveCapturedAudioSamples(samples)\n', '// appendLiveCapturedAudioSamples(samples)\n'),
        (FILES[0], 'activeCaptureEngineStarted = true', 'activeCaptureEngineStarted = false // activeCaptureEngineStarted = true'),
        (FILES[1], 'try capture.start(', '// try capture.start('),
        (FILES[2], 'onSamples?(samples)', '// onSamples?(samples)'),
        (FILES[1], 'frames > 0 && frames == receipt?.convertedFrames', 'true /* frames > 0 && frames == receipt?.convertedFrames */'),
        (FILES[2], 'deliverLocked(try converter.finish())', '/* deliverLocked(try converter.finish()) */'),
        (FILES[2], 'receipt?.recordTransportFailure(stats)', '// receipt?.recordTransportFailure(stats)'),
        (FILES[3], 'fail(c, PT_DISCONTINUITY, 0)', '/* fail(c, PT_DISCONTINUITY, 0) */'),
        (FILES[3], 'CHECK(AudioUnitAddPropertyListener(c->unit, monitoredProperties[i], unit_property_changed, c));', '/* CHECK(AudioUnitAddPropertyListener(c->unit, monitoredProperties[i], unit_property_changed, c)); */'),
        (FILES[3], 'c->boundDevice != device', 'false /* c->boundDevice != device */'),
        (FILES[3], '!isfinite(pcm[i])', 'false /* !isfinite(pcm[i]) */'),
    ]
    for path, old, new in mutations:
        assert old in files[path], f'mutation target missing: {old}'
        changed = dict(files)
        changed[path] = changed[path].replace(old, new)
        assert check(changed), f'FAIL: gate accepted injected defect {old}'
    print(f'PASS: {len(mutations)} injected wiring defects rejected')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    files = {path: (ROOT / path).read_text() for path in FILES}
    errors = check(files)
    if errors:
        for error in errors: print('FAIL:', error)
        raise SystemExit(1)
    if args.self_test: self_test(files)
    print('PASS: capture wiring contract (hardware and dictation still require live evidence)')
