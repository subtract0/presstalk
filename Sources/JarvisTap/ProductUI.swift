import AppKit
import CryptoKit
import Foundation
import PressTalkCore

struct VoiceLightBands {
    let low: Double
    let mid: Double
    let high: Double
}

struct PressTalkCommerceConfig {
    let upgradeURL: URL?
    let plansURL: URL?

    /// Reads the checkout address from `PressTalkOffer`, not from the process
    /// environment.
    ///
    /// It used to be environment-only, which meant both buy buttons were hidden
    /// in every build a customer could ever run: an app launched from Finder or
    /// the Dock inherits none of a shell's exported variables. The buttons were
    /// visible exactly once — in a terminal-launched developer build — and
    /// invisible in the one place they had to work. The environment still wins
    /// when set, so a staging checkout can be pointed at without a rebuild.
    init(env: [String: String] = ProcessInfo.processInfo.environment) {
        // Falls back to the FIRST LIVE RAIL, not to Stripe specifically. Reading
        // PressTalkOffer.checkoutURL here meant Settings lost its purchase
        // button entirely in a configuration the rest of the app considers
        // sellable -- PayPal configured, Stripe not -- because that property is
        // the Stripe rail by name.
        upgradeURL = (env["PRESSTALK_CHECKOUT_URL"] ?? env["PRESSTALK_UPGRADE_URL"])
            .flatMap(URL.init(string:))
            ?? PressTalkOffer.liveCheckoutRails.first
                .flatMap { PressTalkOffer.checkoutURL(for: $0) }
        plansURL = env["PRESSTALK_PLANS_URL"].flatMap(URL.init(string:))
            ?? PressTalkOffer.pricingPageURL
    }
}

struct PressTalkNativeTriggerSignature: Codable, Hashable {
    let subtype: Int
    let data1: Int
    let data2: Int
    let keyboardType: Int
    let sourceStateID: Int
    let modifierFlagsRaw: UInt

    var shortDescription: String {
        "subtype=\(subtype) data1=\(data1) data2=\(data2) keyboardType=\(keyboardType) sourceStateID=\(sourceStateID)"
    }
}

struct PressTalkNativeTriggerCalibration: Codable, Hashable {
    let press: PressTalkNativeTriggerSignature
    let release: PressTalkNativeTriggerSignature
    let calibratedAt: Date

    var shortDescription: String {
        "press[\(press.shortDescription)] release[\(release.shortDescription)]"
    }
}

/// Holds the installation's entitlement: a verified licence if one has been
/// imported, otherwise grandfathering or a trial.
///
/// Verification is entirely offline. No activation call, no machine binding, no
/// periodic re-check. A buy-once local app that stops working when a server does
/// has broken the thing it was sold on, so the licence is a signed file this Mac
/// can check on its own forever.
final class PressTalkLicenseStore {
    private enum Key {
        static let trialStartedAt = "PressTalk.TrialStartedAt"
        /// Recorded once, at the first launch of a licensing-aware build.
        static let predatesPaidLicensing = "PressTalk.PredatesPaidLicensing"
        static let hasSeenSetupGuide = "JarvisTap.HasSeenSetupGuide"
        static let firstDictationDelivered = "JarvisTap.FirstDictationDelivered"
        /// Keychain coordinates for the second copy of the trial start date.
        static let keychainService = "com.am.presstalk.trial"
        static let keychainAccount = "trial-started-at"
    }

    /// Public keys the app trusts. Rotating means adding a key here and shipping
    /// an update; licences signed by an older key keep working because the key
    /// id travels with the licence.
    ///
    /// The original founder key was generated 2026-09-06. Its private half lives outside this repository at
    /// ~/.presstalk-signing/ (mode 600) and must never be committed; only this
    /// public half ships. Rotating means adding a second entry here, not
    /// replacing this one, or every licence already sold stops verifying.
    /// The separate commerce key is held only by the purchase service. Adding
    /// it preserves every licence issued before automatic delivery existed.
    static let trustedPublicKeys: [String: String] = [
        "founder-2026": "kRCsB+YLcYSDKFt8u9qGXodXWEHGORTl3dYydLILFE4=",
        "commerce-2026": "JDwkjz0hZtenKwfUoAF1N0FH03WSruCxlrwkZpfYqtE=",
    ]

    private let defaults: UserDefaults
    private let policy = EntitlementPolicy()
    private let overrideEntitlement: String?
    private let verifier: PressTalkLicenseVerifier
    private lazy var paidLicense = OfflineLicenseStore(defaults: defaults, verifier: verifier)

    /// The trial start date is recorded in both, and the earliest one wins.
    /// UserDefaults alone made "3 days" mean "3 days per reinstall".
    private let anchorStores: [TrialAnchorStore]

    init(defaults: UserDefaults = .standard,
         env: [String: String] = ProcessInfo.processInfo.environment,
         anchorStores: [TrialAnchorStore]? = nil) {
        self.defaults = defaults
        self.overrideEntitlement = env["PRESSTALK_ENTITLEMENT_OVERRIDE"]
        self.anchorStores = anchorStores ?? [
            UserDefaultsTrialAnchorStore(defaults: defaults, key: Key.trialStartedAt),
            KeychainTrialAnchorStore(service: Key.keychainService,
                                     account: Key.keychainAccount),
        ]

        var keys: [String: Curve25519.Signing.PublicKey] = [:]
        for (keyID, encoded) in Self.trustedPublicKeys {
            guard let data = Data(base64Encoded: encoded),
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data)
            else { continue }
            keys[keyID] = key
        }
        let major = Int(
            (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")
                .split(separator: ".").first.map(String.init) ?? "0") ?? 0
        self.verifier = PressTalkLicenseVerifier(trustedKeys: keys, runningMajorVersion: max(major, 1))
    }

    /// Must run before any first-run default is written, and is called from the
    /// top of `runStartup()` for that reason. A second later the flags it reads
    /// are indistinguishable between a year-old install and one that launched
    /// moments ago.
    func recordInstallGenerationIfNeeded() {
        guard defaults.object(forKey: Key.predatesPaidLicensing) == nil else { return }
        let predates = InstallGeneration.predatesPaidLicensing(
            hasSeenSetupGuide: defaults.bool(forKey: Key.hasSeenSetupGuide),
            hasDeliveredDictation: defaults.bool(forKey: Key.firstDictationDelivered))
        defaults.set(predates, forKey: Key.predatesPaidLicensing)
    }

    private var priorUse: EntitlementPolicy.PriorUseEvidence {
        // Reads the recorded decision, never the live flags.
        EntitlementPolicy.PriorUseEvidence(
            predatesPaidLicensing: defaults.bool(forKey: Key.predatesPaidLicensing))
    }

    private var verifiedEntitlement: String? {
        if let overrideEntitlement { return overrideEntitlement }
        return paidLicense.license?.entitlement
    }

    /// Reads every anchor store, believes the earliest date, and refills any
    /// store that came back empty while another still held the date.
    var trialAnchor: TrialAnchor.Resolution {
        let resolution = TrialAnchor.resolve(anchorStores.map { $0.read() })
        if let startedAt = resolution.startedAt {
            for index in resolution.storesToHeal {
                anchorStores[index].write(startedAt)
            }
        }
        return resolution
    }

    var state: EntitlementPolicy.State {
        policy.state(
            verifiedEntitlement: verifiedEntitlement,
            priorUse: priorUse,
            trialStartedAt: trialAnchor.startedAt,
            now: Date())
    }

    /// Whether dictation should be refused right now.
    ///
    /// Deliberately not `!state.allowsDictation`. Three separate conditions have
    /// to hold before anyone is locked out, and each one is a way this could go
    /// wrong for a person who did nothing wrong: the state must actually be
    /// expired, the anchor reading must be trustworthy (a locked keychain proves
    /// nothing), and there must be somewhere to buy a licence. Refusing to
    /// dictate while offering no way to pay is a broken app, not a paywall.
    var shouldBlockDictation: Bool {
        guard case .trialExpired = state else { return false }
        guard TrialAnchor.mayEnforceExpiry(trialAnchor) else { return false }
        return PressTalkOffer.checkoutIsLive
    }

