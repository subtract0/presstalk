import Foundation

/// Activity that must finish before an update can terminate the app.
public enum UpdateSafetyPolicy {
    public struct Activity: Equatable, Sendable {
        public var isRecording: Bool
        public var isProcessing: Bool
        public var isMicrophoneProbeRunning: Bool
        public var isCalibrationRunning: Bool
        public var isPermissionRenewalRunning: Bool
        public var isCapturePending: Bool
        public var isClipboardRestoring: Bool

        public init(
            isRecording: Bool = false, isProcessing: Bool = false,
            isMicrophoneProbeRunning: Bool = false, isCalibrationRunning: Bool = false,
            isPermissionRenewalRunning: Bool = false, isCapturePending: Bool = false,
            isClipboardRestoring: Bool = false
        ) {
            self.isRecording = isRecording
            self.isProcessing = isProcessing
            self.isMicrophoneProbeRunning = isMicrophoneProbeRunning
            self.isCalibrationRunning = isCalibrationRunning
            self.isPermissionRenewalRunning = isPermissionRenewalRunning
            self.isCapturePending = isCapturePending
            self.isClipboardRestoring = isClipboardRestoring
        }

        public var isBusy: Bool {
            isRecording || isProcessing || isMicrophoneProbeRunning || isCalibrationRunning
                || isPermissionRenewalRunning || isCapturePending || isClipboardRestoring
        }
    }

    public static let officialBundleIdentifier = "com.am.presstalk"
    public static let officialTeamIdentifier = "5HUC5LA94B"
    public static let officialFeedURL = "https://presstalk.app/appcast.xml"

    public static func isEligible(
        bundleIdentifier: String?, isApplicationBundle: Bool,
        hasValidProductionSignature: Bool, feedURL: String?, publicKey: String?,
        requiresSignedFeed: Bool, verifiesBeforeExtraction: Bool
    ) -> Bool {
        bundleIdentifier == officialBundleIdentifier && isApplicationBundle
            && hasValidProductionSignature && feedURL == officialFeedURL
            && publicKey.flatMap { Data(base64Encoded: $0) }?.count == 32
            && requiresSignedFeed && verifiesBeforeExtraction
    }
}

/// Holds Sparkle's continuation until the app atomically reserves installation.
/// This class and its callbacks are used on the main actor. The reservation is
/// owned by the app and blocks every path that can begin capture or recovery.
@MainActor public final class UpdateInstallationGate {
    public enum State: Equatable { case idle, waitingForIdle, installing }
    public private(set) var state: State = .idle
    public private(set) var hasReservation = false
    private var pending: (() -> Void)?
    private let tryReserve: () -> Bool
    private let release: () -> Void

    public init(tryReserve: @escaping () -> Bool, release: @escaping () -> Void) {
        self.tryReserve = tryReserve
        self.release = release
    }

    public func postpone(_ install: @escaping () -> Void) {
        pending = install
        if !hasReservation { state = .waitingForIdle }
    }

    @discardableResult public func resumeWhenSafe() -> Bool {
        guard let install = pending else { return false }
        if !hasReservation {
            guard tryReserve() else { return false }
            hasReservation = true
        }
        // Publish the reservation and consume the continuation before invoking
        // Sparkle: its installation callbacks may synchronously re-enter us.
        pending = nil
        state = .installing
        install()
        return true
    }

    public func cancel() {
        pending = nil
        state = .idle
        let mustRelease = hasReservation
        hasReservation = false
        if mustRelease { release() }
    }
}
