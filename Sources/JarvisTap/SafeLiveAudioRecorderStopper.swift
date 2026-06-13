import AVFoundation
import Foundation
import WhisperKit

final class SafeLiveAudioRecorderStopper {
    private struct RetiredAudioEngine {
        let id: ObjectIdentifier
        let engine: AVAudioEngine
        let retiredAt: Date
    }

    private let retainSeconds: TimeInterval
    private let retiredLimit: Int
    private let trace: (String) -> Void
    private let lock = NSLock()
    private var retiredAudioEngines: [RetiredAudioEngine] = []

    init(
        retainSeconds: TimeInterval = 3.0,
        retiredLimit: Int = 8,
        trace: @escaping (String) -> Void
    ) {
        self.retainSeconds = retainSeconds
        self.retiredLimit = retiredLimit
        self.trace = trace
    }

    func stop(_ whisperKit: WhisperKit?, reason: String) {
        guard let audioProcessor = whisperKit?.audioProcessor else { return }

        var retiredID: ObjectIdentifier?

        lock.lock()
        if let processor = audioProcessor as? AudioProcessor,
           let engine = processor.audioEngine {
            retiredID = ObjectIdentifier(engine)
            trace("Stopping live audio recording safely reason=\(reason)")
            processor.audioBufferCallback = nil

            engine.inputNode.removeTap(onBus: 0)
            for node in engine.attachedNodes {
                node.removeTap(onBus: 0)
            }
            engine.disconnectNodeInput(engine.inputNode)
            engine.stop()
            engine.reset()

            retiredAudioEngines.append(
                RetiredAudioEngine(
                    id: ObjectIdentifier(engine),
                    engine: engine,
                    retiredAt: Date()
                )
            )
            pruneLocked()
            processor.audioEngine = nil
        } else {
            audioProcessor.stopRecording()
        }
        lock.unlock()

        guard let retiredID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + retainSeconds) { [weak self] in
            self?.releaseRetiredAudioEngine(id: retiredID)
        }
    }

    private func pruneLocked(now: Date = Date()) {
        retiredAudioEngines.removeAll {
            now.timeIntervalSince($0.retiredAt) >= retainSeconds
        }
        if retiredAudioEngines.count > retiredLimit {
            retiredAudioEngines.removeFirst(retiredAudioEngines.count - retiredLimit)
        }
    }

    private func releaseRetiredAudioEngine(id: ObjectIdentifier) {
        lock.lock()
        retiredAudioEngines.removeAll { $0.id == id }
        pruneLocked()
        lock.unlock()
    }
}
