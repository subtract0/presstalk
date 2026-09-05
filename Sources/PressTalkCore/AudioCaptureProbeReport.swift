import Foundation

/// Result of asking the microphone for a short burst of audio.
///
/// This exists because `AVCaptureDevice.authorizationStatus` answers a question
/// nobody asked: whether a TCC record says yes. It stays `.authorized` while the
/// input tap delivers nothing -- a stale grant after a signing-identity change, a
/// device that vanished, a hardened process missing an entitlement. Every one of
/// those reads as "microphone permission granted" and produces empty
/// transcripts. The only honest check is to record briefly and count what
/// arrived.
public struct AudioCaptureProbeReport: Codable, Equatable {
    public enum Outcome: String, Codable {
        /// Frames arrived. The capture path works end to end.
        case captured
        /// The engine started and no frames arrived. Almost always a missing
        /// entitlement or a revoked TCC grant, never a hardware fault.
        case silentDenial = "silent_denial"
        /// The audio engine refused to start at all.
        case engineFailed = "engine_failed"
        /// No usable input device is present.
        case noInputDevice = "no_input_device"
    }

    public let outcome: Outcome
    public let authorizationStatus: String
    public let sampleRate: Double
    public let channelCount: UInt32
    public let framesCaptured: Int
    public let peakAmplitude: Float
    public let durationSeconds: Double
    public let detail: String

    public init(
        outcome: Outcome,
        authorizationStatus: String,
        sampleRate: Double,
        channelCount: UInt32,
        framesCaptured: Int,
        peakAmplitude: Float,
        durationSeconds: Double,
        detail: String
    ) {
        self.outcome = outcome
        self.authorizationStatus = authorizationStatus
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.framesCaptured = framesCaptured
        self.peakAmplitude = peakAmplitude
        self.durationSeconds = durationSeconds
        self.detail = detail
    }

    /// A frame count of zero after a successful engine start is the signature of
    /// a silent denial. Splitting this out keeps the judgement testable without
    /// AVFoundation.
    public static func classify(
        engineStarted: Bool,
        hasInputDevice: Bool,
        framesCaptured: Int
    ) -> Outcome {
        if !hasInputDevice { return .noInputDevice }
        if !engineStarted { return .engineFailed }
        return framesCaptured > 0 ? .captured : .silentDenial
    }

    /// Wording for a person, not a log line. A silent denial must never be
    /// reported as "microphone permission granted", which is what the system
    /// API would have us say.
    public var userFacingSummary: String {
        switch outcome {
        case .captured:
            return "Microphone is working. Captured \(framesCaptured) audio frames."
        case .silentDenial:
            return "macOS reports microphone access as \(authorizationStatus), but no audio arrived. "
                + "This build cannot record. Reinstall PressTalk; if it persists, this is a bug, not a setting."
        case .engineFailed:
            return "The audio engine could not start: \(detail)"
        case .noInputDevice:
            return "No microphone is available. Connect an input device and try again."
        }
    }

    public var isUsable: Bool { outcome == .captured }
}