    /// Called after the first successful dictation. The trial starts when the
    /// product first works, not when it was installed.
    func startTrialIfNeeded() {
        guard verifiedEntitlement == nil, !priorUse.indicatesPriorUse else { return }
        // Checks every store, not just UserDefaults. Someone who reinstalled
        // still has a date in the keychain, and starting a new one here would
        // hand them the fresh trial the anchor exists to prevent.
        let existing = TrialAnchor.resolve(anchorStores.map { $0.read() })
        if let startedAt = existing.startedAt {
            for index in existing.storesToHeal { anchorStores[index].write(startedAt) }
            return
        }
        // An unreadable store may already hold a date. Writing a new one now
        // could only ever be a later date, and the earliest-wins rule would
        // discard it -- but writing into a store that could not be read risks
        // overwriting the real one, so wait for a reading that is trustworthy.
        guard existing.isTrustworthy else { return }
        let now = Date()
        for store in anchorStores { store.write(now) }
    }

    /// Verifies before storing. A bad paste must never displace a licence that
    /// was working.
    @discardableResult
    func importLicense(_ encoded: String) -> Result<PressTalkLicense, PressTalkLicenseError> {
        paidLicense.importLicense(encoded)
    }

    var currentPlanName: String {
        switch state {
        case .grandfathered: return "Free (early user)"
        case .licensed(let entitlement): return entitlement.capitalized
        case .trial: return "Trial"
        case .trialExpired: return "Trial finished"
        }
    }

    var planSummary: String { PressTalkOffer.stateSummary(state) }
    var pricingSummary: String { PressTalkOffer.founderSummary }
}

private final class VoiceLightView: NSView {
    /// True while the microphone is still coming up.
    ///
    /// Arming is drawn as a small dim core and nothing else. Dimming the full
    /// glow was not enough: the owner reported the light appearing "almost
    /// instantly" and only brightening when he spoke louder, while the log
    /// showed a full second of arming on AirPods. A slightly fainter version of
    /// the same shape reads as the same shape. A dot that is not the shape, and
    /// then the shape, reads as two states.
    private var isArming = false
    private var displayedLow: CGFloat = 0.06
    private var displayedMid: CGFloat = 0.05
    private var displayedHigh: CGFloat = 0.05
    private var shapePhase: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setArming(_ arming: Bool) {
        guard isArming != arming else { return }
        isArming = arming
        if arming {
            // Start from the floor so the first live band expands outward from
            // the core rather than snapping down to it.
            displayedLow = 0.0; displayedMid = 0.0; displayedHigh = 0.0
        }
        needsDisplay = true
    }

    func setBands(_ bands: VoiceLightBands) {
        // Bands arriving while arming would animate a light that is not
        // listening yet, which is the misinformation this state exists to stop.
        guard !isArming else { return }
        let low = CGFloat(max(0.0, min(1.0, bands.low)))
        let mid = CGFloat(max(0.0, min(1.0, bands.mid)))
        let high = CGFloat(max(0.0, min(1.0, bands.high)))

        displayedLow = (displayedLow * 0.72) + (low * 0.28)
        displayedMid = (displayedMid * 0.66) + (mid * 0.34)
        displayedHigh = (displayedHigh * 0.58) + (high * 0.42)
        shapePhase += 0.07 + (max(low, mid, high) * 0.10)
        if shapePhase > (.pi * 200) {
            shapePhase.formTruncatingRemainder(dividingBy: .pi * 2)
        }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let lowAccent = accentuated(displayedLow, gamma: 0.44, gain: 1.75)
        let midAccent = accentuated(displayedMid, gamma: 0.40, gain: 1.95)
        let highAccent = accentuated(displayedHigh, gamma: 0.35, gain: 2.15)
        let overall = max(lowAccent * 0.78, midAccent * 0.92, highAccent)

        context.clear(bounds)
        context.saveGState()
        context.setBlendMode(.screen)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        if isArming {
            // About 9 mm across on a standard display. Present enough to say
            // the key registered, small and still enough that nobody could
            // mistake it for the listening state, which fills the circle.
            drawSoftGlow(in: context, center: center, radius: 15,
                         xScale: 1.0, yScale: 1.0, alpha: 0.30)
            context.restoreGState()
            return
        }

        drawSoftGlow(
            in: context,
            center: center,
            radius: 214 + (overall * 92) + (lowAccent * 28),
            xScale: 1.04,
            yScale: 1.00,
            alpha: 0.26 + (overall * 0.28)
        )
        drawSoftGlow(
            in: context,
            center: center,
            radius: 128 + (midAccent * 48),
            xScale: 0.90,
            yScale: 1.18,
            alpha: 0.16 + (midAccent * 0.18)
        )
        drawSoftGlow(
            in: context,
            center: center,
            radius: 116 + (highAccent * 40),
            xScale: 1.26,
            yScale: 0.84,
            alpha: 0.15 + (highAccent * 0.17)
        )

        drawSoftGlow(
            in: context,
            center: center,
            radius: 88 + (midAccent * 26) + (highAccent * 22),
            xScale: 1.0,
            yScale: 1.0,
            alpha: 0.34 + (overall * 0.26)
        )
        drawGuideCore(
            in: context,
            center: center,
            radius: 20,
            alpha: 0.92 + (overall * 0.08)
        )
        context.restoreGState()
    }

    private func accentuated(_ value: CGFloat, gamma: CGFloat, gain: CGFloat) -> CGFloat {
        let lifted = pow(max(0.0, value), gamma) * gain
        return min(1.0, lifted)
    }

    private func drawSoftGlow(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        xScale: CGFloat,
        yScale: CGFloat,
        alpha: CGFloat
    ) {
        drawScaledRadialGradient(
            in: context,
            center: center,
            radius: radius,
            xScale: xScale,
            yScale: yScale,
            alpha: alpha
        )
    }

    private func drawGuideCore(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        alpha: CGFloat
    ) {
        drawScaledRadialGradient(
            in: context,
            center: center,
            radius: radius,
            xScale: 1.0,
            yScale: 1.0,
            alpha: alpha,
            stops: [
                (0.0, min(1.0, alpha)),
                (0.48, min(0.98, alpha * 0.94)),
                (0.78, min(0.42, alpha * 0.32)),
                (1.0, 0.0),
            ]
        )

        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(min(0.32, alpha * 0.24)).cgColor)
        context.setLineWidth(1.0)
        context.strokeEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        context.restoreGState()
    }

    private func drawScaledRadialGradient(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        xScale: CGFloat,
        yScale: CGFloat,
        alpha: CGFloat,
        stops: [(CGFloat, CGFloat)] = [
            (0.0, 1.0),
            (0.18, 0.58),
            (0.54, 0.16),
            (1.0, 0.0),
        ]
    ) {
        let colorComponents = stops.flatMap { _, stopAlpha in
            [CGFloat(1), CGFloat(1), CGFloat(1), min(1.0, alpha * stopAlpha)]
        }
        let locations = stops.map(\.0)

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let gradient = CGGradient(
                colorSpace: colorSpace,
                colorComponents: colorComponents,
                locations: locations,
                count: stops.count
            )
        else { return }

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: xScale, y: yScale)
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: 0,
            endCenter: .zero,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
        context.restoreGState()
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}

private final class CaptureHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class JarvisTapSettingsStore {
    enum InsertionSuffixOption: String, CaseIterable {
        case none
        case space
        case periodSpace
        case commaSpace
        case colonSpace
        case semicolonSpace
        case newline

        var displayName: String {
            switch self {
            case .none:
                return "Nothing"
            case .space:
                return "Space"
            case .periodSpace:
                return "Period + Space"
            case .commaSpace:
                return "Comma + Space"
            case .colonSpace:
                return "Colon + Space"
            case .semicolonSpace:
                return "Semicolon + Space"
            case .newline:
                return "New Line"
            }
        }
    }

    enum TriggerKeyOption: String, CaseIterable {
        case optionSpace = "option_space"
        case option = "option"
        case leftOption = "left_option"
        case rightOption = "right_option"
        case fn = "fn"
        case trackpadHold = "trackpad_hold"
        case f5 = "f5"

        var displayName: String {
            switch self {
            case .optionSpace:
                return "Option + Space"
            case .fn:
                return "Fn / Globe"
            case .option:
                return "Either Option"
            case .leftOption:
                return "Left Option"
            case .rightOption:
                return "Right Option"
            case .f5:
                return "Legacy F5 / Mic"
            case .trackpadHold:
                return "Trackpad Hold"
            }
        }
    }

