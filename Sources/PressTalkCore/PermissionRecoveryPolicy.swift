/// Chooses the next user action when macOS permission UI and usable access differ.
///
/// The application supplies observations from the running process. A checked
/// switch, a successful Settings launch, or a successful reset is never a grant.
/// This policy does not request permissions, run commands, or restart the app.
public struct PermissionRecoveryPolicy {
    public enum State: String, Equatable, Codable, Sendable {
        case openSystemSettings
        case waitingForReturn
        case finishCurrentDictation
        case restartToRefresh
        case renewPermission
        case systemApprovalRequired
        case ready
    }

    public struct Context: Equatable, Sendable {
        public var permissionAvailable: Bool
        public var hasOpenedSystemSettings: Bool
        public var hasReturnedFromSystemSettings: Bool
        public var restartAttempted: Bool
        public var permissionRenewalAttempted: Bool
        public var identityMismatchConfirmed: Bool
        public var recordingOrProcessing: Bool

        public init(
            permissionAvailable: Bool,
            hasOpenedSystemSettings: Bool = false,
            hasReturnedFromSystemSettings: Bool = false,
            restartAttempted: Bool = false,
            permissionRenewalAttempted: Bool = false,
            identityMismatchConfirmed: Bool = false,
            recordingOrProcessing: Bool = false
        ) {
            self.permissionAvailable = permissionAvailable
            self.hasOpenedSystemSettings = hasOpenedSystemSettings
            self.hasReturnedFromSystemSettings = hasReturnedFromSystemSettings
            self.restartAttempted = restartAttempted
            self.permissionRenewalAttempted = permissionRenewalAttempted
            self.identityMismatchConfirmed = identityMismatchConfirmed
            self.recordingOrProcessing = recordingOrProcessing
        }
    }

    public init() {}

    public func state(for context: Context) -> State {
        if context.permissionAvailable { return .ready }
        // Recovery must never interrupt retained audio or text delivery.
        if context.recordingOrProcessing { return .finishCurrentDictation }
        // A reset is not consent. There is no reset/relaunch/prompt loop when
        // macOS or a managed-device policy still denies the renewed request.
        if context.permissionRenewalAttempted { return .systemApprovalRequired }
        // A positively identified old signing requirement cannot be repaired
        // by restarting the same current binary. Do not make the user try it.
        if context.identityMismatchConfirmed { return .renewPermission }
        if context.restartAttempted { return .renewPermission }
        guard context.hasOpenedSystemSettings else { return .openSystemSettings }
        guard context.hasReturnedFromSystemSettings else { return .waitingForReturn }
        return .restartToRefresh
    }
}
