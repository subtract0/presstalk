import AppKit
import Foundation

struct VoiceLightBands {
    let low: Double
    let mid: Double
    let high: Double
}

struct PressTalkCommerceConfig {
    let upgradeURL: URL?
    let plansURL: URL?

    init(env: [String: String] = ProcessInfo.processInfo.environment) {
        upgradeURL = env["PRESSTALK_UPGRADE_URL"].flatMap(URL.init(string:))
        plansURL = env["PRESSTALK_PLANS_URL"].flatMap(URL.init(string:))
    }
}

struct PressTalkRuntimeStatus {
    let inputMonitoringGranted: Bool
    let microphoneGranted: Bool
    let accessibilityGranted: Bool
    let inputPipelineReady: Bool
    let inputListenerStatus: String
    let pasteAutomatically: Bool
    let systemDictationHotkeyDisabled: Bool
    let adHocSigned: Bool
    let permissionPaneOpeningAllowed: Bool
    let speechModelStatus: String
    let f5BridgeStatus: String

    var inputMonitoringEffective: Bool {
        inputMonitoringGranted || inputPipelineReady
    }

    static let placeholder = PressTalkRuntimeStatus(
        inputMonitoringGranted: false,
        microphoneGranted: false,
        accessibilityGranted: false,
        inputPipelineReady: false,
        inputListenerStatus: "Checking...",
        pasteAutomatically: true,
        systemDictationHotkeyDisabled: true,
        adHocSigned: false,
        permissionPaneOpeningAllowed: false,
        speechModelStatus: "Checking...",
        f5BridgeStatus: "Checking..."
    )
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

final class PressTalkLicenseStore {
    enum Tier: String {
        case freeBeta
        case pro
        case founding

        var displayName: String {
            switch self {
            case .freeBeta:
                return "Free Beta"
            case .pro:
                return "Pro"
            case .founding:
                return "Founding"
            }
        }

        var summary: String {
            switch self {
            case .freeBeta:
                return "Unlimited local dictation stays free. Paid plans are for power features, not basic speech-to-text."
            case .pro:
                return "Pro is intended for advanced vocabulary, formatting modes, app profiles, and workflow control."
            case .founding:
                return "Founding is the early-supporter tier with all Pro features through the early product cycle."
            }
        }
    }

    private enum Key {
        static let tier = "JarvisTap.PlanTier"
    }

    private let defaults: UserDefaults
    private let overrideTier: Tier?

    init(defaults: UserDefaults = .standard, env: [String: String] = ProcessInfo.processInfo.environment) {
        self.defaults = defaults
        self.overrideTier = env["PRESSTALK_PLAN_TIER"].flatMap(Tier.init(rawValue:))
        defaults.register(defaults: [
            Key.tier: Tier.freeBeta.rawValue,
        ])
    }

    var currentTier: Tier {
        if let overrideTier {
            return overrideTier
        }
        return Tier(rawValue: defaults.string(forKey: Key.tier) ?? "") ?? .freeBeta
    }

    var pricingSummary: String {
        "Planned pricing: Pro $8/mo or $59/yr. Founding $49 lifetime. Core local dictation remains free."
    }
}

private final class VoiceLightView: NSView {
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