    private enum Key {
        static let showHUD = "JarvisTap.ShowHUD"
        static let pasteAutomatically = "JarvisTap.PasteAutomatically"
        static let showAbortPopups = "JarvisTap.ShowAbortPopups"
        static let releaseTailMaxSeconds = "JarvisTap.ReleaseTailMaxSeconds"
        static let insertionSuffix = "JarvisTap.InsertionSuffix"
        static let triggerKey = "JarvisTap.TriggerKey"
        static let hasSeenSetupGuide = "JarvisTap.HasSeenSetupGuide"
        static let firstDictationDelivered = "JarvisTap.FirstDictationDelivered"
        static let firstRunSetupCompleted = "JarvisTap.FirstRunSetupCompleted"
        static let nativeTriggerCalibration = "JarvisTap.NativeTriggerCalibration"
    }

    private let defaults: UserDefaults

    init(config: JarvisTapConfig, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Language detection is automatic for every installation, including upgrades.
        defaults.removeObject(forKey: "JarvisTap.PreferredLanguage")
        defaults.register(defaults: [
            Key.showHUD: true,
            Key.pasteAutomatically: config.agentMode == "dictation",
            Key.showAbortPopups: true,
            Key.releaseTailMaxSeconds: config.releaseTailPaddingSeconds,
            Key.insertionSuffix: InsertionSuffixOption.space.rawValue,
            Key.triggerKey: config.triggerKey.rawValue,
            Key.hasSeenSetupGuide: false,
            Key.firstDictationDelivered: false,
            Key.firstRunSetupCompleted: false,
        ])
    }

    var showHUD: Bool {
        get { defaults.bool(forKey: Key.showHUD) }
        set { defaults.set(newValue, forKey: Key.showHUD) }
    }

    var pasteAutomatically: Bool {
        get { defaults.bool(forKey: Key.pasteAutomatically) }
        set { defaults.set(newValue, forKey: Key.pasteAutomatically) }
    }

    var showAbortPopups: Bool {
        get { defaults.bool(forKey: Key.showAbortPopups) }
        set { defaults.set(newValue, forKey: Key.showAbortPopups) }
    }

    var releaseTailMaxSeconds: TimeInterval {
        get {
            let value = defaults.double(forKey: Key.releaseTailMaxSeconds)
            return max(0.15, min(0.90, value))
        }
        set {
            defaults.set(max(0.15, min(0.90, newValue)), forKey: Key.releaseTailMaxSeconds)
        }
    }

    var insertionSuffix: InsertionSuffixOption {
        get {
            InsertionSuffixOption(rawValue: defaults.string(forKey: Key.insertionSuffix) ?? "") ?? .space
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.insertionSuffix)
        }
    }

    var triggerKey: TriggerKeyOption {
        get {
            TriggerKeyOption(rawValue: defaults.string(forKey: Key.triggerKey) ?? "") ?? .fn
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.triggerKey)
        }
    }

    /// Set the first time a dictation actually produces text. Setup is not
    /// finished because three toggles are on; it is finished because words
    /// arrived.
    var firstDictationDelivered: Bool {
        get { defaults.bool(forKey: Key.firstDictationDelivered) }
        set { defaults.set(newValue, forKey: Key.firstDictationDelivered) }
    }

    var firstRunSetupCompleted: Bool {
        get { defaults.bool(forKey: Key.firstRunSetupCompleted) }
        set { defaults.set(newValue, forKey: Key.firstRunSetupCompleted) }
    }

    var hasSeenSetupGuide: Bool {
        get { defaults.bool(forKey: Key.hasSeenSetupGuide) }
        set { defaults.set(newValue, forKey: Key.hasSeenSetupGuide) }
    }

    var nativeTriggerCalibration: PressTalkNativeTriggerCalibration? {
        get {
            guard let data = defaults.data(forKey: Key.nativeTriggerCalibration) else { return nil }
            return try? JSONDecoder().decode(PressTalkNativeTriggerCalibration.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.nativeTriggerCalibration)
            } else {
                defaults.removeObject(forKey: Key.nativeTriggerCalibration)
            }
        }
    }
}

final class PressTalkHUDController {
    enum Style {
        case warming
        case ready
        case listening
        case processing
        case inserted
        case copied
        case error

        var symbolName: String {
            switch self {
            case .warming:
                return "hourglass.circle.fill"
            case .ready:
                return "waveform.badge.mic"
            case .listening:
                return "mic.fill"
            case .processing:
                return "ellipsis.circle.fill"
            case .inserted, .copied:
                return "checkmark.circle.fill"
            case .error:
                return "exclamationmark.triangle.fill"
            }
        }

        var tintColor: NSColor {
            switch self {
            case .warming:
                return .systemOrange
            case .ready:
                return .systemBlue
            case .listening:
                return .systemRed
            case .processing:
                return .systemOrange
            case .inserted, .copied:
                return .systemGreen
            case .error:
                return .systemRed
            }
        }
    }

    private enum Mode {
        case none
        case light
        case cardTop
        case cardBottom
    }

    private let panel: NSPanel
    private let rootView = NSView()
    private let cardContainer = NSVisualEffectView()
    private let lightContainer = FlippedView()
    private let voiceLightView = VoiceLightView(frame: NSRect(x: 0, y: 0, width: 760, height: 440))
    private let liveTranscriptField = NSTextField(wrappingLabelWithString: "")
    private let iconView = NSImageView()
    private let titleField = NSTextField(wrappingLabelWithString: "")
    private let detailField = NSTextField(wrappingLabelWithString: "")
    private var hideWorkItem: DispatchWorkItem?
    private var mode: Mode = .none
    private var lightAnchorPoint: CGPoint?
    private var lightVerticalLift: CGFloat = 0
    private let listeningAnchorXRatio: CGFloat = 0.41
    private let liveTranscriptMaxCharacters = 220

    init() {
        panel = CaptureHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 112),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true

        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor

        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.material = .hudWindow
        cardContainer.blendingMode = .behindWindow
        cardContainer.state = .active
        cardContainer.wantsLayer = true
        cardContainer.layer?.cornerRadius = 20
        cardContainer.layer?.masksToBounds = true

        lightContainer.translatesAutoresizingMaskIntoConstraints = false
        lightContainer.wantsLayer = true
        lightContainer.layer?.backgroundColor = NSColor.clear.cgColor

        liveTranscriptField.translatesAutoresizingMaskIntoConstraints = true
        liveTranscriptField.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        liveTranscriptField.textColor = NSColor.white.withAlphaComponent(0.95)
        liveTranscriptField.alignment = .center
        liveTranscriptField.maximumNumberOfLines = 3
        liveTranscriptField.lineBreakMode = .byTruncatingHead
        liveTranscriptField.cell?.wraps = true
        liveTranscriptField.drawsBackground = false
        liveTranscriptField.isBordered = false
        liveTranscriptField.isBezeled = false
        liveTranscriptField.isEditable = false
        liveTranscriptField.isSelectable = false
        liveTranscriptField.isHidden = true
        let transcriptShadow = NSShadow()
        transcriptShadow.shadowColor = NSColor.black.withAlphaComponent(0.50)
        transcriptShadow.shadowBlurRadius = 9
        transcriptShadow.shadowOffset = NSSize(width: 0, height: 1)
        liveTranscriptField.shadow = transcriptShadow

        titleField.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byWordWrapping
        titleField.maximumNumberOfLines = 0

