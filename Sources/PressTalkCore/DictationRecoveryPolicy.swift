import Foundation

/// Keeps the last few dictations recoverable without turning PressTalk into a
/// recording archive.
///
/// The tension is the product: someone who dictates a paragraph into the wrong
/// window wants it back, and someone who bought this because it is local does
/// not want a transcript log on disk. So everything here is in memory, bounded,
/// and expires; nothing is written to disk and nothing survives a quit.
public struct DictationRecoveryPolicy {
    public struct Entry: Equatable {
        public let text: String
        public let createdAt: Date
        /// Set when insertion failed and the text was only copied, so the entry
        /// can be surfaced differently from one that landed correctly.
        public let deliveryFailed: Bool

        public init(text: String, createdAt: Date, deliveryFailed: Bool = false) {
            self.text = text
            self.createdAt = createdAt
            self.deliveryFailed = deliveryFailed
        }
    }

    /// How many transcripts to keep. Small on purpose: this is an undo, not a
    /// history feature, and every extra entry is more dictation sitting in
    /// memory than the user asked for.
    public let maximumEntries: Int
    /// Entries older than this are dropped. Someone who dictated a password an
    /// hour ago should not find it in a menu.
    public let expiry: TimeInterval

    public init(maximumEntries: Int = 5, expiry: TimeInterval = 15 * 60) {
        self.maximumEntries = max(1, maximumEntries)
        self.expiry = max(0, expiry)
    }

    /// Adds an entry and applies both bounds. Blank text is never stored: an
    /// empty row in a recovery menu is a worse answer than no row.
    public func inserting(_ entry: Entry, into entries: [Entry], now: Date) -> [Entry] {
        guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return pruned(entries, now: now)
        }
        var updated = pruned(entries, now: now)
        updated.insert(entry, at: 0)
        if updated.count > maximumEntries {
            updated.removeSubrange(maximumEntries...)
        }
        return updated
    }

    public func pruned(_ entries: [Entry], now: Date) -> [Entry] {
        entries.filter { now.timeIntervalSince($0.createdAt) < expiry }
    }

    /// A short, single-line label for a menu. Long dictations are truncated for
    /// display only; the stored text stays whole, because the point is to hand
    /// back exactly what was said.
    public func menuLabel(for entry: Entry, characterLimit: Int = 48) -> String {
        let collapsed = entry.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if collapsed.count <= characterLimit {
            body = collapsed
        } else {
            body = String(collapsed.prefix(characterLimit - 1)) + "…"
        }
        return entry.deliveryFailed ? "\(body)  (not pasted)" : body
    }
}

/// Whether the audio from the last attempt is worth keeping for a retry.
///
/// Retained audio is the sharpest edge in this file. It is the raw recording,
/// held in memory, and the only defensible reasons to keep it are that the last
/// attempt failed and the user might immediately want another go.
public struct RetainedAudioPolicy {
    public enum Disposition: String, Equatable {
        /// The attempt failed and a retry could still succeed.
        case retainForRetry = "retain_for_retry"
        /// Recognition worked. There is nothing to retry, so drop it.
        case discardRecognized = "discard_recognized"
        /// Nothing was captured; there is nothing to retain.
        case discardEmpty = "discard_empty"
        /// Held too long or too large.
        case discardExpired = "discard_expired"
    }

    public let maximumSeconds: TimeInterval
    public let expiry: TimeInterval

    public init(maximumSeconds: TimeInterval = 120, expiry: TimeInterval = 5 * 60) {
        self.maximumSeconds = maximumSeconds
        self.expiry = expiry
    }

    public func disposition(
        recognitionSucceeded: Bool,
        capturedSeconds: TimeInterval,
        ageSeconds: TimeInterval = 0
    ) -> Disposition {
        if capturedSeconds <= 0 { return .discardEmpty }
        if recognitionSucceeded { return .discardRecognized }
        if capturedSeconds > maximumSeconds { return .discardExpired }
        if ageSeconds >= expiry { return .discardExpired }
        return .retainForRetry
    }

    public func shouldRetain(
        recognitionSucceeded: Bool,
        capturedSeconds: TimeInterval,
        ageSeconds: TimeInterval = 0
    ) -> Bool {
        disposition(
            recognitionSucceeded: recognitionSucceeded,
            capturedSeconds: capturedSeconds,
            ageSeconds: ageSeconds
        ) == .retainForRetry
    }
}
