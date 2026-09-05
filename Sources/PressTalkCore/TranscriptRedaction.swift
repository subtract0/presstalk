import CryptoKit
import Foundation

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

    /// A short digest, enough to tell whether two transcripts are the same
    /// without revealing either.
    public static func digest(_ text: String) -> String {
        let hash = SHA256.hash(data: Data(text.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// The form that goes in the log.
    public static func redacted(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "<empty>" }
        return "<redacted chars=\(trimmed.count) words=\(wordCount(trimmed)) digest=\(digest(trimmed))>"
    }

    /// What actually gets written, honouring the opt-in.
    public static func loggable(
        _ text: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        isVerboseLoggingEnabled(environment) ? text : redacted(text)
    }
}