        detailField.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        detailField.textColor = .secondaryLabelColor
        detailField.maximumNumberOfLines = 0
        detailField.lineBreakMode = .byWordWrapping
        for field in [titleField, detailField] {
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            field.cell?.usesSingleLineMode = false
            field.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleField.translatesAutoresizingMaskIntoConstraints = false
        detailField.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleField, detailField])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        lightContainer.addSubview(voiceLightView)
        lightContainer.addSubview(liveTranscriptField)
        cardContainer.addSubview(iconView)
        cardContainer.addSubview(textStack)

        rootView.addSubview(lightContainer)
        rootView.addSubview(cardContainer)
        panel.contentView = rootView

        voiceLightView.translatesAutoresizingMaskIntoConstraints = true
        voiceLightView.frame = NSRect(x: 30, y: 15, width: 760, height: 440)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 20),
            iconView.centerYAnchor.constraint(equalTo: cardContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -20),
            textStack.centerYAnchor.constraint(equalTo: cardContainer.centerYAnchor),
            titleField.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            detailField.widthAnchor.constraint(equalTo: textStack.widthAnchor),
        ])

        if let contentView = panel.contentView {
            NSLayoutConstraint.activate([
                rootView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                rootView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                rootView.topAnchor.constraint(equalTo: contentView.topAnchor),
                rootView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

                cardContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
                cardContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
                cardContainer.topAnchor.constraint(equalTo: rootView.topAnchor),
                cardContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

                lightContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
                lightContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
                lightContainer.topAnchor.constraint(equalTo: rootView.topAnchor),
                lightContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            ])
        }

        cardContainer.isHidden = true
        lightContainer.isHidden = true
    }

    func show(title: String, detail: String?, style: Style, autoHideAfter: TimeInterval? = nil) {
        hideWorkItem?.cancel()
        mode = (style == .error) ? .cardBottom : .cardTop
        cardContainer.isHidden = false
        lightContainer.isHidden = true
        panel.hasShadow = true
        let image = NSImage(systemSymbolName: style.symbolName, accessibilityDescription: title)
        image?.isTemplate = false
        iconView.image = image
        iconView.contentTintColor = style.tintColor
        titleField.stringValue = title
        detailField.stringValue = detail ?? ""
        detailField.isHidden = detail?.isEmpty ?? true

        let cardWidth: CGFloat = 460
        let textWidth = cardWidth - 20 - 28 - 14 - 20
        titleField.preferredMaxLayoutWidth = textWidth
        detailField.preferredMaxLayoutWidth = textWidth
        // Transcript confirmations are previews. Instructions and errors get
        // the height needed for the complete message, including long device names.
        detailField.maximumNumberOfLines = (style == .inserted || style == .copied) ? 4 : 0
        func wrappedHeight(_ field: NSTextField) -> CGFloat {
            guard !field.isHidden else { return 0 }
            let bounds = NSRect(x: 0, y: 0, width: textWidth, height: .greatestFiniteMagnitude)
            return ceil(field.cell?.cellSize(forBounds: bounds).height ?? field.intrinsicContentSize.height)
        }
        let contentHeight = wrappedHeight(titleField) + (detailField.isHidden ? 0 : 4 + wrappedHeight(detailField))
        panel.setContentSize(NSSize(width: cardWidth, height: max(112, contentHeight + 44)))
        panel.contentView?.layoutSubtreeIfNeeded()
        positionPanel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        if let autoHideAfter {
            let workItem = DispatchWorkItem { [weak self] in
                self?.hide()
            }
            hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + autoHideAfter, execute: workItem)
        }
    }

    func showListeningLight(
        bands: VoiceLightBands,
        anchorPoint: CGPoint? = nil,
        verticalLift: CGFloat = 0,
        alpha: CGFloat = 1,
        transcript: String? = nil,
        arming: Bool = false
    ) {
        hideWorkItem?.cancel()
        mode = .light
        cardContainer.isHidden = true
        lightContainer.isHidden = false
        panel.hasShadow = false
        panel.setContentSize(NSSize(width: 820, height: 470))
        setLightAnchor(anchorPoint, verticalLift: verticalLift)
        setLiveTranscript(transcript)
        voiceLightView.setArming(arming)
        voiceLightView.setBands(bands)
        positionPanel()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.alphaValue = alpha
        panel.orderFrontRegardless()
    }

    func updateListeningLight(
        bands: VoiceLightBands,
        anchorPoint: CGPoint? = nil,
        verticalLift: CGFloat? = nil,
        alpha: CGFloat? = nil,
        transcript: String? = nil
    ) {
        if mode != .light {
            showListeningLight(
                bands: bands,
                anchorPoint: anchorPoint,
                verticalLift: verticalLift ?? 0,
                alpha: alpha ?? 1,
                transcript: transcript
            )
            return
        }
        if anchorPoint != nil || verticalLift != nil {
            setLightAnchor(anchorPoint, verticalLift: verticalLift)
        }
        voiceLightView.setBands(bands)
        if let alpha {
            panel.alphaValue = alpha
        }
        if let transcript {
            setLiveTranscript(transcript)
        }
        positionPanel()
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    func setLightAnchor(_ anchorPoint: CGPoint?, verticalLift: CGFloat? = nil) {
        lightAnchorPoint = anchorPoint
        if let verticalLift {
            lightVerticalLift = verticalLift
        }
        if mode == .light {
            positionPanel()
        }
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        mode = .none
        lightAnchorPoint = nil
        lightVerticalLift = 0
        setLiveTranscript(nil)
        panel.orderOut(nil)
    }

    private func setLiveTranscript(_ transcript: String?) {
        let displayText = liveTranscriptDisplayText(from: transcript)
        liveTranscriptField.stringValue = displayText ?? ""
        liveTranscriptField.isHidden = displayText == nil
    }

    private func liveTranscriptDisplayText(from transcript: String?) -> String? {
        guard let transcript else { return nil }
        let collapsed = transcript
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > liveTranscriptMaxCharacters else { return collapsed }
        let suffixLength = max(0, liveTranscriptMaxCharacters - 3)
        return "..." + String(collapsed.suffix(suffixLength))
    }

    private func positionPanel() {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let screen else { return }

        var frame = panel.frame
        switch mode {
        case .light:
            let anchorPoint = lightAnchorPoint ?? NSEvent.mouseLocation
            let anchorScreen = NSScreen.screens.first(where: { $0.frame.contains(anchorPoint) }) ?? screen
            let visibleFrame = anchorScreen.visibleFrame
            let desiredX = anchorPoint.x - (frame.width / 2)
            let desiredY = anchorPoint.y - (frame.height / 2)
            frame.origin.x = min(
                max(desiredX, visibleFrame.minX - 18),
                visibleFrame.maxX - frame.width + 18
            )
            frame.origin.y = min(
                max(desiredY, visibleFrame.minY - 18),
                visibleFrame.maxY - frame.height + 18
            )
            let localCenterX = anchorPoint.x - frame.origin.x
            let localBottomY = anchorPoint.y - frame.origin.y
            let containerHeight = max(lightContainer.bounds.height, frame.height)
            let localCenterY = (containerHeight - localBottomY) - lightVerticalLift
            voiceLightView.frame = NSRect(
                x: localCenterX - (voiceLightView.frame.width / 2),
                y: localCenterY - (voiceLightView.frame.height / 2),
                width: voiceLightView.frame.width,
                height: voiceLightView.frame.height
            )
            let transcriptWidth = min(CGFloat(520), max(CGFloat(300), frame.width - 120))
            let transcriptHeight: CGFloat = 76
            let horizontalInset: CGFloat = 40
            let belowY = localCenterY + 72
            let aboveY = localCenterY - 118
            let preferredY = belowY + transcriptHeight + 18 <= frame.height ? belowY : aboveY
            let maxTranscriptX = max(horizontalInset, frame.width - transcriptWidth - horizontalInset)
            let transcriptX = min(max(localCenterX - (transcriptWidth / 2), horizontalInset), maxTranscriptX)
            let transcriptY = min(
                max(preferredY, CGFloat(24)),
                max(CGFloat(24), frame.height - transcriptHeight - 24)
            )
            liveTranscriptField.frame = NSRect(
                x: transcriptX,
                y: transcriptY,
                width: transcriptWidth,
                height: transcriptHeight
            )
        case .cardBottom:
            let screenFrame = screen.frame
            let centerX = screenFrame.minX + (screenFrame.width * listeningAnchorXRatio)
            frame.origin.x = centerX - (frame.width / 2)
            frame.origin.y = screen.visibleFrame.minY + 28
        case .cardTop, .none:
            frame.origin.x = screen.visibleFrame.midX - (frame.width / 2)
            frame.origin.y = screen.visibleFrame.maxY - frame.height - 36
        }
        panel.setFrame(frame, display: true)
    }
}

final class PressTalkSettingsWindowController: NSWindowController, NSMenuDelegate {
    var onSettingsChanged: (() -> Void)?
    var onRunSetupCheck: (() -> Void)?
    var onRunPhysicalSmoke: (() -> Void)?
    var onExportDiagnostics: (() -> Void)?
    var onRestartApp: (() -> Void)?
    var onRepairLocalSigning: (() -> Void)?
    var onOpenMicrophoneSettings: (() -> Void)?
    var onOpenInputMonitoringSettings: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
    var onDisableSystemDictationHotkey: (() -> Void)?
    var onEnableF5Fallback: (() -> Void)?
    var onDisableF5Fallback: (() -> Void)?
    var onStartNativeCalibration: (() -> Void)?
    var onClearNativeCalibration: (() -> Void)?

