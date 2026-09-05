import CryptoKit
import Foundation
import Security

/// Keeps dictated words out of files.
///
/// PressTalk's whole pitch is that what you say stays on your Mac. Writing every
/// transcript into a log on disk does not break that literally -- the file never
/// leaves -- but it produces a plaintext record of everything the user has ever
/// dictated, sitting unencrypted in ~/Library/Logs, swept up by backups, and
/// attached to any diagnostics export. Passwords, medical notes, and half-drafted
/// messages all land there. Nobody agreed to that by buying a dictation app.
///
/// Diagnosing transcription bugs still needs *something*, so the redacted form
/// keeps what is useful for debugging -- length, word count, a stable digest to
/// compare two runs -- and drops the words.
public enum TranscriptRedaction {
    /// Set PRESSTALK_LOG_TRANSCRIPTS=1 to log them verbatim. Only for someone
    /// deliberately debugging their own recognition, never a default.
    public static let optInEnvironmentKey = "PRESSTALK_LOG_TRANSCRIPTS"

    public static func isVerboseLoggingEnabled(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let value = (environment[optInEnvironmentKey] ?? "0")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    /// Random per process, discarded on exit. Without it the digest below is an
    /// unsalted SHA-256 prefix over a short, guessable string, which is not
    /// redaction at all: a four-digit utterance falls to ten thousand guesses,
    /// and "what is my PIN" is exactly the kind of thing people dictate. Salting
    /// per run keeps the digest useful for comparing two transcripts inside one
    /// debugging session and worthless to anyone reading the file afterwards.
    private static let sessionSalt: Data = {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }()

    /// Tells two transcripts apart within one run. Means nothing across runs, on
    /// purpose.
    public static func digest(_ text: String) -> String {
        var input = sessionSalt
        input.append(Data(text.utf8))
        let hash = SHA256.hash(data: input)
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// The form that goes in the log.
    public static func redacted(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "<empty>" }
        return "<redacted chars=\(trimmed.count) words=\(wordCount(trimmed)) run-digest=\(digest(trimmed))>"
    }

    /// What actually gets written, honouring the opt-in.
    public static func loggable(
        _ text: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        isVerboseLoggingEnabled(environment) ? text : redacted(text)
    }
}