    func setBands(_ bands: VoiceLightBands) {
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

        drawSoftGlow(
            in: context,
            center: center,
            radius: 214 + (overall * 92) + (lowAccent * 28),
            xScale: 1.04,
            yScale: 1.00,
            alpha: 0.18 + (overall * 0.20)
        )
        drawSoftGlow(
            in: context,
            center: center,
            radius: 128 + (midAccent * 48),
            xScale: 0.90,
            yScale: 1.18,
            alpha: 0.10 + (midAccent * 0.13)
        )
        drawSoftGlow(
            in: context,
            center: center,
            radius: 116 + (highAccent * 40),
            xScale: 1.26,
            yScale: 0.84,
            alpha: 0.09 + (highAccent * 0.12)
        )

        drawSoftGlow(
            in: context,
            center: center,
            radius: 88 + (midAccent * 26) + (highAccent * 22),
            xScale: 1.0,
            yScale: 1.0,
            alpha: 0.24 + (overall * 0.20)
        )
        drawGuideCore(
            in: context,
            center: center,
            radius: 17,
            alpha: 0.84 + (overall * 0.14)
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

final class JarvisTapSettingsStore {
    enum LanguageOption: String, CaseIterable {
        case auto
        case german
        case english

        var displayName: String {
            switch self {
            case .auto:
                return "Auto"
            case .german:
                return "German"
            case .english:
                return "English"
            }
        }

        var whisperLanguageCode: String? {
            switch self {
            case .auto:
                return nil
            case .german:
                return "de"
            case .english:
                return "en"
            }
        }

        static func fromWhisperLanguage(_ language: String?) -> LanguageOption {
            switch language?.lowercased() {
            case "de":
                return .german
            case "en":
                return .english
            default:
                return .auto
            }
        }
    }

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
        case fn = "fn"
        case option = "option"
        case leftOption = "left_option"
        case rightOption = "right_option"
        case f5 = "f5"
        case trackpadHold = "trackpad_hold"

        var displayName: String {
            switch self {
            case .fn:
                return "Fn / Globe"
            case .option:
                return "Either Option"
            case .leftOption:
                return "Left Option"
            case .rightOption:
                return "Right Option"
            case .f5:
                return "F5 / Mic"
            case .trackpadHold:
                return "Trackpad Hold"
            }
        }
    }

    private enum Key {
        static let showHUD = "JarvisTap.ShowHUD"
        static let pasteAutomatically = "JarvisTap.PasteAutomatically"
        static let showAbortPopups = "JarvisTap.ShowAbortPopups"
        static let preferredLanguage = "JarvisTap.PreferredLanguage"
        static let releaseTailMaxSeconds = "JarvisTap.ReleaseTailMaxSeconds"
        static let insertionSuffix = "JarvisTap.InsertionSuffix"
        static let triggerKey = "JarvisTap.TriggerKey"
        static let hasSeenSetupGuide = "JarvisTap.HasSeenSetupGuide"
        static let nativeTriggerCalibration = "JarvisTap.NativeTriggerCalibration"
    }

    private let defaults: UserDefaults

    init(config: JarvisTapConfig, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.showHUD: true,
            Key.pasteAutomatically: config.agentMode == "dictation",
            Key.showAbortPopups: true,
            Key.preferredLanguage: LanguageOption.fromWhisperLanguage(config.whisperLanguage).rawValue,
            Key.releaseTailMaxSeconds: config.releaseTailPaddingSeconds,
            Key.insertionSuffix: InsertionSuffixOption.space.rawValue,
            Key.triggerKey: config.triggerKey.rawValue,
            Key.hasSeenSetupGuide: false,
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

    var preferredLanguage: LanguageOption {
        get {
            LanguageOption(rawValue: defaults.string(forKey: Key.preferredLanguage) ?? "") ?? .auto
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.preferredLanguage)
        }
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
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(wrappingLabelWithString: "")
    private var hideWorkItem: DispatchWorkItem?
    private var mode: Mode = .none
    private var lightAnchorPoint: CGPoint?
    private var lightVerticalLift: CGFloat = 0
    private let listeningAnchorXRatio: CGFloat = 0.41

    init() {
        panel = NSPanel(
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

        titleField.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail

        detailField.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        detailField.textColor = .secondaryLabelColor
        detailField.maximumNumberOfLines = 2
        detailField.lineBreakMode = .byTruncatingTail

        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleField.translatesAutoresizingMaskIntoConstraints = false
        detailField.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleField, detailField])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        lightContainer.addSubview(voiceLightView)
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

        panel.setContentSize(NSSize(width: 460, height: 112))
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
        alpha: CGFloat = 1
    ) {
        hideWorkItem?.cancel()
        mode = .light
        cardContainer.isHidden = true
        lightContainer.isHidden = false
        panel.hasShadow = false
        panel.setContentSize(NSSize(width: 820, height: 470))
        setLightAnchor(anchorPoint, verticalLift: verticalLift)
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
        alpha: CGFloat? = nil
    ) {
        if mode != .light {
            showListeningLight(
                bands: bands,
                anchorPoint: anchorPoint,
                verticalLift: verticalLift ?? 0,
                alpha: alpha ?? 1
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
        panel.orderOut(nil)
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

final class PressTalkSettingsWindowController: NSWindowController {
    var onSettingsChanged: (() -> Void)?
    var onRunSetupCheck: (() -> Void)?
    var onExportDiagnostics: (() -> Void)?
    var onRestartApp: (() -> Void)?
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
    private var runtimeStatus: PressTalkRuntimeStatus = .placeholder
    private let showHUDCheckbox = NSButton(checkboxWithTitle: "Show compact HUD", target: nil, action: nil)
    private let pasteAutomaticallyCheckbox = NSButton(checkboxWithTitle: "Paste transcript automatically", target: nil, action: nil)
    private let triggerKeyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let insertionSuffixPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let releaseTailSlider = NSSlider(value: 0.35, minValue: 0.15, maxValue: 0.90, target: nil, action: nil)
    private let releaseTailValueLabel = NSTextField(labelWithString: "")
    private let currentPlanValueLabel = NSTextField(labelWithString: "")
    private let planSummaryLabel = NSTextField(wrappingLabelWithString: "")
    private let pricingSummaryLabel = NSTextField(wrappingLabelWithString: "")
    private let plansButton = NSButton(title: "View Plans", target: nil, action: nil)
    private let upgradeButton = NSButton(title: "Upgrade to Pro", target: nil, action: nil)
    private let setupHintLabel = NSTextField(wrappingLabelWithString: "")
    private let inputMonitoringValueLabel = NSTextField(labelWithString: "")
    private let microphoneValueLabel = NSTextField(labelWithString: "")
    private let accessibilityValueLabel = NSTextField(labelWithString: "")
    private let systemDictationValueLabel = NSTextField(labelWithString: "")
    private let speechModelValueLabel = NSTextField(labelWithString: "")
    private let f5BridgeValueLabel = NSTextField(labelWithString: "")
    private let runSetupCheckButton = NSButton(title: "Run Setup Check", target: nil, action: nil)
    private let restartAppButton = NSButton(title: "Restart PressTalk", target: nil, action: nil)
    private let exportDiagnosticsButton = NSButton(title: "Export Diagnostics", target: nil, action: nil)
    private let microphoneSettingsButton = NSButton(title: "Microphone", target: nil, action: nil)
    private let inputMonitoringSettingsButton = NSButton(title: "Input Monitoring", target: nil, action: nil)
    private let accessibilitySettingsButton = NSButton(title: "Accessibility", target: nil, action: nil)
    private let disableSystemDictationButton = NSButton(title: "Disable Apple Dictation Key", target: nil, action: nil)
    private let calibrateNativeF5Button = NSButton(title: "Calibrate Native F5", target: nil, action: nil)
    private let clearNativeCalibrationButton = NSButton(title: "Clear Native Calibration", target: nil, action: nil)
    private let enableF5FallbackButton = NSButton(title: "Enable F5 Fallback", target: nil, action: nil)
    private let disableF5FallbackButton = NSButton(title: "Disable F5 Fallback", target: nil, action: nil)

    init(
        settingsStore: JarvisTapSettingsStore,
        licenseStore: PressTalkLicenseStore,
        commerceConfig: PressTalkCommerceConfig = PressTalkCommerceConfig()
    ) {
        self.settingsStore = settingsStore
        self.licenseStore = licenseStore
        self.commerceConfig = commerceConfig

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PressTalk Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        reloadFromStore()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
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
        languagePopup.selectItem(at: JarvisTapSettingsStore.LanguageOption.allCases.firstIndex(of: settingsStore.preferredLanguage) ?? 0)
        insertionSuffixPopup.selectItem(at: JarvisTapSettingsStore.InsertionSuffixOption.allCases.firstIndex(of: settingsStore.insertionSuffix) ?? 0)
        releaseTailSlider.doubleValue = settingsStore.releaseTailMaxSeconds
        currentPlanValueLabel.stringValue = licenseStore.currentTier.displayName
        planSummaryLabel.stringValue = licenseStore.currentTier.summary
        pricingSummaryLabel.stringValue = licenseStore.pricingSummary
        plansButton.isHidden = commerceConfig.plansURL == nil
        upgradeButton.isHidden = commerceConfig.upgradeURL == nil
        refreshReleaseTailLabel()
        applyRuntimeStatus()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "Hold a key. Speak. Release.")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)

        let subtitleLabel = NSTextField(wrappingLabelWithString: "PressTalk stays local. Hold Fn, Option, F5, or the trackpad to bring up the light, speak, then release to paste cleaned dictation into the focused app. These settings apply immediately.")
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor

        let setupLabel = NSTextField(labelWithString: "Setup & Diagnostics")
        setupLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        setupHintLabel.font = NSFont.systemFont(ofSize: 12)
        setupHintLabel.textColor = .secondaryLabelColor

        let planLabel = NSTextField(labelWithString: "Current plan")
        planLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        currentPlanValueLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        currentPlanValueLabel.textColor = .labelColor

        planSummaryLabel.font = NSFont.systemFont(ofSize: 12)
        planSummaryLabel.textColor = .secondaryLabelColor

        pricingSummaryLabel.font = NSFont.systemFont(ofSize: 12)
        pricingSummaryLabel.textColor = .secondaryLabelColor

        let languageLabel = NSTextField(labelWithString: "Language")
        languageLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let triggerKeyLabel = NSTextField(labelWithString: "Trigger")
        triggerKeyLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        triggerKeyPopup.addItems(withTitles: JarvisTapSettingsStore.TriggerKeyOption.allCases.map(\.displayName))

        languagePopup.addItems(withTitles: JarvisTapSettingsStore.LanguageOption.allCases.map(\.displayName))

        let insertionSuffixLabel = NSTextField(labelWithString: "After insertion")
        insertionSuffixLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        insertionSuffixPopup.addItems(withTitles: JarvisTapSettingsStore.InsertionSuffixOption.allCases.map(\.displayName))

        let tailLabel = NSTextField(labelWithString: "Release tail")
        tailLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let tailHintLabel = NSTextField(labelWithString: "Keeps listening briefly after key-up so the last syllables are not clipped.")
        tailHintLabel.font = NSFont.systemFont(ofSize: 12)
        tailHintLabel.textColor = .secondaryLabelColor

        let footerLabel = NSTextField(labelWithString: "Install with Homebrew: brew install --cask presstalk")
        footerLabel.font = NSFont.systemFont(ofSize: 12)
        footerLabel.textColor = .secondaryLabelColor

        let plansRow = NSStackView(views: [planLabel, currentPlanValueLabel])
        plansRow.orientation = .horizontal
        plansRow.alignment = .centerY
        plansRow.distribution = .equalSpacing

        plansButton.bezelStyle = .rounded
        upgradeButton.bezelStyle = .rounded

        let commerceButtonsRow = NSStackView(views: [plansButton, upgradeButton])
        commerceButtonsRow.orientation = .horizontal
        commerceButtonsRow.alignment = .centerY
        commerceButtonsRow.spacing = 8

        for button in [
            runSetupCheckButton,
            restartAppButton,
            exportDiagnosticsButton,
            microphoneSettingsButton,
            inputMonitoringSettingsButton,
            accessibilitySettingsButton,
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

        let diagnosticsButtonsRow = NSStackView(views: [runSetupCheckButton, restartAppButton, exportDiagnosticsButton])
        diagnosticsButtonsRow.orientation = .horizontal
        diagnosticsButtonsRow.alignment = .centerY
        diagnosticsButtonsRow.spacing = 8

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

        let inputMonitoringRow = makeStatusRow(title: "Input Monitoring", valueLabel: inputMonitoringValueLabel)
        let microphoneRow = makeStatusRow(title: "Microphone", valueLabel: microphoneValueLabel)
        let accessibilityRow = makeStatusRow(title: "Accessibility", valueLabel: accessibilityValueLabel)
        let systemDictationRow = makeStatusRow(title: "Apple Dictation key", valueLabel: systemDictationValueLabel)
        let speechModelRow = makeStatusRow(title: "Speech model", valueLabel: speechModelValueLabel)
        let f5BridgeRow = makeStatusRow(title: "Trigger path", valueLabel: f5BridgeValueLabel)

        let languageRow = NSStackView(views: [languageLabel, languagePopup])
        languageRow.orientation = .horizontal
        languageRow.alignment = .centerY
        languageRow.distribution = .fillProportionally
        languageRow.spacing = 12

        let triggerKeyRow = NSStackView(views: [triggerKeyLabel, triggerKeyPopup])
        triggerKeyRow.orientation = .horizontal
        triggerKeyRow.alignment = .centerY
        triggerKeyRow.distribution = .fillProportionally
        triggerKeyRow.spacing = 12

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
            dictationButtonsRow,
            nativeButtonsRow,
            fallbackButtonsRow,
            plansRow,
            planSummaryLabel,
            pricingSummaryLabel,
            commerceButtonsRow,
            showHUDCheckbox,
            pasteAutomaticallyCheckbox,
            triggerKeyRow,
            languageRow,
            insertionSuffixRow,
            tailHeaderRow,
            releaseTailSlider,
            tailHintLabel,
            footerLabel,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
        ])

        showHUDCheckbox.target = self
        showHUDCheckbox.action = #selector(toggleShowHUD(_:))

        pasteAutomaticallyCheckbox.target = self
        pasteAutomaticallyCheckbox.action = #selector(togglePasteAutomatically(_:))

        triggerKeyPopup.target = self
        triggerKeyPopup.action = #selector(changeTriggerKey(_:))

        languagePopup.target = self
        languagePopup.action = #selector(changeLanguage(_:))

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

        restartAppButton.target = self
        restartAppButton.action = #selector(restartApp(_:))

        exportDiagnosticsButton.target = self
        exportDiagnosticsButton.action = #selector(exportDiagnostics(_:))

        microphoneSettingsButton.target = self
        microphoneSettingsButton.action = #selector(openMicrophoneSettings(_:))

        inputMonitoringSettingsButton.target = self
        inputMonitoringSettingsButton.action = #selector(openInputMonitoringSettings(_:))

        accessibilitySettingsButton.target = self
        accessibilitySettingsButton.action = #selector(openAccessibilitySettings(_:))

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
        valueLabel.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [titleLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .equalSpacing
        return row
    }

    private func applyRuntimeStatus() {
        configureInputMonitoringLabel(inputMonitoringValueLabel)
        configureMicrophoneLabel(microphoneValueLabel)
        configureAccessibilityLabel(accessibilityValueLabel)
        configureInterferenceLabel(systemDictationValueLabel, disabled: runtimeStatus.systemDictationHotkeyDisabled)
        configureDetailLabel(speechModelValueLabel, text: runtimeStatus.speechModelStatus)
        configureDetailLabel(f5BridgeValueLabel, text: runtimeStatus.f5BridgeStatus)
        configurePermissionPaneButtons()
        setupHintLabel.stringValue = permissionHintText()
    }

    private func configurePermissionPaneButtons() {
        let enabled = runtimeStatus.permissionPaneOpeningAllowed
        let tooltip = enabled ? nil : "System Settings opening is disabled for this run. Export diagnostics instead of re-granting repeatedly."
        for button in [microphoneSettingsButton, inputMonitoringSettingsButton, accessibilitySettingsButton] {
            button.isEnabled = enabled
            button.isHidden = !enabled
            button.toolTip = tooltip
        }
    }

    private func configureInputMonitoringLabel(_ label: NSTextField) {
        if runtimeStatus.inputMonitoringGranted {
            label.stringValue = "Granted"
            label.textColor = .systemGreen
        } else if runtimeStatus.inputPipelineReady {
            label.stringValue = "Listener ready"
            label.textColor = .systemGreen
        } else {
            label.stringValue = "Preflight unavailable"
            label.textColor = .systemOrange
        }
    }

    private func configureAccessibilityLabel(_ label: NSTextField) {
        if runtimeStatus.accessibilityGranted {
            label.stringValue = "Granted"
            label.textColor = .systemGreen
        } else if runtimeStatus.pasteAutomatically {
            label.stringValue = "Copy fallback"
            label.textColor = .systemOrange
        } else {
            label.stringValue = "Copy-only mode"
            label.textColor = .secondaryLabelColor
        }
    }

    private func configureMicrophoneLabel(_ label: NSTextField) {
        if runtimeStatus.microphoneGranted {
            label.stringValue = "Granted"
            label.textColor = .systemGreen
        } else {
            label.stringValue = "Preflight unavailable"
            label.textColor = .systemOrange
        }
    }

    private func permissionHintText() -> String {
        if !runtimeStatus.microphoneGranted {
            if runtimeStatus.adHocSigned {
                return "Microphone preflight is unavailable to this ad-hoc build. If macOS already shows PressTalk enabled, export diagnostics instead of re-granting repeatedly."
            }
            return "Microphone preflight is unavailable to this PressTalk build. If macOS already shows PressTalk enabled, export diagnostics instead of re-granting repeatedly."
        }

        if !runtimeStatus.inputMonitoringEffective {
            return "Input listener is not ready. If macOS already shows PressTalk enabled, export diagnostics instead of re-granting repeatedly."
        }

        if !runtimeStatus.accessibilityGranted && runtimeStatus.pasteAutomatically {
            return "Input listener is ready. Auto-paste is not trusted by this build, so dictation will be copied instead."
        }

        if !runtimeStatus.accessibilityGranted {
            return "Input listener is ready. Copy-only mode does not need Accessibility until auto-paste is enabled."
        }

        return "PressTalk is ready for the current build."
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
        let index = max(0, sender.indexOfSelectedItem)
        settingsStore.triggerKey = JarvisTapSettingsStore.TriggerKeyOption.allCases[index]
        onSettingsChanged?()
    }

    @objc private func changeLanguage(_ sender: NSPopUpButton) {
        let index = max(0, sender.indexOfSelectedItem)
        settingsStore.preferredLanguage = JarvisTapSettingsStore.LanguageOption.allCases[index]
        onSettingsChanged?()
    }

    @objc private func changeInsertionSuffix(_ sender: NSPopUpButton) {
        let index = max(0, sender.indexOfSelectedItem)
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

    @objc private func restartApp(_ sender: Any?) {
        onRestartApp?()
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
