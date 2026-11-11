import AppKit
import Security
import Sparkle
import PressTalkCore

/// Standard Sparkle UI and preferences, restricted to the official signed app.
/// The application owns capture/termination locking through the callbacks below.
@MainActor final class PressTalkUpdater: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    var tryReserveInstallation: (() -> Bool)?
    var releaseInstallationReservation: (() -> Void)?
    var isApplicationBusy: (() -> Bool)?
    var onStateChanged: (() -> Void)?

    private(set) var isAvailable: Bool
    private(set) var status: String { didSet { onStateChanged?() } }
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []
    private lazy var installationGate = UpdateInstallationGate(
        tryReserve: { [weak self] in self?.tryReserveInstallation?() ?? false },
        release: { [weak self] in self?.releaseInstallationReservation?() })

    init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        isAvailable = UpdateSafetyPolicy.isEligible(
            bundleIdentifier: bundle.bundleIdentifier,
            isApplicationBundle: bundle.bundleURL.pathExtension == "app"
                && info["CFBundlePackageType"] as? String == "APPL",
            hasValidProductionSignature: Self.hasValidProductionSignature(bundle),
            feedURL: info["SUFeedURL"] as? String,
            publicKey: info["SUPublicEDKey"] as? String,
            requiresSignedFeed: info["SURequireSignedFeed"] as? Bool == true,
            verifiesBeforeExtraction: info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        status = isAvailable ? "Updates are ready."
            : "Automatic updates are available in the official PressTalk release."
        super.init()
    }

    var canCheckForUpdates: Bool {
        (controller?.updater.canCheckForUpdates ?? false) && !(isApplicationBusy?() ?? true)
    }
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            guard let updater = controller?.updater else { return }
            updater.automaticallyChecksForUpdates = newValue
            onStateChanged?()
        }
    }
    var automaticallyDownloadsUpdates: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            guard let updater = controller?.updater else { return }
            updater.automaticallyDownloadsUpdates = newValue
            onStateChanged?()
        }
    }

    func start() {
        guard isAvailable, controller == nil else { return }
        let candidate = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        // Initial check/download defaults belong in Info.plist. Changing them
        // here would overwrite the user's saved opt-out on every launch.
        candidate.updater.sendsSystemProfile = false
        controller = candidate
        do {
            try candidate.updater.start()
            observations = [
                candidate.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.onStateChanged?() }
                },
                candidate.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.onStateChanged?() }
                },
                candidate.updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.onStateChanged?() }
                },
            ]
            status = "PressTalk checks for signed updates automatically when enabled."
        } catch {
            controller = nil
            isAvailable = false
            status = "Updates could not start. \(error.localizedDescription)"
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }

    /// Call after capture, processing or permission recovery changes state.
    func activityDidChange() {
        if installationGate.resumeWhenSafe(), installationGate.state == .installing {
            status = "Installing the update and restarting PressTalk…"
        }
    }

    /// Call if termination was cancelled after an installation reservation.
    /// A terminal Sparkle cycle also invalidates any deferred continuation.
    func installationWasCancelled() {
        installationGate.cancel()
        status = "Update installation was deferred. You can keep dictating."
    }

    func updater(
        _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        installationGate.postpone(installHandler)
        status = "Update ready. Waiting for dictation and setup to finish."
        // Return YES to Sparkle before invoking its continuation, even when idle.
        DispatchQueue.main.async { [weak self] in self?.activityDidChange() }
        return true
    }

    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        status = "Update downloaded. It will install when PressTalk quits."
        // Preserve Sparkle's standard install-on-quit behavior. The app's
        // applicationShouldTerminate gate protects this path as well.
        return false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        installationWasCancelled()
        status = "Update check ended. \(error.localizedDescription)"
    }

    func updater(
        _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        // Sparkle has cleared its driver before this terminal callback, even
        // for a dismissal/cancellation without an error. Never retain that
        // driver's weak continuation. StandardUpdaterController updates this
        // process's main bundle; successful final installation happens only
        // after this process terminates, so there is no live success window
        // requiring its reservation to survive this callback.
        if installationGate.state != .idle { installationWasCancelled() }
        if let error {
            status = error.localizedDescription
        } else {
            onStateChanged?()
        }
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func feedParameters(for updater: SPUUpdater, sendingSystemProfile: Bool) -> [[String: String]] { [] }

    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        !(isApplicationBusy?() ?? true)
    }
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate {
            status = "A PressTalk update is available. Choose Check for Updates when ready."
        }
    }

    private static func hasValidProductionSignature(_ bundle: Bundle) -> Bool {
        guard bundle.bundleIdentifier == UpdateSafetyPolicy.officialBundleIdentifier,
              bundle.bundleURL.pathExtension == "app" else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        let requirementText = "anchor apple generic and identifier \"\(UpdateSafetyPolicy.officialBundleIdentifier)\""
            + " and certificate leaf[subject.OU] = \"\(UpdateSafetyPolicy.officialTeamIdentifier)\""
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
    }
}
