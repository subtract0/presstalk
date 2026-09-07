/// Resolves a primary recognizer result when the optional secondary is absent.
/// A completed recognition with no accepted words is different from a failure.
public enum TranscriptFallback {
    public enum PrimaryOutcome {
        case notAttempted
        case completed
        case failed(Error)
    }

    /// Nil means no recognizer ran; the caller must report its missing backend.
    public static func withoutSecondary(
        acceptedPrimary: String?,
        acceptedStreaming: String?,
        primary: PrimaryOutcome
    ) throws -> String? {
        if let acceptedPrimary { return acceptedPrimary }
        if let acceptedStreaming { return acceptedStreaming }
        switch primary {
        case .completed: return ""
        case .failed(let error): throw error
        case .notAttempted: return nil
        }
    }
}
