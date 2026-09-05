import AVFoundation
import Foundation

extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

struct ParakeetTranscriptCandidate {
    let text: String
    let confidence: Double
}

final class TraceLogger {
    private let logURL: URL
    private let queue = DispatchQueue(label: "com.am.jarvistap.trace-log")
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Rotate once the log passes this. Left unbounded, the trace log reached
    /// 45 MB on the development machine, which is both a disk cost nobody agreed
    /// to and a very long-lived record of app activity.
    private let maximumBytes: Int
    private var writtenSinceCheck = 0

    init(path: String, maximumBytes: Int = 8 * 1024 * 1024) {
        logURL = URL(fileURLWithPath: path)
        self.maximumBytes = maximumBytes
        let directoryURL = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
    }

    /// Keeps one previous file. Two generations is enough to investigate
    /// something that happened yesterday and few enough to stay bounded.
    private func rotateIfNeeded() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > maximumBytes else { return }
        let previous = logURL.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: logURL, to: previous)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
    }

    func log(_ message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        queue.sync { [logURL] in
            guard let data = line.data(using: .utf8) else { return }
            // Checking the file size on every line would stat the file thousands
            // of times a minute, so amortise it.
            writtenSinceCheck += data.count
            if writtenSinceCheck > 256 * 1024 {
                writtenSinceCheck = 0
                rotateIfNeeded()
            }
            do {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                fputs("[PressTalk] Trace log write failed: \(error)\n", stderr)
            }
        }
    }
}

final class NativeSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    private var configuredVoice: AVSpeechSynthesisVoice?

    func configure(voiceIdentifier: String?) {
        if let voiceIdentifier, !voiceIdentifier.isEmpty {
            configuredVoice = resolvedVoice(for: voiceIdentifier)
        }

        if configuredVoice == nil {
            configuredVoice = defaultEnglishVoice()
        }
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = configuredVoice ?? defaultEnglishVoice()
        synthesizer.speak(utterance)
    }

    private func resolvedVoice(for requestedVoice: String) -> AVSpeechSynthesisVoice? {
        if let voice = AVSpeechSynthesisVoice(identifier: requestedVoice) {
            return voice
        }

        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let voice = voices.first(where: { $0.name.caseInsensitiveCompare(requestedVoice) == .orderedSame }) {
            return voice
        }
        if let voice = voices.first(where: { $0.language.caseInsensitiveCompare(requestedVoice) == .orderedSame }) {
            return voice
        }
        return nil
    }

    private func defaultEnglishVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let preferredVoices = [
            ("Samantha", "en_US"),
            ("Daniel", "en_GB"),
            ("Karen", "en_AU"),
            ("Moira", "en_IE"),
        ]

        for (name, language) in preferredVoices {
            if let voice = voices.first(where: { $0.name == name && $0.language == language }) {
                return voice
            }
        }

        return voices.first(where: { $0.language.lowercased().hasPrefix("en") })
    }
}

enum JarvisTapError: Error, CustomStringConvertible {
    case invalidHTTPResponse
    case invalidRemotePayload
    case httpFailure(Int, String)
    case whisperUnavailable
    case tokenizerUnavailable(String)
    case audioBufferUnavailable
    case accessibilityPermissionMissing
    case eventSynthesisUnavailable
    case audioInputUnavailable(String)

    var description: String {
        switch self {
        case .invalidHTTPResponse:
            return "invalid HTTP response"
        case .invalidRemotePayload:
            return "remote endpoint returned an unsupported payload"
        case let .httpFailure(code, body):
            return "HTTP \(code): \(body)"
        case .whisperUnavailable:
            return "WhisperKit was not initialized"
        case .tokenizerUnavailable(let message):
            return "Whisper tokenizer unavailable: \(message)"
        case .audioBufferUnavailable:
            return "Failed to allocate an audio buffer"
        case .accessibilityPermissionMissing:
            return "Paste permission preflight is unavailable"
        case .eventSynthesisUnavailable:
            return "Failed to synthesize keyboard events"
        case .audioInputUnavailable(let message):
            return "Audio input unavailable: \(message)"
        }
    }
}

enum TranscriptInsertionResult {
    case inserted(method: String)
    case pasteCommandPosted
    case copiedFallback(reason: String)
}