    private let settingsStore: JarvisTapSettingsStore
    private let licenseStore: PressTalkLicenseStore
    private let commerceConfig: PressTalkCommerceConfig
    private let audioInputDefaults: UserDefaults
    private var runtimeStatus: PressTalkRuntimeStatus = .placeholder
    private let showHUDCheckbox = NSButton(checkboxWithTitle: "Show compact HUD", target: nil, action: nil)
    private let pasteAutomaticallyCheckbox = NSButton(checkboxWithTitle: "Paste transcript automatically", target: nil, action: nil)
    private let triggerKeyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let insertionSuffixPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    /// What the picker lists. Supplied by the app so CoreAudio stays out of
    /// the view, and so the list is whatever the capture path would actually
    /// see rather than a second enumeration that can disagree with it.
    struct AudioInputChoice {
        let uid: String
        let name: String
        let isDefault: Bool
        let isBluetooth: Bool
        /// What this device has actually cost on this Mac, or nil if it has
        /// never been used or is fast. Measured, never assumed.
        let startNote: String?
    }
    var onListAudioInputs: (() -> [AudioInputChoice])?
    var onAudioInputPreferenceChanged: (() -> Void)?

    private let microphonePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let microphoneHintLabel = NSTextField(wrappingLabelWithString: "")
    /// The devices currently listed, so selecting one can say what it costs.
    private var microphoneChoices: [AudioInputChoice] = []
    static let microphoneHintDefault =
        "Choose the microphone PressTalk uses. This does not change your Mac's "
        + "default input. A new choice applies to your next recording."

    /// Device UID per menu index, so a choice survives the AudioDeviceID being
    /// reassigned. Observed on this machine: the same Shure moved from id 156
    /// to 157 across a reconnect.
    private var microphoneMenuUIDs: [String?] = []
    private let releaseTailSlider = NSSlider(value: 0.35, minValue: 0.15, maxValue: 0.90, target: nil, action: nil)
    private let releaseTailValueLabel = NSTextField(labelWithString: "")
    private let currentPlanValueLabel = NSTextField(labelWithString: "")
    private let planSummaryLabel = NSTextField(wrappingLabelWithString: "")
    private let pricingSummaryLabel = NSTextField(wrappingLabelWithString: "")
    private let plansButton = NSButton(title: "Pricing", target: nil, action: nil)
    private let upgradeButton = NSButton(title: "Buy PressTalk", target: nil, action: nil)
    private let setupHintLabel = NSTextField(wrappingLabelWithString: "")
    private let inputMonitoringValueLabel = NSTextField(labelWithString: "")
    private let microphoneValueLabel = NSTextField(labelWithString: "")
    private let accessibilityValueLabel = NSTextField(labelWithString: "")
    private let systemDictationValueLabel = NSTextField(labelWithString: "")
    private let speechModelValueLabel = NSTextField(labelWithString: "")
    private let f5BridgeValueLabel = NSTextField(labelWithString: "")
    private let runSetupCheckButton = NSButton(title: "Run Setup Check", target: nil, action: nil)
    private let runPhysicalSmokeButton = NSButton(title: "Test Dictation Shortcut", target: nil, action: nil)
    private let restartAppButton = NSButton(title: "Restart PressTalk", target: nil, action: nil)
    private let repairLocalSigningButton = NSButton(title: "Repair Signing", target: nil, action: nil)
    private let exportDiagnosticsButton = NSButton(title: "Export Diagnostics", target: nil, action: nil)
    private let enterLicenseButton = NSButton(title: "Enter Licence Key…", target: nil, action: nil)
    private let microphoneSettingsButton = NSButton(title: "Microphone", target: nil, action: nil)
    private let inputMonitoringSettingsButton = NSButton(title: "Input Monitoring", target: nil, action: nil)
    private let accessibilitySettingsButton = NSButton(title: "Accessibility", target: nil, action: nil)
    private let revealAppButton = NSButton(title: "Show This App", target: nil, action: nil)
    private let disableSystemDictationButton = NSButton(title: "Disable Apple Dictation Key", target: nil, action: nil)
    private let calibrateNativeF5Button = NSButton(title: "Calibrate Native F5", target: nil, action: nil)
    private let clearNativeCalibrationButton = NSButton(title: "Clear Native Calibration", target: nil, action: nil)
    private let enableF5FallbackButton = NSButton(title: "Enable F5 Fallback", target: nil, action: nil)
    private let disableF5FallbackButton = NSButton(title: "Disable F5 Fallback", target: nil, action: nil)
    private var legacyShortcutRows: [NSView] = []

    init(
        settingsStore: JarvisTapSettingsStore,
        licenseStore: PressTalkLicenseStore,
        commerceConfig: PressTalkCommerceConfig = PressTalkCommerceConfig(),
        audioInputDefaults: UserDefaults = .standard
    ) {
        self.settingsStore = settingsStore
        self.licenseStore = licenseStore
        self.commerceConfig = commerceConfig
        self.audioInputDefaults = audioInputDefaults

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PressTalk Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 420)
        super.init(window: window)
        buildUI()
        reloadFromStore()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        // Rebuilt on every open. Devices come and go -- a Shure moved from id
        // 156 to 157 across a reconnect on this machine -- and a list built
        // once at construction is both stale and empty, because the app wires
        // onListAudioInputs after the window is created.
        rebuildMicrophoneMenu()
        reloadFromStore()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateRuntimeStatus(_ status: PressTalkRuntimeStatus) {
        runtimeStatus = status
        applyRuntimeStatus()
    }

    func reloadFromStore() {
        showHUDCheckbox.state = settingsStore.showHUD ? .on : .off
        pasteAutomaticallyCheckbox.state = settingsStore.pasteAutomatically ? .on : .off
        triggerKeyPopup.selectItem(at: JarvisTapSettingsStore.TriggerKeyOption.allCases.firstIndex(of: settingsStore.triggerKey) ?? 0)
        insertionSuffixPopup.selectItem(at: JarvisTapSettingsStore.InsertionSuffixOption.allCases.firstIndex(of: settingsStore.insertionSuffix) ?? 0)
        releaseTailSlider.doubleValue = settingsStore.releaseTailMaxSeconds
        currentPlanValueLabel.stringValue = licenseStore.currentPlanName
        planSummaryLabel.stringValue = licenseStore.planSummary
        pricingSummaryLabel.stringValue = licenseStore.pricingSummary
        pricingSummaryLabel.isHidden = !pricingSummaryLabel.stringValue.isEmpty &&
            planSummaryLabel.stringValue.contains(pricingSummaryLabel.stringValue)
        plansButton.isHidden = commerceConfig.plansURL == nil
        upgradeButton.isHidden = commerceConfig.upgradeURL == nil
        if case .licensed = licenseStore.state { upgradeButton.isHidden = true }
        refreshReleaseTailLabel()
        applyRuntimeStatus()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "Hold a key. Speak. Release.")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)

        let subtitleLabel = NSTextField(wrappingLabelWithString: "Hold your chosen shortcut, speak, then release. PressTalk transcribes on this Mac and detects your language automatically.")
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor

        let setupLabel = NSTextField(labelWithString: "Setup & Diagnostics")
        setupLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        setupHintLabel.font = NSFont.systemFont(ofSize: 12)
        setupHintLabel.textColor = .secondaryLabelColor

        let planLabel = NSTextField(labelWithString: "Licence")
        planLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        currentPlanValueLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        currentPlanValueLabel.textColor = .labelColor

        planSummaryLabel.font = NSFont.systemFont(ofSize: 12)
        planSummaryLabel.textColor = .secondaryLabelColor

        pricingSummaryLabel.font = NSFont.systemFont(ofSize: 12)
        pricingSummaryLabel.textColor = .secondaryLabelColor

        let triggerKeyLabel = NSTextField(labelWithString: "Trigger")
        triggerKeyLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        triggerKeyPopup.addItems(withTitles: JarvisTapSettingsStore.TriggerKeyOption.allCases.map(\.displayName))

        let microphoneLabel = NSTextField(labelWithString: "Microphone")
        microphoneLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        rebuildMicrophoneMenu()

        let insertionSuffixLabel = NSTextField(labelWithString: "After insertion")
        insertionSuffixLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        insertionSuffixPopup.addItems(withTitles: JarvisTapSettingsStore.InsertionSuffixOption.allCases.map(\.displayName))

        let tailLabel = NSTextField(labelWithString: "Finish speaking after release")
        tailLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let tailHintLabel = NSTextField(wrappingLabelWithString: "Maximum time to keep listening after you release the shortcut. Recording can end sooner when speech has finished.")
        tailHintLabel.font = NSFont.systemFont(ofSize: 12)
        tailHintLabel.textColor = .secondaryLabelColor

        let plansRow = NSStackView(views: [planLabel, currentPlanValueLabel])
        plansRow.orientation = .horizontal
        plansRow.alignment = .centerY
        plansRow.distribution = .equalSpacing

        plansButton.bezelStyle = .rounded
        upgradeButton.bezelStyle = .rounded

        let commerceButtonsRow = NSStackView(views: [plansButton, upgradeButton, enterLicenseButton])
        commerceButtonsRow.orientation = .horizontal
        commerceButtonsRow.alignment = .centerY
        commerceButtonsRow.spacing = 8

        for button in [
            runSetupCheckButton,
            runPhysicalSmokeButton,
            restartAppButton,
            repairLocalSigningButton,
            exportDiagnosticsButton,
            microphoneSettingsButton,
            inputMonitoringSettingsButton,
            accessibilitySettingsButton,
            revealAppButton,
            disableSystemDictationButton,
            calibrateNativeF5Button,
            clearNativeCalibrationButton,
            enableF5FallbackButton,
            disableF5FallbackButton,
        ] {
            button.bezelStyle = .rounded
        }

        let setupButtonsRow = NSStackView(views: [microphoneSettingsButton, inputMonitoringSettingsButton, accessibilitySettingsButton])
        setupButtonsRow.orientation = .horizontal
        setupButtonsRow.alignment = .centerY
        setupButtonsRow.spacing = 8

        let diagnosticsButtonsRow = NSStackView(views: [runSetupCheckButton, exportDiagnosticsButton])
        diagnosticsButtonsRow.orientation = .horizontal
        diagnosticsButtonsRow.alignment = .centerY
        diagnosticsButtonsRow.spacing = 8

        let maintenanceButtonsRow = NSStackView(views: [restartAppButton, repairLocalSigningButton, revealAppButton])
        maintenanceButtonsRow.orientation = .horizontal
        maintenanceButtonsRow.alignment = .centerY
        maintenanceButtonsRow.spacing = 8

        let physicalSmokeButtonsRow = NSStackView(views: [runPhysicalSmokeButton])
        physicalSmokeButtonsRow.orientation = .horizontal
        physicalSmokeButtonsRow.alignment = .centerY
        physicalSmokeButtonsRow.spacing = 8

        let dictationButtonsRow = NSStackView(views: [disableSystemDictationButton])
        dictationButtonsRow.orientation = .horizontal
        dictationButtonsRow.alignment = .centerY
        dictationButtonsRow.spacing = 8

        let nativeButtonsRow = NSStackView(views: [calibrateNativeF5Button, clearNativeCalibrationButton])
        nativeButtonsRow.orientation = .horizontal
        nativeButtonsRow.alignment = .centerY
        nativeButtonsRow.spacing = 8

        let fallbackButtonsRow = NSStackView(views: [enableF5FallbackButton, disableF5FallbackButton])
        fallbackButtonsRow.orientation = .horizontal
        fallbackButtonsRow.alignment = .centerY
        fallbackButtonsRow.spacing = 8
        legacyShortcutRows = [nativeButtonsRow, fallbackButtonsRow]

        let inputMonitoringRow = makeStatusRow(title: "Input Monitoring", valueLabel: inputMonitoringValueLabel)
        let microphoneRow = makeStatusRow(title: "Microphone", valueLabel: microphoneValueLabel)
        let accessibilityRow = makeStatusRow(title: "Accessibility", valueLabel: accessibilityValueLabel)
        let systemDictationRow = makeStatusRow(title: "Apple Dictation key", valueLabel: systemDictationValueLabel)
        let speechModelRow = makeStatusRow(title: "Speech model", valueLabel: speechModelValueLabel)
        let f5BridgeRow = makeStatusRow(title: "Trigger path", valueLabel: f5BridgeValueLabel)

        let triggerKeyRow = NSStackView(views: [triggerKeyLabel, triggerKeyPopup])
        triggerKeyRow.orientation = .horizontal
        triggerKeyRow.alignment = .centerY
        triggerKeyRow.distribution = .fillProportionally
        triggerKeyRow.spacing = 12

        // Named for the picker, not the permission status row above, which is
        // already called microphoneRow.
        let microphonePickerRow = NSStackView(views: [microphoneLabel, microphonePopup])
        microphonePickerRow.orientation = .horizontal
        microphonePickerRow.alignment = .centerY
        microphonePickerRow.distribution = .fillProportionally
        microphonePickerRow.spacing = 12

        microphoneHintLabel.stringValue = Self.microphoneHintDefault
        microphoneHintLabel.font = NSFont.systemFont(ofSize: 12)
        microphoneHintLabel.textColor = .secondaryLabelColor
        microphoneHintLabel.lineBreakMode = .byWordWrapping
        microphoneHintLabel.maximumNumberOfLines = 0

        let insertionSuffixRow = NSStackView(views: [insertionSuffixLabel, insertionSuffixPopup])
        insertionSuffixRow.orientation = .horizontal
        insertionSuffixRow.alignment = .centerY
        insertionSuffixRow.distribution = .fillProportionally
        insertionSuffixRow.spacing = 12

        let tailHeaderRow = NSStackView(views: [tailLabel, releaseTailValueLabel])
        tailHeaderRow.orientation = .horizontal
        tailHeaderRow.alignment = .centerY
        tailHeaderRow.distribution = .equalSpacing

        let stack = NSStackView(views: [
            titleLabel,
            subtitleLabel,
            triggerKeyRow,
            microphonePickerRow,
            microphoneHintLabel,
            showHUDCheckbox,
            pasteAutomaticallyCheckbox,
            insertionSuffixRow,
            tailHeaderRow,
            releaseTailSlider,
            tailHintLabel,
            setupLabel,
            setupHintLabel,
            inputMonitoringRow,
            microphoneRow,
            accessibilityRow,
            systemDictationRow,
            speechModelRow,
            f5BridgeRow,
            setupButtonsRow,
            diagnosticsButtonsRow,
            maintenanceButtonsRow,
            physicalSmokeButtonsRow,
            dictationButtonsRow,
            nativeButtonsRow,
            fallbackButtonsRow,
            plansRow,
            planSummaryLabel,
            pricingSummaryLabel,
            commerceButtonsRow,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        // Constrain wrapped text and rows to the viewport, including at the
        // minimum window width. Intrinsic text width must not widen the page.
        for view in [subtitleLabel, microphoneHintLabel, tailHintLabel, setupHintLabel,
                     planSummaryLabel, pricingSummaryLabel, triggerKeyRow,
                     microphonePickerRow, insertionSuffixRow, tailHeaderRow,
                     releaseTailSlider, inputMonitoringRow, microphoneRow,
                     accessibilityRow, systemDictationRow, speechModelRow,
                     f5BridgeRow, plansRow] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for field in [subtitleLabel, microphoneHintLabel, tailHintLabel, setupHintLabel,
                      planSummaryLabel, pricingSummaryLabel] {
            field.maximumNumberOfLines = 0
            field.lineBreakMode = .byWordWrapping
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            field.cell?.usesSingleLineMode = false
            field.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        contentView.addSubview(scrollView)
        documentView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -18),
        ])

        showHUDCheckbox.target = self
        showHUDCheckbox.action = #selector(toggleShowHUD(_:))

        pasteAutomaticallyCheckbox.target = self
        pasteAutomaticallyCheckbox.action = #selector(togglePasteAutomatically(_:))

        triggerKeyPopup.target = self
        triggerKeyPopup.action = #selector(changeTriggerKey(_:))

        insertionSuffixPopup.target = self
        insertionSuffixPopup.action = #selector(changeInsertionSuffix(_:))

        releaseTailSlider.target = self
        releaseTailSlider.action = #selector(changeReleaseTail(_:))

        plansButton.target = self
        plansButton.action = #selector(openPlans(_:))

        upgradeButton.target = self
        upgradeButton.action = #selector(openUpgrade(_:))

        runSetupCheckButton.target = self
        runSetupCheckButton.action = #selector(runSetupCheck(_:))
        runSetupCheckButton.setAccessibilityIdentifier("settings.runSetupCheck")
        microphonePopup.setAccessibilityIdentifier("settings.microphone")
        triggerKeyPopup.setAccessibilityIdentifier("settings.trigger")
        showHUDCheckbox.setAccessibilityIdentifier("settings.showHUD")
        pasteAutomaticallyCheckbox.setAccessibilityIdentifier("settings.autoPaste")
        insertionSuffixPopup.setAccessibilityIdentifier("settings.insertionSuffix")
        releaseTailSlider.setAccessibilityIdentifier("settings.releaseTail")

        runPhysicalSmokeButton.target = self
        runPhysicalSmokeButton.action = #selector(runPhysicalSmoke(_:))
        runPhysicalSmokeButton.setAccessibilityIdentifier("settings.testDictation")

        restartAppButton.target = self
        restartAppButton.action = #selector(restartApp(_:))

        repairLocalSigningButton.target = self
        repairLocalSigningButton.action = #selector(repairLocalSigning(_:))

        exportDiagnosticsButton.target = self
        exportDiagnosticsButton.action = #selector(exportDiagnostics(_:))
        enterLicenseButton.target = self
        enterLicenseButton.action = #selector(enterLicense(_:))

        microphoneSettingsButton.target = self
        microphoneSettingsButton.action = #selector(openMicrophoneSettings(_:))

        inputMonitoringSettingsButton.target = self
        inputMonitoringSettingsButton.action = #selector(openInputMonitoringSettings(_:))

        accessibilitySettingsButton.target = self
        accessibilitySettingsButton.action = #selector(openAccessibilitySettings(_:))
        revealAppButton.target = self
        revealAppButton.action = #selector(revealApp(_:))
        revealAppButton.toolTip = Bundle.main.bundleURL.path

        disableSystemDictationButton.target = self
        disableSystemDictationButton.action = #selector(disableSystemDictationHotkey(_:))

        calibrateNativeF5Button.target = self
        calibrateNativeF5Button.action = #selector(startNativeCalibration(_:))

        clearNativeCalibrationButton.target = self
        clearNativeCalibrationButton.action = #selector(clearNativeCalibration(_:))

        enableF5FallbackButton.target = self
        enableF5FallbackButton.action = #selector(enableF5Fallback(_:))

        disableF5FallbackButton.target = self
        disableF5FallbackButton.action = #selector(disableF5Fallback(_:))
    }

    private func makeStatusRow(title: String, valueLabel: NSTextField) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        valueLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        valueLabel.lineBreakMode = .byWordWrapping
        valueLabel.maximumNumberOfLines = 0
        valueLabel.cell?.wraps = true
        valueLabel.cell?.isScrollable = false
        valueLabel.cell?.usesSingleLineMode = false
        valueLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let row = NSStackView(views: [titleLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .top
        row.distribution = .fill
        row.spacing = 12
        titleLabel.widthAnchor.constraint(equalToConstant: 140).isActive = true
        return row
    }

    private func applyRuntimeStatus() {
        for row in legacyShortcutRows { row.isHidden = settingsStore.triggerKey != .f5 }
        clearNativeCalibrationButton.isEnabled = settingsStore.nativeTriggerCalibration != nil
        disableSystemDictationButton.isHidden = runtimeStatus.systemDictationHotkeyDisabled ||
            (settingsStore.triggerKey != .fn && settingsStore.triggerKey != .f5)
        configureInputMonitoringLabel(inputMonitoringValueLabel)
        configureMicrophoneLabel(microphoneValueLabel)
        configureAccessibilityLabel(accessibilityValueLabel)
        configureInterferenceLabel(systemDictationValueLabel, disabled: runtimeStatus.systemDictationHotkeyDisabled)
        configureDetailLabel(speechModelValueLabel, text: runtimeStatus.speechModelStatus)
        configureDetailLabel(f5BridgeValueLabel, text: runtimeStatus.f5BridgeStatus)
        configurePermissionPaneButtons()
        configureRepairLocalSigningButton()
        setupHintLabel.stringValue = permissionHintText()
    }

    private func configureRepairLocalSigningButton() {
        let shouldShow = runtimeStatus.localSigningRepairNeeded
        repairLocalSigningButton.isHidden = !shouldShow
        repairLocalSigningButton.isEnabled = shouldShow
        repairLocalSigningButton.toolTip = shouldShow
            ? "Runs the bundled local signing repair helper with permission panes disabled, then runs the production insertion probe."
            : nil
    }

    private func configurePermissionPaneButtons() {
        // Manual controls must work even when background launch settings
        // suppress automatic permission prompts.
        let enabled = true
        let tooltip: String? = nil
        let microphoneNeedsPane = !runtimeStatus.microphoneGranted
        let shortcutNeedsAccessibility = runtimeStatus.triggerRequiresWritableEventTap &&
            !runtimeStatus.accessibilityGranted
        let inputMonitoringNeedsPane = !runtimeStatus.inputMonitoringEffective &&
            !runtimeStatus.triggerUsesRegisteredHotKey &&
            !shortcutNeedsAccessibility &&
            !runtimeStatus.localSigningRepairNeeded
        let accessibilityNeedsPane = shortcutNeedsAccessibility ||
            (runtimeStatus.pasteAutomatically && !runtimeStatus.activeFieldInsertionReady &&
             !runtimeStatus.localSigningRepairNeeded)

        configurePermissionPaneButton(
            microphoneSettingsButton,
            enabled: enabled,
            shouldShow: microphoneNeedsPane,
            tooltip: tooltip
        )
        configurePermissionPaneButton(
            inputMonitoringSettingsButton,
            enabled: enabled,
            shouldShow: inputMonitoringNeedsPane,
            tooltip: tooltip
        )
        configurePermissionPaneButton(
            accessibilitySettingsButton,
            enabled: enabled,
            shouldShow: accessibilityNeedsPane,
            tooltip: tooltip
        )
    }

    private func configurePermissionPaneButton(
        _ button: NSButton,
        enabled: Bool,
        shouldShow: Bool,
        tooltip: String?
    ) {
        button.isEnabled = enabled && shouldShow
        button.isHidden = !enabled || !shouldShow
        button.toolTip = tooltip
    }

    private func configureInputMonitoringLabel(_ label: NSTextField) {
        applyPermissionLabel(runtimeStatus.inputMonitoringPermissionLabel, to: label)
    }

    private func configureAccessibilityLabel(_ label: NSTextField) {
        applyPermissionLabel(runtimeStatus.accessibilityPermissionLabel, to: label)
    }

    private func configureMicrophoneLabel(_ label: NSTextField) {
        applyPermissionLabel(runtimeStatus.microphonePermissionLabel, to: label)
    }

    private func applyPermissionLabel(_ permissionLabel: PressTalkPermissionLabel, to label: NSTextField) {
        label.stringValue = permissionLabel.text
        switch permissionLabel.tone {
        case .ready:
            label.textColor = .systemGreen
        case .warning:
            label.textColor = .systemOrange
        case .secondary:
            label.textColor = .secondaryLabelColor
        }
    }

    private func permissionHintText() -> String {
        let help = " Use the permission buttons below. If macOS already shows this app enabled, use Show This App to locate the running copy before replacing its stale entry with the + button."
        if !runtimeStatus.microphoneGranted {
            return "Microphone access is needed to record your voice." + help
        }
        if !runtimeStatus.inputMonitoringEffective {
            if runtimeStatus.triggerRequiresWritableEventTap && !runtimeStatus.accessibilityGranted {
                return "Your selected shortcut needs Accessibility permission." + help
            }
            return "The selected shortcut is not ready. Check Input Monitoring, then run Setup Check." + help
        }
        if runtimeStatus.pasteAutomatically && !runtimeStatus.accessibilityGranted {
            return "Accessibility permission is needed to insert text into another app. Until then, dictation copies to the clipboard." + help
        }
        if runtimeStatus.speechModelStatus != "Ready" {
            return "Permissions are set. Speech model: \(runtimeStatus.speechModelStatus)."
        }
        return runtimeStatus.pasteAutomatically
            ? "Permissions are set. Dictate a sentence in another app to check recording and insertion."
            : "Dictation copies to the clipboard. Use ⌘V to paste it into another app."
    }

    private func configureDetailLabel(_ label: NSTextField, text: String) {
        label.stringValue = text
        label.textColor = .secondaryLabelColor
    }

    private func configureInterferenceLabel(_ label: NSTextField, disabled: Bool) {
        label.stringValue = disabled ? "Disabled" : "Active"
        label.textColor = disabled ? .systemGreen : .systemOrange
    }

    private func refreshReleaseTailLabel() {
        releaseTailValueLabel.stringValue = String(format: "%.2f s", settingsStore.releaseTailMaxSeconds)
    }

    @objc private func toggleShowHUD(_ sender: NSButton) {
        settingsStore.showHUD = sender.state == .on
        onSettingsChanged?()
    }

    @objc private func togglePasteAutomatically(_ sender: NSButton) {
        settingsStore.pasteAutomatically = sender.state == .on
        onSettingsChanged?()
    }

    @objc private func changeTriggerKey(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard JarvisTapSettingsStore.TriggerKeyOption.allCases.indices.contains(index) else { return }
        settingsStore.triggerKey = JarvisTapSettingsStore.TriggerKeyOption.allCases[index]
        onSettingsChanged?()
    }

    /// Rebuilt every time Settings opens, because devices come and go and a
    /// stale list is how someone ends up selecting a microphone that is no
    /// longer plugged in.
    func rebuildMicrophoneMenu() {
        let previous = AudioInputPreference(
            storageValue: audioInputDefaults.string(forKey: "PressTalk.AudioInputPreference"))
        microphonePopup.removeAllItems()
        microphoneMenuUIDs = []

        microphonePopup.addItem(withTitle: "System default")
        microphoneMenuUIDs.append(nil)
        microphonePopup.addItem(withTitle: "Prefer wired or built-in")
        microphoneMenuUIDs.append("")

        microphoneChoices = onListAudioInputs?() ?? []
        for device in microphoneChoices {
            // No mute annotation. It came from kAudioDevicePropertyMute, whose
            // meaning on a given device cannot be established from one read --
            // it labelled a Shure "muted" while Zoom was recording from it.
            // Showing a conclusion in a picker that the app withdrew from its
            // error messages would just move the wrong claim somewhere quieter.
            let mutedNote = ""
            let defaultNote = device.isDefault ? " (current default)" : ""
            microphonePopup.addItem(withTitle: "\(device.name)\(defaultNote)\(mutedNote)")
            microphoneMenuUIDs.append(device.uid)
        }

        switch previous {
        case .systemDefault: microphonePopup.selectItem(at: 0)
        case .preferWired: microphonePopup.selectItem(at: 1)
        case .specificDevice(let uid):
            if let index = microphoneMenuUIDs.firstIndex(of: uid) {
                microphonePopup.selectItem(at: index)
            } else {
                // Chosen device is unplugged. Show that rather than silently
                // reverting, so nobody wonders why their choice stopped
                // applying.
                microphonePopup.addItem(withTitle: "Chosen microphone (not connected)")
                microphoneMenuUIDs.append(uid)
                microphonePopup.selectItem(at: microphonePopup.numberOfItems - 1)
            }
        }
        microphonePopup.target = self
        microphonePopup.action = #selector(changeMicrophone(_:))
        microphonePopup.menu?.delegate = self
        updateMicrophoneHint(for: previous)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === microphonePopup.menu { rebuildMicrophoneMenu() }
    }

    @objc private func changeMicrophone(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < microphoneMenuUIDs.count else { return }
        let preference: AudioInputPreference
        switch microphoneMenuUIDs[index] {
        case .none: preference = .systemDefault
        case .some(let uid) where uid.isEmpty: preference = .preferWired
        case .some(let uid): preference = .specificDevice(uid: uid)
        }
        audioInputDefaults.set(preference.storageValue,
                                  forKey: "PressTalk.AudioInputPreference")
        // Choosing a microphone withdraws the crash breaker's skip. It told
        // this person a device had failed and to pick it again here if they
        // wanted it; continuing to skip it after they did would make the
        // instruction a lie.
        audioInputDefaults.removeObject(forKey: "PressTalk.AudioInputAvoidUID")
        onAudioInputPreferenceChanged?()

        updateMicrophoneHint(for: preference)
    }

    private func updateMicrophoneHint(for preference: AudioInputPreference) {
        let selectedDevice: MicrophoneSelectionHint.Device?
        if case .specificDevice(let uid) = preference,
           let choice = microphoneChoices.first(where: { $0.uid == uid }) {
            selectedDevice = .init(name: choice.name,
                                   isBluetooth: choice.isBluetooth,
                                   startNote: choice.startNote)
        } else {
            selectedDevice = nil
        }
        let fallback: String
        switch preference {
        case .systemDefault:
            fallback = "Uses the Mac's current default microphone when each recording starts. PressTalk does not change that default."
        case .preferWired:
            fallback = "Chooses an available wired or built-in microphone first, otherwise another available input. PressTalk does not change the Mac's default."
        case .specificDevice:
            fallback = selectedDevice == nil
                ? "Your chosen microphone is not connected. Reconnect it or choose another microphone; PressTalk will not switch silently."
                : Self.microphoneHintDefault
        }
        microphoneHintLabel.stringValue = MicrophoneSelectionHint.text(
            forSelected: selectedDevice, default: fallback)
    }

    @objc private func changeInsertionSuffix(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard JarvisTapSettingsStore.InsertionSuffixOption.allCases.indices.contains(index) else { return }
        settingsStore.insertionSuffix = JarvisTapSettingsStore.InsertionSuffixOption.allCases[index]
        onSettingsChanged?()
    }

    @objc private func changeReleaseTail(_ sender: NSSlider) {
        let steppedValue = (sender.doubleValue / 0.05).rounded() * 0.05
        settingsStore.releaseTailMaxSeconds = steppedValue
        sender.doubleValue = steppedValue
        refreshReleaseTailLabel()
        onSettingsChanged?()
    }

    @objc private func openPlans(_ sender: Any?) {
        guard let url = commerceConfig.plansURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openUpgrade(_ sender: Any?) {
        guard let url = commerceConfig.upgradeURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func runSetupCheck(_ sender: Any?) {
        onRunSetupCheck?()
    }

    @objc private func runPhysicalSmoke(_ sender: Any?) {
        onRunPhysicalSmoke?()
    }

    @objc private func restartApp(_ sender: Any?) {
        onRestartApp?()
    }

    @objc private func repairLocalSigning(_ sender: Any?) {
        onRepairLocalSigning?()
    }

    /// Paste a licence key. Verified before it is stored, so a bad paste cannot
    /// displace a licence that was already working.
    @objc private func enterLicense(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Enter your licence key"
        alert.informativeText = "Paste the key from your receipt email. "
            + "It is checked on this Mac; nothing is sent anywhere."
        alert.addButton(withTitle: "Activate")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "PRESSTALK-1.…"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        switch licenseStore.importLicense(field.stringValue) {
        case .success(let license):
            let confirmation = NSAlert()
            confirmation.messageText = "Licence activated"
            confirmation.informativeText = license.maxMajorVersion == PressTalkLicense.allMajorVersions
                ? "\(license.entitlement.capitalized). Every future Mac update included."
                : "\(license.entitlement.capitalized). Covers updates through \(license.maxMajorVersion).x."
            confirmation.runModal()
            reloadFromStore()
        case .failure(let error):
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "That licence key did not activate"
            // The user-facing message says what to do; the raw case does not.
            failure.informativeText = error.userFacingMessage
            failure.runModal()
        }
    }

    @objc private func exportDiagnostics(_ sender: Any?) {
        onExportDiagnostics?()
    }

    @objc private func openMicrophoneSettings(_ sender: Any?) {
        onOpenMicrophoneSettings?()
    }

    @objc private func openInputMonitoringSettings(_ sender: Any?) {
        onOpenInputMonitoringSettings?()
    }

    @objc private func revealApp(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    @objc private func openAccessibilitySettings(_ sender: Any?) {
        onOpenAccessibilitySettings?()
    }

    @objc private func disableSystemDictationHotkey(_ sender: Any?) {
        onDisableSystemDictationHotkey?()
    }

    @objc private func startNativeCalibration(_ sender: Any?) {
        onStartNativeCalibration?()
    }

    @objc private func clearNativeCalibration(_ sender: Any?) {
        onClearNativeCalibration?()
    }

    @objc private func enableF5Fallback(_ sender: Any?) {
        onEnableF5Fallback?()
    }

    @objc private func disableF5Fallback(_ sender: Any?) {
        onDisableF5Fallback?()
    }
}
