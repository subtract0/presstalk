import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox
import CoreAudio
import CoreML
import Darwin
import FluidAudio
import Foundation
import IOKit.hidsystem
import PressTalkCore
import WhisperKit

private let fnModifierMask = CGEventFlags(rawValue: UInt64(NX_SECONDARYFNMASK))
private let leftOptionModifierMask = CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))
private let rightOptionModifierMask = CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK))

final class JarvisTapApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct StreamingSnapshot {
        var currentText = ""
        var confirmedText = ""
        var unconfirmedText = ""
        var updatedAt: Date?
        var audioDurationSeconds = 0.0
        var revision = 0
    }

    private enum WhisperLoadState {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private enum Trigger: String {
        case trackpadHold = "trackpad_hold"
        case configuredKey = "configured_key"
        case f5 = "f5"
    }

    private enum TriggerPhase: String {
        case press
        case release
    }

    private enum TriggerSource: String {
        case trackpadHold = "trackpad_hold"
        case registeredHotKey = "registered_hotkey"
        case modifierKey = "modifier_key"
        case darwinNotification = "darwin_notification"
        case nativeSystemDefined = "native_system_defined"
        case cgFunctionKey = "cg_function_key"

        var bridgeLabel: String {
            switch self {
            case .trackpadHold:
                return "Trackpad hold"
            case .registeredHotKey:
                return "Registered hotkey"
            case .modifierKey:
                return "Modifier key"
            case .darwinNotification:
                return "Karabiner fallback"
            case .nativeSystemDefined:
                return "Native microphone key"
            case .cgFunctionKey:
                return "Function-key path"
            }
        }
    }

    private struct NativeCalibrationSession {
        var pressCounts: [PressTalkNativeTriggerSignature: Int] = [:]
        var releaseCounts: [PressTalkNativeTriggerSignature: Int] = [:]

        mutating func record(_ signature: PressTalkNativeTriggerSignature) {
            if signature.data2 == 1 {
                pressCounts[signature, default: 0] += 1
            } else if signature.data2 == 0 {
                releaseCounts[signature, default: 0] += 1
            }
        }

        var strongestPress: (signature: PressTalkNativeTriggerSignature, count: Int)? {
            pressCounts.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
        }

        var strongestRelease: (signature: PressTalkNativeTriggerSignature, count: Int)? {
            releaseCounts.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
        }

        var isComplete: Bool {
            (strongestPress?.count ?? 0) >= 3 && (strongestRelease?.count ?? 0) >= 3
        }
    }

    private struct TriggerBridgeTelemetry {
        var trackpadHoldSeen = false
        var registeredHotKeySeen = false
        var modifierKeySeen = false
        var nativeSystemDefinedSeen = false
        var darwinNotificationSeen = false
        var cgFunctionKeySeen = false
        var lastSource: TriggerSource?
        var lastEventAt: Date?
        var lastPhase: TriggerPhase?
    }

    private struct TrackpadHoldState {
        let downLocation: CGPoint
        let downAt: Date
        var currentLocation: CGPoint
        var maxDistance: CGFloat
        var latestPressure: Double
        var armed = false
    }

    private enum PresentationState {
        case warming
        case ready
        case listening(String?)
        case processing
        case inserted(String)
        case copied(String)
        case aborted(String)
        case audioUnavailable(String)
        case error(String)
        case setupRequired(String)
        case diagnosticStarted(String)
    }

    private struct PermissionCheckResult {
        let inputMonitoringGranted: Bool
        let microphoneGranted: Bool
        let microphoneAuthorizationStatus: String
        let accessibilityGranted: Bool
    }

    private enum DarwinTriggerNotification {
        static let press = "com.am.jarvistap.trigger.press"
        static let release = "com.am.jarvistap.trigger.release"
    }

    private enum ProductionInsertionProbeNotification {
        static let insert = "com.am.presstalk.production-insertion-probe.insert"
        static let payloadFileName = "production-insertion-probe.txt"
        static let markerFileName = "production-insertion-probe.enabled"
        static let markerMaxAgeSeconds: TimeInterval = 60
    }

    private enum InputMethodInsertionContext {
        case dictation
        case productionProbe
    }

    private struct InputMethodInsertionAcknowledgement {
        let inserted: Bool
        let reason: String?
    }

    private struct InputMethodInsertionFailure {
        let reason: String
        let occurredAt: Date

        var runtimeStatus: String {
            switch reason {
            case "input_method_ack_timeout":
                return "ack_timeout"
            default:
                return "client_unavailable"
            }
        }
    }

    private struct InputMethodPreselectionSession {
        let originalSource: TISInputSource
        let enabledSource: TISInputSource
        let candidateSource: TISInputSource
        let enabledBeforeKeys: Set<String>
        let startedAt: Date
    }

    private let config = JarvisTapConfig.load()
    private lazy var settingsStore = JarvisTapSettingsStore(config: config)
    private lazy var licenseStore = PressTalkLicenseStore()
    private lazy var traceLogger = TraceLogger(path: config.traceLogPath)
    private lazy var transcriptTextPolicy = TranscriptTextPolicy(
        shortHoldNoSpeechSuppressionSeconds: shortHoldNoSpeechSuppressionSeconds
    )
    private lazy var transcriptRecallPolicy = TranscriptRecallPolicy(
        chunkedWhisperFallbackMinimumCaptureSeconds: chunkedWhisperFallbackMinimumCaptureSeconds,
        textPolicy: transcriptTextPolicy
    )
    private lazy var appCodeSignatureSummary = codeSignatureSummary()
    private lazy var memoryStore = ConversationMemoryStore(path: config.memoryStorePath, traceLogger: traceLogger)
    private lazy var responder = RemoteResponder(config: config, traceLogger: traceLogger)
    private lazy var codexAgent = CodexAgent(config: config, traceLogger: traceLogger, memoryStore: memoryStore)
    private let speaker = NativeSpeaker()

    private let f5KeyCode = CGKeyCode(kVK_F5)
    private let optionSpaceHotKeyCode = UInt32(kVK_Space)
    private let optionSpaceHotKeyID = UInt32(1)
    private let registeredHotKeySignature = OSType(0x50544B59)
    private let remappedMicrophoneKeyCode = CGKeyCode(kVK_F20)
    private let systemDefinedEventType = CGEventType(rawValue: UInt32(NX_SYSDEFINED))!
    private let mediaKeySubtype = Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS)
    private let microphoneKeySubtype = Int16(7)
    private let systemDictationHotkeyIdentifier = "162"
    private let mediaKeyStateMask = 0xFF00
    private let mediaKeyDownState = 0x0A00
    private let mediaKeyUpState = 0x0B00
    private let mediaKeyRepeatMask = 0x1
    private let streamShutdownTimeoutSeconds: TimeInterval = 2.0
    private let realtimeStreamInitialAudioSeconds: TimeInterval = 1.0
    private let realtimeStreamMinNewAudioSeconds: TimeInterval = 0.75
    private let realtimeStreamPollSeconds: TimeInterval = 0.15
    private let realtimeStreamFreshnessSeconds: TimeInterval = 2.0
    private let realtimeStreamFinalMaxLagSeconds: TimeInterval = 0.65
    private let chunkedWhisperFallbackChunkSeconds: TimeInterval = 5.5
    private let chunkedWhisperFallbackMinimumCaptureSeconds: TimeInterval = 7.5
    private let trackpadHoldDelaySeconds: TimeInterval = 0.50
    private let trackpadHoldCancelDistancePoints: CGFloat = 15.0
    private let shortHoldNoSpeechSuppressionSeconds: TimeInterval = 1.50
    private let trackpadPreviewTickSeconds: TimeInterval = 1.0 / 30.0
    private let nativePointerCancellationWindowSeconds: TimeInterval = 0.20
    private let retiredAudioEngineRetainSeconds: TimeInterval = 3.0
    private let retiredAudioEngineLimit = 8
    private let setupRetryIntervalSeconds: TimeInterval = 5.0
    private let inputMethodFailureCooldownSeconds: TimeInterval = 10 * 60
    private let inputMethodDictationEnvKey = "PRESSTALK_ENABLE_EXPERIMENTAL_INPUT_METHOD_DICTATION"
    private let stateLock = NSLock()
    private let audioCaptureLock = NSLock()
    private let audioEngineStopLock = NSLock()

    private var eventTap: CFMachPort?
    private var eventTapInstallSummary = "not_installed"
    private var runLoopSource: CFRunLoopSource?
    private var registeredHotKeyRef: EventHotKeyRef?
    private var registeredHotKeyEventHandler: EventHandlerRef?
    private var specialKeyMonitor: Any?
    /// Microphone capture. PressTalk records through WhisperKit's
    /// `AudioProcessor` no matter which recognizer transcribes, so this instance
    /// is built with `load: false, download: false`: it costs 2 ms and zero
    /// bytes on disk, and it is what makes a 461 MB first run possible instead
    /// of 1.1 GB.
    private var audioCaptureKit: WhisperKit?

    /// The full WhisperKit model, ~619 MB on disk. Needed only when WhisperKit
    /// is the final recognizer, or when the Parakeet quality fallback actually
    /// fires. Nil is a normal state, not a failure.
    private var whisperKit: WhisperKit?
    private var parakeetAsrManager: AsrManager?
    private var parakeetDecoderLayerCount = 2
    private var fluidStreamingAsrManager: (any StreamingAsrManager)?
    private var fluidStreamingFedSampleCount = 0
    private var streamTranscriber: AudioStreamTranscriber?
    private var retiredAudioEngines: [(id: ObjectIdentifier, engine: AVAudioEngine, retiredAt: Date)] = []
    private var decodingOptions = DecodingOptions(
        verbose: false,
        task: .transcribe,
        language: nil,
        temperature: 0,
        usePrefillPrompt: true,
        usePrefillCache: true,
        detectLanguage: true,
        skipSpecialTokens: true,
        withoutTimestamps: true,
        wordTimestamps: false
    )

    private var isRecording = false
    private var isProcessing = false
    private var activeTrigger: Trigger?
    private var activeTriggerSource: TriggerSource?
    private var activeTriggerStartedAt: Date?
    private var latestStreamingState = StreamingSnapshot()
    private var streamTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var lastPrintedPartial = ""
    private var liveCapturedAudioSamples: [Float] = []
    private var activeCaptureSessionID: UInt64 = 0
    private var activeCaptureEngineStarted = false
    private var lastInputDebugSignature = ""
    private var darwinNotificationObserverInstalled = false
    private var productionInsertionProbeObserverInstalled = false
    private var whisperLoadState: WhisperLoadState = .idle
    private let dictationRecoveryPolicy = DictationRecoveryPolicy()
    /// In memory only, bounded and expiring. Never written to disk: someone who
    /// bought this because it is local should not find a transcript log in
    /// Application Support.
    private var recoverableDictations: [DictationRecoveryPolicy.Entry] = []
    private var recentDictationsMenu: NSMenu?
    private var firstRunSetupWindowController: FirstRunSetupWindowController?
    private var whisperWarmupTask: Task<Void, Never>?
    private var amplitudeMonitorTask: Task<Void, Never>?
    private var trackpadPreviewTask: Task<Void, Never>?
    private var presentationState: PresentationState = .warming
    private var inputPipelineReady = false
    private var triggerBridgeTelemetry = TriggerBridgeTelemetry()
    private var karabinerFallbackEnabled = false
    private var nativeCalibrationSession: NativeCalibrationSession?
    private var nativeCalibrationTimeoutWorkItem: DispatchWorkItem?
    private var nativeAutoCalibrationObservations = NativeCalibrationSession()
    private var lastPointerEventAt: Date?
    private var firstPointerEventLogged = false
    private var trackpadHoldState: TrackpadHoldState?
    private var trackpadArmWorkItem: DispatchWorkItem?
    /// Set by an actual capture probe, never by the authorization status.
    private var microphoneCaptureVerified = false
    private var microphonePermissionRequestInFlight = false
    private var microphonePermissionRequestAttempted = false
    private var lastInputMethodInsertionFailure: InputMethodInsertionFailure?
    private var activeInputMethodPreselection: InputMethodPreselectionSession?
    private var inputMethodHelperWarmupScheduled = false
    private var activeAudioInputDeviceDescription = "unknown"

    private var statusItem: NSStatusItem?
    private var statusSummaryMenuItem: NSMenuItem?
    private var statusDetailMenuItem: NSMenuItem?
    private var toggleHUDMenuItem: NSMenuItem?
    private var togglePasteMenuItem: NSMenuItem?
    private var toggleAbortPopupsMenuItem: NSMenuItem?
    private var repairLocalSigningMenuItem: NSMenuItem?
    private var settingsWindowController: PressTalkSettingsWindowController?
    private var hudController: PressTalkHUDController?
    private var manualSmokeProcess: Process?
    private var readyResetWorkItem: DispatchWorkItem?
    private var setupRetryTimer: Timer?
    private var singletonLockFileDescriptor: Int32 = -1

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    private func resetLiveCapturedAudioSamples() {
        audioCaptureLock.lock()
        liveCapturedAudioSamples.removeAll(keepingCapacity: true)
        audioCaptureLock.unlock()
    }

    private func appendLiveCapturedAudioSamples(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        audioCaptureLock.lock()
        liveCapturedAudioSamples.append(contentsOf: samples)
        audioCaptureLock.unlock()
    }

    private func appendLiveCapturedAudioSamples(_ samples: [Float], sessionID: UInt64) {
        guard withStateLock({
            activeCaptureSessionID == sessionID && (isRecording || isProcessing)
        }) else { return }
        appendLiveCapturedAudioSamples(samples)
    }

    private func liveCapturedAudioSampleCount() -> Int {
        audioCaptureLock.lock()
        defer { audioCaptureLock.unlock() }
        return liveCapturedAudioSamples.count
    }

    private func currentLiveCapturedAudioSamples() -> [Float] {
        audioCaptureLock.lock()
        let samples = liveCapturedAudioSamples
        audioCaptureLock.unlock()
        return samples
    }

    private func recentLiveCapturedAudioSamples(maxCount: Int) -> [Float] {
        guard maxCount > 0 else { return [] }
        audioCaptureLock.lock()
        let samples: [Float]
        if liveCapturedAudioSamples.count > maxCount {
            samples = Array(liveCapturedAudioSamples.suffix(maxCount))
        } else {
            samples = liveCapturedAudioSamples
        }
        audioCaptureLock.unlock()
        return samples
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let exitCode = runStartup()
        if exitCode != 0 {
            NSApp.terminate(nil)
            exit(exitCode)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopSetupRetry()
        restoreInputMethodPreselectionIfNeeded(reason: "application_terminating")
        if singletonLockFileDescriptor >= 0 {
            flock(singletonLockFileDescriptor, LOCK_UN)
            close(singletonLockFileDescriptor)
            singletonLockFileDescriptor = -1
        }
    }

    func runStartup() -> Int32 {
        if ProcessInfo.processInfo.environment["PRESSTALK_ACCESSIBILITY_TRUST_PROBE"] == "1" {
            printAccessibilityTrustProbe()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return 0
        }

        // Before anything writes a first-run default. Deciding this later cannot
        // work: by then a new install carries the same flags an old one does,
        // which grandfathered every user and made the trial unreachable.
        licenseStore.recordInstallGenerationIfNeeded()

        traceLogger.log("Startup initiated trace_log=\(config.traceLogPath)")
        guard acquireSingletonLock() else {
            traceLogger.log("Duplicate PressTalk instance detected; exiting secondary process")
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return 0
        }
        traceLogger.log("Bundle path=\(Bundle.main.bundleURL.path)")
        traceLogger.log("Executable path=\(Bundle.main.executableURL?.path ?? "unknown")")
        traceLogger.log("Agent mode=\(config.agentMode)")
        traceLogger.log(
            "Release tail max seconds=\(String(format: "%.2f", settingsStore.releaseTailMaxSeconds))"
        )
        traceLogger.log("ASR backend=\(config.asrBackend)")
        traceLogger.log("Streaming ASR backend=\(config.streamingASRBackend ?? "none")")
        traceLogger.log("Streaming transcription enabled=\(config.streamingTranscriptionEnabled ? 1 : 0)")
        traceLogger.log(
            "Parakeet quality fallback enabled=\(config.parakeetQualityFallbackEnabled ? 1 : 0) min_confidence=\(String(format: "%.3f", config.parakeetQualityFallbackMinConfidence))"
        )
        traceLogger.log("HUD enabled=\(settingsStore.showHUD ? 1 : 0) paste_automatically=\(settingsStore.pasteAutomatically ? 1 : 0) trigger_key=\(settingsStore.triggerKey.rawValue) insertion_suffix=\(settingsStore.insertionSuffix.rawValue)")
        traceLogger.log("Native microphone key path enabled=\(config.enableNativeMicrophoneKey ? 1 : 0)")
        traceLogger.log("Native microphone calibration stored=\(settingsStore.nativeTriggerCalibration == nil ? 0 : 1)")

        speaker.configure(voiceIdentifier: config.sayVoice)
        installProductUI()
        installProductionInsertionProbeNotification()
        applyWhisperDecodingPreferences()
        refreshRuntimeStatusUI()

        let shouldPresentSetupGuide = config.autoShowSetupWindow && !settingsStore.hasSeenSetupGuide
        if shouldPresentSetupGuide {
            settingsStore.hasSeenSetupGuide = true
        }

        // Guided setup runs until text has actually been delivered once, not
        // just until the permissions look right.
        if config.autoShowSetupWindow && !settingsStore.firstRunSetupCompleted {
            DispatchQueue.main.async { [weak self] in
                self?.presentFirstRunSetup()
            }
        }

        completeStartupIfPossible(
            showSetupWindowOnFailure: shouldPresentSetupGuide,
            forcePresentSetupWindow: shouldPresentSetupGuide
        )
        return 0
    }

    private func completeStartupIfPossible(
        showSetupWindowOnFailure: Bool,
        forcePresentSetupWindow: Bool = false,
        presentFailureStatus: Bool = true
    ) {
        refreshRuntimeStatusUI()
        let permissions = checkSetupPermissions()

        if presentFailureStatus {
            print("Checking Input Monitoring permission...")
            fflush(stdout)
        }
        if permissions.inputMonitoringGranted {
            traceLogger.log("Input Monitoring permission OK")
        } else {
            traceLogger.log("Input Monitoring preflight unavailable; attempting listener capability probe")
            if presentFailureStatus {
                print("Input Monitoring preflight unavailable; trying the key listener anyway.")
                fflush(stdout)
            }
        }

        if presentFailureStatus {
            print("Checking microphone permission...")
            fflush(stdout)
        }
        guard permissions.microphoneGranted else {
            if permissions.microphoneAuthorizationStatus == "not_determined" {
                requestMicrophonePermissionAndRetry(
                    showSetupWindowOnFailure: showSetupWindowOnFailure,
                    forcePresentSetupWindow: forcePresentSetupWindow,
                    presentFailureStatus: presentFailureStatus
                )
                return
            }
            if presentFailureStatus {
                traceLogger.log("Startup blocked: microphone unavailable to current build status=\(permissions.microphoneAuthorizationStatus)")
                printMicrophoneHelp()
                present(.setupRequired("Microphone preflight is \(permissions.microphoneAuthorizationStatus). Export diagnostics before changing settings."))
            }
            refreshRuntimeStatusUI()
            scheduleSetupRetry()
            if shouldPresentSetupWindow(showSetupWindowOnFailure: showSetupWindowOnFailure, forcePresentSetupWindow: forcePresentSetupWindow) {
                DispatchQueue.main.async { [weak self] in
                    self?.settingsWindowController?.present()
                }
            }
            return
        }
        traceLogger.log("Microphone permission OK")
        if presentFailureStatus {
            print("Microphone permission OK.")
            fflush(stdout)
        }

        if presentFailureStatus {
            print("Checking Accessibility permission...")
            fflush(stdout)
        }
        if permissions.accessibilityGranted {
            traceLogger.log("Accessibility permission OK")
        } else {
            traceLogger.log("Accessibility preflight unavailable; paste will use capability probe")
            if presentFailureStatus {
                print("Accessibility preflight unavailable; continuing and testing paste when needed.")
                fflush(stdout)
            }
        }

        if !inputPipelineReady {
            installDarwinTriggerNotifications()

            guard installInputTriggerListener() else {
                if presentFailureStatus {
                    traceLogger.log("Startup blocked: input trigger listener install failed")
                    printTapFailureHelp()
                    present(.setupRequired("PressTalk could not attach the input trigger listener."))
                }
                refreshRuntimeStatusUI()
                scheduleSetupRetry()
                if shouldPresentSetupWindow(showSetupWindowOnFailure: showSetupWindowOnFailure, forcePresentSetupWindow: forcePresentSetupWindow) {
                    DispatchQueue.main.async { [weak self] in
                        self?.settingsWindowController?.present()
                    }
                }
                return
            }

            installSystemDefinedMonitor()
            inputPipelineReady = true
            stopSetupRetry()
            traceLogger.log("Input trigger listeners installed")
            print("Input trigger listeners installed.")
            fflush(stdout)
            traceLogger.log("PressTalk armed")
            print("PressTalk armed. Hold \(settingsStore.triggerKey.displayName) to speak, then release to finalize.")
            print("ASR warmup: background")
            print("ASR model: \(config.whisperModel)")
            print("ASR language: \(config.whisperLanguage ?? "auto")")
            print("Agent mode: \(config.agentMode)")
            fflush(stdout)
            scheduleInputMethodHelperWarmupIfNeeded()
        }

        refreshRuntimeStatusUI()

        if shouldPresentSetupWindow(showSetupWindowOnFailure: false, forcePresentSetupWindow: forcePresentSetupWindow) {
            DispatchQueue.main.async { [weak self] in
                self?.settingsWindowController?.present()
            }
        }

        let currentPresentation = withStateLock { presentationState }
        if case .listening = currentPresentation {
            return
        }
        if case .processing = currentPresentation {
            return
        }

        present(.warming)
        startWhisperWarmupIfNeeded()
    }

    private func shouldPresentSetupWindow(showSetupWindowOnFailure: Bool, forcePresentSetupWindow: Bool) -> Bool {
        config.allowPermissionPaneOpen &&
            config.autoShowSetupWindow &&
            (showSetupWindowOnFailure || forcePresentSetupWindow)
    }

    private func scheduleSetupRetry() {
        guard setupRetryTimer == nil else { return }
        traceLogger.log("Setup retry timer started interval_seconds=\(String(format: "%.1f", setupRetryIntervalSeconds))")
        let timer = Timer(timeInterval: setupRetryIntervalSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.inputPipelineReady {
                self.stopSetupRetry()
                return
            }
            self.completeStartupIfPossible(
                showSetupWindowOnFailure: false,
                forcePresentSetupWindow: false,
                presentFailureStatus: false
            )
        }
        setupRetryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        refreshRuntimeStatusUI()
    }

    private func stopSetupRetry() {
        guard let setupRetryTimer else { return }
        setupRetryTimer.invalidate()
        self.setupRetryTimer = nil
        traceLogger.log("Setup retry timer stopped")
        refreshRuntimeStatusUI()
    }

    private func acquireSingletonLock() -> Bool {
        let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JarvisTap", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        } catch {
            traceLogger.log("Failed to create support directory for singleton lock: \(error)")
            return true
        }

        let lockPath = supportDirectory.appendingPathComponent("presstalk.lock").path
        let fileDescriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            traceLogger.log("Failed to open singleton lock path=\(lockPath)")
            return true
        }

        if flock(fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            close(fileDescriptor)
            return false
        }

        ftruncate(fileDescriptor, 0)
        let pidLine = "\(getpid())\n"
        _ = pidLine.withCString { pointer in
            write(fileDescriptor, pointer, strlen(pointer))
        }
        singletonLockFileDescriptor = fileDescriptor
        return true
    }

    private func applyWhisperDecodingPreferences() {
        if let whisperLanguage = settingsStore.preferredLanguage.whisperLanguageCode {
            decodingOptions.language = whisperLanguage
            decodingOptions.detectLanguage = false
        } else {
            decodingOptions.language = nil
            decodingOptions.detectLanguage = true
        }
    }

    private var appDisplayTitle: String {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        guard let version else {
            return "PressTalk"
        }
        return "PressTalk \(version)"
    }

    private func installProductUI() {
        guard statusItem == nil else { return }

        let settingsWindowController = PressTalkSettingsWindowController(settingsStore: settingsStore, licenseStore: licenseStore)
        settingsWindowController.onSettingsChanged = { [weak self] in
            self?.handleSettingsChanged()
        }
        settingsWindowController.onRunSetupCheck = { [weak self] in
            self?.completeStartupIfPossible(showSetupWindowOnFailure: false, forcePresentSetupWindow: false)
        }
        settingsWindowController.onRunPhysicalSmoke = { [weak self] in
            self?.runPhysicalSmokeFromSettings()
        }
        settingsWindowController.onExportDiagnostics = { [weak self] in
            self?.exportDiagnostics()
        }
        settingsWindowController.onRestartApp = { [weak self] in
            self?.restartPressTalkFromSettings()
        }
        settingsWindowController.onRepairLocalSigning = { [weak self] in
            self?.repairLocalSigningFromSettings()
        }
        settingsWindowController.onOpenMicrophoneSettings = { [weak self] in
            self?.openMicrophonePrivacyPane()
        }
        settingsWindowController.onOpenInputMonitoringSettings = { [weak self] in
            self?.openInputMonitoringPrivacyPane()
        }
        settingsWindowController.onOpenAccessibilitySettings = { [weak self] in
            self?.requestAccessibilitySetup()
        }
        settingsWindowController.onDisableSystemDictationHotkey = { [weak self] in
            self?.disableSystemDictationHotkeyFromSettings()
        }
        settingsWindowController.onEnableF5Fallback = { [weak self] in
            self?.configureKarabinerFallback(enabled: true)
        }
        settingsWindowController.onDisableF5Fallback = { [weak self] in
            self?.configureKarabinerFallback(enabled: false)
        }
        settingsWindowController.onStartNativeCalibration = { [weak self] in
            self?.startNativeTriggerCalibration()
        }
        settingsWindowController.onClearNativeCalibration = { [weak self] in
            self?.clearNativeTriggerCalibration()
        }
        self.settingsWindowController = settingsWindowController
        hudController = PressTalkHUDController()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.toolTip = "PressTalk: hold \(settingsStore.triggerKey.displayName) to dictate"
        }

        let menu = NSMenu()

        let statusSummaryMenuItem = NSMenuItem(title: appDisplayTitle, action: nil, keyEquivalent: "")
        statusSummaryMenuItem.isEnabled = false
        self.statusSummaryMenuItem = statusSummaryMenuItem
        menu.addItem(statusSummaryMenuItem)

        let statusDetailMenuItem = NSMenuItem(title: "Warming up speech model…", action: nil, keyEquivalent: "")
        statusDetailMenuItem.isEnabled = false
        self.statusDetailMenuItem = statusDetailMenuItem
        menu.addItem(statusDetailMenuItem)

        menu.addItem(.separator())

        let showHUDMenuItem = NSMenuItem(title: "Show HUD", action: #selector(toggleHUDFromMenu(_:)), keyEquivalent: "")
        showHUDMenuItem.target = self
        self.toggleHUDMenuItem = showHUDMenuItem
        menu.addItem(showHUDMenuItem)

        let autoPasteMenuItem = NSMenuItem(title: "Paste Automatically", action: #selector(toggleAutoPasteFromMenu(_:)), keyEquivalent: "")
        autoPasteMenuItem.target = self
        self.togglePasteMenuItem = autoPasteMenuItem
        menu.addItem(autoPasteMenuItem)

        let abortPopupsMenuItem = NSMenuItem(title: "Show Abort Guidance", action: #selector(toggleAbortPopupsFromMenu(_:)), keyEquivalent: "")
        abortPopupsMenuItem.target = self
        self.toggleAbortPopupsMenuItem = abortPopupsMenuItem
        menu.addItem(abortPopupsMenuItem)

        let recentItem = NSMenuItem(title: "Recent Dictations", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        // Prune when the submenu opens, not only when a dictation completes.
        // Otherwise an entry that aged out during an idle afternoon is still
        // sitting there to be copied.
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        recentItem.toolTip = "The last few transcripts, kept in memory only. Choose one to copy it."
        recentDictationsMenu = recentMenu
        menu.addItem(recentItem)
        refreshRecentDictationsMenu()

        let setupItem = NSMenuItem(title: "Run Setup…", action: #selector(openFirstRunSetupFromMenu(_:)), keyEquivalent: "")
        setupItem.target = self
        setupItem.toolTip = "Walks through microphone, trigger, and pasting one step at a time."
        menu.addItem(setupItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let setupCheckItem = NSMenuItem(title: "Run Setup Check", action: #selector(runSetupCheckFromMenu(_:)), keyEquivalent: "")
        setupCheckItem.target = self
        menu.addItem(setupCheckItem)

        let physicalSmokeItem = NSMenuItem(title: "Run Physical Smoke…", action: #selector(runPhysicalSmokeFromMenu(_:)), keyEquivalent: "")
        physicalSmokeItem.target = self
        physicalSmokeItem.toolTip = "Opens the bundled physical trigger smoke helper without opening privacy panes."
        menu.addItem(physicalSmokeItem)

        let repairSigningItem = NSMenuItem(title: "Repair Signing…", action: #selector(repairLocalSigningFromMenu(_:)), keyEquivalent: "")
        repairSigningItem.target = self
        repairSigningItem.isHidden = true
        repairSigningItem.toolTip = "Runs the bundled signing repair helper with permission panes disabled."
        self.repairLocalSigningMenuItem = repairSigningItem
        menu.addItem(repairSigningItem)

        let reloadItem = NSMenuItem(title: "Reload Speech Model", action: #selector(reloadSpeechModelFromMenu(_:)), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let logsItem = NSMenuItem(title: "Reveal Logs", action: #selector(revealLogsFromMenu(_:)), keyEquivalent: "l")
        logsItem.target = self
        menu.addItem(logsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit PressTalk", action: #selector(quitFromMenu(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshMenuSettingsState()
        applyPresentationState(.warming)
    }

    private func refreshMenuSettingsState() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.toggleHUDMenuItem?.state = self.settingsStore.showHUD ? .on : .off
            self.togglePasteMenuItem?.state = self.settingsStore.pasteAutomatically ? .on : .off
            self.toggleAbortPopupsMenuItem?.state = self.settingsStore.showAbortPopups ? .on : .off
        }
    }

    private func handleSettingsChanged() {
        applyWhisperDecodingPreferences()
        refreshMenuSettingsState()
        traceLogger.log(
            "Settings updated show_hud=\(settingsStore.showHUD ? 1 : 0) paste_automatically=\(settingsStore.pasteAutomatically ? 1 : 0) abort_popups=\(settingsStore.showAbortPopups ? 1 : 0) trigger_key=\(settingsStore.triggerKey.rawValue) language=\(settingsStore.preferredLanguage.rawValue) release_tail_max_seconds=\(String(format: "%.2f", settingsStore.releaseTailMaxSeconds)) insertion_suffix=\(settingsStore.insertionSuffix.rawValue)"
        )

        if !settingsStore.showHUD {
            DispatchQueue.main.async { [weak self] in
                self?.hudController?.hide()
            }
        } else {
            present(withStateLock { presentationState })
        }
    }

    private func cancelReadyReset() {
        DispatchQueue.main.async { [weak self] in
            self?.readyResetWorkItem?.cancel()
            self?.readyResetWorkItem = nil
        }
    }

    private func scheduleReturnToReady(after seconds: TimeInterval = 1.4) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.readyResetWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.present(.ready)
            }
            self.readyResetWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
        }
    }

    private func startAmplitudeMonitoring() {
        stopAmplitudeMonitoring(hideLight: false)

        let task = Task(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard self.activeTriggerUsesVoiceLight() else {
                    try? await Task.sleep(nanoseconds: 33_000_000)
                    continue
                }
                let bands = self.currentLiveListeningLightBands()
                let anchorPoint = self.currentHoldlightAnchorPoint()
                let verticalLift = self.currentHoldlightVerticalLift()
                await MainActor.run { [weak self] in
                    guard let self, self.settingsStore.showHUD else { return }
                    self.hudController?.updateListeningLight(
                        bands: bands,
                        anchorPoint: anchorPoint,
                        verticalLift: verticalLift,
                        alpha: 1
                    )
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }

        withStateLock {
            amplitudeMonitorTask = task
        }
    }

    private func stopAmplitudeMonitoring(hideLight: Bool = true) {
        let task = withStateLock { () -> Task<Void, Never>? in
            let existing = amplitudeMonitorTask
            amplitudeMonitorTask = nil
            return existing
        }
        task?.cancel()

        guard hideLight else { return }
        DispatchQueue.main.async { [weak self] in
            self?.hudController?.hide()
        }
    }

    private func currentInputLightBands() -> VoiceLightBands {
        let sampleWindow = Int(Double(WhisperKit.sampleRate) * 0.12)
        let recentSamples = recentLiveCapturedAudioSamples(maxCount: sampleWindow)
        guard !recentSamples.isEmpty else {
            return VoiceLightBands(low: 0.04, mid: 0.04, high: 0.04)
        }

        return frequencyBandLevels(for: recentSamples, sampleRate: Double(WhisperKit.sampleRate))
    }

    private func currentLiveListeningLightBands() -> VoiceLightBands {
        let baseBands = currentInputLightBands()
        guard let holdState = withStateLock({ trackpadHoldState }), holdState.armed else {
            return baseBands
        }

        let normalizedPressure = min(max(holdState.latestPressure, 0), 1)
        let normalizedDistance = min(
            max(Double(holdState.maxDistance / trackpadHoldCancelDistancePoints), 0),
            1
        )
        let stability = 1 - normalizedDistance

        func energize(_ value: Double, floor: Double = 0.03, gain: Double) -> Double {
            let lifted = max(0.0, value - floor)
            return min(1.0, pow(lifted * gain, 0.42))
        }

        let lowTone = energize(baseBands.low, gain: 4.6)
        let midTone = energize(baseBands.mid, gain: 5.4)
        let highTone = energize(baseBands.high, gain: 6.2)

        return VoiceLightBands(
            low: min(1.0, lowTone + (normalizedPressure * 0.08) + (stability * 0.03)),
            mid: min(1.0, midTone + (normalizedPressure * 0.12) + (stability * 0.04)),
            high: min(1.0, highTone + (normalizedPressure * 0.16) + (normalizedDistance * 0.12))
        )
    }

    private func currentHoldlightAnchorPoint() -> CGPoint? {
        let triggerState = withStateLock { () -> (Trigger?, CGPoint?) in
            (activeTrigger, trackpadHoldState?.downLocation)
        }
        if triggerState.0 == .trackpadHold {
            return triggerState.1
        }
        return keyboardTriggerLightAnchorPoint()
    }

    private func currentHoldlightVerticalLift() -> CGFloat {
        0
    }

    private func keyboardTriggerLightAnchorPoint() -> CGPoint? {
        NSEvent.mouseLocation
    }

    private func activeTriggerUsesVoiceLight() -> Bool {
        withStateLock {
            activeTrigger != nil
        }
    }

    private func frequencyBandLevels(for samples: [Float], sampleRate: Double) -> VoiceLightBands {
        guard !samples.isEmpty else {
            return VoiceLightBands(low: 0.04, mid: 0.04, high: 0.04)
        }

        let dt = 1.0 / sampleRate
        let lowAlpha = dt / ((1.0 / (2.0 * Double.pi * 280.0)) + dt)
        let midAlpha = dt / ((1.0 / (2.0 * Double.pi * 1800.0)) + dt)

        var lowPass = 0.0
        var midPass = 0.0
        var lowSquares = 0.0
        var midSquares = 0.0
        var highSquares = 0.0

        for sample in samples {
            let value = Double(sample)
            lowPass += lowAlpha * (value - lowPass)
            midPass += midAlpha * (value - midPass)

            let lowBand = lowPass
            let midBand = midPass - lowPass
            let highBand = value - midPass

            lowSquares += lowBand * lowBand
            midSquares += midBand * midBand
            highSquares += highBand * highBand
        }

        let sampleCount = Double(samples.count)
        let lowRMS = sqrt(lowSquares / sampleCount)
        let midRMS = sqrt(midSquares / sampleCount)
        let highRMS = sqrt(highSquares / sampleCount)

        func gate(_ rms: Double, threshold: Double, gain: Double) -> Double {
            let gated = max(0.0, rms - threshold)
            return min(1.0, pow(gated * gain, 0.82))
        }

        return VoiceLightBands(
            low: max(0.03, gate(lowRMS, threshold: 0.0008, gain: 42.0)),
            mid: max(0.03, gate(midRMS, threshold: 0.0007, gain: 52.0)),
            high: max(0.03, gate(highRMS, threshold: 0.00055, gain: 66.0))
        )
    }

    private func present(_ state: PresentationState) {
        withStateLock {
            presentationState = state
        }
        DispatchQueue.main.async { [weak self] in
            self?.applyPresentationState(state)
        }
    }

    private func applyPresentationState(_ state: PresentationState) {
        let uiState: (summary: String, detail: String, symbol: String, hudStyle: PressTalkHUDController.Style, autoHide: TimeInterval?)

        switch state {
        case .warming:
            uiState = (appDisplayTitle, "Warming up the local speech model…", "hourglass.circle.fill", .warming, nil)
        case .ready:
            let status = currentRuntimeStatus()
            if localSigningRepairNeeded(status) {
                uiState = (
                    "Paste Repair Needed",
                    "Transcription ready. Click Repair Signing in the menu bar to restore active-field paste.",
                    "wrench.and.screwdriver.fill",
                    .warming,
                    nil
                )
            } else if settingsStore.pasteAutomatically &&
                !status.activeFieldInsertionReady {
                uiState = (
                    "Paste Fallback Blocked",
                    (status.inputMethodFallbackStatus == "probe_only" || status.inputMethodFallbackStatus == "ready")
                        ? "Transcription ready. Auto-insert needs Accessibility; dictation will copy."
                        : "Transcription ready. Input method status: \(status.inputMethodFallbackStatus).",
                    "exclamationmark.triangle.fill",
                    .warming,
                    nil
                )
            } else {
                uiState = (appDisplayTitle, "Ready. Hold \(settingsStore.triggerKey.displayName) to dictate.", "waveform.badge.mic", .ready, 1.1)
            }
        case .listening(let partial):
            uiState = ("Listening", partial?.nonEmpty ?? "Release \(settingsStore.triggerKey.displayName) to paste.", "mic.fill", .listening, nil)
        case .processing:
            uiState = ("Processing", "Cleaning and finalizing your dictation…", "ellipsis.circle.fill", .processing, nil)
        case .inserted(let transcript):
            uiState = ("Inserted", transcript, "checkmark.circle.fill", .inserted, 1.5)
        case .copied(let transcript):
            uiState = ("Copied to Clipboard", transcript, "doc.on.clipboard.fill", .copied, 1.5)
        case .aborted(let message):
            uiState = ("Transcription Aborted", message, "hand.raised.fill", .error, 4.0)
        case .audioUnavailable(let message):
            uiState = ("No Audio Input", message, "mic.slash.fill", .error, 4.0)
        case .error(let message):
            uiState = ("Couldn’t Hear That", message, "exclamationmark.triangle.fill", .error, 1.7)
        case .setupRequired(let message):
            uiState = ("Setup Required", message, "slider.horizontal.3", .warming, nil)
        case .diagnosticStarted(let message):
            uiState = ("Diagnostic Started", message, "waveform.path.badge.plus", .ready, 2.0)
        }

        if case .inserted = state {
            scheduleReturnToReady()
        } else if case .copied = state {
            scheduleReturnToReady()
        } else if case .aborted = state {
            scheduleReturnToReady(after: 4.0)
        } else if case .error = state {
            scheduleReturnToReady()
        } else if case .diagnosticStarted = state {
            scheduleReturnToReady(after: 2.0)
        } else if case .setupRequired = state {
            cancelReadyReset()
        } else {
            cancelReadyReset()
        }

        statusSummaryMenuItem?.title = uiState.summary
        statusDetailMenuItem?.title = uiState.detail

        updateStatusItemPresentation(state: state, uiState: uiState)

        guard settingsStore.showHUD else {
            if case .listening = state {
                traceLogger.log("HUD listening skipped reason=show_hud_disabled")
            }
            hudController?.hide()
            return
        }

        switch state {
        case .listening(let partial):
            if activeTriggerUsesVoiceLight() {
                traceLogger.log("HUD listening presentation=voice_light")
                hudController?.showListeningLight(
                    bands: currentLiveListeningLightBands(),
                    anchorPoint: currentHoldlightAnchorPoint(),
                    verticalLift: currentHoldlightVerticalLift(),
                    alpha: 1,
                    transcript: partial?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                )
            } else {
                traceLogger.log("HUD listening presentation=card trigger=\(settingsStore.triggerKey.rawValue)")
                hudController?.show(
                    title: uiState.summary,
                    detail: uiState.detail,
                    style: uiState.hudStyle,
                    autoHideAfter: uiState.autoHide
                )
            }
        case .setupRequired:
            hudController?.hide()
        case .aborted, .audioUnavailable, .error, .diagnosticStarted:
            hudController?.show(
                title: uiState.summary,
                detail: uiState.detail,
                style: uiState.hudStyle,
                autoHideAfter: uiState.autoHide
            )
        case .ready, .warming, .processing, .inserted, .copied:
            hudController?.hide()
        }
    }

    private func updateStatusItemPresentation(
        state: PresentationState,
        uiState: (summary: String, detail: String, symbol: String, hudStyle: PressTalkHUDController.Style, autoHide: TimeInterval?)
    ) {
        guard let statusItem, let button = statusItem.button else { return }
        button.toolTip = "\(uiState.summary) — \(uiState.detail)"

        switch state {
        case .listening:
            statusItem.length = 76
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = NSAttributedString(
                string: "● REC",
                attributes: [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                ]
            )
        case .processing:
            statusItem.length = 82
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = NSAttributedString(
                string: "… STT",
                attributes: [
                    .foregroundColor: NSColor.systemOrange,
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                ]
            )
        default:
            statusItem.length = NSStatusItem.squareLength
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            let image = NSImage(systemSymbolName: uiState.symbol, accessibilityDescription: uiState.summary)
            image?.isTemplate = true
            button.image = image
        }
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        refreshRuntimeStatusUI()
        settingsWindowController?.present()
    }

    @objc private func runSetupCheckFromMenu(_ sender: Any?) {
        completeStartupIfPossible(showSetupWindowOnFailure: false, forcePresentSetupWindow: false)
    }

    @objc private func repairLocalSigningFromMenu(_ sender: Any?) {
        repairLocalSigningFromSettings()
    }

    @objc private func runPhysicalSmokeFromMenu(_ sender: Any?) {
        runPhysicalSmokeFromSettings()
    }

    @objc private func toggleHUDFromMenu(_ sender: Any?) {
        settingsStore.showHUD.toggle()
        settingsWindowController?.reloadFromStore()
        handleSettingsChanged()
    }

    @objc private func toggleAutoPasteFromMenu(_ sender: Any?) {
        settingsStore.pasteAutomatically.toggle()
        settingsWindowController?.reloadFromStore()
        handleSettingsChanged()
    }

    @objc private func toggleAbortPopupsFromMenu(_ sender: Any?) {
        settingsStore.showAbortPopups.toggle()
        settingsWindowController?.reloadFromStore()
        handleSettingsChanged()
    }

    @objc private func reloadSpeechModelFromMenu(_ sender: Any?) {
        traceLogger.log("Manual speech model reload requested")
        withStateLock {
            whisperWarmupTask?.cancel()
            whisperWarmupTask = nil
            whisperKit = nil
            audioCaptureKit = nil
            parakeetAsrManager = nil
            parakeetDecoderLayerCount = 2
            streamTranscriber = nil
            whisperLoadState = .idle
        }
        refreshRuntimeStatusUI()
        present(.warming)
        startWhisperWarmupIfNeeded()
    }

    @objc private func revealLogsFromMenu(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: config.traceLogPath)])
    }

    @objc private func quitFromMenu(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func refreshRuntimeStatusUI() {
        refreshKarabinerFallbackState()
        let status = currentRuntimeStatus()
        writeRuntimeStatusSnapshot(status)
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindowController?.updateRuntimeStatus(status)
            self?.updateRepairLocalSigningMenuItem(status)
        }
    }

    private func updateRepairLocalSigningMenuItem(_ status: PressTalkRuntimeStatus) {
        let repairNeeded = localSigningRepairNeeded(status)
        repairLocalSigningMenuItem?.isHidden = !repairNeeded
        repairLocalSigningMenuItem?.isEnabled = repairNeeded
    }

    private func selectedTriggerObservedForRuntimeStatus() -> Bool {
        let telemetry = withStateLock { triggerBridgeTelemetry }
        switch settingsStore.triggerKey {
        case .optionSpace:
            return telemetry.registeredHotKeySeen
        case .trackpadHold:
            return telemetry.trackpadHoldSeen
        case .fn, .option, .leftOption, .rightOption:
            return telemetry.modifierKeySeen
        case .f5:
            return telemetry.darwinNotificationSeen ||
                telemetry.nativeSystemDefinedSeen ||
                telemetry.cgFunctionKeySeen
        }
    }

    /// The optional second-opinion recognizer. "Enabled" in settings and
    /// "actually loaded" are different things once the model is a separate
    /// download, so say which one is true.
    private func currentQualityFallbackStatus() -> String {
        guard usesParakeetFinalBackend else { return "Not applicable" }
        guard config.parakeetQualityFallbackEnabled else { return "Off" }
        if whisperKit != nil { return "Ready" }
        if whisperModelIsLocallyAvailable { return "Downloaded, loading" }
        return "Not downloaded (dictation uses Parakeet alone)"
    }

    private func currentRuntimeStatus() -> PressTalkRuntimeStatus {
        let microphoneAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let whisperStatus: String = withStateLock {
            switch whisperLoadState {
            case .idle:
                return inputPipelineReady ? "Queued" : "Waiting for setup"
            case .loading:
                return "Warming up"
            case .ready:
                return "Ready"
            case .failed(let reason):
                return "Failed: \(reason)"
            }
        }

        let bridgeStatus = currentTriggerBridgeStatus()
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
        let codeSignatureIdentifier = codeSignatureValue(prefix: "Identifier=")
        let codeSignatureCDHash = codeSignatureValue(prefix: "CDHash=")
        let codeSignatureAuthority = codeSignatureValue(prefix: "Authority=")
        let inputMethodFallbackStatus = currentInputMethodFallbackStatus()

        return PressTalkRuntimeStatus(
            bundleIdentifier: bundleIdentifier,
            inputMonitoringGranted: CGPreflightListenEventAccess(),
            microphoneGranted: microphoneAuthorizationStatus == .authorized,
            microphoneAuthorizationStatus: microphoneAuthorizationStatusDescription(microphoneAuthorizationStatus),
            accessibilityGranted: AXIsProcessTrusted(),
            inputPipelineReady: inputPipelineReady,
            inputListenerStatus: eventTapInstallSummary,
            triggerKey: settingsStore.triggerKey.rawValue,
            selectedTriggerObserved: selectedTriggerObservedForRuntimeStatus(),
            pasteAutomatically: settingsStore.pasteAutomatically,
            inputMethodFallbackStatus: inputMethodFallbackStatus,
            systemDictationHotkeyDisabled: !currentSystemDictationHotkeyEnabled(),
            adHocSigned: appCodeSignatureSummary.contains("Signature=adhoc"),
            permissionPaneOpeningAllowed: config.allowPermissionPaneOpen,
            speechModelStatus: whisperStatus,
            asrBackend: config.asrBackend,
            streamingASRBackend: config.streamingASRBackend ?? "none",
            realtimePartialTranscriptionEnabled: config.streamingTranscriptionEnabled,
            asrMode: currentASRModeDescription(),
            qualityFallbackStatus: currentQualityFallbackStatus(),
            f5BridgeStatus: bridgeStatus,
            codeSignatureIdentifier: codeSignatureIdentifier,
            codeSignatureCDHash: codeSignatureCDHash,
            codeSignatureAuthority: codeSignatureAuthority
        )
    }

    private func writeRuntimeStatusSnapshot(_ status: PressTalkRuntimeStatus) {
        let statusURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JarvisTap/runtime-status.json")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: [String: Any] = [
            "generatedAt": formatter.string(from: Date()),
            "app": [
                "name": "PressTalk",
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
                "bundlePath": Bundle.main.bundleURL.path,
                "executablePath": Bundle.main.executableURL?.path ?? "unknown",
                "processID": ProcessInfo.processInfo.processIdentifier,
            ],
            "runtime": [
                "inputPipelineReady": inputPipelineReady,
                "inputListener": eventTapInstallSummary,
                "setupRetryActive": setupRetryTimer != nil,
                "activeFieldInsertionReady": status.activeFieldInsertionReady,
                "activeFieldInsertionStatus": status.activeFieldInsertionStatus,
                "agentMode": config.agentMode,
                "triggerKey": settingsStore.triggerKey.rawValue,
                "selectedTriggerObserved": status.selectedTriggerObserved,
                "asrBackend": status.asrBackend,
                "streamingASRBackend": status.streamingASRBackend,
                "asrMode": status.asrMode,
                "qualityFallbackStatus": status.qualityFallbackStatus,
                "realtimePartialTranscriptionEnabled": status.realtimePartialTranscriptionEnabled,
                "whisperModel": config.whisperModel,
                "whisperLanguage": config.whisperLanguage ?? "auto",
                "traceLogPath": config.traceLogPath,
            ],
            "permissions": [
                "inputMonitoringGranted": status.inputMonitoringGranted,
                "inputMonitoringEffective": status.inputMonitoringEffective,
                "inputMonitoringStatus": status.inputMonitoringStatus,
                "microphoneGranted": status.microphoneGranted,
                "microphoneAuthorizationStatus": status.microphoneAuthorizationStatus,
                "microphoneStatus": status.microphoneGranted ? "preflight_granted" : "preflight_\(status.microphoneAuthorizationStatus)",
                "accessibilityGranted": status.accessibilityGranted,
                "accessibilityStatus": accessibilityStatusDescription(status),
                "inputMethodFallbackStatus": status.inputMethodFallbackStatus,
                "systemDictationHotkeyDisabled": status.systemDictationHotkeyDisabled,
                "permissionPaneOpeningAllowed": status.permissionPaneOpeningAllowed,
            ],
            "status": [
                "speechModel": status.speechModelStatus,
                "triggerPath": status.f5BridgeStatus,
                "adHocSigned": status.adHocSigned,
                "codeSignatureIdentifier": status.codeSignatureIdentifier,
                "codeSignatureCDHash": status.codeSignatureCDHash,
                "codeSignatureAuthority": status.codeSignatureAuthority,
            ],
            "codeSignatureSummary": appCodeSignatureSummary,
        ]

        do {
            try FileManager.default.createDirectory(
                at: statusURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: statusURL, options: [.atomic])
        } catch {
            traceLogger.log("Runtime status snapshot write failed error=\(error)")
        }
    }

    private func openMicrophonePrivacyPane() {
        guard config.allowPermissionPaneOpen else {
            traceLogger.log("Suppressed Microphone privacy pane open because PRESSTALK_OPEN_PERMISSION_PANES is not enabled")
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openInputMonitoringPrivacyPane() {
        guard config.allowPermissionPaneOpen else {
            traceLogger.log("Suppressed Input Monitoring privacy pane open because PRESSTALK_OPEN_PERMISSION_PANES is not enabled")
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAccessibilityPrivacyPane() {
        guard config.allowPermissionPaneOpen else {
            traceLogger.log("Suppressed Accessibility privacy pane open because PRESSTALK_OPEN_PERMISSION_PANES is not enabled")
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func requestAccessibilitySetup() {
        openAccessibilityPrivacyPane()
        refreshRuntimeStatusUI()
    }

    private func disableSystemDictationHotkeyFromSettings() {
        ensureSystemDictationInterferenceDisabledIfNeeded()
        refreshRuntimeStatusUI()
        if currentSystemDictationHotkeyEnabled() {
            present(.error("Apple Dictation is still bound to F5. Run Setup Check again."))
        } else {
            present(.copied("Apple Dictation key disabled for PressTalk."))
        }
    }

    private func exportDiagnostics() {
        let diagnosticsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JarvisTap/Diagnostics", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let diagnosticsURL = diagnosticsDirectory.appendingPathComponent("PressTalk-diagnostics-\(timestamp).txt")
            let runtimeStatus = currentRuntimeStatus()
            let bridgeDetails = currentTriggerBridgeDetails()
            let traceTail = recentTraceLogLines(limit: 160)
            let report = """
            PressTalk Diagnostics
            Generated: \(formatter.string(from: Date()))
            Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
            Bundle path: \(Bundle.main.bundleURL.path)
            Executable path: \(Bundle.main.executableURL?.path ?? "unknown")
            Bundle identifier: \(runtimeStatus.bundleIdentifier)
            Process ID: \(ProcessInfo.processInfo.processIdentifier)
            Launch label: \(config.launchdLabel)

            Permissions
            - Input Monitoring preflight: \(runtimeStatus.inputMonitoringGranted ? "granted" : "unavailable")
            - Input listener effective: \(runtimeStatus.inputMonitoringEffective ? "yes" : "no")
            - Input Monitoring status: \(runtimeStatus.inputMonitoringStatusDescription)
            - Microphone preflight: \(runtimeStatus.microphoneGranted ? "granted" : runtimeStatus.microphoneAuthorizationStatus)
            - Accessibility status: \(accessibilityStatusDescription(runtimeStatus))
            - Input method fallback: \(runtimeStatus.inputMethodFallbackStatus)
            - Apple Dictation key: \(runtimeStatus.systemDictationHotkeyDisabled ? "disabled" : "active")

            Code signature
            Identifier: \(runtimeStatus.codeSignatureIdentifier)
            CDHash: \(runtimeStatus.codeSignatureCDHash)
            Authority: \(runtimeStatus.codeSignatureAuthority)
            \(appCodeSignatureSummary)

            Runtime
            - Speech model: \(runtimeStatus.speechModelStatus)
            - ASR backend: \(runtimeStatus.asrBackend)
            - Streaming ASR backend: \(runtimeStatus.streamingASRBackend)
            - ASR mode: \(runtimeStatus.asrMode)
            - Realtime partial transcription: \(runtimeStatus.realtimePartialTranscriptionEnabled ? "enabled" : "disabled")
            - Trigger path: \(runtimeStatus.f5BridgeStatus)
            - Input listener: \(eventTapInstallSummary)
            - Native calibration: \(currentNativeCalibrationSummary())
            - Trigger sources seen: \(bridgeDetails.sourcesSummary)
            - Last trigger source: \(bridgeDetails.lastSource ?? "none")
            - Last trigger phase: \(bridgeDetails.lastPhase ?? "none")
            - Last trigger time: \(bridgeDetails.lastTimestamp ?? "none")
            - Agent mode: \(config.agentMode)
            - Whisper model: \(config.whisperModel)
            - Whisper language: \(config.whisperLanguage ?? "auto")
            - Trigger key: \(settingsStore.triggerKey.rawValue)
            - HUD enabled: \(settingsStore.showHUD ? "yes" : "no")
            - Paste automatically: \(settingsStore.pasteAutomatically ? "yes" : "no")
            - Release tail max seconds: \(String(format: "%.2f", settingsStore.releaseTailMaxSeconds))
            - Insertion suffix: \(settingsStore.insertionSuffix.rawValue)

            Trace tail
            \(traceTail)
            """
            try report.write(to: diagnosticsURL, atomically: true, encoding: .utf8)
            traceLogger.log("Diagnostics exported path=\(diagnosticsURL.path)")
            if config.allowPermissionPaneOpen {
                NSWorkspace.shared.activateFileViewerSelecting([diagnosticsURL])
                present(.copied("Diagnostics exported to \(diagnosticsURL.lastPathComponent)"))
            } else {
                traceLogger.log("Diagnostics file reveal suppressed because PRESSTALK_OPEN_PERMISSION_PANES is not enabled")
                present(.copied("Diagnostics exported quietly: \(diagnosticsURL.lastPathComponent)"))
            }
        } catch {
            traceLogger.log("Diagnostics export failed error=\(error)")
            present(.error("Diagnostics export failed."))
        }
    }

    private func runPhysicalSmokeFromSettings() {
        guard let resourceURL = Bundle.main.resourceURL else {
            traceLogger.log("Manual physical smoke helper missing path=\(Bundle.main.resourceURL?.path ?? "nil")")
            present(.error("The physical smoke helper is missing from this build."))
            return
        }
        let compiledHelperURL = resourceURL.appendingPathComponent("presstalk-manual-fn-smoke")
        let scriptHelperURL = resourceURL.appendingPathComponent("presstalk-manual-fn-smoke.swift")
        let helperURL: URL
        let executableURL: URL
        let arguments: [String]
        if FileManager.default.isExecutableFile(atPath: compiledHelperURL.path) {
            helperURL = compiledHelperURL
            executableURL = compiledHelperURL
            arguments = []
        } else if FileManager.default.isExecutableFile(atPath: scriptHelperURL.path) {
            helperURL = scriptHelperURL
            executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments = ["swift", scriptHelperURL.path]
        } else {
            traceLogger.log("Manual physical smoke helper missing path=\(resourceURL.path)")
            present(.error("The physical smoke helper is missing from this build."))
            return
        }

        let diagnosticsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JarvisTap/Diagnostics", isDirectory: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let logURL = diagnosticsDirectory.appendingPathComponent("manual-physical-smoke-launch-\(timestamp).log")
        let pidURL = diagnosticsDirectory.appendingPathComponent("manual-physical-smoke-launch-\(timestamp).pid")

        do {
            try FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
        } catch {
            traceLogger.log("Manual physical smoke log directory failed error=\(error)")
            present(.error("Could not create diagnostics directory for physical smoke."))
            return
        }

        traceLogger.log("Manual physical smoke requested from UI helper=\(helperURL.path) log=\(logURL.path) pid_file=\(pidURL.path)")
        present(.diagnosticStarted("Physical smoke window opening for \(settingsStore.triggerKey.displayName)."))

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PRESSTALK_OPEN_PERMISSION_PANES"] = "0"
        environment["PRESSTALK_AUTO_SHOW_SETUP_WINDOW"] = "0"
        environment["PRESSTALK_MANUAL_SMOKE_TRIGGER_KEY"] = settingsStore.triggerKey.rawValue
        environment["PRESSTALK_MANUAL_SMOKE_TRIGGER_LABEL"] = settingsStore.triggerKey.displayName
        process.environment = environment

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle: FileHandle
        do {
            logHandle = try FileHandle(forWritingTo: logURL)
        } catch {
            traceLogger.log("Manual physical smoke log open failed error=\(error)")
            present(.error("Could not open physical smoke log."))
            return
        }

        process.standardOutput = logHandle
        process.standardError = logHandle
        process.terminationHandler = { [weak self] terminatedProcess in
            logHandle.closeFile()
            DispatchQueue.main.async {
                self?.traceLogger.log("Manual physical smoke helper exited status=\(terminatedProcess.terminationStatus)")
                if self?.manualSmokeProcess === terminatedProcess {
                    self?.manualSmokeProcess = nil
                }
            }
        }

        do {
            manualSmokeProcess = process
            try process.run()
            try "\(process.processIdentifier)\n".write(to: pidURL, atomically: true, encoding: .utf8)
        } catch {
            logHandle.closeFile()
            manualSmokeProcess = nil
            traceLogger.log("Manual physical smoke launch failed error=\(error)")
            present(.error("Could not start physical smoke: \(error.localizedDescription)"))
        }
    }

    private func restartPressTalkFromSettings() {
        traceLogger.log("Restart requested from settings")
        present(.setupRequired("Restarting PressTalk to refresh runtime status."))

        let bundlePath = shellQuoted(Bundle.main.bundleURL.path)
        let launchLabel = "gui/\(getuid())/\(config.launchdLabel)"
        let script = """
        sleep 0.4
        /bin/launchctl kickstart -k \(launchLabel) >/dev/null 2>&1 || /usr/bin/open -g \(bundlePath) >/dev/null 2>&1
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", script]
        do {
            try process.run()
        } catch {
            traceLogger.log("Restart helper launch failed error=\(error)")
            present(.error("Could not restart PressTalk: \(error.localizedDescription)"))
            return
        }

        NSApp.terminate(nil)
    }

    private func repairLocalSigningFromSettings() {
        let status = currentRuntimeStatus()
        guard localSigningRepairNeeded(status) else {
            traceLogger.log("Local signing repair skipped reason=state_not_repairable ad_hoc=\(status.adHocSigned ? 1 : 0) input_method=\(status.inputMethodFallbackStatus) authority=\(status.codeSignatureAuthority)")
            present(.error("Signing repair is only needed for the PressTalk input-method-disabled signing state."))
            return
        }
        guard let helperURL = Bundle.main.resourceURL?.appendingPathComponent("presstalk-repair-local-signing.sh"),
              FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            traceLogger.log("Local signing repair helper missing path=\(Bundle.main.resourceURL?.path ?? "nil")")
            present(.error("The signing repair helper is missing from this build."))
            return
        }

        let diagnosticsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JarvisTap/Diagnostics", isDirectory: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let logURL = diagnosticsDirectory.appendingPathComponent("presstalk-signing-repair-\(timestamp).log")
        let pidURL = diagnosticsDirectory.appendingPathComponent("presstalk-signing-repair-\(timestamp).pid")

        do {
            try FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
        } catch {
            traceLogger.log("Local signing repair log directory failed error=\(error)")
            present(.error("Could not create diagnostics directory for signing repair."))
            return
        }

        let triggerKey = shellQuoted(settingsStore.triggerKey.rawValue)
        let helperPath = shellQuoted(helperURL.path)
        let logPath = shellQuoted(logURL.path)
        let pidPath = shellQuoted(pidURL.path)
        let script = """
        export PRESSTALK_OPEN_PERMISSION_PANES=0
        export PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0
        export PRESSTALK_TRIGGER_KEY=\(triggerKey)
        /usr/bin/nohup /bin/bash \(helperPath) --probe >\(logPath) 2>&1 &
        echo $! >\(pidPath)
        """

        traceLogger.log("Local signing repair requested from settings log=\(logURL.path) pid_file=\(pidURL.path)")
        present(.setupRequired("Signing repair started. Approve only the PressTalk local signing password prompt. PressTalk will restart and run an insertion probe."))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", script]
        do {
            try process.run()
        } catch {
            traceLogger.log("Local signing repair launch failed error=\(error)")
            present(.error("Could not start signing repair: \(error.localizedDescription)"))
        }
    }

    private func localSigningRepairNeeded(_ status: PressTalkRuntimeStatus) -> Bool {
        status.localSigningRepairNeeded
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func configureKarabinerFallback(enabled: Bool) {
        if enabled && settingsStore.triggerKey != .f5 {
            traceLogger.log("Karabiner fallback enable blocked reason=trigger_key_not_f5 selected=\(settingsStore.triggerKey.rawValue)")
            present(.error("Choose Legacy F5 / Mic as the trigger before enabling the F5 fallback."))
            refreshRuntimeStatusUI()
            return
        }

        if !enabled && settingsStore.triggerKey == .f5 && settingsStore.nativeTriggerCalibration == nil && !config.enableNativeMicrophoneKey {
            traceLogger.log("Karabiner fallback disable blocked reason=no_native_calibration")
            present(.error("Native F5 is not calibrated yet. Calibrate native F5 first, then disable the fallback."))
            refreshRuntimeStatusUI()
            return
        }

        guard let helperURL = Bundle.main.resourceURL?.appendingPathComponent("presstalk-karabiner-fallback.sh"),
              FileManager.default.isExecutableFile(atPath: helperURL.path)
        else {
            traceLogger.log("Karabiner fallback helper missing path=\(Bundle.main.resourceURL?.path ?? "nil")")
            present(.error("The F5 fallback helper is missing from this build."))
            return
        }

        let mode = enabled ? "--enable" : "--disable"
        traceLogger.log("Karabiner fallback helper requested mode=\(mode)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [helperURL.path, mode]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                DispatchQueue.main.async {
                    self?.traceLogger.log("Karabiner fallback helper completed mode=\(mode) status=\(process.terminationStatus)")
                    self?.refreshKarabinerFallbackState()
                    self?.refreshRuntimeStatusUI()
                    if process.terminationStatus == 0 {
                        let message = enabled
                            ? "Enabled optional F5 fallback."
                            : "Disabled optional F5 fallback."
                        self?.present(.copied(message))
                    } else {
                        self?.present(.error("F5 fallback update failed."))
                    }
                    if !output.isEmpty {
                        print(output)
                        fflush(stdout)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.traceLogger.log("Karabiner fallback helper failed mode=\(mode) error=\(error)")
                    self?.present(.error("F5 fallback update failed."))
                }
            }
        }
    }

    private func currentTriggerBridgeStatus() -> String {
        guard inputPipelineReady else {
            return "Waiting for setup"
        }

        if isModifierTriggerKey(settingsStore.triggerKey) && !eventTapInstallSummary.contains(":default") {
            return "\(settingsStore.triggerKey.displayName) blocked: writable key tap unavailable"
        }

        let telemetry = withStateLock { triggerBridgeTelemetry }
        if settingsStore.triggerKey == .optionSpace {
            if telemetry.registeredHotKeySeen {
                return "Option + Space trigger"
            }
            if eventTapInstallSummary.contains("carbon:registered") {
                return "Option + Space ready"
            }
            return "Option + Space unavailable: registered hotkey not installed"
        }
        if settingsStore.triggerKey == .trackpadHold && !telemetry.trackpadHoldSeen {
            return "Trackpad Hold waiting for pointer event"
        }
        if telemetry.modifierKeySeen {
            var detail = "\(settingsStore.triggerKey.displayName) trigger"
            var alternates: [String] = []
            if telemetry.trackpadHoldSeen {
                alternates.append(TriggerSource.trackpadHold.bridgeLabel)
            }
            if telemetry.registeredHotKeySeen {
                alternates.append(TriggerSource.registeredHotKey.bridgeLabel)
            }
            if telemetry.darwinNotificationSeen {
                alternates.append(TriggerSource.darwinNotification.bridgeLabel)
            }
            if telemetry.cgFunctionKeySeen {
                alternates.append(TriggerSource.cgFunctionKey.bridgeLabel)
            }
            if telemetry.nativeSystemDefinedSeen {
                alternates.append(TriggerSource.nativeSystemDefined.bridgeLabel)
            }
            if !alternates.isEmpty {
                detail += " (also saw \(alternates.joined(separator: ", ")))"
            }
            return detail
        }
        if telemetry.trackpadHoldSeen {
            var detail = TriggerSource.trackpadHold.bridgeLabel
            var alternates: [String] = []
            if telemetry.darwinNotificationSeen {
                alternates.append(TriggerSource.darwinNotification.bridgeLabel)
            }
            if telemetry.registeredHotKeySeen {
                alternates.append(TriggerSource.registeredHotKey.bridgeLabel)
            }
            if telemetry.cgFunctionKeySeen {
                alternates.append(TriggerSource.cgFunctionKey.bridgeLabel)
            }
            if telemetry.nativeSystemDefinedSeen {
                alternates.append(TriggerSource.nativeSystemDefined.bridgeLabel)
            }
            if !alternates.isEmpty {
                detail += " (also saw \(alternates.joined(separator: ", ")))"
            }
            return detail
        }
        if withStateLock({ nativeCalibrationSession != nil }) {
            return "Calibrating native F5; press and release F5 three times"
        }
        let nativeCalibration = settingsStore.nativeTriggerCalibration
        let nativeCalibrationActive = nativeCalibration != nil

        if nativeCalibrationActive {
            if telemetry.nativeSystemDefinedSeen {
                if karabinerFallbackEnabled {
                    return "Native calibrated (fallback still installed)"
                }
                return "Native calibrated"
            }
            if karabinerFallbackEnabled {
                return "Native calibrated; waiting for first F5 press"
            }
            return "Native calibrated; no fallback installed"
        }

        if settingsStore.triggerKey != .f5 {
            return "\(settingsStore.triggerKey.displayName) ready"
        }

        if !karabinerFallbackEnabled && !config.enableNativeMicrophoneKey {
            return "F5 ready"
        }

        if karabinerFallbackEnabled && !telemetry.nativeSystemDefinedSeen && !telemetry.darwinNotificationSeen && !telemetry.cgFunctionKeySeen {
            return "F5 ready; legacy fallback configured"
        }
        guard telemetry.nativeSystemDefinedSeen || telemetry.darwinNotificationSeen || telemetry.cgFunctionKeySeen else {
            if config.enableNativeMicrophoneKey {
                return "F5 ready; native legacy path experimental"
            }
            return "F5 ready"
        }

        let primarySource: TriggerSource
        if telemetry.nativeSystemDefinedSeen {
            primarySource = .nativeSystemDefined
        } else if telemetry.darwinNotificationSeen {
            primarySource = .darwinNotification
        } else {
            primarySource = .cgFunctionKey
        }

        var detail = primarySource.bridgeLabel
        var alternates: [String] = []
        if telemetry.darwinNotificationSeen && primarySource != .darwinNotification {
            alternates.append(TriggerSource.darwinNotification.bridgeLabel)
        }
        if telemetry.cgFunctionKeySeen && primarySource != .cgFunctionKey {
            alternates.append(TriggerSource.cgFunctionKey.bridgeLabel)
        }
        if telemetry.nativeSystemDefinedSeen && primarySource != .nativeSystemDefined {
            alternates.append(TriggerSource.nativeSystemDefined.bridgeLabel)
        }
        if !alternates.isEmpty {
            detail += " (also saw \(alternates.joined(separator: ", ")))"
        }
        return detail
    }

    private func currentSystemDictationHotkeyEnabled() -> Bool {
        let defaults = UserDefaults(suiteName: "com.apple.symbolichotkeys")
        guard
            let hotkeys = defaults?.dictionary(forKey: "AppleSymbolicHotKeys"),
            let entry = hotkeys[systemDictationHotkeyIdentifier] as? [String: Any]
        else {
            return false
        }
        return (entry["enabled"] as? Bool) ?? false
    }

    @discardableResult
    private func ensureSystemDictationInterferenceDisabledIfNeeded() -> Bool {
        var changed = false

        if let defaults = UserDefaults(suiteName: "com.apple.symbolichotkeys") {
            var hotkeys = defaults.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
            var entry = (hotkeys[systemDictationHotkeyIdentifier] as? [String: Any]) ?? [:]
            if (entry["enabled"] as? Bool) != false {
                entry["enabled"] = false
                if entry["value"] == nil {
                    entry["value"] = [
                        "type": "standard",
                        "parameters": [65535, Int(kVK_F5), 1572864],
                    ]
                }
                hotkeys[systemDictationHotkeyIdentifier] = entry
                defaults.set(hotkeys, forKey: "AppleSymbolicHotKeys")
                defaults.synchronize()
                changed = true
                traceLogger.log("Disabled Apple Dictation symbolic hotkey id=\(systemDictationHotkeyIdentifier)")
            }
        }

        if let defaults = UserDefaults(suiteName: "com.apple.HIToolbox") {
            if (defaults.object(forKey: "AppleDictationAutoEnable") as? Bool) != false {
                defaults.set(false, forKey: "AppleDictationAutoEnable")
                changed = true
            }
            if (defaults.object(forKey: "DictationIMIntroMessagePresented") as? Bool) != true {
                defaults.set(true, forKey: "DictationIMIntroMessagePresented")
                changed = true
            }
            if (defaults.object(forKey: "NSDisabledDictationMenuItem") as? Bool) != true {
                defaults.set(true, forKey: "NSDisabledDictationMenuItem")
                changed = true
            }
            defaults.synchronize()
        }

        if changed {
            traceLogger.log("Refreshing macOS input services after disabling Apple Dictation key")
            for command in ["/usr/bin/killall cfprefsd", "/usr/bin/killall SystemUIServer"] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", "\(command) >/dev/null 2>&1 || true"]
                try? process.run()
                process.waitUntilExit()
            }
        }

        return !currentSystemDictationHotkeyEnabled()
    }

    private func currentTriggerBridgeDetails() -> (sourcesSummary: String, lastSource: String?, lastPhase: String?, lastTimestamp: String?) {
        let telemetry = withStateLock { triggerBridgeTelemetry }
        var sources: [String] = []
        if telemetry.trackpadHoldSeen {
            sources.append(TriggerSource.trackpadHold.rawValue)
        }
        if telemetry.registeredHotKeySeen {
            sources.append(TriggerSource.registeredHotKey.rawValue)
        }
        if telemetry.modifierKeySeen {
            sources.append(TriggerSource.modifierKey.rawValue)
        }
        if telemetry.nativeSystemDefinedSeen {
            sources.append(TriggerSource.nativeSystemDefined.rawValue)
        }
        if telemetry.darwinNotificationSeen {
            sources.append(TriggerSource.darwinNotification.rawValue)
        }
        if telemetry.cgFunctionKeySeen {
            sources.append(TriggerSource.cgFunctionKey.rawValue)
        }

        let lastTimestamp = telemetry.lastEventAt.map { date in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: date)
        }

        return (
            sources.isEmpty ? "none" : sources.joined(separator: ", "),
            telemetry.lastSource?.rawValue,
            telemetry.lastPhase?.rawValue,
            lastTimestamp
        )
    }

    private func nativeMicrophoneKeyEnabled() -> Bool {
        config.enableNativeMicrophoneKey || settingsStore.nativeTriggerCalibration != nil
    }

    private func currentNativeCalibrationSummary() -> String {
        guard let calibration = settingsStore.nativeTriggerCalibration else { return "none" }
        return calibration.shortDescription
    }

    private func startNativeTriggerCalibration() {
        nativeCalibrationTimeoutWorkItem?.cancel()
        withStateLock {
            nativeCalibrationSession = NativeCalibrationSession()
        }

        traceLogger.log("Native trigger calibration started")
        present(.copied("Native F5 calibration started. Press and release F5 three times now."))

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.finishNativeTriggerCalibrationDueToTimeout()
        }
        nativeCalibrationTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 18, execute: timeoutWorkItem)
        refreshRuntimeStatusUI()
    }

    private func clearNativeTriggerCalibration() {
        nativeCalibrationTimeoutWorkItem?.cancel()
        nativeCalibrationTimeoutWorkItem = nil
        withStateLock {
            nativeCalibrationSession = nil
        }
        settingsStore.nativeTriggerCalibration = nil
        traceLogger.log("Native trigger calibration cleared")
        present(.copied("Cleared native F5 calibration."))
        refreshRuntimeStatusUI()
    }

    private func finishNativeTriggerCalibrationDueToTimeout() {
        let session = withStateLock { () -> NativeCalibrationSession? in
            defer { nativeCalibrationSession = nil }
            return nativeCalibrationSession
        }
        guard let session else { return }

        guard
            let strongestPress = session.strongestPress,
            let strongestRelease = session.strongestRelease,
            strongestPress.count >= 2,
            strongestRelease.count >= 2
        else {
            traceLogger.log("Native trigger calibration timed out without a stable signature")
            present(.error("Native F5 calibration timed out. Try again and press only F5."))
            refreshRuntimeStatusUI()
            return
        }

        let calibration = PressTalkNativeTriggerCalibration(
            press: strongestPress.signature,
            release: strongestRelease.signature,
            calibratedAt: Date()
        )
        settingsStore.nativeTriggerCalibration = calibration
        traceLogger.log("Native trigger calibration saved \(calibration.shortDescription)")
        present(.copied("Native F5 calibrated. You can disable the fallback now."))
        refreshRuntimeStatusUI()
    }

    private func signature(for event: NSEvent, cgEvent: CGEvent?) -> PressTalkNativeTriggerSignature {
        PressTalkNativeTriggerSignature(
            subtype: Int(event.subtype.rawValue),
            data1: event.data1,
            data2: event.data2,
            keyboardType: Int(cgEvent?.getIntegerValueField(.keyboardEventKeyboardType) ?? -1),
            sourceStateID: Int(cgEvent?.getIntegerValueField(.eventSourceStateID) ?? -1),
            modifierFlagsRaw: event.modifierFlags.rawValue
        )
    }

    private func recordNativeCalibrationCandidateIfNeeded(_ signature: PressTalkNativeTriggerSignature) {
        var completed = false
        var isRecordingCandidate = false
        withStateLock {
            guard var session = nativeCalibrationSession else { return }
            isRecordingCandidate = true
            session.record(signature)
            nativeCalibrationSession = session
            completed = session.isComplete
        }

        guard isRecordingCandidate else { return }
        traceLogger.log("Native calibration candidate \(signature.shortDescription)")

        guard completed else {
            refreshRuntimeStatusUI()
            return
        }
        nativeCalibrationTimeoutWorkItem?.cancel()
        nativeCalibrationTimeoutWorkItem = nil
        finishNativeTriggerCalibrationDueToTimeout()
    }

    private func recordAutomaticNativeCalibrationObservationIfNeeded(_ signature: PressTalkNativeTriggerSignature) {
        guard settingsStore.nativeTriggerCalibration == nil else { return }

        let shouldSkip = withStateLock {
            triggerBridgeTelemetry.darwinNotificationSeen || triggerBridgeTelemetry.cgFunctionKeySeen
        }
        if shouldSkip {
            return
        }

        var completed = false
        withStateLock {
            nativeAutoCalibrationObservations.record(signature)
            completed = nativeAutoCalibrationObservations.isComplete
        }

        guard completed else { return }
        saveAutomaticNativeCalibrationIfPossible()
    }

    private func saveAutomaticNativeCalibrationIfPossible() {
        let observation = withStateLock { nativeAutoCalibrationObservations }
        guard
            settingsStore.nativeTriggerCalibration == nil,
            let strongestPress = observation.strongestPress,
            let strongestRelease = observation.strongestRelease,
            strongestPress.count >= 3,
            strongestRelease.count >= 3
        else {
            return
        }

        let calibration = PressTalkNativeTriggerCalibration(
            press: strongestPress.signature,
            release: strongestRelease.signature,
            calibratedAt: Date()
        )
        settingsStore.nativeTriggerCalibration = calibration
        traceLogger.log("Auto-saved native trigger calibration \(calibration.shortDescription)")
        refreshRuntimeStatusUI()
    }

    private func refreshKarabinerFallbackState() {
        karabinerFallbackEnabled = currentKarabinerFallbackEnabledFromDisk()
    }

    private func currentKarabinerFallbackEnabledFromDisk() -> Bool {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/karabiner/karabiner.json")
        guard
            let data = try? Data(contentsOf: configURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profiles = object["profiles"] as? [[String: Any]]
        else {
            return false
        }

        let descriptions = Set([
            "Send PressTalk press and release notifications from the F5 / microphone key",
            "Send JarvisTap press and release notifications from the F5 / microphone key",
            "Map the F5 / microphone key to Fn+F5 for PressTalk",
        ])
        let fnFallbackDescription = "PressTalk F5 fallback via virtual F20"

        let selectedProfile = profiles.first(where: { ($0["selected"] as? Bool) == true }) ?? profiles.first
        let rules = ((selectedProfile?["complex_modifications"] as? [String: Any])?["rules"] as? [[String: Any]]) ?? []
        let complexFallbackEnabled = rules.contains { rule in
            if descriptions.contains(rule["description"] as? String ?? "") {
                return true
            }

            let manipulators = rule["manipulators"] as? [[String: Any]] ?? []
            return manipulators.contains { manipulator in
                let from = manipulator["from"] as? [String: Any]
                let to = manipulator["to"] as? [[String: Any]] ?? []
                let fromKey = from?["consumer_key_code"] as? String
                if fromKey == "microphone" || fromKey == "dictation" {
                    let sendsFnF5 = to.contains { target in
                        guard (target["key_code"] as? String) == "f5" else { return false }
                        let modifiers = target["modifiers"] as? [String] ?? []
                        return modifiers.contains("fn")
                    }
                    let sendsDarwinNotification = to.contains { target in
                        guard let command = target["shell_command"] as? String else { return false }
                        return command.contains("notifyutil")
                            && command.contains("com.am.jarvistap.trigger.press")
                    }
                    return sendsFnF5 || sendsDarwinNotification
                }

                let fromKeyCode = from?["key_code"] as? String
                guard fromKeyCode == "f5" else {
                    return false
                }

                return to.contains { target in
                    if (target["key_code"] as? String) == "f5" {
                        let modifiers = target["modifiers"] as? [String] ?? []
                        return modifiers.contains("fn")
                    }
                    guard let command = target["shell_command"] as? String else { return false }
                    return command.contains("notifyutil")
                        && command.contains("com.am.jarvistap.trigger.press")
                }
            }
        }

        let fnFunctionKeys = (selectedProfile?["fn_function_keys"] as? [[String: Any]]) ?? []
        let fnFallbackEnabled = fnFunctionKeys.contains { entry in
            if (entry["description"] as? String) == fnFallbackDescription {
                return true
            }

            let from = entry["from"] as? [String: Any]
            let to = entry["to"] as? [[String: Any]]
            return (from?["key_code"] as? String) == "f5"
                && (to?.contains {
                    guard let keyCode = $0["key_code"] as? String else { return false }
                    return keyCode == "f20" || keyCode == "f5"
                } ?? false)
        }

        return complexFallbackEnabled || fnFallbackEnabled
    }

    private func recentTraceLogLines(limit: Int) -> String {
        guard let contents = try? String(contentsOfFile: config.traceLogPath, encoding: .utf8) else {
            return "<trace unavailable>"
        }
        let lines = contents.split(whereSeparator: \.isNewline)
        return lines.suffix(limit).joined(separator: "\n")
    }

    private func codeSignatureSummary() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", Bundle.main.bundleURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let interestingPrefixes = [
                "Identifier=",
                "Format=",
                "CodeDirectory ",
                "CandidateCDHash ",
                "CDHash=",
                "Signature=",
                "Authority=",
                "TeamIdentifier=",
            ]
            let lines = output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { line in
                    interestingPrefixes.contains { line.hasPrefix($0) }
                }
            let statusLine = "codesign status=\(process.terminationStatus)"
            return ([statusLine] + lines).joined(separator: "\n")
        } catch {
            return "codesign unavailable: \(error.localizedDescription)"
        }
    }

    private func codeSignatureValue(prefix: String) -> String {
        appCodeSignatureSummary
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                guard line.hasPrefix(prefix) else { return nil }
                let value = line.dropFirst(prefix.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            .first ?? "unknown"
    }

    private func printAccessibilityTrustProbe() {
        let promptRequested = ProcessInfo.processInfo.environment["PRESSTALK_ACCESSIBILITY_TRUST_PROMPT"] == "1"
        let promptOptions = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptRequested,
        ] as CFDictionary
        let accessibilityTrusted = AXIsProcessTrustedWithOptions(promptOptions)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: [String: Any] = [
            "generatedAt": formatter.string(from: Date()),
            "probeKind": "actual_bundle_accessibility_trust",
            "promptRequested": promptRequested,
            "accessibilityTrusted": accessibilityTrusted,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
            "bundlePath": Bundle.main.bundleURL.path,
            "executablePath": Bundle.main.executableURL?.path ?? "unknown",
            "processID": ProcessInfo.processInfo.processIdentifier,
            "codeSignatureIdentifier": codeSignatureValue(prefix: "Identifier="),
            "codeSignatureCDHash": codeSignatureValue(prefix: "CDHash="),
            "codeSignatureAuthority": codeSignatureValue(prefix: "Authority="),
            "codeSignatureSummary": appCodeSignatureSummary,
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            fputs("[PressTalk] Accessibility trust probe JSON failed: \(error)\n", stderr)
        }
    }

    private func requestMicrophonePermissionAndRetry(
        showSetupWindowOnFailure: Bool,
        forcePresentSetupWindow: Bool,
        presentFailureStatus: Bool
    ) {
        guard !microphonePermissionRequestInFlight && !microphonePermissionRequestAttempted else {
            if presentFailureStatus {
                traceLogger.log("Startup blocked: microphone still not determined after request attempt")
                present(.setupRequired("Microphone approval is still pending. Approve the native PressTalk microphone prompt; do not open privacy panes repeatedly."))
            }
            refreshRuntimeStatusUI()
            scheduleSetupRetry()
            return
        }

        microphonePermissionRequestInFlight = true
        microphonePermissionRequestAttempted = true
        traceLogger.log("Requesting native microphone permission reason=not_determined")
        if presentFailureStatus {
            print("Requesting microphone access...")
            fflush(stdout)
            present(.setupRequired("Approve the native PressTalk microphone prompt to enable local dictation."))
        }
        refreshRuntimeStatusUI()

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                self.microphonePermissionRequestInFlight = false
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                self.traceLogger.log("Native microphone permission request completed granted=\(granted ? 1 : 0) status=\(self.microphoneAuthorizationStatusDescription(status))")
                self.refreshRuntimeStatusUI()
                self.completeStartupIfPossible(
                    showSetupWindowOnFailure: showSetupWindowOnFailure,
                    forcePresentSetupWindow: forcePresentSetupWindow,
                    presentFailureStatus: true
                )
            }
        }
    }

    private func checkSetupPermissions() -> PermissionCheckResult {
        let inputMonitoringGranted = CGPreflightListenEventAccess()
        let microphoneAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let microphoneGranted = microphoneAuthorizationStatus == .authorized
        let accessibilityGranted = AXIsProcessTrusted()

        return PermissionCheckResult(
            inputMonitoringGranted: inputMonitoringGranted,
            microphoneGranted: microphoneGranted,
            microphoneAuthorizationStatus: microphoneAuthorizationStatusDescription(microphoneAuthorizationStatus),
            accessibilityGranted: accessibilityGranted
        )
    }

    private func microphoneAuthorizationStatusDescription(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not_determined"
        @unknown default:
            return "unknown"
        }
    }

    private func loadWhisperKitSync() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var thrownError: Error?

        Task.detached(priority: .userInitiated) {
            do {
                try await self.loadWhisperKit()
            } catch {
                thrownError = error
            }
            semaphore.signal()
        }

        semaphore.wait()
        if let thrownError {
            throw thrownError
        }
    }

    private func whisperComputeSelection() -> WhisperComputeSelection {
        let preset = config.whisperComputePreset
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "+", with: "-")

        switch preset {
        case "default", "whisperkit-default", "ane", "neural-engine":
            return WhisperComputeSelection(
                label: "whisperkit-default",
                options: nil
            )
        case "cpu", "cpu-only":
            return WhisperComputeSelection(
                label: "cpu-only mel=cpuOnly audioEncoder=cpuOnly textDecoder=cpuOnly prefill=cpuOnly",
                options: ModelComputeOptions(
                    melCompute: .cpuOnly,
                    audioEncoderCompute: .cpuOnly,
                    textDecoderCompute: .cpuOnly,
                    prefillCompute: .cpuOnly
                )
            )
        case "cpu-gpu", "cpu-gpu-no-ane", "no-ane", "safe":
            return WhisperComputeSelection(
                label: "cpu-gpu-no-ane mel=cpuAndGPU audioEncoder=cpuAndGPU textDecoder=cpuAndGPU prefill=cpuOnly",
                options: ModelComputeOptions(
                    melCompute: .cpuAndGPU,
                    audioEncoderCompute: .cpuAndGPU,
                    textDecoderCompute: .cpuAndGPU,
                    prefillCompute: .cpuOnly
                )
            )
        default:
            traceLogger.log("Unknown Whisper compute preset=\(config.whisperComputePreset); using cpu-gpu-no-ane")
            return WhisperComputeSelection(
                label: "cpu-gpu-no-ane mel=cpuAndGPU audioEncoder=cpuAndGPU textDecoder=cpuAndGPU prefill=cpuOnly",
                options: ModelComputeOptions(
                    melCompute: .cpuAndGPU,
                    audioEncoderCompute: .cpuAndGPU,
                    textDecoderCompute: .cpuAndGPU,
                    prefillCompute: .cpuOnly
                )
            )
        }
    }

    /// Brings up microphone capture without touching a speech model.
    ///
    /// `WhisperKit(load: false, download: false)` returns in about 2 ms with a
    /// working `AudioProcessor` and no tokenizer, which is all the recording
    /// path needs. Startup used to call `loadWhisperKit()` unconditionally, so a
    /// new user waited for a 619 MB download of a model the default recognizer
    /// never consults.
    /// Reads an audio file and resamples it to the 16 kHz mono float samples the
    /// capture callback would have produced.
    /// Appends one JSON line per completed dictation when the harness is
    /// running. The trace log already carries this, but parsing prose is how
    /// measurement scripts quietly start reporting the wrong number.
    private func recordHarnessOutcome(transcript: String, releasedAt: Date) {
        guard let resultsURL = config.harnessResultsURL else { return }
        let record: [String: Any] = [
            "transcript": transcript,
            "fixture": Self.resolveFixtureAudioURL(config.fixtureAudioURL)?.lastPathComponent ?? "",
            "keyupToTranscriptSeconds": Date().timeIntervalSince(releasedAt),
            "recordedAt": ISO8601DateFormatter().string(from: Date()),
            "asrBackend": config.asrBackend,
            "qualityFallbackStatus": currentQualityFallbackStatus(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record),
              var line = String(data: data, encoding: .utf8)
        else { return }
        line.append("\n")
        if let handle = try? FileHandle(forWritingTo: resultsURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: resultsURL)
        }
    }

    /// A `.txt` fixture is a pointer, re-read on every capture, so one app
    /// session can sweep a whole corpus. Pointing straight at audio keeps the
    /// simple single-clip case unchanged.
    static func resolveFixtureAudioURL(_ configured: URL?) -> URL? {
        guard let configured else { return nil }
        guard configured.pathExtension.lowercased() == "txt" else { return configured }
        guard let contents = try? String(contentsOf: configured, encoding: .utf8) else { return nil }
        let path = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    static func loadFixtureAudioSamples(at url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(WhisperKit.sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw JarvisTapError.audioInputUnavailable("cannot build a 16 kHz mono fixture format")
        }

        guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            throw JarvisTapError.audioInputUnavailable("cannot convert \(file.processingFormat) to 16 kHz mono")
        }

        let sourceFrames = AVAudioFrameCount(file.length)
        guard sourceFrames > 0,
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: sourceFrames)
        else {
            throw JarvisTapError.audioInputUnavailable("fixture is empty: \(url.lastPathComponent)")
        }
        try file.read(into: sourceBuffer)

        let ratio = targetFormat.sampleRate / file.processingFormat.sampleRate
        let targetCapacity = AVAudioFrameCount(Double(sourceFrames) * ratio) + 1024
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) else {
            throw JarvisTapError.audioInputUnavailable("cannot allocate a fixture conversion buffer")
        }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: targetBuffer, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return sourceBuffer
        }
        if let conversionError {
            throw conversionError
        }

        guard let channel = targetBuffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(targetBuffer.frameLength)))
    }

    private func loadAudioCaptureEngine() async throws {
        if audioCaptureKit != nil { return }
        let started = Date()
        let captureConfig = WhisperKitConfig(
            model: config.whisperModel,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: false,
            download: false
        )
        audioCaptureKit = try await WhisperKit(captureConfig)
        traceLogger.log(
            "Audio capture engine ready seconds=\(String(format: "%.3f", Date().timeIntervalSince(started))) model_loaded=0")
    }

    /// True when the full WhisperKit model is already on disk, so loading it
    /// costs time but no download.
    private var whisperModelIsLocallyAvailable: Bool {
        localWhisperModelFolder(for: config.whisperModel) != nil
    }

    private func loadWhisperKit() async throws {
        print("Loading WhisperKit model: \(config.whisperModel)")
        fflush(stdout)

        let localModelFolder = localWhisperModelFolder(for: config.whisperModel)
        var localTokenizerFolder = localWhisperTokenizerFolder(for: config.whisperModel)
        let downloadBase = whisperModelSearchRoots().first
        let shouldDownloadModel = localModelFolder == nil

        if localTokenizerFolder == nil {
            try await ensureLocalWhisperTokenizerIfPossible(for: config.whisperModel)
            localTokenizerFolder = localWhisperTokenizerFolder(for: config.whisperModel)
        }

        if let localModelFolder {
            traceLogger.log("Using local Whisper model folder=\(localModelFolder)")
        }
        if let localTokenizerFolder {
            traceLogger.log("Using local Whisper tokenizer folder=\(localTokenizerFolder.path)")
        } else {
            throw JarvisTapError.tokenizerUnavailable("No local tokenizer cache for \(config.whisperModel)")
        }
        if shouldDownloadModel, let downloadBase {
            traceLogger.log("Whisper model download base=\(downloadBase.path)")
        }

        let computeSelection = whisperComputeSelection()
        traceLogger.log("Whisper compute preset=\(computeSelection.label)")

        let wkConfig = WhisperKitConfig(
            model: config.whisperModel,
            downloadBase: downloadBase,
            modelFolder: localModelFolder,
            tokenizerFolder: localTokenizerFolder,
            computeOptions: computeSelection.options,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: shouldDownloadModel
        )

        let whisperKit = try await WhisperKit(wkConfig)
        guard let tokenizer = whisperKit.tokenizer else {
            throw JarvisTapError.whisperUnavailable
        }

        let transcriber = AudioStreamTranscriber(
            audioEncoder: whisperKit.audioEncoder,
            featureExtractor: whisperKit.featureExtractor,
            segmentSeeker: whisperKit.segmentSeeker,
            textDecoder: whisperKit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: whisperKit.audioProcessor,
            decodingOptions: decodingOptions
        ) { [weak self] oldState, newState in
            guard let self else { return }
            self.handleStreamingStateChange(oldState: oldState, newState: newState)
        }

        self.whisperKit = whisperKit
        self.streamTranscriber = transcriber
    }

    private var usesParakeetFinalBackend: Bool {
        switch config.asrBackend {
        case "parakeet", "parakeet-v3", "parakeet-v3-ane", "ane", "npu":
            return true
        default:
            return false
        }
    }

    private var fluidTrueStreamingVariant: StreamingModelVariant? {
        switch config.streamingASRBackend ?? config.asrBackend {
        case "parakeet-eou-160", "parakeet-eou-160ms":
            return .parakeetEou160ms
        case "parakeet-eou-320", "parakeet-eou-320ms":
            return .parakeetEou320ms
        case "parakeet-eou-1280", "parakeet-eou-1280ms":
            return .parakeetEou1280ms
        case "nemotron-560", "nemotron-560ms":
            return .nemotron560ms
        case "nemotron-1120", "nemotron-1120ms":
            return .nemotron1120ms
        case "nemotron-2240", "nemotron-2240ms", "nemotron":
            return .nemotron2240ms
        default:
            return nil
        }
    }

    private var usesFluidTrueStreamingBackend: Bool {
        fluidTrueStreamingVariant != nil
    }

    private func currentASRModeDescription() -> String {
        if usesParakeetFinalBackend, let fluidTrueStreamingVariant {
            let streamingMode = fluidTrueStreamingVariant.rawValue.replacingOccurrences(of: "-", with: "_")
            return config.streamingTranscriptionEnabled
                ? "parakeet_v3_ane_final_pass_with_\(streamingMode)_true_streaming_partials"
                : "parakeet_v3_ane_final_pass"
        }

        if let fluidTrueStreamingVariant {
            let baseMode = fluidTrueStreamingVariant.rawValue.replacingOccurrences(of: "-", with: "_")
            return config.streamingTranscriptionEnabled
                ? "\(baseMode)_true_streaming"
                : "\(baseMode)_final_pass"
        }

        if usesParakeetFinalBackend {
            return config.streamingTranscriptionEnabled
                ? "parakeet_v3_ane_final_pass_with_realtime_whisper_partials"
                : "parakeet_v3_ane_final_pass"
        }

        return config.streamingTranscriptionEnabled
            ? "realtime_whisper_partials_with_offline_finalize"
            : "offline_whisper_final_pass"
    }

    private func loadParakeetV3ANE() async throws {
        traceLogger.log("Loading Parakeet v3 ASR backend compute=cpuAndNeuralEngine")
        let loadStart = Date()
        let configuration = AsrModels.defaultConfiguration()
        let models = try await AsrModels.downloadAndLoad(
            configuration: configuration,
            version: .v3,
            encoderComputeUnits: nil
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        let decoderLayerCount = await manager.decoderLayerCount
        parakeetAsrManager = manager
        parakeetDecoderLayerCount = decoderLayerCount
        traceLogger.log(
            "Parakeet v3 ASR ready load_seconds=\(String(format: "%.2f", Date().timeIntervalSince(loadStart))) decoder_layers=\(decoderLayerCount)"
        )
    }

    private func loadFluidTrueStreamingASR() async throws {
        guard let variant = fluidTrueStreamingVariant else { return }
        traceLogger.log("Loading FluidAudio true streaming ASR backend=\(config.streamingASRBackend ?? config.asrBackend) variant=\(variant.rawValue) compute=cpuAndNeuralEngine")
        let loadStart = Date()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let manager = variant.createManager(configuration: configuration)
        try await manager.loadModels()
        let displayName = await manager.displayName
        fluidStreamingAsrManager = manager
        traceLogger.log(
            "FluidAudio true streaming ASR ready backend=\(config.streamingASRBackend ?? config.asrBackend) variant=\(variant.rawValue) display_name=\(displayName) load_seconds=\(String(format: "%.2f", Date().timeIntervalSince(loadStart)))"
        )
    }

    private func parakeetLanguageHint() -> Language? {
        switch settingsStore.preferredLanguage {
        case .auto:
            return nil
        case .german:
            return .german
        case .english:
            return .english
        }
    }

    private func transcribeParakeetV3ANE(samples: [Float]) async throws -> ParakeetTranscriptCandidate {
        guard let parakeetAsrManager else {
            throw JarvisTapError.whisperUnavailable
        }

        var decoderState = TdtDecoderState.make(decoderLayers: parakeetDecoderLayerCount)
        let language = parakeetLanguageHint()
        let startedAt = Date()
        let result = try await parakeetAsrManager.transcribe(
            samples,
            decoderState: &decoderState,
            language: language
        )
        traceLogger.log(
            "Parakeet v3 ASR pass completed samples=\(samples.count) inference_seconds=\(String(format: "%.3f", Date().timeIntervalSince(startedAt))) confidence=\(String(format: "%.3f", Double(result.confidence))) language=\(settingsStore.preferredLanguage.rawValue)"
        )
        return ParakeetTranscriptCandidate(
            text: cleanedTranscriptText(result.text),
            confidence: Double(result.confidence)
        )
    }

    private func makeStreamTranscriber(using whisperKit: WhisperKit) throws -> AudioStreamTranscriber {
        guard let tokenizer = whisperKit.tokenizer else {
            throw JarvisTapError.whisperUnavailable
        }

        return AudioStreamTranscriber(
            audioEncoder: whisperKit.audioEncoder,
            featureExtractor: whisperKit.featureExtractor,
            segmentSeeker: whisperKit.segmentSeeker,
            textDecoder: whisperKit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: whisperKit.audioProcessor,
            decodingOptions: decodingOptions
        ) { [weak self] oldState, newState in
            guard let self else { return }
            self.handleStreamingStateChange(oldState: oldState, newState: newState)
        }
    }

    private func makeMonoPCMBuffer(samples: ArraySlice<Float>) throws -> AVAudioPCMBuffer {
        guard !samples.isEmpty else {
            throw JarvisTapError.audioBufferUnavailable
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(WhisperKit.sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw JarvisTapError.audioBufferUnavailable
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw JarvisTapError.audioBufferUnavailable
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else {
            throw JarvisTapError.audioBufferUnavailable
        }
        samples.withUnsafeBufferPointer { sampleBuffer in
            if let baseAddress = sampleBuffer.baseAddress {
                channel.update(from: baseAddress, count: sampleBuffer.count)
            }
        }
        return buffer
    }

    private func resetStreamingSession() throws {
        guard let audioCaptureKit else {
            throw JarvisTapError.whisperUnavailable
        }

        traceLogger.log("Resetting Whisper streaming session")
        safelyStopLiveAudioRecording(captureKit: audioCaptureKit, reason: "reset_streaming_session")
        audioCaptureKit.audioProcessor.purgeAudioSamples(keepingLast: 0)
        fluidStreamingFedSampleCount = 0
        // Only the WhisperKit-backed streaming preview needs the full model.
        if let whisperKit {
            streamTranscriber = try makeStreamTranscriber(using: whisperKit)
        } else {
            streamTranscriber = nil
        }
    }

    /// Reads the live audio device and asks `AudioInputPreflightPolicy` whether
    /// it is safe to hand to WhisperKit.
    ///
    /// The decision lives in PressTalkCore so it can be tested; only the device
    /// read is here. See AudioInputPreflightPolicy for why this guard exists --
    /// short version: installTapOnBus raises an ObjC exception that Swift cannot
    /// catch, and it killed the app three times in six days.
    private static func audioInputPreflightFailure() -> String? {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardware = input.inputFormat(forBus: 0)
        let output = input.outputFormat(forBus: 0)
        let buildable = AVAudioFormat(commonFormat: output.commonFormat,
                                      sampleRate: hardware.sampleRate,
                                      channels: output.channelCount,
                                      interleaved: output.isInterleaved) != nil
        return AudioInputPreflightPolicy().failureReason(
            hardwareSampleRate: hardware.sampleRate,
            nodeSampleRate: output.sampleRate,
            nodeChannelCount: output.channelCount,
            canBuildTapFormat: buildable)
    }

    private func safelyStopLiveAudioRecording(captureKit: WhisperKit?, reason: String) {
        guard let audioProcessor = captureKit?.audioProcessor else { return }

        var retiredID: ObjectIdentifier?

        audioEngineStopLock.lock()
        if let processor = audioProcessor as? AudioProcessor,
           let engine = processor.audioEngine {
            retiredID = ObjectIdentifier(engine)
            traceLogger.log("Stopping live audio recording safely reason=\(reason)")
            processor.audioBufferCallback = nil

            engine.inputNode.removeTap(onBus: 0)
            for node in engine.attachedNodes {
                node.removeTap(onBus: 0)
            }
            engine.disconnectNodeInput(engine.inputNode)
            engine.stop()
            engine.reset()

            retiredAudioEngines.append((id: ObjectIdentifier(engine), engine: engine, retiredAt: Date()))
            pruneRetiredAudioEnginesLocked()
            processor.audioEngine = nil
        } else {
            audioProcessor.stopRecording()
        }
        audioEngineStopLock.unlock()

        // The microphone is released, so the system default can go back to
        // whatever the user had before PressTalk borrowed it. Only ever set
        // when they explicitly chose a non-default device.
        restoreDisplacedDefaultInputDevice()

        guard let retiredID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + retiredAudioEngineRetainSeconds) { [weak self] in
            self?.releaseRetiredAudioEngine(id: retiredID)
        }
    }

    private func pruneRetiredAudioEnginesLocked(now: Date = Date()) {
        retiredAudioEngines.removeAll {
            now.timeIntervalSince($0.retiredAt) >= retiredAudioEngineRetainSeconds
        }
        if retiredAudioEngines.count > retiredAudioEngineLimit {
            retiredAudioEngines.removeFirst(retiredAudioEngines.count - retiredAudioEngineLimit)
        }
    }

    private func releaseRetiredAudioEngine(id: ObjectIdentifier) {
        audioEngineStopLock.lock()
        retiredAudioEngines.removeAll { $0.id == id }
        pruneRetiredAudioEnginesLocked()
        audioEngineStopLock.unlock()
    }

    private func localWhisperModelFolder(for model: String) -> String? {
        for root in whisperModelSearchRoots() {
            for folder in localWhisperModelFolderCandidates(root: root, model: model) {
                if isUsableLocalWhisperModelFolder(folder, model: model) {
                    return folder.path
                }
                if FileManager.default.fileExists(atPath: folder.path) {
                    traceLogger.log("Ignoring incomplete local Whisper model folder=\(folder.path)")
                }
            }
        }
        return nil
    }

    private func localWhisperModelFolderCandidates(root: URL, model: String) -> [URL] {
        let repositoryPath = "argmaxinc/whisperkit-coreml"
        return [
            root
                .appendingPathComponent(repositoryPath, isDirectory: true)
                .appendingPathComponent(model, isDirectory: true),
            root
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(repositoryPath, isDirectory: true)
                .appendingPathComponent(model, isDirectory: true),
        ]
    }

    private func localWhisperTokenizerFolder(for model: String) -> URL? {
        guard let tokenizerModelName = whisperTokenizerModelName(for: model) else { return nil }

        for root in whisperTokenizerSearchRoots() {
            for folder in localWhisperTokenizerFolderCandidates(root: root, tokenizerModelName: tokenizerModelName) {
                let tokenizerPath = folder.appendingPathComponent("tokenizer.json")
                let tokenizerConfigPath = folder.appendingPathComponent("tokenizer_config.json")
                if FileManager.default.fileExists(atPath: tokenizerPath.path),
                   FileManager.default.fileExists(atPath: tokenizerConfigPath.path)
                {
                    return folder
                }
            }
        }
        return nil
    }

    private func whisperTokenizerModelName(for model: String) -> String? {
        switch model {
        case let name where name.contains("whisper-large-v3"):
            return "whisper-large-v3"
        case "openai_whisper-tiny":
            return "whisper-tiny"
        default:
            return nil
        }
    }

    private func localWhisperTokenizerFolderCandidates(root: URL, tokenizerModelName: String) -> [URL] {
        return [
            root
                .appendingPathComponent("openai", isDirectory: true)
                .appendingPathComponent(tokenizerModelName, isDirectory: true),
            root
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("openai", isDirectory: true)
                .appendingPathComponent(tokenizerModelName, isDirectory: true),
        ]
    }

    private func ensureLocalWhisperTokenizerIfPossible(for model: String) async throws {
        guard let tokenizerModelName = whisperTokenizerModelName(for: model),
              let root = whisperTokenizerSearchRoots().first
        else { return }

        let targetFolder = root
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("openai", isDirectory: true)
            .appendingPathComponent(tokenizerModelName, isDirectory: true)
        let requiredFiles = ["tokenizer.json", "tokenizer_config.json"]
        let fileManager = FileManager.default
        if requiredFiles.allSatisfy({ fileManager.fileExists(atPath: targetFolder.appendingPathComponent($0).path) }) {
            return
        }

        traceLogger.log("Prefetching Whisper tokenizer cache model=openai/\(tokenizerModelName) target=\(targetFolder.path)")
        try fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)

        for fileName in requiredFiles {
            let destination = targetFolder.appendingPathComponent(fileName)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            let urlString = "https://huggingface.co/openai/\(tokenizerModelName)/resolve/main/\(fileName)"
            guard let url = URL(string: urlString) else {
                throw JarvisTapError.tokenizerUnavailable("Invalid tokenizer URL for \(fileName)")
            }
            try await downloadTokenizerFile(from: url, to: destination)
        }
        traceLogger.log("Whisper tokenizer cache ready folder=\(targetFolder.path)")
    }

    private func downloadTokenizerFile(from url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw JarvisTapError.tokenizerUnavailable("Download failed status=\(statusCode) url=\(url.absoluteString)")
        }
        let temporaryURL = destination.appendingPathExtension("tmp")
        try data.write(to: temporaryURL, options: [.atomic])
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        traceLogger.log("Downloaded Whisper tokenizer file=\(destination.lastPathComponent) bytes=\(data.count)")
    }

    private func whisperTokenizerSearchRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/JarvisTap/Tokenizers", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/JarvisTap/Models", isDirectory: true),
        ]
    }

    private func whisperModelSearchRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/JarvisTap/Models", isDirectory: true),
        ]
    }

    private func isUsableLocalWhisperModelFolder(_ folder: URL, model: String) -> Bool {
        let fileManager = FileManager.default
        let requiredFiles = requiredWhisperModelFiles(for: model)
        guard !requiredFiles.isEmpty else {
            return fileManager.fileExists(atPath: folder.path)
        }

        for relativePath in requiredFiles {
            let path = folder.appendingPathComponent(relativePath).path
            guard fileManager.fileExists(atPath: path) else {
                return false
            }
        }
        return true
    }

    private func requiredWhisperModelFiles(for model: String) -> [String] {
        switch model {
        case let name where name.contains("whisper-large-v3") && name.contains("turbo"):
            return [
                "config.json",
                "generation_config.json",
                "AudioEncoder.mlmodelc/model.mil",
                "AudioEncoder.mlmodelc/weights/weight.bin",
                "MelSpectrogram.mlmodelc/model.mil",
                "MelSpectrogram.mlmodelc/weights/weight.bin",
                "TextDecoder.mlmodelc/model.mil",
                "TextDecoder.mlmodelc/weights/weight.bin",
                "TextDecoderContextPrefill.mlmodelc/model.mil",
                "TextDecoderContextPrefill.mlmodelc/weights/weight.bin",
            ]
        case let name where name.contains("whisper-large-v3"):
            return [
                "config.json",
                "generation_config.json",
                "AudioEncoder.mlmodelc/model.mil",
                "AudioEncoder.mlmodelc/weights/weight.bin",
                "MelSpectrogram.mlmodelc/model.mil",
                "MelSpectrogram.mlmodelc/weights/weight.bin",
                "TextDecoder.mlmodelc/model.mil",
                "TextDecoder.mlmodelc/weights/weight.bin",
            ]
        case "openai_whisper-tiny":
            return [
                "config.json",
                "generation_config.json",
                "AudioEncoder.mlmodelc/model.mil",
                "AudioEncoder.mlmodelc/weights/weight.bin",
                "MelSpectrogram.mlmodelc/model.mil",
                "MelSpectrogram.mlmodelc/weights/weight.bin",
                "TextDecoder.mlmodelc/model.mil",
                "TextDecoder.mlmodelc/weights/weight.bin",
            ]
        default:
            return []
        }
    }

    private func installDarwinTriggerNotifications() {
        guard !darwinNotificationObserverInstalled else { return }

        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer, let rawName = name?.rawValue as String? else { return }
            let app = Unmanaged<JarvisTapApp>.fromOpaque(observer).takeUnretainedValue()
            app.handleDarwinTriggerNotification(named: rawName)
        }

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            observer,
            callback,
            DarwinTriggerNotification.press as CFString,
            nil,
            .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center,
            observer,
            callback,
            DarwinTriggerNotification.release as CFString,
            nil,
            .deliverImmediately
        )

        darwinNotificationObserverInstalled = true
        traceLogger.log("Darwin trigger notifications installed")
    }

    private func handleDarwinTriggerNotification(named name: String) {
        traceLogger.log("Darwin trigger notification received name=\(name)")
        DispatchQueue.main.async { [self] in
            // The notification normally exists for the F5 bridge. The test
            // harness reuses it as a headless trigger, because there is no way
            // to hold a physical key from a script and an unexercised paste path
            // is how silent regressions ship.
            guard settingsStore.triggerKey == .f5 || config.testHarnessEnabled else {
                traceLogger.log("Darwin trigger notification ignored reason=trigger_key_not_f5 selected=\(settingsStore.triggerKey.rawValue)")
                return
            }
            switch name {
            case DarwinTriggerNotification.press:
                handlePress(.configuredKey, source: .darwinNotification)
            case DarwinTriggerNotification.release:
                handleRelease(.configuredKey, source: .darwinNotification)
            default:
                break
            }
        }
    }

    private func productionInsertionProbePayloadURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JarvisTap", isDirectory: true)
            .appendingPathComponent(ProductionInsertionProbeNotification.payloadFileName)
    }

    private func productionInsertionProbeMarkerURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JarvisTap", isDirectory: true)
            .appendingPathComponent(ProductionInsertionProbeNotification.markerFileName)
    }

    private func installProductionInsertionProbeNotification() {
        guard !productionInsertionProbeObserverInstalled else { return }

        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer, let rawName = name?.rawValue as String? else { return }
            let app = Unmanaged<JarvisTapApp>.fromOpaque(observer).takeUnretainedValue()
            app.handleProductionInsertionProbeNotification(named: rawName)
        }

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            callback,
            ProductionInsertionProbeNotification.insert as CFString,
            nil,
            .deliverImmediately
        )

        productionInsertionProbeObserverInstalled = true
        traceLogger.log("Production insertion probe notification installed")
    }

    private func handleProductionInsertionProbeNotification(named name: String) {
        guard name == ProductionInsertionProbeNotification.insert else { return }
        traceLogger.log("Production insertion probe notification received")
        DispatchQueue.main.async { [self] in
            do {
                let markerURL = productionInsertionProbeMarkerURL()
                let markerAttributes = try FileManager.default.attributesOfItem(atPath: markerURL.path)
                guard let markerModifiedAt = markerAttributes[.modificationDate] as? Date else {
                    traceLogger.log("Production insertion probe ignored reason=marker_timestamp_missing")
                    return
                }
                guard abs(markerModifiedAt.timeIntervalSinceNow) <= ProductionInsertionProbeNotification.markerMaxAgeSeconds else {
                    traceLogger.log("Production insertion probe ignored reason=marker_stale")
                    return
                }

                let payload = try String(
                    contentsOf: productionInsertionProbePayloadURL(),
                    encoding: .utf8
                ).trimmingCharacters(in: .newlines)
                guard !payload.isEmpty else {
                    traceLogger.log("Production insertion probe ignored reason=empty_payload")
                    return
                }

                let result = try insertTranscriptIntoFocusedApp(payload, context: .productionProbe)
                switch result {
                case .inserted(let method):
                    traceLogger.log("Production insertion probe inserted method=\(method)")
                case .pasteCommandPosted:
                    traceLogger.log("Production insertion probe paste command posted")
                case .copiedFallback(let reason):
                    traceLogger.log("Production insertion probe copied fallback reason=\(reason)")
                }
            } catch {
                if (error as NSError).domain == NSCocoaErrorDomain &&
                    (error as NSError).code == NSFileReadNoSuchFileError {
                    traceLogger.log("Production insertion probe ignored reason=marker_or_payload_missing")
                } else {
                    traceLogger.log("Production insertion probe failed error=\(error)")
                }
            }
        }
    }

    private func installInputTriggerListener() -> Bool {
        if settingsStore.triggerKey == .optionSpace {
            return installRegisteredHotKey()
        }
        return installEventTap()
    }

    private func installRegisteredHotKey() -> Bool {
        if registeredHotKeyRef != nil {
            eventTapInstallSummary = "carbon:registered"
            return true
        }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        var handlerRef: EventHandlerRef?
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else {
                return noErr
            }

            let app = Unmanaged<JarvisTapApp>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let parameterStatus = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard parameterStatus == noErr,
                  hotKeyID.signature == app.registeredHotKeySignature,
                  hotKeyID.id == app.optionSpaceHotKeyID
            else {
                return noErr
            }

            let eventKind = GetEventKind(eventRef)
            DispatchQueue.main.async { [weak app] in
                guard let app else { return }
                if eventKind == UInt32(kEventHotKeyPressed) {
                    app.handlePress(.configuredKey, source: .registeredHotKey)
                } else if eventKind == UInt32(kEventHotKeyReleased) {
                    app.handleRelease(.configuredKey, source: .registeredHotKey)
                }
            }
            return noErr
        }

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            eventTypes.count,
            &eventTypes,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &handlerRef
        )
        guard handlerStatus == noErr, let handlerRef else {
            eventTapInstallSummary = "carbon:handler_failed_\(handlerStatus)"
            traceLogger.log("Registered hotkey handler install failed status=\(handlerStatus)")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: registeredHotKeySignature, id: optionSpaceHotKeyID)
        var hotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            optionSpaceHotKeyCode,
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr, let hotKeyRef else {
            RemoveEventHandler(handlerRef)
            eventTapInstallSummary = "carbon:register_failed_\(registerStatus)"
            traceLogger.log("Registered hotkey install failed status=\(registerStatus)")
            return false
        }

        registeredHotKeyEventHandler = handlerRef
        registeredHotKeyRef = hotKeyRef
        eventTapInstallSummary = "carbon:registered"
        traceLogger.log("Registered hotkey installed trigger=option_space")
        return true
    }

    private func installEventTap() -> Bool {
        let pointerEventTypes: [CGEventType] = [
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseUp,
        ]
        var mask = (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << systemDefinedEventType.rawValue)
        for eventType in pointerEventTypes {
            mask |= 1 << eventType.rawValue
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let app = Unmanaged<JarvisTapApp>.fromOpaque(userInfo).takeUnretainedValue()
            return app.handle(eventType: type, event: event)
        }

        let tapLocations: [(CGEventTapLocation, String)] = [
            (.cghidEventTap, "hid"),
            (.cgSessionEventTap, "session"),
        ]
        let tapOptions: [(CGEventTapOptions, String)] = {
            let listenOnly = (CGEventTapOptions.listenOnly, "listen_only")
            let writable = (CGEventTapOptions.defaultTap, "default")

            if settingsStore.triggerKey != .trackpadHold {
                return [writable, listenOnly]
            }
            return [listenOnly, writable]
        }()

        var selectedTap: CFMachPort?
        var selectedTapName = ""
        for (option, optionName) in tapOptions {
            for (location, locationName) in tapLocations {
                guard let tap = CGEvent.tapCreate(
                    tap: location,
                    place: option == .listenOnly ? .tailAppendEventTap : .headInsertEventTap,
                    options: option,
                    eventsOfInterest: CGEventMask(mask),
                    callback: callback,
                    userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
                ) else {
                    traceLogger.log("Global event tap create failed location=\(locationName) mode=\(optionName)")
                    continue
                }
                selectedTap = tap
                selectedTapName = "\(locationName):\(optionName)"
                break
            }
            if selectedTap != nil {
                break
            }
        }

        guard let tap = selectedTap else {
            eventTapInstallSummary = "failed"
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            eventTapInstallSummary = "\(selectedTapName):run_loop_source_failed"
            return false
        }

        eventTap = tap
        eventTapInstallSummary = selectedTapName
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        traceLogger.log("Global event tap installed location=\(selectedTapName)")
        return true
    }

    private func handle(eventType: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        switch eventType {
        case .leftMouseDown:
            recordPointerActivity(eventType: eventType)
            if settingsStore.triggerKey == .trackpadHold {
                handleTrackpadPointerDown(event)
            }
            return Unmanaged.passUnretained(event)
        case .leftMouseDragged:
            recordPointerActivity(eventType: eventType)
            if settingsStore.triggerKey == .trackpadHold {
                handleTrackpadPointerDragged(event)
            }
            return Unmanaged.passUnretained(event)
        case .leftMouseUp:
            recordPointerActivity(eventType: eventType)
            if settingsStore.triggerKey == .trackpadHold {
                handleTrackpadPointerUp(event)
            }
            return Unmanaged.passUnretained(event)
        case .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            recordPointerActivity(eventType: eventType)
            return Unmanaged.passUnretained(event)
        case .keyDown:
            if isConfiguredFunctionTriggerKeyCode(keyCode) {
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                traceInputDebug("cg keyDown keyCode=\(keyCode) repeat=\(isRepeat)")
                if !isRepeat {
                    handlePress(.configuredKey, source: .cgFunctionKey)
                }
                return nil
            }
        case .keyUp:
            if isConfiguredFunctionTriggerKeyCode(keyCode) {
                traceInputDebug("cg keyUp keyCode=\(keyCode)")
                handleRelease(.configuredKey, source: .cgFunctionKey)
                return nil
            }
        case .flagsChanged:
            if handleConfiguredModifierFlagsChanged(keyCode: keyCode, flags: event.flags) {
                return nil
            }
        case systemDefinedEventType:
            if handleSystemDefinedEvent(NSEvent(cgEvent: event), cgEvent: event) {
                return nil
            }
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func installSystemDefinedMonitor() {
        specialKeyMonitor = nil
    }

    private func handleSystemDefinedEvent(_ event: NSEvent?, cgEvent: CGEvent? = nil) -> Bool {
        guard let event else { return false }
        guard event.type == .systemDefined else { return false }

        let mediaKeyCode = rawMediaKeyCode(from: event.data1)
        let signature = signature(for: event, cgEvent: cgEvent)
        traceInputDebug(
            "systemDefined subtype=\(event.subtype.rawValue) mediaKeyCode=\(mediaKeyCode) data1=\(event.data1) data2=\(event.data2) keyboardType=\(signature.keyboardType) sourceStateID=\(signature.sourceStateID) modifiers=0x\(String(signature.modifierFlagsRaw, radix: 16))"
        )

        if event.subtype.rawValue == microphoneKeySubtype {
            recordNativeCalibrationCandidateIfNeeded(signature)
        }

        if matchesNativeMicrophoneSystemDefinedEvent(event, signature: signature, mediaKeyCode: mediaKeyCode) {
            guard settingsStore.triggerKey == .f5, nativeMicrophoneKeyEnabled() else {
                return false
            }
            if event.data2 == 1 {
                if hadRecentPointerActivity(windowSeconds: nativePointerCancellationWindowSeconds) {
                    let windowSeconds = String(format: "%.2f", nativePointerCancellationWindowSeconds)
                    traceLogger.log("Suppressed native microphone press due to recent pointer activity window_seconds=\(windowSeconds)")
                    return true
                }
                handlePress(.configuredKey, source: .nativeSystemDefined)
            } else if event.data2 == 0 {
                handleRelease(.configuredKey, source: .nativeSystemDefined)
            }
            return true
        }

        guard settingsStore.triggerKey == .f5 else { return false }
        guard event.subtype.rawValue == mediaKeySubtype else { return false }

        let matchesF5 = mediaKeyCode == Int(f5KeyCode)
        guard matchesF5 else { return false }

        let keyFlags = event.data1 & 0xFFFF
        let keyState = keyFlags & mediaKeyStateMask
        let isRepeat = (keyFlags & mediaKeyRepeatMask) != 0

        if keyState == mediaKeyDownState {
            if !isRepeat {
                handlePress(.configuredKey, source: .nativeSystemDefined)
            }
        } else if keyState == mediaKeyUpState {
            handleRelease(.configuredKey, source: .nativeSystemDefined)
        }
        return true
    }

    private func matchesNativeMicrophoneSystemDefinedEvent(
        _ event: NSEvent,
        signature: PressTalkNativeTriggerSignature,
        mediaKeyCode: Int
    ) -> Bool {
        if let calibration = settingsStore.nativeTriggerCalibration {
            return signature == calibration.press || signature == calibration.release
        }
        return isBroadNativeMicrophoneSystemDefinedEvent(event, mediaKeyCode: mediaKeyCode)
    }

    private func isBroadNativeMicrophoneSystemDefinedEvent(_ event: NSEvent, mediaKeyCode: Int) -> Bool {
        guard event.subtype.rawValue == microphoneKeySubtype else { return false }
        guard mediaKeyCode == 0 else { return false }
        guard event.data1 == 1 else { return false }
        return event.data2 == 0 || event.data2 == 1
    }

    private func rawMediaKeyCode(from data1: Int) -> Int {
        Int((UInt32(bitPattern: Int32(data1)) >> 16) & 0xFFFF)
    }

    private func isPointerActivityEventType(_ eventType: CGEventType) -> Bool {
        switch eventType {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp,
             .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp:
            return true
        default:
            return false
        }
    }

    private func recordPointerActivity(eventType: CGEventType) {
        var shouldLog = false
        withStateLock {
            lastPointerEventAt = Date()
            if !firstPointerEventLogged {
                firstPointerEventLogged = true
                shouldLog = true
            }
        }
        if shouldLog {
            traceLogger.log("Pointer event observed type=\(eventType.rawValue)")
            refreshRuntimeStatusUI()
        }
    }

    private func handleTrackpadPointerDown(_ event: CGEvent) {
        let location = pointerLocation()
        let pressure = pointerPressure(from: event)
        traceLogger.log(
            "Trackpad pointer down observed location=\(formattedPoint(location)) pressure=\(String(format: "%.2f", pressure))"
        )

        let workItem: DispatchWorkItem? = withStateLock {
            guard !isRecording, !isProcessing else { return nil }

            trackpadArmWorkItem?.cancel()
            trackpadHoldState = TrackpadHoldState(
                downLocation: location,
                downAt: Date(),
                currentLocation: location,
                maxDistance: 0,
                latestPressure: pressure
            )

            let workItem = DispatchWorkItem { [weak self] in
                self?.armTrackpadHoldIfEligible()
            }
            trackpadArmWorkItem = workItem
            return workItem
        }

        guard let workItem else { return }

        traceLogger.log(
            "Trackpad hold pending location=\(formattedPoint(location)) delay_seconds=\(String(format: "%.2f", trackpadHoldDelaySeconds)) pressure=\(String(format: "%.2f", pressure))"
        )
        startTrackpadPreview()
        DispatchQueue.main.asyncAfter(deadline: .now() + trackpadHoldDelaySeconds, execute: workItem)
    }

    private func handleTrackpadPointerDragged(_ event: CGEvent) {
        let location = pointerLocation()
        let pressure = pointerPressure(from: event)

        enum DragOutcome {
            case none
            case cancelPending(CGFloat)
            case cancelRecording(CGFloat)
        }

        let outcome: DragOutcome = withStateLock {
            guard var holdState = trackpadHoldState else { return .none }

            holdState.currentLocation = location
            holdState.latestPressure = max(holdState.latestPressure, pressure)
            let distance = hypot(
                holdState.currentLocation.x - holdState.downLocation.x,
                holdState.currentLocation.y - holdState.downLocation.y
            )
            holdState.maxDistance = max(holdState.maxDistance, distance)
            trackpadHoldState = holdState

            guard distance >= trackpadHoldCancelDistancePoints else {
                return .none
            }
            return holdState.armed ? .cancelRecording(distance) : .cancelPending(distance)
        }

        switch outcome {
        case .none:
            break
        case .cancelPending(let distance):
            cancelTrackpadHold(reason: "moved_before_arm", distance: distance)
        case .cancelRecording(let distance):
            cancelTrackpadHold(reason: "moved_after_arm", distance: distance)
        }
    }

    private func handleTrackpadPointerUp(_ event: CGEvent) {
        let location = pointerLocation()
        let pressure = pointerPressure(from: event)

        let armed = withStateLock { () -> Bool in
            trackpadArmWorkItem?.cancel()
            trackpadArmWorkItem = nil

            guard var holdState = trackpadHoldState else { return false }
            holdState.currentLocation = location
            holdState.latestPressure = max(holdState.latestPressure, pressure)
            trackpadHoldState = nil
            return holdState.armed
        }

        if armed {
            traceLogger.log("Trackpad hold released location=\(formattedPoint(location))")
            handleRelease(.trackpadHold, source: .trackpadHold)
            return
        }

        cancelTrackpadPrearmCaptureSilently()
        stopTrackpadPreview(hideLight: true)
        traceLogger.log("Trackpad hold released before arm location=\(formattedPoint(location))")
    }

    private func armTrackpadHoldIfEligible() {
        let shouldArm: Bool = withStateLock {
            guard var holdState = trackpadHoldState, !holdState.armed else {
                trackpadArmWorkItem = nil
                return false
            }

            let distance = hypot(
                holdState.currentLocation.x - holdState.downLocation.x,
                holdState.currentLocation.y - holdState.downLocation.y
            )
            guard distance < trackpadHoldCancelDistancePoints else {
                trackpadArmWorkItem = nil
                trackpadHoldState = nil
                return false
            }

            holdState.armed = true
            trackpadHoldState = holdState
            trackpadArmWorkItem = nil
            return true
        }

        guard shouldArm else {
            stopTrackpadPreview(hideLight: true)
            return
        }

        stopTrackpadPreview(hideLight: false)
        traceLogger.log("Trackpad hold armed")
        let recordingStarted = withStateLock {
            isRecording && activeTrigger == .trackpadHold
        }
        if recordingStarted {
            traceLogger.log(triggerStartLogMessage(for: .trackpadHold))
            present(.listening(nil))
            startAmplitudeMonitoring()
        } else {
            handlePress(.trackpadHold, source: .trackpadHold)
        }

        let promotedRecordingStarted = withStateLock {
            isRecording && activeTrigger == .trackpadHold
        }
        if !promotedRecordingStarted {
            withStateLock {
                trackpadHoldState = nil
            }
            stopTrackpadPreview(hideLight: true)
        }
    }

    private func cancelTrackpadPrearmCaptureSilently() {
        var streamTaskToCancel: Task<Void, Never>?
        var shouldResetStreamingSession = false

        withStateLock {
            guard isRecording, activeTrigger == .trackpadHold else { return }
            isRecording = false
            activeTrigger = nil
            activeTriggerSource = nil
            activeTriggerStartedAt = nil
            activeCaptureEngineStarted = false
            streamTaskToCancel = streamTask
            streamTask = nil
            latestStreamingState = StreamingSnapshot()
            lastPrintedPartial = ""
            shouldResetStreamingSession = true
        }

        guard shouldResetStreamingSession else { return }

        traceLogger.log("Trackpad prearm capture cancelled before visible arm")
        streamTaskToCancel?.cancel()
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if let transcriber = self.streamTranscriber {
                await transcriber.stopStreamTranscription()
            }
            try? self.resetStreamingSession()
        }
    }

    private func startTrackpadPreview() {
        stopTrackpadPreview(hideLight: false)

        let task = Task(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let holdState = self.withStateLock({ self.trackpadHoldState }), !holdState.armed else {
                    return
                }

                let bands = self.previewLightBands(for: holdState)
                let verticalLift = self.previewLightVerticalLift(for: holdState)
                let alpha = self.previewLightAlpha(for: holdState)
                await MainActor.run { [weak self] in
                    guard let self, self.settingsStore.showHUD else { return }
                    self.hudController?.updateListeningLight(
                        bands: bands,
                        anchorPoint: holdState.downLocation,
                        verticalLift: verticalLift,
                        alpha: alpha
                    )
                }

                let sleepNanoseconds = UInt64(self.trackpadPreviewTickSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
            }
        }

        withStateLock {
            trackpadPreviewTask = task
        }
    }

    private func stopTrackpadPreview(hideLight: Bool) {
        let task = withStateLock { () -> Task<Void, Never>? in
            let existing = trackpadPreviewTask
            trackpadPreviewTask = nil
            return existing
        }
        task?.cancel()

        guard hideLight else { return }
        let shouldHide = withStateLock { !isRecording }
        guard shouldHide else { return }
        DispatchQueue.main.async { [weak self] in
            self?.hudController?.hide()
        }
    }

    private func cancelTrackpadHold(reason: String, distance: CGFloat) {
        var streamTaskToCancel: Task<Void, Never>?
        var shouldResetStreamingSession = false
        var captureDurationSeconds = 0.0
        var wasAudible = false
        var hadTranscriptEvidence = false

        withStateLock {
            trackpadArmWorkItem?.cancel()
            trackpadArmWorkItem = nil
            trackpadHoldState = nil

            guard isRecording,
                  activeTrigger == .trackpadHold
            else {
                return
            }

            if let activeTriggerStartedAt {
                captureDurationSeconds = Date().timeIntervalSince(activeTriggerStartedAt)
            }
            let captureStats = currentTrackpadCaptureStats()
            wasAudible = captureStats.audible
            hadTranscriptEvidence = captureStats.transcriptEvidence
            captureDurationSeconds = max(captureDurationSeconds, captureStats.durationSeconds)

            isRecording = false
            activeTrigger = nil
            activeTriggerSource = nil
            activeTriggerStartedAt = nil
            activeCaptureEngineStarted = false
            streamTaskToCancel = streamTask
            streamTask = nil
            latestStreamingState = StreamingSnapshot()
            lastPrintedPartial = ""
            shouldResetStreamingSession = true
        }

        stopTrackpadPreview(hideLight: true)
        traceLogger.log(
            "Trackpad hold cancelled reason=\(reason) distance=\(String(format: "%.2f", distance)) duration_seconds=\(String(format: "%.2f", captureDurationSeconds)) audible=\(wasAudible ? 1 : 0) transcript_evidence=\(hadTranscriptEvidence ? 1 : 0)"
        )

        guard shouldResetStreamingSession else { return }

        stopAmplitudeMonitoring()
        streamTaskToCancel?.cancel()
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if let transcriber = self.streamTranscriber {
                await transcriber.stopStreamTranscription()
            }
            try? self.resetStreamingSession()
        }

        guard captureDurationSeconds >= 1.0 else { return }
        if wasAudible {
            guard settingsStore.showAbortPopups else { return }
            present(.aborted("Transcribing aborted through movement. Press and stay there to record. Let go to paste."))
            return
        }
        present(.error("I didn’t catch any clear speech."))
    }

    private func currentTrackpadCaptureStats() -> (durationSeconds: Double, audible: Bool, transcriptEvidence: Bool) {
        let samples = currentLiveCapturedAudioSamples()
        let stats = audioLevelStats(for: samples)
        let durationSeconds = Double(samples.count) / Double(WhisperKit.sampleRate)
        let transcriptEvidence = !bestTranscriptCandidate(from: [
            latestStreamingState.confirmedText,
            latestStreamingState.unconfirmedText,
            latestStreamingState.currentText,
        ]).isEmpty
        let audible = transcriptEvidence || stats.rms >= 0.0025 || stats.peak >= 0.03
        return (durationSeconds, audible, transcriptEvidence)
    }

    private func previewLightBands(for holdState: TrackpadHoldState) -> VoiceLightBands {
        let elapsed = Date().timeIntervalSince(holdState.downAt)
        let progress = min(max(elapsed / trackpadHoldDelaySeconds, 0), 1)
        let appearance = min(max(pow(progress, 1.65), 0), 1)
        let normalizedDistance = min(
            max(Double(holdState.maxDistance / trackpadHoldCancelDistancePoints), 0),
            1
        )
        let stability = 1 - normalizedDistance
        let pressure = min(max(holdState.latestPressure, 0), 1)
        let pulse = 0.5 + (0.5 * sin(elapsed * 10))

        return VoiceLightBands(
            low: min(1.0, (0.015 + (appearance * 0.19) + (stability * 0.08) + (pressure * 0.04)) * max(0.20, appearance)),
            mid: min(1.0, (0.012 + (appearance * 0.22) + (pulse * 0.05) + (pressure * 0.06)) * max(0.20, appearance)),
            high: min(1.0, (0.010 + (appearance * 0.16) + ((1 - stability) * 0.10) + (pressure * 0.10)) * max(0.20, appearance))
        )
    }

    private func previewLightVerticalLift(for holdState: TrackpadHoldState) -> CGFloat {
        0
    }

    private func previewLightAlpha(for holdState: TrackpadHoldState) -> CGFloat {
        let rawProgress = min(max(Date().timeIntervalSince(holdState.downAt) / trackpadHoldDelaySeconds, 0), 1)
        let delayedProgress = min(max((rawProgress - 0.5) / 0.5, 0), 1)
        let eased = min(max(pow(delayedProgress, 1.8), 0), 1)
        return CGFloat(eased * 0.96)
    }

    private func pointerPressure(from event: CGEvent) -> Double {
        let rawPressure = event.getDoubleValueField(.mouseEventPressure)
        if rawPressure > 0 {
            return min(max(rawPressure, 0), 1)
        }
        if let event = NSEvent(cgEvent: event), event.pressure > 0 {
            return min(max(Double(event.pressure), 0), 1)
        }
        return 0
    }

    private func pointerLocation() -> CGPoint {
        NSEvent.mouseLocation
    }

    private func formattedPoint(_ point: CGPoint) -> String {
        "(\(String(format: "%.0f", point.x)), \(String(format: "%.0f", point.y)))"
    }

    private func hadRecentPointerActivity(windowSeconds: TimeInterval = 0.18) -> Bool {
        withStateLock {
            guard let lastPointerEventAt else { return false }
            let delta = Date().timeIntervalSince(lastPointerEventAt)
            return delta >= 0 && delta < windowSeconds
        }
    }

    private func cancelSpuriousNativeRecordingIfNeeded() {
        var streamTaskToCancel: Task<Void, Never>?
        var shouldCancel = false

        withStateLock {
            guard isRecording,
                  activeTrigger == .configuredKey,
                  activeTriggerSource == .nativeSystemDefined,
                  let activeTriggerStartedAt
            else {
                return
            }

            let delta = Date().timeIntervalSince(activeTriggerStartedAt)
            guard delta >= 0, delta < nativePointerCancellationWindowSeconds else {
                return
            }

            isRecording = false
            activeTrigger = nil
            activeTriggerSource = nil
            self.activeTriggerStartedAt = nil
            activeCaptureEngineStarted = false
            streamTaskToCancel = streamTask
            streamTask = nil
            latestStreamingState = StreamingSnapshot()
            lastPrintedPartial = ""
            shouldCancel = true
        }

        guard shouldCancel else { return }

        let windowSeconds = String(format: "%.2f", nativePointerCancellationWindowSeconds)
        traceLogger.log("Cancelled native recording due to immediate pointer activity window_seconds=\(windowSeconds)")
        stopAmplitudeMonitoring()
        streamTaskToCancel?.cancel()
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if let transcriber = self.streamTranscriber {
                await transcriber.stopStreamTranscription()
            }
            try? self.resetStreamingSession()
        }
        present(.ready)
    }

    private func isConfiguredFunctionTriggerKeyCode(_ keyCode: CGKeyCode) -> Bool {
        guard settingsStore.triggerKey == .f5 else { return false }
        return keyCode == f5KeyCode || keyCode == remappedMicrophoneKeyCode
    }

    private func handleConfiguredModifierFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        let triggerKey = settingsStore.triggerKey
        guard isModifierTriggerKey(triggerKey) else { return false }
        guard modifierEventMatchesConfiguredTrigger(keyCode: keyCode, triggerKey: triggerKey) else { return false }

        let isPressed = modifierTriggerIsPressed(triggerKey, flags: flags)
        traceInputDebug("cg flagsChanged keyCode=\(keyCode) trigger=\(triggerKey.rawValue) pressed=\(isPressed)")
        if isPressed {
            handlePress(.configuredKey, source: .modifierKey)
        } else {
            handleRelease(.configuredKey, source: .modifierKey)
        }
        return true
    }

    private func isModifierTriggerKey(_ triggerKey: JarvisTapSettingsStore.TriggerKeyOption) -> Bool {
        switch triggerKey {
        case .fn, .option, .leftOption, .rightOption:
            return true
        case .optionSpace, .f5, .trackpadHold:
            return false
        }
    }

    private func modifierEventMatchesConfiguredTrigger(
        keyCode: CGKeyCode,
        triggerKey: JarvisTapSettingsStore.TriggerKeyOption
    ) -> Bool {
        switch triggerKey {
        case .fn:
            return keyCode == CGKeyCode(kVK_Function)
        case .option:
            return keyCode == CGKeyCode(kVK_Option) || keyCode == CGKeyCode(kVK_RightOption)
        case .leftOption:
            return keyCode == CGKeyCode(kVK_Option)
        case .rightOption:
            return keyCode == CGKeyCode(kVK_RightOption)
        case .optionSpace, .f5, .trackpadHold:
            return false
        }
    }

    private func modifierTriggerIsPressed(
        _ triggerKey: JarvisTapSettingsStore.TriggerKeyOption,
        flags: CGEventFlags
    ) -> Bool {
        switch triggerKey {
        case .fn:
            return flags.contains(fnModifierMask)
        case .option:
            return flags.contains(.maskAlternate)
        case .leftOption:
            return flags.contains(leftOptionModifierMask)
        case .rightOption:
            return flags.contains(rightOptionModifierMask)
        case .optionSpace, .f5, .trackpadHold:
            return false
        }
    }

    private func traceInputDebug(_ message: String) {
        let shouldLog = withStateLock { () -> Bool in
            guard message != lastInputDebugSignature else { return false }
            lastInputDebugSignature = message
            return true
        }
        guard shouldLog else { return }
        traceLogger.log("Input debug: \(message)")
    }

    /// German vocabulary repair. Backend-independent: it fixes what the
    /// recogniser mangles regardless of which recogniser produced it, which
    /// matters because brands and compounds fail on parakeet and whisper at
    /// nearly the same rate. Measured on a held-out German eval:
    /// 16.55%% -> 13.93%% WER, 13 clips fixed, 0 broken.
    ///
    /// The guard against over-correction is Alex's own vocabulary (a 26k-word
    /// list built from 4.76M tokens of his German transcripts), so a real word
    /// he actually says is never rewritten.
    ///
    /// Set PRESSTALK_DISABLE_VOCAB_REPAIR=1 to turn it off.
    private lazy var germanVocabularyPolicy: GermanVocabularyPolicy? = {
        let raw = ProcessInfo.processInfo.environment["PRESSTALK_DISABLE_VOCAB_REPAIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let raw, !raw.isEmpty, !["0", "false", "no", "off"].contains(raw) {
            traceLogger.log("German vocabulary repair DISABLED by environment")
            return nil
        }
        let vocabulary = GermanVocabularyPolicy.loadUserVocabulary()
        // FAIL SAFE. The guard list is what stops the corrector rewriting real
        // German words the user actually says. If the resource bundle is missing
        // -- which it was on the first packaged build, because the app bundle did
        // not copy JarvisTap_PressTalkCore.bundle -- an empty set would mean NO
        // guard, and the repair would run at full confidence over everything.
        // Silently degrading to unguarded correction is worse than not correcting
        // at all, so refuse instead.
        guard vocabulary.count >= 1000 else {
            traceLogger.log(
                "German vocabulary repair DISABLED: guard list missing or too small (\(vocabulary.count) words). "
                + "Refusing to correct without the guard.")
            return nil
        }
        traceLogger.log("German vocabulary repair enabled guard_words=\(vocabulary.count)")
        return GermanVocabularyPolicy(userVocabulary: vocabulary)
    }()

    private func cleanedTranscriptText(_ text: String) -> String {
        let cleaned = transcriptTextPolicy.cleanedText(text)
        guard let policy = germanVocabularyPolicy else { return cleaned }
        let (repaired, changes) = policy.corrected(cleaned)
        if !changes.isEmpty {
            // The change list is the most useful diagnostic this feature has and
            // it is also made of words the user said, so the pairs are behind the
            // same opt-in as the transcripts. The kinds and the count are not.
            let kinds = changes.map(\.kind).joined(separator: ",")
            if TranscriptRedaction.isVerboseLoggingEnabled() {
                let summary = changes.map { "\($0.kind):'\($0.from)'->'\($0.to)'" }.joined(separator: " ")
                traceLogger.log("Vocabulary repair applied count=\(changes.count) \(summary)")
            } else {
                traceLogger.log("Vocabulary repair applied count=\(changes.count) kinds=\(kinds)")
            }
        }
        return repaired
    }

    private func normalizedTranscriptPhrase(_ text: String) -> String {
        transcriptTextPolicy.normalizedPhrase(text)
    }

    private func isLikelySilenceHallucination(
        _ text: String,
        signalStats: (rms: Double, peak: Double),
        captureDurationSeconds: TimeInterval
    ) -> Bool {
        transcriptTextPolicy.isLikelySilenceHallucination(
            text,
            signalRMS: signalStats.rms,
            signalPeak: signalStats.peak,
            captureDurationSeconds: captureDurationSeconds
        )
    }

    private func validatedFinalTranscriptCandidate(
        _ text: String,
        signalStats: (rms: Double, peak: Double),
        captureDurationSeconds: TimeInterval,
        context: String
    ) -> String? {
        let cleaned = cleanedTranscriptText(text)
        guard isPlausibleTranscript(cleaned) else { return nil }

        if isLikelySilenceHallucination(
            cleaned,
            signalStats: signalStats,
            captureDurationSeconds: captureDurationSeconds
        ) {
            traceLogger.log(
                "Rejected likely silence hallucination context=\(context) transcript=\(TranscriptRedaction.loggable(cleaned)) rms=\(String(format: "%.5f", signalStats.rms)) peak=\(String(format: "%.5f", signalStats.peak)) duration_seconds=\(String(format: "%.2f", captureDurationSeconds))"
            )
            return nil
        }

        return cleaned
    }

    private func parakeetQualityFallbackReason(
        for candidate: ParakeetTranscriptCandidate,
        captureDurationSeconds: TimeInterval
    ) -> String? {
        guard config.parakeetQualityFallbackEnabled else { return nil }
        // Asking for a second opinion nobody can give throws away a usable
        // transcript: the caller marks the Parakeet result as superseded and the
        // Whisper path then has nothing to supersede it with. When the fallback
        // model is not loaded, the Parakeet transcript is the answer.
        guard whisperKit != nil else { return nil }

        let cleaned = cleanedTranscriptText(candidate.text)
        if candidate.confidence < config.parakeetQualityFallbackMinConfidence {
            return "low_confidence confidence=\(String(format: "%.3f", candidate.confidence)) threshold=\(String(format: "%.3f", config.parakeetQualityFallbackMinConfidence))"
        }

        let tokens = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard tokens.count >= 18, captureDurationSeconds >= 8.0 else { return nil }

        let structuralPunctuation = CharacterSet(charactersIn: ".?!,:;")
        let sentencePunctuation = CharacterSet(charactersIn: ".?!")
        let structuralPunctuationCount = cleaned.unicodeScalars.filter(structuralPunctuation.contains).count
        let sentencePunctuationCount = cleaned.unicodeScalars.filter(sentencePunctuation.contains).count

        if structuralPunctuationCount == 0 {
            return "missing_punctuation words=\(tokens.count) duration_seconds=\(String(format: "%.2f", captureDurationSeconds))"
        }
        if tokens.count >= 30, captureDurationSeconds >= 14.0, sentencePunctuationCount == 0 {
            return "weak_sentence_punctuation words=\(tokens.count) duration_seconds=\(String(format: "%.2f", captureDurationSeconds))"
        }

        return nil
    }

    private func shouldDeferShortWhisperCandidateForRecall(
        whisperTranscript: String,
        parakeetTranscript: String?,
        streamingTranscript: String?,
        captureDurationSeconds: TimeInterval,
        context: String
    ) -> Bool {
        guard let decision = transcriptRecallPolicy.shouldDeferShortWhisperCandidateForRecall(
            whisperTranscript: whisperTranscript,
            parakeetTranscript: parakeetTranscript,
            streamingTranscript: streamingTranscript,
            captureDurationSeconds: captureDurationSeconds,
            context: context
        ) else {
            return false
        }
        traceLogger.log(decision.logMessage)
        return true
    }

    private func shouldRejectWhisperCandidateForRecallQuality(
        whisperTranscript: String,
        parakeetTranscript: String?,
        streamingTranscript: String?,
        captureDurationSeconds: TimeInterval,
        context: String
    ) -> Bool {
        guard let decision = transcriptRecallPolicy.shouldRejectWhisperCandidateForRecallQuality(
            whisperTranscript: whisperTranscript,
            parakeetTranscript: parakeetTranscript,
            streamingTranscript: streamingTranscript,
            captureDurationSeconds: captureDurationSeconds,
            context: context
        ) else {
            return false
        }
        traceLogger.log(decision.logMessage)
        return true
    }

    private func parakeetStreamingRecallFallbackReason(
        parakeetTranscript: String,
        streamingTranscript: String?,
        captureDurationSeconds: TimeInterval,
        context: String
    ) -> String? {
        guard let decision = transcriptRecallPolicy.parakeetStreamingRecallFallback(
            parakeetTranscript: parakeetTranscript,
            streamingTranscript: streamingTranscript,
            captureDurationSeconds: captureDurationSeconds,
            context: context
        ) else {
            return nil
        }
        traceLogger.log(decision.logMessage)
        return decision.fallbackReason
    }

    private func chunkedWhisperFallbackTranscript(
        whisperKit: WhisperKit,
        samples: [Float],
        signalStats: (rms: Double, peak: Double),
        captureDurationSeconds: TimeInterval,
        context: String
    ) async throws -> String? {
        guard captureDurationSeconds >= chunkedWhisperFallbackMinimumCaptureSeconds else { return nil }

        let chunkSampleCount = max(
            Int(Double(WhisperKit.sampleRate) * chunkedWhisperFallbackChunkSeconds),
            WhisperKit.sampleRate
        )
        guard samples.count > chunkSampleCount else { return nil }

        let chunkDecodeOptions = autoDetectDecodingOptions()
        var chunkTranscripts: [String] = []
        var chunkIndex = 0
        var start = 0
        let startedAt = Date()

        while start < samples.count {
            let end = min(samples.count, start + chunkSampleCount)
            let chunkSamples = Array(samples[start..<end])
            let chunkDurationSeconds = Double(chunkSamples.count) / Double(WhisperKit.sampleRate)
            guard chunkDurationSeconds >= 1.0 else { break }

            chunkIndex += 1
            let results = try await whisperKit.transcribe(audioArray: chunkSamples, decodeOptions: chunkDecodeOptions)
            let transcript = cleanedTranscriptText(
                results
                    .map(\.text)
                    .joined(separator: " ")
            )
            traceTranscriptCandidate("Chunked offline Whisper transcript chunk=\(chunkIndex)", text: transcript)
            if let acceptedTranscript = validatedFinalTranscriptCandidate(
                transcript,
                signalStats: signalStats,
                captureDurationSeconds: chunkDurationSeconds,
                context: "\(context)_chunk_\(chunkIndex)"
            ) {
                chunkTranscripts.append(acceptedTranscript)
            }

            if end == samples.count { break }
            start = end
        }

        let mergedTranscript = transcriptRecallPolicy.mergeTranscriptSegments(chunkTranscripts)
        traceLogger.log(
            "Chunked offline Whisper fallback completed context=\(context) chunks=\(chunkIndex) accepted_chunks=\(chunkTranscripts.count) seconds=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))"
        )
        traceTranscriptCandidate("Chunked offline Whisper merged transcript", text: mergedTranscript)
        return validatedFinalTranscriptCandidate(
            mergedTranscript,
            signalStats: signalStats,
            captureDurationSeconds: captureDurationSeconds,
            context: "\(context)_merged"
        )
    }

    private func isPlausibleTranscript(_ text: String) -> Bool {
        transcriptTextPolicy.isPlausibleTranscript(text)
    }

    private func bestTranscriptCandidate(from texts: [String]) -> String {
        transcriptTextPolicy.bestTranscriptCandidate(from: texts)
    }

    private func audioLevelStats(for samples: [Float]) -> (rms: Double, peak: Double) {
        guard !samples.isEmpty else { return (0, 0) }

        var sumSquares = 0.0
        var peak = 0.0
        for sample in samples {
            let magnitude = Double(abs(sample))
            sumSquares += magnitude * magnitude
            if magnitude > peak {
                peak = magnitude
            }
        }

        return (sqrt(sumSquares / Double(samples.count)), peak)
    }

    private func coreAudioStringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return value as String
    }

    private func coreAudioUInt32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    private func defaultCoreAudioInputDeviceID() -> AudioDeviceID? {
        coreAudioUInt32Property(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultInputDevice
        ).map { AudioDeviceID($0) }
    }

    @discardableResult
    private func setDefaultCoreAudioInputDeviceID(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )
        guard status == noErr else {
            traceLogger.log("Audio input default promotion failed status=\(status) device_id=\(deviceID)")
            return false
        }
        traceLogger.log("Audio input default promotion requested device_id=\(deviceID)")
        return true
    }

    private func coreAudioInputChannelCount(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize) == noErr,
              propertySize > 0
        else {
            return 0
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(propertySize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, bufferListPointer) == noErr else {
            return 0
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(
            bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return bufferList.reduce(UInt32(0)) { total, buffer in
            total + buffer.mNumberChannels
        }
    }

    /// Which microphone the user asked for. `.systemDefault` unless they said
    /// otherwise, so PressTalk behaves like every other app until told not to.
    private var audioInputPreference: AudioInputPreference {
        AudioInputPreference(
            storageValue: UserDefaults.standard.string(forKey: "PressTalk.AudioInputPreference"))
    }

    /// Set by device selection, read by the capture path. Changing the system
    /// default input is visible to every application on the Mac, so it happens
    /// only when the user explicitly asked for a device macOS is not using.
    private var audioInputPromotionAllowed = false

    /// How long the audio engine took to start, so the release tail can tell
    /// audio that is late from audio that is missing.
    private var activeEngineStartLatencySeconds: Double = 0

    /// The default we displaced, so it can be put back. Nothing restored it
    /// before: dictating once with AirPods connected silently repointed the
    /// microphone for the whole Mac, permanently, and the user had no idea
    /// PressTalk had done it.
    private var displacedDefaultInputDeviceID: AudioDeviceID?

    /// Puts the system default input back the way we found it.
    func restoreDisplacedDefaultInputDevice() {
        guard let displaced = displacedDefaultInputDeviceID else { return }
        displacedDefaultInputDeviceID = nil
        // Only restore if we are still the reason it changed. If the user
        // picked something else in System Settings meanwhile, that is now their
        // choice and putting our value back would be a second act of the same
        // rudeness this exists to undo.
        guard coreAudioInputDevices().contains(where: { $0.id == displaced }) else {
            traceLogger.log("Audio input default restore skipped reason=device_absent")
            return
        }
        let restored = setDefaultCoreAudioInputDeviceID(displaced)
        traceLogger.log(
            "Audio input default restored device_id=\(displaced) ok=\(restored ? 1 : 0)")
    }

    private func coreAudioInputDevices() -> [AudioInputDeviceCandidate] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        ) == noErr, propertySize > 0 else {
            return []
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        let defaultInputID = defaultCoreAudioInputDeviceID()
        return deviceIDs.compactMap { deviceID -> AudioInputDeviceCandidate? in
            let inputChannels = coreAudioInputChannelCount(for: deviceID)
            guard inputChannels > 0 else { return nil }
            let name = coreAudioStringProperty(objectID: deviceID, selector: kAudioObjectPropertyName) ?? "Audio Device \(deviceID)"
            let transportType = coreAudioUInt32Property(
                objectID: deviceID,
                selector: kAudioDevicePropertyTransportType
            )
            let uid = coreAudioStringProperty(
                objectID: deviceID, selector: kAudioDevicePropertyDeviceUID) ?? ""
            return AudioInputDeviceCandidate(
                id: deviceID,
                name: name,
                inputChannels: inputChannels,
                isDefault: defaultInputID == deviceID,
                transportType: transportType,
                uid: uid
            )
        }
    }

    private struct AudioInputSelection {
        let candidate: AudioInputDeviceCandidate
        let source: String
    }

    private func preferredAudioInputDevice() -> AudioInputSelection? {
        let candidates = coreAudioInputDevices()
        guard !candidates.isEmpty else {
            traceLogger.log("Audio input selection unavailable reason=no_input_devices")
            return nil
        }

        let rankedCandidates = candidates.sorted {
            if $0.selectionScore == $1.selectionScore {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.selectionScore > $1.selectionScore
        }
        // The user's preference decides, and the default preference is
        // "whatever macOS is using". PressTalk used to override any Bluetooth
        // default with a scored physical device, which meant overruling a
        // choice the user had already made, and -- because overriding means
        // promoting -- permanently changing the system default input for every
        // other application on the Mac.
        let preference = audioInputPreference
        let selectorDevices: [AudioInputSelector.Device]
        if case .preferWired = preference {
            // Ranking only matters when avoiding Bluetooth leaves a choice.
            selectorDevices = rankedCandidates.map(\.selectorDevice)
        } else {
            selectorDevices = candidates.map(\.selectorDevice)
        }
        let choice = AudioInputSelector.choose(
            preference: preference, devices: selectorDevices)

        let selected: AudioInputDeviceCandidate
        let selectionSource = choice.reason
        if let uid = choice.deviceUID,
           let match = candidates.first(where: { $0.uid == uid }) {
            selected = match
        } else if let defaultInput = candidates.first(where: { $0.isDefault }) {
            selected = defaultInput
        } else {
            selected = rankedCandidates[0]
        }
        // Only an explicit choice may change the system default. Recorded here
        // so the capture path cannot decide to promote on its own.
        audioInputPromotionAllowed = choice.requiresPromotion
        let summary = rankedCandidates.map { candidate in
            "\(candidate.name.replacingOccurrences(of: " ", with: "_")):score=\(candidate.selectionScore):channels=\(candidate.inputChannels):transport=\(candidate.transportDescription):default=\(candidate.isDefault ? 1 : 0)"
        }.joined(separator: ",")
        traceLogger.log(
            "Audio input selected source=\(selectionSource) id=\(selected.id) name=\(selected.name) transport=\(selected.transportDescription) channels=\(selected.inputChannels) default=\(selected.isDefault ? 1 : 0) score=\(selected.selectionScore) candidates=\(summary)"
        )
        return AudioInputSelection(candidate: selected, source: selectionSource)
    }

    private func normalizedAudioSamples(_ samples: [Float]) -> ([Float], Double) {
        let stats = audioLevelStats(for: samples)
        guard stats.peak > 0 else { return (samples, 1.0) }

        let shouldBoost = stats.peak < 0.25 || stats.rms < 0.03
        guard shouldBoost else { return (samples, 1.0) }

        let gain = min(12.0, 0.75 / stats.peak)
        guard gain > 1.1 else { return (samples, 1.0) }

        let normalized = samples.map { sample -> Float in
            let amplified = Double(sample) * gain
            return Float(max(-1.0, min(1.0, amplified)))
        }
        return (normalized, gain)
    }

    private func triggerStartLogMessage(for trigger: Trigger) -> String {
        switch trigger {
        case .trackpadHold:
            return "🎙️ Trackpad hold armed: recording started"
        case .configuredKey:
            return "🎙️ \(settingsStore.triggerKey.displayName) pressed: recording started"
        case .f5:
            return "🎙️ F5 pressed: recording started"
        }
    }

    private func triggerReleaseLogMessage(for trigger: Trigger) -> String {
        switch trigger {
        case .trackpadHold:
            return "🛑 Trackpad hold released: recording ended"
        case .configuredKey:
            return "🛑 \(settingsStore.triggerKey.displayName) released: recording ended"
        case .f5:
            return "🛑 F5 released: recording ended"
        }
    }

    private func realtimeStreamingDecodingOptions() -> DecodingOptions {
        var options = decodingOptions
        options.withoutTimestamps = true
        options.wordTimestamps = false
        options.temperature = 0
        options.usePrefillPrompt = true
        options.usePrefillCache = true
        return options
    }

    private func commonStableWordPrefix(_ previous: String, _ current: String) -> String {
        let previousWords = cleanedTranscriptText(previous).split(separator: " ").map(String.init)
        let currentWords = cleanedTranscriptText(current).split(separator: " ").map(String.init)
        guard !previousWords.isEmpty, !currentWords.isEmpty else { return "" }

        var prefix: [String] = []
        for (oldWord, newWord) in zip(previousWords, currentWords) {
            guard oldWord.caseInsensitiveCompare(newWord) == .orderedSame else { break }
            prefix.append(newWord)
        }
        return prefix.joined(separator: " ")
    }

    private func updateRealtimeStreamingSnapshot(
        currentText: String,
        confirmedText: String,
        audioDurationSeconds: Double,
        revision: Int
    ) {
        let filteredCurrentText = bestTranscriptCandidate(from: [currentText])
        let filteredConfirmedText = bestTranscriptCandidate(from: [confirmedText])
        let filteredUnconfirmedText = bestTranscriptCandidate(from: [currentText])
        guard !filteredCurrentText.isEmpty || !filteredConfirmedText.isEmpty || !filteredUnconfirmedText.isEmpty else {
            return
        }

        var cleanedToLog: String?
        var shouldPrintPartial = false
        var shouldPresentPartial = false

        withStateLock {
            latestStreamingState = StreamingSnapshot(
                currentText: filteredCurrentText,
                confirmedText: filteredConfirmedText,
                unconfirmedText: filteredUnconfirmedText,
                updatedAt: Date(),
                audioDurationSeconds: audioDurationSeconds,
                revision: revision
            )

            let cleaned = filteredCurrentText
            guard !cleaned.isEmpty, cleaned != lastPrintedPartial else { return }
            lastPrintedPartial = cleaned
            cleanedToLog = cleaned
            shouldPrintPartial = config.printPartials
            shouldPresentPartial = isRecording
        }

        guard let cleanedToLog else { return }
        traceLogger.log("Realtime partial transcript revision=\(revision): \(TranscriptRedaction.loggable(cleanedToLog))")
        if shouldPresentPartial {
            present(.listening(cleanedToLog))
        }
        if shouldPrintPartial {
            print("📝 [PressTalk partial] \(TranscriptRedaction.loggable(cleanedToLog))")
            fflush(stdout)
        }
    }

    private func runRealtimeWhisperLoop(whisperKit: WhisperKit) async {
        let pollNanoseconds = UInt64(realtimeStreamPollSeconds * 1_000_000_000)
        let minimumNewSamples = Int(Double(WhisperKit.sampleRate) * realtimeStreamMinNewAudioSeconds)
        var previousTranscript = ""
        var lastTranscribedSampleCount = 0
        var revision = 0

        traceLogger.log(
            "Realtime Whisper streaming loop started min_audio_seconds=\(String(format: "%.2f", realtimeStreamInitialAudioSeconds)) min_new_seconds=\(String(format: "%.2f", realtimeStreamMinNewAudioSeconds)) poll_seconds=\(String(format: "%.2f", realtimeStreamPollSeconds))"
        )

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: pollNanoseconds)
            if Task.isCancelled { break }

            let capturedSamples = currentLiveCapturedAudioSamples()
            let sampleCount = capturedSamples.count
            let audioDurationSeconds = Double(sampleCount) / Double(WhisperKit.sampleRate)
            guard audioDurationSeconds >= realtimeStreamInitialAudioSeconds else { continue }
            let releaseFinalizeRequested = withStateLock { isProcessing && !isRecording }
            if releaseFinalizeRequested, lastTranscribedSampleCount > 0, sampleCount == lastTranscribedSampleCount {
                break
            }
            guard lastTranscribedSampleCount == 0 || releaseFinalizeRequested || sampleCount - lastTranscribedSampleCount >= minimumNewSamples else {
                continue
            }

            lastTranscribedSampleCount = sampleCount
            let signalStats = audioLevelStats(for: capturedSamples)
            guard signalStats.rms > 0.001 || signalStats.peak > 0.01 else { continue }

            let normalizedSamples = normalizedAudioSamples(capturedSamples).0
            let startedAt = Date()
            do {
                let results = try await whisperKit.transcribe(
                    audioArray: normalizedSamples,
                    decodeOptions: realtimeStreamingDecodingOptions()
                )
                let transcript = cleanedTranscriptText(results.map(\.text).joined(separator: " "))
                guard isPlausibleTranscript(transcript) else { continue }

                revision += 1
                let stablePrefix = commonStableWordPrefix(previousTranscript, transcript)
                let inferenceSeconds = Date().timeIntervalSince(startedAt)
                traceLogger.log(
                    "Realtime Whisper pass completed revision=\(revision) samples=\(sampleCount) duration_seconds=\(String(format: "%.2f", audioDurationSeconds)) inference_seconds=\(String(format: "%.2f", inferenceSeconds)) transcript_chars=\(transcript.count) stable_chars=\(stablePrefix.count)"
                )
                updateRealtimeStreamingSnapshot(
                    currentText: transcript,
                    confirmedText: stablePrefix,
                    audioDurationSeconds: audioDurationSeconds,
                    revision: revision
                )
                previousTranscript = transcript
                let shouldStopAfterPass = releaseFinalizeRequested || withStateLock { isProcessing && !isRecording }
                if shouldStopAfterPass {
                    let latestSampleCount = currentLiveCapturedAudioSamples().count
                    let lagSeconds = Double(max(0, latestSampleCount - sampleCount)) / Double(WhisperKit.sampleRate)
                    traceLogger.log(
                        "Realtime release pass lag revision=\(revision) lag_seconds=\(String(format: "%.2f", lagSeconds)) max_lag_seconds=\(String(format: "%.2f", realtimeStreamFinalMaxLagSeconds))"
                    )
                    guard lagSeconds > realtimeStreamFinalMaxLagSeconds else {
                        break
                    }
                    traceLogger.log("Realtime release pass lag too high; running one final pass over frozen audio")
                    continue
                }
            } catch is CancellationError {
                break
            } catch {
                traceLogger.log("Realtime Whisper pass failed samples=\(sampleCount) error=\(error)")
                if releaseFinalizeRequested {
                    break
                }
            }
        }

        traceLogger.log("Realtime Whisper streaming loop stopped")
    }

    private func appendNewSamplesToFluidStreamingManager(
        _ samples: [Float],
        manager: any StreamingAsrManager
    ) async throws -> Int {
        let startIndex = withStateLock { fluidStreamingFedSampleCount }
        guard samples.count > startIndex else { return 0 }
        let newSamples = samples[startIndex..<samples.count]
        let buffer = try makeMonoPCMBuffer(samples: newSamples)
        try await manager.appendAudio(buffer)
        withStateLock {
            fluidStreamingFedSampleCount = samples.count
        }
        return newSamples.count
    }

    private func runFluidTrueStreamingLoop() async {
        guard let manager = fluidStreamingAsrManager else {
            traceLogger.log("FluidAudio true streaming loop unavailable reason=manager_not_loaded")
            return
        }

        do {
            try await manager.reset()
        } catch {
            traceLogger.log("FluidAudio true streaming reset failed error=\(error)")
            return
        }
        withStateLock {
            fluidStreamingFedSampleCount = 0
        }

        let pollNanoseconds = UInt64(realtimeStreamPollSeconds * 1_000_000_000)
        var revision = 0
        var previousTranscript = ""
        traceLogger.log("FluidAudio true streaming loop started backend=\(config.streamingASRBackend ?? config.asrBackend) poll_seconds=\(String(format: "%.2f", realtimeStreamPollSeconds))")

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: pollNanoseconds)
            if Task.isCancelled { break }

            let capturedSamples = currentLiveCapturedAudioSamples()
            let sampleCount = capturedSamples.count
            let audioDurationSeconds = Double(sampleCount) / Double(WhisperKit.sampleRate)
            let releaseFinalizeRequested = withStateLock { isProcessing && !isRecording }

            do {
                let appendedSamples = try await appendNewSamplesToFluidStreamingManager(capturedSamples, manager: manager)
                let sliceStart = Date()
                try await manager.processBufferedAudio()
                let processSeconds = Date().timeIntervalSince(sliceStart)
                let partialTranscript = cleanedTranscriptText(await manager.getPartialTranscript())
                if isPlausibleTranscript(partialTranscript), partialTranscript != previousTranscript {
                    revision += 1
                    let stablePrefix = commonStableWordPrefix(previousTranscript, partialTranscript)
                    traceLogger.log(
                        "FluidAudio true streaming pass completed revision=\(revision) samples=\(sampleCount) appended_samples=\(appendedSamples) duration_seconds=\(String(format: "%.2f", audioDurationSeconds)) process_seconds=\(String(format: "%.3f", processSeconds)) transcript_chars=\(partialTranscript.count) stable_chars=\(stablePrefix.count)"
                    )
                    updateRealtimeStreamingSnapshot(
                        currentText: partialTranscript,
                        confirmedText: stablePrefix,
                        audioDurationSeconds: audioDurationSeconds,
                        revision: revision
                    )
                    previousTranscript = partialTranscript
                } else if appendedSamples > 0 {
                    traceLogger.log(
                        "FluidAudio true streaming buffered samples=\(sampleCount) appended_samples=\(appendedSamples) duration_seconds=\(String(format: "%.2f", audioDurationSeconds)) process_seconds=\(String(format: "%.3f", processSeconds))"
                    )
                }
            } catch is CancellationError {
                break
            } catch {
                traceLogger.log("FluidAudio true streaming pass failed samples=\(sampleCount) error=\(error)")
                if releaseFinalizeRequested {
                    break
                }
            }

            if releaseFinalizeRequested {
                break
            }
        }

        traceLogger.log("FluidAudio true streaming loop stopped")
    }

    private func resetFluidTrueStreamingTranscriptState() async throws {
        guard let manager = fluidStreamingAsrManager else {
            traceLogger.log("FluidAudio true streaming reset unavailable reason=manager_not_loaded")
            return
        }
        try await manager.reset()
        withStateLock {
            fluidStreamingFedSampleCount = 0
        }
    }

    private func finishFluidTrueStreamingTranscript(
        samples: [Float],
        signalStats: (rms: Double, peak: Double),
        captureDurationSeconds: Double
    ) async throws -> String? {
        guard let manager = fluidStreamingAsrManager else {
            traceLogger.log("FluidAudio true streaming finalize unavailable reason=manager_not_loaded")
            return nil
        }

        let startedAt = Date()
        let appendedSamples = try await appendNewSamplesToFluidStreamingManager(samples, manager: manager)
        try await manager.processBufferedAudio()
        let transcript = cleanedTranscriptText(try await manager.finish())
        traceTranscriptCandidate("FluidAudio true streaming transcript", text: transcript)
        traceLogger.log(
            "FluidAudio true streaming finalize completed backend=\(config.streamingASRBackend ?? config.asrBackend) samples=\(samples.count) appended_samples=\(appendedSamples) finalize_seconds=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))"
        )

        return validatedFinalTranscriptCandidate(
            transcript,
            signalStats: signalStats,
            captureDurationSeconds: captureDurationSeconds,
            context: "fluid_true_streaming"
        )
    }

    private func streamingSnapshotFreshEnoughForFinal(
        _ snapshot: StreamingSnapshot,
        frozenAudioDurationSeconds: Double
    ) -> Bool {
        guard let updatedAt = snapshot.updatedAt else { return false }
        let ageSeconds = Date().timeIntervalSince(updatedAt)
        let lagSeconds = max(0, frozenAudioDurationSeconds - snapshot.audioDurationSeconds)
        let allowedLagSeconds = realtimeStreamFinalMaxLagSeconds
        let fresh = ageSeconds <= realtimeStreamFreshnessSeconds && lagSeconds <= allowedLagSeconds
        traceLogger.log(
            "Realtime final freshness revision=\(snapshot.revision) fresh=\(fresh ? 1 : 0) age_seconds=\(String(format: "%.2f", ageSeconds)) lag_seconds=\(String(format: "%.2f", lagSeconds)) frozen_duration_seconds=\(String(format: "%.2f", frozenAudioDurationSeconds)) snapshot_duration_seconds=\(String(format: "%.2f", snapshot.audioDurationSeconds))"
        )
        return fresh
    }

    private func captureSilenceAwareReleaseTail(
        captureKit: WhisperKit?,
        heldSeconds: Double,
        engineStartLatencySeconds: Double
    ) async {
        let maximumTailSeconds = max(0.15, settingsStore.releaseTailMaxSeconds)
        let pollNanoseconds: UInt64 = 25_000_000
        // How much audio should exist by the moment the key came up. Anything
        // short of this is still travelling through the tap, not missing.
        let expectedAtRelease = max(0, heldSeconds - engineStartLatencySeconds)

        traceLogger.log(
            "Applying release tail max_seconds=\(String(format: "%.2f", maximumTailSeconds)) "
            + "expected_at_release_seconds=\(String(format: "%.2f", expectedAtRelease)) "
            + "held_seconds=\(String(format: "%.2f", heldSeconds)) "
            + "engine_start_seconds=\(String(format: "%.3f", engineStartLatencySeconds))")

        let start = Date()
        var lastCapturedCount = liveCapturedAudioSampleCount()
        var decision = ReleaseTailPolicy.Decision.keepWaiting(reason: "below_minimum")

        while true {
            try? await Task.sleep(nanoseconds: pollNanoseconds)
            guard captureKit != nil else { break }

            let capturedCount = liveCapturedAudioSampleCount()
            let grew = capturedCount > lastCapturedCount
            lastCapturedCount = capturedCount

            let requiredSamples = Int(Double(WhisperKit.sampleRate)
                * ReleaseTailPolicy.minimumSeconds)
            let recent = recentLiveCapturedAudioSamples(maxCount: requiredSamples)

            decision = ReleaseTailPolicy.decide(
                .init(elapsedSeconds: Date().timeIntervalSince(start),
                      capturedSeconds: Double(capturedCount) / Double(WhisperKit.sampleRate),
                      expectedAtReleaseSeconds: expectedAtRelease,
                      recentRMS: recent.isEmpty ? 1.0 : audioLevelStats(for: recent).rms,
                      capturedGrewSinceLastPoll: grew),
                maximumSeconds: maximumTailSeconds)
            if decision.shouldStop { break }
        }

        traceLogger.log(
            "Release tail finished reason=\(decision.reason) "
            + "elapsed_seconds=\(String(format: "%.2f", Date().timeIntervalSince(start))) "
            + "captured_seconds=\(String(format: "%.2f", Double(liveCapturedAudioSampleCount()) / Double(WhisperKit.sampleRate)))")
        safelyStopLiveAudioRecording(captureKit: captureKit, reason: "release_tail")
    }

    /// Wall-clock ceiling for the whole Whisper retry chain, shared across the
    /// primary, relaxed and auto-detect passes.
    ///
    /// Each pass looked reasonable on its own, which is exactly how a 4.2 s
    /// dictation turned into a 6.07 s wait: primary rejected by the recall guard,
    /// relaxed rejected, auto-detect finally accepted. Past the deadline the
    /// already-validated primary candidate is used instead of trying harder,
    /// because a user waiting six seconds for a better sentence would rather have
    /// had the good-enough one.
    var whisperLadderBudgetSeconds: TimeInterval {
        TimeInterval(
            ProcessInfo.processInfo.environment["PRESSTALK_WHISPER_LADDER_BUDGET_SECONDS"]
                .flatMap(Double.init) ?? 1.0)
    }

    private func whisperLadderBudgetExhausted(startedAt: Date, context: String) -> Bool {
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed >= whisperLadderBudgetSeconds else { return false }
        traceLogger.log(
            "Whisper retry budget exhausted context=\(context) elapsed_seconds=\(String(format: "%.3f", elapsed)) budget_seconds=\(String(format: "%.2f", whisperLadderBudgetSeconds))")
        return true
    }

    private func relaxedDecodingOptions() -> DecodingOptions {
        var options = decodingOptions
        options.noSpeechThreshold = nil
        options.logProbThreshold = nil
        options.firstTokenLogProbThreshold = nil
        options.compressionRatioThreshold = nil
        options.temperature = 0.2
        options.temperatureIncrementOnFallback = 0.2
        return options
    }

    private func autoDetectDecodingOptions() -> DecodingOptions {
        var options = relaxedDecodingOptions()
        options.language = nil
        options.detectLanguage = true
        return options
    }

    /// The single place recognizer candidates reach the log. Twelve call sites
    /// route through here, which is why redacting here rather than at each one
    /// is the fix that actually holds.
    private func traceTranscriptCandidate(_ label: String, text: String) {
        let cleaned = cleanedTranscriptText(text)
        traceLogger.log("\(label): \(TranscriptRedaction.loggable(cleaned))")
    }

    private func transcriptForInsertion(_ transcript: String) -> String {
        let cleanedTranscript = cleanedTranscriptText(transcript)
        guard !cleanedTranscript.isEmpty else { return "" }

        let option = settingsStore.insertionSuffix
        switch option {
        case .none:
            return cleanedTranscript
        case .space:
            return cleanedTranscript + " "
        case .newline:
            return cleanedTranscript + "\n"
        case .periodSpace:
            return cleanedTranscript + punctuationAwareSuffix(for: cleanedTranscript, punctuation: ".", trailing: " ")
        case .commaSpace:
            return cleanedTranscript + punctuationAwareSuffix(for: cleanedTranscript, punctuation: ",", trailing: " ")
        case .colonSpace:
            return cleanedTranscript + punctuationAwareSuffix(for: cleanedTranscript, punctuation: ":", trailing: " ")
        case .semicolonSpace:
            return cleanedTranscript + punctuationAwareSuffix(for: cleanedTranscript, punctuation: ";", trailing: " ")
        }
    }

    private func punctuationAwareSuffix(for cleanedTranscript: String, punctuation: String, trailing: String) -> String {
        let lastCharacter = cleanedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).last

        if let lastCharacter, ".!,?:;".contains(lastCharacter) {
            return trailing
        }

        return punctuation + trailing
    }

    private func startWhisperWarmupIfNeeded() {
        let shouldStart = withStateLock { () -> Bool in
            switch whisperLoadState {
            case .idle, .failed:
                whisperLoadState = .loading
                return true
            case .loading, .ready:
                return false
            }
        }
        guard shouldStart else { return }
        refreshRuntimeStatusUI()

        let task = Task(priority: .userInitiated) { [self] in
            do {
                traceLogger.log("ASR backend=\(config.asrBackend)")
                traceLogger.log("Whisper decode language=\(settingsStore.preferredLanguage.whisperLanguageCode ?? "auto")")

                // Capture first, and cheaply. Everything below is a recognizer.
                try await loadAudioCaptureEngine()

                if usesParakeetFinalBackend {
                    try await loadParakeetV3ANE()
                    print("Parakeet v3 ANE ready.")
                    fflush(stdout)

                    // Dictation is ready the moment the primary recognizer is,
                    // which is about 0.7s in. Waiting for the optional fallback
                    // too made that 7.3s, and a trigger pressed inside that
                    // window is refused with "still warming up" -- so the app
                    // spent seven seconds looking broken to earn a second
                    // opinion it usually does not need.
                    markSpeechModelReady()

                    // The quality fallback re-checks low-confidence Parakeet
                    // output. Worth loading when the model is already here;
                    // never worth a surprise 619 MB download on someone who just
                    // wanted to dictate a sentence. While it is absent the
                    // fallback does not fire and currentQualityFallbackStatus
                    // says so out loud.
                    if config.parakeetQualityFallbackEnabled {
                        if whisperModelIsLocallyAvailable || config.qualityFallbackAutoDownload {
                            traceLogger.log("Loading Whisper quality fallback in background local=\(whisperModelIsLocallyAvailable ? 1 : 0)")
                            Task(priority: .utility) { [self] in
                                let started = Date()
                                do {
                                    try await loadWhisperKit()
                                    traceLogger.log(
                                        "Whisper quality fallback ready seconds=\(String(format: "%.2f", Date().timeIntervalSince(started)))")
                                } catch {
                                    // Not fatal. Parakeet is the recognizer;
                                    // this was the optional second opinion.
                                    traceLogger.log("Whisper quality fallback failed to load error=\(error)")
                                }
                                refreshRuntimeStatusUI()
                            }
                        } else {
                            traceLogger.log(
                                "Whisper quality fallback NOT loaded reason=model_not_downloaded; dictation uses Parakeet alone")
                        }
                    }
                } else {
                    // WhisperKit is the final recognizer here, so the model is
                    // not optional.
                    traceLogger.log("Loading WhisperKit model=\(config.whisperModel)")
                    try await loadWhisperKit()
                    traceLogger.log("WhisperKit ready")
                    print("WhisperKit ready.")
                    fflush(stdout)
                }
                if usesFluidTrueStreamingBackend && config.streamingTranscriptionEnabled {
                    try await loadFluidTrueStreamingASR()
                    print("FluidAudio true streaming ASR ready.")
                    fflush(stdout)
                }

                markSpeechModelReady()
            } catch {
                traceLogger.log("Startup failed: WhisperKit load error=\(error)")
                fputs("[PressTalk] Failed to load WhisperKit: \(error)\n", stderr)
                withStateLock {
                    whisperLoadState = .failed(String(describing: error))
                    whisperWarmupTask = nil
                }
                refreshRuntimeStatusUI()
                present(.error("The local speech model failed to load."))
            }
        }

        withStateLock {
            whisperWarmupTask = task
        }
    }

    /// Flips the app into the dictating state. Idempotent, because the Parakeet
    /// path announces readiness before the optional fallback finishes loading
    /// and the warmup tail would otherwise announce it a second time.
    /// Shows guided setup, wiring each step to the same code paths the rest of
    /// the app uses, so the window cannot drift into claiming something the app
    /// disagrees with.
    /// Called once the transcript has actually gone somewhere: inserted into the
    /// focused app, or copied to the clipboard when insertion was unavailable.
    ///
    /// Recognising text and delivering it are different events, and this used to
    /// fire on the first. Setup's entire claim is that it finishes when words
    /// arrive somewhere the user can see, so recording it before insertion made
    /// that claim false, and started the trial clock for someone who might never
    /// have seen a word appear.
    /// Last time the expiry notice was shown, so holding the key repeatedly
    /// after the trial ends produces one window rather than one per press.
    private var lastTrialExpiredNoticeAt: Date?

    /// Tells someone the trial is over and gives them both ways out.
    ///
    /// Modal, on the main queue, and throttled. It is reached from the trigger
    /// handler, which can fire many times a second if a key sticks; without the
    /// throttle a stuck Fn key would stack modal windows until the app had to be
    /// force quit, turning an expired trial into a crash report.
    private func presentTrialExpiredIfNeeded() {
        let now = Date()
        if let last = lastTrialExpiredNoticeAt, now.timeIntervalSince(last) < 20 { return }
        lastTrialExpiredNoticeAt = now

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = "Your PressTalk trial has ended"
            alert.informativeText = PressTalkOffer.founderSummary
                + "\n\nThe licence is a signed file this Mac checks on its own. "
                + "No account, and nothing is sent anywhere."
            alert.addButton(withTitle: "Buy PressTalk — $\(PressTalkOffer.founderPriceUSD)")
            alert.addButton(withTitle: "Enter licence key")
            alert.addButton(withTitle: "Not now")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if let url = PressTalkOffer.checkoutURL { NSWorkspace.shared.open(url) }
            case .alertSecondButtonReturn:
                self.promptForLicenseKey()
            default:
                break
            }
        }
    }

    /// The same paste-a-key flow the settings pane offers, reachable from the
    /// expiry notice so someone who already bought is one click from working
    /// again rather than hunting through menus.
    private func promptForLicenseKey() {
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

        let outcome = NSAlert()
        switch licenseStore.importLicense(field.stringValue) {
        case .success(let license):
            outcome.messageText = "Licence activated"
            outcome.informativeText =
                "\(license.entitlement.capitalized). Dictation is available again."
            // A key that just verified means the next press must not be
            // refused by a throttle timestamp from the refusal before it.
            lastTrialExpiredNoticeAt = nil
        case .failure(let error):
            outcome.alertStyle = .warning
            outcome.messageText = "That licence key did not activate"
            outcome.informativeText = error.userFacingMessage
        }
        outcome.runModal()
    }

    private func recordDelivery(_ transcript: String, reachedTargetApp: Bool) {
        rememberDictation(transcript, deliveryFailed: !reachedTargetApp)
        guard !settingsStore.firstDictationDelivered else { return }
        settingsStore.firstDictationDelivered = true
        // The trial starts when the product first works, not when it was
        // installed, so a slow model download does not eat someone's trial.
        licenseStore.startTrialIfNeeded()
        traceLogger.log("First dictation delivered reached_target_app=\(reachedTargetApp ? 1 : 0)")
    }

    /// Records a transcript so it can be recovered from the menu. Dictating a
    /// paragraph into the wrong window used to mean losing it outright.
    private func rememberDictation(_ transcript: String, deliveryFailed: Bool) {
        let entry = DictationRecoveryPolicy.Entry(
            text: transcript, createdAt: Date(), deliveryFailed: deliveryFailed)
        recoverableDictations = dictationRecoveryPolicy.inserting(
            entry, into: recoverableDictations, now: Date())
        DispatchQueue.main.async { [weak self] in
            self?.refreshRecentDictationsMenu()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === recentDictationsMenu {
            refreshRecentDictationsMenu()
        }
    }

    private func refreshRecentDictationsMenu() {
        guard let menu = recentDictationsMenu else { return }
        // Prune on display too: an entry that aged out while the menu sat closed
        // must not still be offered.
        recoverableDictations = dictationRecoveryPolicy.pruned(recoverableDictations, now: Date())
        menu.removeAllItems()

        if recoverableDictations.isEmpty {
            let empty = NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for (index, entry) in recoverableDictations.enumerated() {
            let item = NSMenuItem(
                title: dictationRecoveryPolicy.menuLabel(for: entry),
                action: #selector(copyRecentDictation(_:)),
                keyEquivalent: "")
            item.target = self
            item.tag = index
            item.toolTip = entry.text
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let forget = NSMenuItem(title: "Forget These", action: #selector(forgetRecentDictations(_:)), keyEquivalent: "")
        forget.target = self
        forget.toolTip = "Clears them from memory now, rather than waiting for them to expire."
        menu.addItem(forget)
    }

    @objc private func copyRecentDictation(_ sender: NSMenuItem) {
        // Re-check expiry at the moment of use. A menu can be held open past an
        // entry's lifetime, and handing back expired text would quietly break
        // the promise the expiry exists to keep.
        recoverableDictations = dictationRecoveryPolicy.pruned(recoverableDictations, now: Date())
        guard recoverableDictations.indices.contains(sender.tag) else {
            traceLogger.log("Recovered dictation expired before it was copied")
            refreshRecentDictationsMenu()
            return
        }
        let entry = recoverableDictations[sender.tag]
        copyTranscriptToPasteboard(entry.text)
        traceLogger.log("Recovered dictation copied characters=\(entry.text.count)")
        present(.copied(entry.text))
    }

    @objc private func forgetRecentDictations(_ sender: Any?) {
        let count = recoverableDictations.count
        recoverableDictations.removeAll()
        refreshRecentDictationsMenu()
        traceLogger.log("Recoverable dictations cleared count=\(count)")
    }

    @objc private func openFirstRunSetupFromMenu(_ sender: Any?) {
        presentFirstRunSetup()
    }

    func presentFirstRunSetup() {
        let controller = firstRunSetupWindowController ?? FirstRunSetupWindowController()
        firstRunSetupWindowController = controller

        controller.onReadConditions = { [weak self] in
            guard let self else {
                return FirstRunSetupPolicy.Conditions(
                    microphoneCaptureVerified: false, inputMonitoringGranted: false,
                    accessibilityGranted: false, speechModelReady: false,
                    firstDictationDelivered: false, triggerRequiresInputMonitoring: true)
            }
            let status = self.currentRuntimeStatus()
            return FirstRunSetupPolicy.Conditions(
                microphoneCaptureVerified: self.microphoneCaptureVerified,
                inputMonitoringGranted: status.inputMonitoringEffective,
                accessibilityGranted: status.accessibilityGranted,
                speechModelReady: self.withStateLock {
                    if case .ready = self.whisperLoadState { return true }
                    return false
                },
                firstDictationDelivered: self.settingsStore.firstDictationDelivered,
                triggerRequiresInputMonitoring: status.triggerRequiresWritableEventTap
                    || status.triggerUsesRegisteredHotKey)
        }

        controller.onRequestMicrophoneAccess = { completion in
            AVCaptureDevice.requestAccess(for: .audio) { granted in completion(granted) }
        }

        controller.onVerifyMicrophone = { [weak self] in
            let report = AudioCaptureProbe.run()
            self?.microphoneCaptureVerified = report.isUsable
            self?.traceLogger.log(
                "Setup microphone probe outcome=\(report.outcome.rawValue) frames=\(report.framesCaptured) authorization=\(report.authorizationStatus)")
            return report
        }

        controller.onOpenInputMonitoringSettings = { [weak self] in
            self?.openInputMonitoringPrivacyPane()
        }
        controller.onOpenAccessibilitySettings = { [weak self] in
            self?.openAccessibilityPrivacyPane()
        }
        controller.onDownloadSpeechModel = { [weak self] in
            self?.startWhisperWarmupIfNeeded()
        }
        controller.onFinish = { [weak self] in
            self?.settingsStore.firstRunSetupCompleted = true
            self?.traceLogger.log("First-run setup completed")
        }

        controller.present()
    }

    private func markSpeechModelReady() {
        let alreadyReady = withStateLock { () -> Bool in
            if case .ready = whisperLoadState { return true }
            whisperLoadState = .ready
            whisperWarmupTask = nil
            return false
        }
        guard !alreadyReady else { return }
        traceLogger.log("Speech model ready for live use")
        refreshRuntimeStatusUI()
        present(.ready)
    }

    private func currentWhisperReadinessMessage() -> String? {
        withStateLock {
            switch whisperLoadState {
            case .ready:
                return nil
            case .loading:
                return "The speech model is still warming up."
            case .failed(let reason):
                return "The speech model failed to load: \(reason)"
            case .idle:
                return "The speech model is not ready yet."
            }
        }
    }

    private func stagePreparedTranscriptOnPasteboard(_ preparedTranscript: String) -> PasteboardInsertionStaging {
        PasteboardInsertionStaging.stage(preparedTranscript, on: .general)
    }

    private func restorePasteboardAfterInsertion(_ staging: PasteboardInsertionStaging) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            staging.restoreIfUnchanged(on: .general)
        }
    }

    private func copyTranscriptToPasteboard(_ transcript: String) {
        let preparedTranscript = transcriptForInsertion(transcript)
        guard !preparedTranscript.isEmpty else { return }

        copyPreparedTranscriptToPasteboard(preparedTranscript)
    }

    private func copyPreparedTranscriptToPasteboard(_ preparedTranscript: String) {
        _ = PasteboardInsertionStaging.stage(preparedTranscript, on: .general)
    }

    private func runTISOperationOnMainThread<T>(_ operation: () -> T) -> T {
        if Thread.isMainThread {
            return operation()
        }

        var result: T?
        DispatchQueue.main.sync {
            result = operation()
        }
        return result!
    }

    private func inputSourceProperty(_ source: TISInputSource, _ key: CFString) -> Any? {
        runTISOperationOnMainThread {
            guard let unmanaged = TISGetInputSourceProperty(source, key) else { return nil }
            return Unmanaged<AnyObject>.fromOpaque(unmanaged).takeUnretainedValue()
        }
    }

    private func inputSourceStringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        inputSourceProperty(source, key) as? String
    }

    private func inputSourceBoolProperty(_ source: TISInputSource, _ key: CFString) -> Bool? {
        guard let value = inputSourceProperty(source, key) else { return nil }
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private func inputSourceIdentityKey(_ source: TISInputSource) -> String {
        let keyParts = [
            inputSourceStringProperty(source, kTISPropertyInputSourceID),
            inputSourceStringProperty(source, kTISPropertyBundleID),
        ].compactMap { $0 }
        return keyParts.isEmpty ? "\(Unmanaged.passUnretained(source).toOpaque())" : keyParts.joined(separator: "|")
    }

    private func inputSourceList(properties: CFDictionary?, includeAllInstalled: Bool) -> [TISInputSource] {
        runTISOperationOnMainThread {
            guard let list = TISCreateInputSourceList(properties, includeAllInstalled) else {
                return []
            }
            return (list.takeRetainedValue() as NSArray as Array).compactMap { object in
                guard CFGetTypeID(object as CFTypeRef) == TISInputSourceGetTypeID() else { return nil }
                return (object as! TISInputSource)
            }
        }
    }

    private func installedInputMethodBundleURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods", isDirectory: true)
            .appendingPathComponent("PressTalkInputMethod.app", isDirectory: true)
    }

    private func inputMethodBundleHasCurrentSourceID(_ bundleURL: URL) -> Bool {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            return false
        }
        return info["CFBundleIdentifier"] as? String == "com.am.presstalk.inputmethod.container" &&
            info["TISInputSourceID"] as? String == "com.am.presstalk.inputmethod.container"
    }

    private func ensureInputMethodInstalledForInsertion() -> URL? {
        let installedURL = installedInputMethodBundleURL()
        let executableURL = installedURL.appendingPathComponent("Contents/MacOS/presstalk-input-method")
        if FileManager.default.isExecutableFile(atPath: executableURL.path),
           inputMethodBundleHasCurrentSourceID(installedURL) {
            return installedURL
        }

        guard let bundledURL = Bundle.main.resourceURL?.appendingPathComponent("PressTalkInputMethod.app", isDirectory: true) else {
            traceLogger.log("Input method insertion unavailable reason=bundled_input_method_missing")
            return nil
        }

        do {
            try FileManager.default.createDirectory(
                at: installedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: installedURL.path) {
                try FileManager.default.removeItem(at: installedURL)
            }
            try FileManager.default.copyItem(at: bundledURL, to: installedURL)
            traceLogger.log("Input method installed for insertion path=\(installedURL.path)")
            return installedURL
        } catch {
            traceLogger.log("Input method insertion unavailable reason=install_failed error=\(error)")
            return nil
        }
    }

    private func pressTalkInputMethodSources(includeAllInstalled: Bool) -> [TISInputSource] {
        let sourceID = "com.am.presstalk.inputmethod.container"
        let legacySourceIDs = [
            "com.am.presstalk.inputmethod.dictation",
            "com.am.presstalk.inputmethod",
        ]
        let sourceIDs = [sourceID] + legacySourceIDs

        func sources(matching key: CFString, value: String) -> [TISInputSource] {
            inputSourceList(
                properties: [key: value] as CFDictionary,
                includeAllInstalled: includeAllInstalled
            )
        }

        let directSources = sourceIDs.flatMap { sources(matching: kTISPropertyInputSourceID, value: $0) }
            + sourceIDs.flatMap { sources(matching: kTISPropertyBundleID, value: $0) }
        let fullScanSources = inputSourceList(properties: nil, includeAllInstalled: includeAllInstalled)
            .filter { source in
                let values = [
                    inputSourceStringProperty(source, kTISPropertyInputSourceID),
                    inputSourceStringProperty(source, kTISPropertyBundleID),
                    inputSourceStringProperty(source, kTISPropertyLocalizedName),
                ].compactMap { $0?.lowercased() }
                return values.contains { value in
                    sourceIDs.contains { value == $0.lowercased() } ||
                        value.contains("presstalk")
                }
            }

        var seen = Set<String>()
        var result: [TISInputSource] = []
        for source in directSources + fullScanSources {
            let key = inputSourceIdentityKey(source)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(source)
        }
        return result
    }

    private func preferredPressTalkInputMethodSource(from sources: [TISInputSource]) -> TISInputSource? {
        sources.first {
            inputSourceStringProperty($0, kTISPropertyInputSourceID) == "com.am.presstalk.inputmethod.container" &&
                (inputSourceBoolProperty($0, kTISPropertyInputSourceIsSelectCapable) ?? true)
        } ?? sources.first {
            inputSourceBoolProperty($0, kTISPropertyInputSourceIsSelectCapable) ?? false
        } ?? sources.first
    }

    private func disableInputMethodSourcesEnabledOnlyForInsertion(
        _ sources: [TISInputSource],
        enabledBeforeKeys: Set<String>
    ) {
        var disabled = Set<String>()
        for source in sources {
            let key = inputSourceIdentityKey(source)
            guard !enabledBeforeKeys.contains(key), !disabled.contains(key) else { continue }
            disabled.insert(key)
            let disableStatus = runTISOperationOnMainThread {
                TISDisableInputSource(source)
            }
            if disableStatus != 0 {
                traceLogger.log("Input method insertion disable failed status=\(disableStatus)")
            }
        }
    }

    private func restoreInputMethodSelection(
        originalSource: TISInputSource,
        enabledSource: TISInputSource,
        candidateSource: TISInputSource,
        enabledBeforeKeys: Set<String>,
        reason: String
    ) {
        let restoreStatus = runTISOperationOnMainThread {
            TISSelectInputSource(originalSource)
        }
        if restoreStatus != 0 {
            traceLogger.log("Input method insertion restore failed status=\(restoreStatus) reason=\(reason)")
        }
        disableInputMethodSourcesEnabledOnlyForInsertion(
            [enabledSource, candidateSource],
            enabledBeforeKeys: enabledBeforeKeys
        )
    }

    private func takeInputMethodPreselection() -> InputMethodPreselectionSession? {
        withStateLock {
            let session = activeInputMethodPreselection
            activeInputMethodPreselection = nil
            return session
        }
    }

    private func restoreInputMethodPreselectionIfNeeded(reason: String) {
        guard let session = takeInputMethodPreselection() else { return }
        restoreInputMethodSelection(
            originalSource: session.originalSource,
            enabledSource: session.enabledSource,
            candidateSource: session.candidateSource,
            enabledBeforeKeys: session.enabledBeforeKeys,
            reason: reason
        )
        let age = Date().timeIntervalSince(session.startedAt)
        traceLogger.log("Input method preselection restored reason=\(reason) age_seconds=\(String(format: "%.2f", age))")
    }

    private func inputMethodDictationInsertionEnabled() -> Bool {
        ProcessInfo.processInfo.environment[inputMethodDictationEnvKey] == "1"
    }

    private func scheduleInputMethodHelperWarmupIfNeeded() {
        guard config.agentMode == "dictation",
              settingsStore.pasteAutomatically,
              inputMethodDictationInsertionEnabled(),
              !AXIsProcessTrusted()
        else {
            return
        }

        let shouldSchedule = withStateLock { () -> Bool in
            guard !inputMethodHelperWarmupScheduled else { return false }
            inputMethodHelperWarmupScheduled = true
            return true
        }
        guard shouldSchedule else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.warmInputMethodHelperForInsertionIfNeeded()
        }
    }

    private func warmInputMethodHelperForInsertionIfNeeded() {
        guard config.agentMode == "dictation",
              settingsStore.pasteAutomatically,
              inputMethodDictationInsertionEnabled(),
              !AXIsProcessTrusted()
        else {
            return
        }

        let busy = withStateLock { isRecording || isProcessing || activeInputMethodPreselection != nil }
        guard !busy else {
            traceLogger.log("Input method helper warmup skipped reason=busy")
            return
        }

        guard let bundleURL = ensureInputMethodInstalledForInsertion() else {
            return
        }

        let registerStatus = runTISOperationOnMainThread {
            TISRegisterInputSource(bundleURL as CFURL)
        }
        guard registerStatus == 0 else {
            traceLogger.log("Input method helper warmup unavailable reason=register_failed status=\(registerStatus)")
            return
        }

        let originalSource = runTISOperationOnMainThread {
            TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        }
        let enabledBeforeKeys = Set(pressTalkInputMethodSources(includeAllInstalled: false).map(inputSourceIdentityKey))
        let allSources = pressTalkInputMethodSources(includeAllInstalled: true)
        guard let candidate = preferredPressTalkInputMethodSource(from: allSources) else {
            traceLogger.log("Input method helper warmup unavailable reason=source_not_recognized")
            return
        }

        let candidateWasEnabledBefore = enabledBeforeKeys.contains(inputSourceIdentityKey(candidate))
        if !candidateWasEnabledBefore {
            let enableStatus = runTISOperationOnMainThread {
                TISEnableInputSource(candidate)
            }
            guard enableStatus == 0 else {
                traceLogger.log("Input method helper warmup unavailable reason=enable_failed status=\(enableStatus)")
                return
            }
        }

        let enabledSources = pressTalkInputMethodSources(includeAllInstalled: false)
        let enabledSource = preferredPressTalkInputMethodSource(from: enabledSources) ?? candidate
        let selectStatus = runTISOperationOnMainThread {
            TISSelectInputSource(enabledSource)
        }
        guard selectStatus == 0 else {
            traceLogger.log("Input method helper warmup unavailable reason=select_failed status=\(selectStatus)")
            disableInputMethodSourcesEnabledOnlyForInsertion(
                [enabledSource, candidate],
                enabledBeforeKeys: enabledBeforeKeys
            )
            return
        }

        let sourceID = inputSourceStringProperty(enabledSource, kTISPropertyInputSourceID) ?? "unknown"
        traceLogger.log(
            "Input method helper warmup selected source=\(sourceID) enabled_count=\(enabledSources.count) all_installed_count=\(allSources.count)"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            let hasPreselection = self.withStateLock { self.activeInputMethodPreselection != nil }
            guard !hasPreselection else {
                self.traceLogger.log("Input method helper warmup restore skipped reason=active_preselection")
                return
            }
            self.restoreInputMethodSelection(
                originalSource: originalSource,
                enabledSource: enabledSource,
                candidateSource: candidate,
                enabledBeforeKeys: enabledBeforeKeys,
                reason: "helper_warmup"
            )
            self.traceLogger.log("Input method helper warmup restored")
        }
    }

    private func beginInputMethodPreselectionForDictationIfNeeded() {
        guard config.agentMode == "dictation",
              settingsStore.pasteAutomatically,
              inputMethodDictationInsertionEnabled(),
              !AXIsProcessTrusted()
        else {
            return
        }

        let alreadyPreselected = withStateLock { activeInputMethodPreselection != nil }
        guard !alreadyPreselected else { return }

        guard let bundleURL = ensureInputMethodInstalledForInsertion() else {
            return
        }

        let registerStatus = runTISOperationOnMainThread {
            TISRegisterInputSource(bundleURL as CFURL)
        }
        guard registerStatus == 0 else {
            traceLogger.log("Input method preselection unavailable reason=register_failed status=\(registerStatus)")
            return
        }

        let originalSource = runTISOperationOnMainThread {
            TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        }
        let enabledBeforeKeys = Set(pressTalkInputMethodSources(includeAllInstalled: false).map(inputSourceIdentityKey))
        let allSources = pressTalkInputMethodSources(includeAllInstalled: true)
        guard let candidate = preferredPressTalkInputMethodSource(from: allSources) else {
            traceLogger.log("Input method preselection unavailable reason=source_not_recognized")
            return
        }

        let candidateWasEnabledBefore = enabledBeforeKeys.contains(inputSourceIdentityKey(candidate))
        if !candidateWasEnabledBefore {
            let enableStatus = runTISOperationOnMainThread {
                TISEnableInputSource(candidate)
            }
            guard enableStatus == 0 else {
                traceLogger.log("Input method preselection unavailable reason=enable_failed status=\(enableStatus)")
                return
            }
        }

        let enabledSources = pressTalkInputMethodSources(includeAllInstalled: false)
        let enabledSource = preferredPressTalkInputMethodSource(from: enabledSources) ?? candidate
        let enableNoEffect = !candidateWasEnabledBefore && enabledSources.isEmpty
        if enableNoEffect {
            traceLogger.log("Input method preselection enable had no visible effect")
        }

        let selectStatus = runTISOperationOnMainThread {
            TISSelectInputSource(enabledSource)
        }
        guard selectStatus == 0 else {
            let reason = enableNoEffect ? "enable_no_effect" : "select_failed"
            traceLogger.log("Input method preselection unavailable reason=\(reason) status=\(selectStatus)")
            disableInputMethodSourcesEnabledOnlyForInsertion(
                [enabledSource, candidate],
                enabledBeforeKeys: enabledBeforeKeys
            )
            return
        }

        let sourceID = inputSourceStringProperty(enabledSource, kTISPropertyInputSourceID) ?? "unknown"
        withStateLock {
            activeInputMethodPreselection = InputMethodPreselectionSession(
                originalSource: originalSource,
                enabledSource: enabledSource,
                candidateSource: candidate,
                enabledBeforeKeys: enabledBeforeKeys,
                startedAt: Date()
            )
        }
        traceLogger.log(
            "Input method preselected for dictation source=\(sourceID) enabled_count=\(enabledSources.count) all_installed_count=\(allSources.count)"
        )
    }

    private func currentInputMethodFallbackStatus() -> String {
        guard settingsStore.pasteAutomatically else {
            return "not_used"
        }
        guard inputMethodDictationInsertionEnabled() else {
            return "probe_only"
        }

        let installedURL = installedInputMethodBundleURL()
        let executableURL = installedURL.appendingPathComponent("Contents/MacOS/presstalk-input-method")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path),
              inputMethodBundleHasCurrentSourceID(installedURL)
        else {
            return "not_installed"
        }

        let enabledSources = pressTalkInputMethodSources(includeAllInstalled: false)
        if preferredPressTalkInputMethodSource(from: enabledSources) != nil {
            if let recentFailure = recentInputMethodInsertionFailure() {
                return recentFailure.runtimeStatus
            }
            return "ready"
        }

        let allSources = pressTalkInputMethodSources(includeAllInstalled: true)
        guard !allSources.isEmpty else {
            return "source_not_recognized"
        }
        if preferredPressTalkInputMethodSource(from: allSources) != nil {
            return "recognized_disabled"
        }
        return "recognized_not_selectable"
    }

    private func recentInputMethodInsertionFailure(now: Date = Date()) -> InputMethodInsertionFailure? {
        guard let failure = withStateLock({ lastInputMethodInsertionFailure }) else {
            return nil
        }
        guard now.timeIntervalSince(failure.occurredAt) <= inputMethodFailureCooldownSeconds else {
            withStateLock {
                if lastInputMethodInsertionFailure?.occurredAt == failure.occurredAt {
                    lastInputMethodInsertionFailure = nil
                }
            }
            traceLogger.log("Input method insertion degradation expired reason=\(failure.reason)")
            return nil
        }
        return failure
    }

    private func recordInputMethodInsertionFailure(reason: String) {
        let failure = InputMethodInsertionFailure(reason: reason, occurredAt: Date())
        withStateLock {
            lastInputMethodInsertionFailure = failure
        }
        traceLogger.log("Input method insertion degraded status=\(failure.runtimeStatus) reason=\(reason)")
        DispatchQueue.main.async { [weak self] in
            self?.refreshRuntimeStatusUI()
        }
    }

    private func clearInputMethodInsertionFailure(reason: String) {
        let hadFailure = withStateLock { () -> Bool in
            let hadFailure = lastInputMethodInsertionFailure != nil
            lastInputMethodInsertionFailure = nil
            return hadFailure
        }
        guard hadFailure else { return }
        traceLogger.log("Input method insertion degradation cleared reason=\(reason)")
        DispatchQueue.main.async { [weak self] in
            self?.refreshRuntimeStatusUI()
        }
    }

    private func copiedFallbackReason(for failure: InputMethodInsertionFailure) -> String {
        switch failure.runtimeStatus {
        case "ack_timeout":
            return "input_method_ack_timeout_accessibility_required"
        default:
            return "input_method_client_unavailable_accessibility_required"
        }
    }

    private func inputMethodInsertionAcknowledgement(at url: URL) -> InputMethodInsertionAcknowledgement? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        guard let inserted = object["inserted"] as? Bool else {
            return nil
        }
        return InputMethodInsertionAcknowledgement(
            inserted: inserted,
            reason: object["reason"] as? String
        )
    }

    private func accessibilityStatusDescription(_ status: PressTalkRuntimeStatus) -> String {
        if status.accessibilityGranted {
            return "ax_trusted"
        }
        if !status.pasteAutomatically {
            return "ax_false_copy_only"
        }
        switch status.inputMethodFallbackStatus {
        case "ready":
            return "ax_false_accessibility_required"
        case "probe_only":
            return "ax_false_input_method_probe_only"
        case "client_unavailable":
            return "ax_false_input_method_client_unavailable"
        case "ack_timeout":
            return "ax_false_input_method_ack_timeout"
        case "recognized_disabled":
            return "ax_false_input_method_recognized_disabled"
        case "recognized_not_selectable":
            return "ax_false_input_method_recognized_not_selectable"
        case "source_not_recognized":
            return "ax_false_input_method_source_not_recognized"
        case "not_installed":
            return "ax_false_input_method_not_installed"
        default:
            return "ax_false_input_method_\(status.inputMethodFallbackStatus)"
        }
    }

    private func axElement(from object: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(object, to: AXUIElement.self)
    }

    private func axRange(from object: CFTypeRef?) -> CFRange? {
        guard let object, CFGetTypeID(object) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(object, to: AXValue.self)
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    private func insertPreparedTranscriptUsingInputMethod(
        _ preparedTranscript: String,
        maxAttempts: Int = 3,
        preselectedSession: InputMethodPreselectionSession? = nil
    ) -> String? {
        let clampedMaxAttempts = min(max(maxAttempts, 1), 3)
        let originalSource: TISInputSource
        let enabledBeforeKeys: Set<String>
        let candidate: TISInputSource
        let enabledSource: TISInputSource

        if let preselectedSession {
            originalSource = preselectedSession.originalSource
            enabledBeforeKeys = preselectedSession.enabledBeforeKeys
            candidate = preselectedSession.candidateSource
            enabledSource = preselectedSession.enabledSource
            let age = Date().timeIntervalSince(preselectedSession.startedAt)
            let sourceID = inputSourceStringProperty(enabledSource, kTISPropertyInputSourceID) ?? "unknown"
            traceLogger.log("Input method insertion using press-time preselection source=\(sourceID) age_seconds=\(String(format: "%.2f", age))")
        } else {
            guard let bundleURL = ensureInputMethodInstalledForInsertion() else {
                return nil
            }

            let registerStatus = runTISOperationOnMainThread {
                TISRegisterInputSource(bundleURL as CFURL)
            }
            guard registerStatus == 0 else {
                traceLogger.log("Input method insertion unavailable reason=register_failed status=\(registerStatus)")
                return nil
            }

            originalSource = runTISOperationOnMainThread {
                TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            }
            enabledBeforeKeys = Set(pressTalkInputMethodSources(includeAllInstalled: false).map(inputSourceIdentityKey))
            var allSources = pressTalkInputMethodSources(includeAllInstalled: true)
            guard let selectedCandidate = preferredPressTalkInputMethodSource(from: allSources) else {
                traceLogger.log("Input method insertion unavailable reason=source_not_recognized")
                return nil
            }
            candidate = selectedCandidate

            let candidateWasEnabledBefore = enabledBeforeKeys.contains(inputSourceIdentityKey(candidate))
            if !candidateWasEnabledBefore {
                let enableStatus = runTISOperationOnMainThread {
                    TISEnableInputSource(candidate)
                }
                guard enableStatus == 0 else {
                    traceLogger.log("Input method insertion unavailable reason=enable_failed status=\(enableStatus)")
                    return nil
                }
            }

            allSources = pressTalkInputMethodSources(includeAllInstalled: false)
            enabledSource = preferredPressTalkInputMethodSource(from: allSources) ?? candidate
            if allSources.isEmpty {
                traceLogger.log("Input method insertion selecting recognized source because enabled-source requery is empty")
            }
            let enableNoEffect = !candidateWasEnabledBefore && allSources.isEmpty
            if enableNoEffect {
                traceLogger.log("Input method insertion enable had no visible effect")
            }
            let selectableSourceID = inputSourceStringProperty(enabledSource, kTISPropertyInputSourceID) ?? "unknown"
            let allInstalledCountAfterEnable = pressTalkInputMethodSources(includeAllInstalled: true).count
            traceLogger.log(
                "Input method insertion source state enabled_count=\(allSources.count) all_installed_count=\(allInstalledCountAfterEnable) selected_candidate=\(selectableSourceID)"
            )

            let selectStatus = runTISOperationOnMainThread {
                TISSelectInputSource(enabledSource)
            }
            guard selectStatus == 0 else {
                let reason = enableNoEffect ? "enable_no_effect" : "select_failed"
                traceLogger.log("Input method insertion unavailable reason=\(reason) status=\(selectStatus)")
                disableInputMethodSourcesEnabledOnlyForInsertion(
                    [enabledSource, candidate],
                    enabledBeforeKeys: enabledBeforeKeys
                )
                return nil
            }
        }

        defer {
            restoreInputMethodSelection(
                originalSource: originalSource,
                enabledSource: enabledSource,
                candidateSource: candidate,
                enabledBeforeKeys: enabledBeforeKeys,
                reason: preselectedSession == nil ? "post_insert" : "post_preselected_insert"
            )
        }

        let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JarvisTap", isDirectory: true)
        let payloadURL = supportDirectory.appendingPathComponent("input-method-insert.txt")
        let acknowledgementURL = supportDirectory.appendingPathComponent("input-method-insert-ack.json")

        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: acknowledgementURL)
            try preparedTranscript.write(
                to: payloadURL,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            traceLogger.log("Input method insertion unavailable reason=payload_write_failed error=\(error)")
            return nil
        }

        func postInsertionNotification(attempt: Int) {
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.am.presstalk.inputmethod.insert" as CFString),
                nil,
                nil,
                true
            )
            traceLogger.log("Input method insertion notification posted source=com.am.presstalk.inputmethod.container attempt=\(attempt)")
        }

        func waitForInsertionAcknowledgement(timeout: TimeInterval) -> InputMethodInsertionAcknowledgement? {
            let acknowledgementDeadline = Date().addingTimeInterval(timeout)
            while Date() < acknowledgementDeadline {
                if let acknowledgement = inputMethodInsertionAcknowledgement(at: acknowledgementURL) {
                    return acknowledgement
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            return nil
        }

        for attempt in 1...clampedMaxAttempts {
            Thread.sleep(forTimeInterval: attempt == 1 ? 0.75 : 0.35)
            postInsertionNotification(attempt: attempt)
            Thread.sleep(forTimeInterval: 0.25)

            if let acknowledgement = waitForInsertionAcknowledgement(timeout: attempt == 1 ? 2.0 : 3.0) {
                if acknowledgement.inserted {
                    traceLogger.log("Input method insertion acknowledgement inserted=1 attempt=\(attempt)")
                    clearInputMethodInsertionFailure(reason: "input_method_ack_inserted")
                    return "input_method_notification"
                }
                let detail = acknowledgement.reason ?? "input_method_ack_false"
                traceLogger.log("Input method insertion unavailable reason=input_method_ack_false detail=\(detail)")
                recordInputMethodInsertionFailure(reason: detail)
                return nil
            }

            guard attempt < clampedMaxAttempts else { break }
            traceLogger.log("Input method insertion acknowledgement retrying reason=input_method_ack_timeout attempt=\(attempt)")
            let restoreStatus = runTISOperationOnMainThread {
                TISSelectInputSource(originalSource)
            }
            if restoreStatus != 0 {
                traceLogger.log("Input method insertion retry restore failed status=\(restoreStatus)")
            }
            Thread.sleep(forTimeInterval: 0.2)
            let reselectStatus = runTISOperationOnMainThread {
                TISSelectInputSource(enabledSource)
            }
            if reselectStatus != 0 {
                traceLogger.log("Input method insertion unavailable reason=retry_select_failed status=\(reselectStatus)")
                return nil
            }
        }

        traceLogger.log("Input method insertion unavailable reason=input_method_ack_timeout")
        recordInputMethodInsertionFailure(reason: "input_method_ack_timeout")
        return nil
    }

    private func insertPreparedTranscriptUsingAccessibility(_ preparedTranscript: String) -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )
        guard focusedError == .success, let focusedObject else {
            traceLogger.log("AX direct insertion unavailable reason=focused_element error=\(focusedError.rawValue)")
            return nil
        }

        guard let focusedElement = axElement(from: focusedObject) else {
            traceLogger.log("AX direct insertion unavailable reason=focused_object_not_ax_element")
            return nil
        }

        let selectedTextError = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            preparedTranscript as CFTypeRef
        )
        if selectedTextError == .success {
            return "ax_selected_text"
        }

        var selectedRangeObject: CFTypeRef?
        let selectedRangeError = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeObject
        )
        let selectedRange = selectedRangeError == .success ? axRange(from: selectedRangeObject) : nil

        var valueObject: CFTypeRef?
        let valueError = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &valueObject
        )
        guard valueError == .success, let currentValue = valueObject as? String, let selectedRange else {
            traceLogger.log(
                "AX direct insertion unavailable reason=value_range selected_text_error=\(selectedTextError.rawValue) selected_range_error=\(selectedRangeError.rawValue) value_error=\(valueError.rawValue)"
            )
            return nil
        }

        let currentNSString = currentValue as NSString
        let safeLocation = min(max(selectedRange.location, 0), currentNSString.length)
        let safeLength = min(max(selectedRange.length, 0), currentNSString.length - safeLocation)
        let updatedValue = currentNSString.replacingCharacters(
            in: NSRange(location: safeLocation, length: safeLength),
            with: preparedTranscript
        )
        let setValueError = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            updatedValue as CFTypeRef
        )
        guard setValueError == .success else {
            traceLogger.log("AX direct insertion unavailable reason=set_value error=\(setValueError.rawValue)")
            return nil
        }

        var updatedRange = CFRange(
            location: safeLocation + (preparedTranscript as NSString).length,
            length: 0
        )
        if let updatedRangeValue = AXValueCreate(.cfRange, &updatedRange) {
            _ = AXUIElementSetAttributeValue(
                focusedElement,
                kAXSelectedTextRangeAttribute as CFString,
                updatedRangeValue
            )
        }
        return "ax_value_range"
    }

    private func focusedApplicationProcessID() -> pid_t? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedApplicationObject: CFTypeRef?
        let focusedApplicationError = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApplicationObject
        )
        guard focusedApplicationError == .success, let focusedApplicationObject else {
            traceLogger.log("Focused application PID unavailable reason=focused_application error=\(focusedApplicationError.rawValue)")
            return nil
        }

        guard let focusedApplication = axElement(from: focusedApplicationObject) else {
            traceLogger.log("Focused application PID unavailable reason=focused_application_not_ax_element")
            return nil
        }

        var processID: pid_t = 0
        let processIDError = AXUIElementGetPid(focusedApplication, &processID)
        guard processIDError == .success, processID > 0 else {
            traceLogger.log("Focused application PID unavailable reason=get_pid error=\(processIDError.rawValue) pid=\(processID)")
            return nil
        }
        return processID
    }

    private func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var valueObject: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueObject)
        guard error == .success else { return nil }
        return valueObject as? String
    }

    private func axBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var valueObject: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueObject)
        guard error == .success else { return nil }
        return valueObject as? Bool
    }

    private func axChildren(of element: AXUIElement) -> [AXUIElement] {
        var childrenObject: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenObject)
        guard error == .success, let childrenObject else { return [] }
        return (childrenObject as? [AXUIElement]) ?? []
    }

    private func findPasteMenuItem(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth <= 8 else { return nil }

        let role = axStringAttribute(element, kAXRoleAttribute as String)
        let title = axStringAttribute(element, kAXTitleAttribute as String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let pasteTitles: Set<String> = ["paste", "einsetzen", "einfügen"]
        if role == kAXMenuItemRole as String,
           let title,
           pasteTitles.contains(title),
           axBoolAttribute(element, kAXEnabledAttribute as String) != false {
            return element
        }

        for child in axChildren(of: element) {
            if let match = findPasteMenuItem(in: child, depth: depth + 1) {
                return match
            }
        }
        return nil
    }

    private func pressFocusedApplicationPasteMenuItem() -> Bool {
        guard let focusedPID = focusedApplicationProcessID() else {
            return false
        }

        let focusedApplication = AXUIElementCreateApplication(focusedPID)
        var menuBarObject: CFTypeRef?
        let menuBarError = AXUIElementCopyAttributeValue(
            focusedApplication,
            kAXMenuBarAttribute as CFString,
            &menuBarObject
        )
        guard menuBarError == .success,
              let menuBarObject,
              let menuBar = axElement(from: menuBarObject)
        else {
            traceLogger.log("Paste menu unavailable reason=menu_bar error=\(menuBarError.rawValue) target_pid=\(focusedPID)")
            return false
        }

        guard let pasteMenuItem = findPasteMenuItem(in: menuBar) else {
            traceLogger.log("Paste menu unavailable reason=item_not_found target_pid=\(focusedPID)")
            return false
        }

        let pressError = AXUIElementPerformAction(pasteMenuItem, kAXPressAction as CFString)
        guard pressError == .success else {
            traceLogger.log("Paste menu press failed error=\(pressError.rawValue) target_pid=\(focusedPID)")
            return false
        }

        traceLogger.log("Paste menu pressed target_pid=\(focusedPID)")
        return true
    }

    private func postPasteShortcut() throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            throw JarvisTapError.eventSynthesisUnavailable
        }

        commandDown.flags = .maskCommand
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        commandUp.flags = []

        func postPasteSequence(_ post: (CGEvent) -> Void) {
            post(commandDown)
            Thread.sleep(forTimeInterval: 0.035)
            post(keyDown)
            Thread.sleep(forTimeInterval: 0.035)
            post(keyUp)
            Thread.sleep(forTimeInterval: 0.035)
            post(commandUp)
        }

        if let focusedPID = focusedApplicationProcessID() {
            postPasteSequence { event in
                event.postToPid(focusedPID)
            }
            traceLogger.log("Paste shortcut posted target_pid=\(focusedPID)")
            return
        }

        postPasteSequence { event in
            event.post(tap: .cgSessionEventTap)
        }
        traceLogger.log("Paste shortcut posted target=session")
    }

    private func releaseLatchedAlternateModifierAfterInsertionIfNeeded(reason: String) {
        guard !configuredTriggerUsesAlternateModifier else { return }

        let hidFlags = CGEventSource.flagsState(.hidSystemState)
        let sessionFlags = CGEventSource.flagsState(.combinedSessionState)
        guard hidFlags.contains(.maskAlternate) || sessionFlags.contains(.maskAlternate) else { return }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        for keyCode in [CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption)] {
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                keyUp.flags = []
                keyUp.post(tap: .cgSessionEventTap)
            }
        }

        traceLogger.log(
            "Released latched Option modifier after insertion reason=\(reason) hid_flags=0x\(String(hidFlags.rawValue, radix: 16)) session_flags=0x\(String(sessionFlags.rawValue, radix: 16))"
        )
    }

    private var configuredTriggerUsesAlternateModifier: Bool {
        switch settingsStore.triggerKey {
        case .optionSpace, .option, .leftOption, .rightOption:
            return true
        case .fn, .trackpadHold, .f5:
            return false
        }
    }

    private func insertTranscriptIntoFocusedApp(
        _ transcript: String,
        context: InputMethodInsertionContext
    ) throws -> TranscriptInsertionResult {
        let preparedTranscript = transcriptForInsertion(transcript)
        guard !preparedTranscript.isEmpty else {
            return .copiedFallback(reason: "empty_transcript")
        }

        guard AXIsProcessTrusted() else {
            let copiedBeforeFallback = context == .dictation
            var fallbackStaging: PasteboardInsertionStaging?
            if copiedBeforeFallback {
                fallbackStaging = stagePreparedTranscriptOnPasteboard(preparedTranscript)
                traceLogger.log("Accessibility preflight unavailable; copied transcript before insertion fallback")
            }

            if context == .dictation && !inputMethodDictationInsertionEnabled() {
                restoreInputMethodPreselectionIfNeeded(reason: "dictation_input_method_probe_only")
                traceLogger.log("Accessibility preflight unavailable; input method dictation insertion disabled after real-field client failures; copying transcript")
                return .copiedFallback(reason: "accessibility_required_for_auto_insert")
            }

            let preselectedSession = context == .dictation ? takeInputMethodPreselection() : nil
            if context == .dictation, let recentFailure = recentInputMethodInsertionFailure(), preselectedSession == nil {
                let fallbackReason = copiedFallbackReason(for: recentFailure)
                traceLogger.log(
                    "Accessibility preflight unavailable and input method insertion skipped reason=recent_\(recentFailure.reason); copying transcript"
                )
                if !copiedBeforeFallback {
                    copyPreparedTranscriptToPasteboard(preparedTranscript)
                }
                return .copiedFallback(reason: fallbackReason)
            }
            let maxInputMethodAttempts = context == .productionProbe ? 3 : 1
            if let method = insertPreparedTranscriptUsingInputMethod(
                preparedTranscript,
                maxAttempts: maxInputMethodAttempts,
                preselectedSession: preselectedSession
            ) {
                if let fallbackStaging {
                    restorePasteboardAfterInsertion(fallbackStaging)
                }
                return .inserted(method: method)
            }
            traceLogger.log("Accessibility preflight unavailable and input method insertion unavailable; copying transcript")
            if !copiedBeforeFallback {
                copyPreparedTranscriptToPasteboard(preparedTranscript)
            }
            return .copiedFallback(reason: "accessibility_preflight_unavailable")
        }

        let pasteboardStaging = stagePreparedTranscriptOnPasteboard(preparedTranscript)

        if pressFocusedApplicationPasteMenuItem() {
            restorePasteboardAfterInsertion(pasteboardStaging)
            return .inserted(method: "ax_menu_paste")
        }

        do {
            try postPasteShortcut()
            traceLogger.log("Accessibility trusted; paste command posted with transcript on pasteboard")
            restorePasteboardAfterInsertion(pasteboardStaging)
            return .pasteCommandPosted
        } catch {
            traceLogger.log("Accessibility paste command unavailable error=\(error)")
        }

        if let method = insertPreparedTranscriptUsingAccessibility(preparedTranscript) {
            restorePasteboardAfterInsertion(pasteboardStaging)
            return .inserted(method: method)
        }

        return .copiedFallback(reason: "accessibility_paste_command_unavailable")
    }

    private func recordTriggerSource(_ source: TriggerSource, phase: TriggerPhase) {
        var shouldLogObservation = false
        withStateLock {
            switch source {
            case .trackpadHold:
                shouldLogObservation = !triggerBridgeTelemetry.trackpadHoldSeen
                triggerBridgeTelemetry.trackpadHoldSeen = true
            case .registeredHotKey:
                shouldLogObservation = !triggerBridgeTelemetry.registeredHotKeySeen
                triggerBridgeTelemetry.registeredHotKeySeen = true
            case .modifierKey:
                shouldLogObservation = !triggerBridgeTelemetry.modifierKeySeen
                triggerBridgeTelemetry.modifierKeySeen = true
            case .darwinNotification:
                shouldLogObservation = !triggerBridgeTelemetry.darwinNotificationSeen
                triggerBridgeTelemetry.darwinNotificationSeen = true
            case .nativeSystemDefined:
                shouldLogObservation = !triggerBridgeTelemetry.nativeSystemDefinedSeen
                triggerBridgeTelemetry.nativeSystemDefinedSeen = true
            case .cgFunctionKey:
                shouldLogObservation = !triggerBridgeTelemetry.cgFunctionKeySeen
                triggerBridgeTelemetry.cgFunctionKeySeen = true
            }
            triggerBridgeTelemetry.lastSource = source
            triggerBridgeTelemetry.lastEventAt = Date()
            triggerBridgeTelemetry.lastPhase = phase
        }
        if shouldLogObservation {
            traceLogger.log("Trigger bridge observed source=\(source.rawValue)")
        }
        refreshRuntimeStatusUI()
    }

    private func shouldSuppressDuplicateTriggerEvent(phase: TriggerPhase, source: TriggerSource) -> Bool {
        let duplicateWindowSeconds = 0.14
        return withStateLock {
            guard let lastEventAt = triggerBridgeTelemetry.lastEventAt,
                  let lastPhase = triggerBridgeTelemetry.lastPhase,
                  let lastSource = triggerBridgeTelemetry.lastSource
            else { return false }
            guard lastPhase == phase else { return false }
            guard lastSource != source else { return false }
            let delta = Date().timeIntervalSince(lastEventAt)
            return delta >= 0 && delta < duplicateWindowSeconds
        }
    }

    private func handlePress(_ trigger: Trigger, source: TriggerSource, announce: Bool = true) {
        if shouldSuppressDuplicateTriggerEvent(phase: .press, source: source) {
            traceLogger.log("Trigger duplicate ignored trigger=\(trigger.rawValue) phase=press source=\(source.rawValue)")
            return
        }
        recordTriggerSource(source, phase: .press)

        // Checked before the state lock and before the microphone opens, so an
        // expired trial never records audio it is not going to transcribe.
        // `shouldBlockDictation` is false unless the trial genuinely expired,
        // the anchor reading was trustworthy, and a checkout actually exists to
        // buy from -- see PressTalkLicenseStore.
        if licenseStore.shouldBlockDictation {
            traceLogger.log("Dictation refused reason=trial_expired")
            presentTrialExpiredIfNeeded()
            return
        }

        enum PressDecision {
            case ignoreSilently
            case ignoreStillProcessing
            case start(UInt64)
        }

        let decision = withStateLock { () -> PressDecision in
            if isRecording {
                return .ignoreSilently
            }
            if isProcessing {
                return .ignoreStillProcessing
            }

            latestStreamingState = StreamingSnapshot()
            lastPrintedPartial = ""
            activeCaptureSessionID &+= 1
            activeCaptureEngineStarted = false
            activeTrigger = trigger
            activeTriggerSource = source
            isRecording = true
            activeTriggerStartedAt = Date()
            return .start(activeCaptureSessionID)
        }

        let captureSessionID: UInt64
        switch decision {
        case .ignoreSilently:
            return
        case .ignoreStillProcessing:
            traceLogger.log("Trigger ignored trigger=\(trigger.rawValue) reason=still_processing")
            print("⏳ [PressTalk] Still processing the previous dictation. Ignoring trigger.")
            fflush(stdout)
            return
        case .start(let sessionID):
            captureSessionID = sessionID
        }
        resetLiveCapturedAudioSamples()

        if let readinessMessage = currentWhisperReadinessMessage() {
            withStateLock {
                isRecording = false
                activeTrigger = nil
                activeTriggerSource = nil
                activeTriggerStartedAt = nil
                activeCaptureEngineStarted = false
            }
            startWhisperWarmupIfNeeded()
            traceLogger.log("Trigger ignored trigger=\(trigger.rawValue) reason=whisper_not_ready")
            print("⌛ [PressTalk] \(readinessMessage)")
            fflush(stdout)
            present(.error(readinessMessage))
            speaker.speak(readinessMessage)
            return
        }

        do {
            try resetStreamingSession()
        } catch {
            withStateLock {
                isRecording = false
                activeTrigger = nil
                activeTriggerSource = nil
                activeTriggerStartedAt = nil
                activeCaptureEngineStarted = false
            }
            traceLogger.log("Trigger failed trigger=\(trigger.rawValue) reason=stream_transcriber_unavailable error=\(error)")
            fputs("[PressTalk] Stream transcriber unavailable: \(error)\n", stderr)
            return
        }

        beginInputMethodPreselectionForDictationIfNeeded()

        if announce {
            traceLogger.log(triggerStartLogMessage(for: trigger))
            present(.listening(nil))
            print("🎤 [PressTalk] Listening... [trigger=\(trigger.rawValue)]")
            fflush(stdout)
        } else {
            traceLogger.log("Trackpad prearm capture started")
        }

        let selectedAudioInputSelection = preferredAudioInputDevice()
        let selectedAudioInput = selectedAudioInputSelection?.candidate
        var selectedAudioInputDescription = selectedAudioInput.map {
            if $0.isDefault {
                return "system default (\($0.name) [id=\($0.id), transport=\($0.transportDescription), channels=\($0.inputChannels)])"
            }
            return "\($0.name) [id=\($0.id), transport=\($0.transportDescription), channels=\($0.inputChannels)]"
        } ?? "system default"
        if let selectedAudioInput, selectedAudioInput.isDefault == false,
           audioInputPromotionAllowed {
            let previousDefault = defaultCoreAudioInputDeviceID()
            let promotionSucceeded = setDefaultCoreAudioInputDeviceID(selectedAudioInput.id)
            if promotionSucceeded, let previousDefault, previousDefault != selectedAudioInput.id {
                displacedDefaultInputDeviceID = previousDefault
            }
            // CoreAudio reports the new default device long before it is ready
            // to deliver buffers. On 2026-09-06 a fixed 0.12 s sleep here was
            // followed by an engine that took 1.66 s to start and then captured
            // 37 seconds of digital silence: the default had changed, the
            // hardware had not finished re-arming.
            //
            // Polling until the default actually reports the promoted device is
            // a better wait than a constant, because it ends as soon as the
            // switch lands instead of always costing the same. It is still not
            // proof that audio will flow -- nothing observable here is -- so
            // CaptureIntegrity remains the backstop that tells the user when it
            // does not. The observed settle time is logged so the real
            // distribution can replace this guess with a measurement.
            var promotedDefaultID: AudioDeviceID?
            if promotionSucceeded {
                let settleDeadline = Date().addingTimeInterval(0.75)
                let settleStartedAt = Date()
                repeat {
                    promotedDefaultID = defaultCoreAudioInputDeviceID()
                    if promotedDefaultID == selectedAudioInput.id { break }
                    Thread.sleep(forTimeInterval: 0.02)
                } while Date() < settleDeadline
                traceLogger.log(
                    "Audio input default promotion settle seconds="
                    + String(format: "%.3f", Date().timeIntervalSince(settleStartedAt))
                    + " landed=\(promotedDefaultID == selectedAudioInput.id ? 1 : 0)")
                // A device that has just been re-armed needs a moment before
                // its first buffer is real rather than a zero-filled prime.
                Thread.sleep(forTimeInterval: 0.08)
            } else {
                promotedDefaultID = defaultCoreAudioInputDeviceID()
            }
            if promotionSucceeded, promotedDefaultID == selectedAudioInput.id {
                selectedAudioInputDescription = "system default promoted (\(selectedAudioInput.name) [id=\(selectedAudioInput.id), transport=\(selectedAudioInput.transportDescription), channels=\(selectedAudioInput.inputChannels)])"
                traceLogger.log(
                    "Audio input default promotion verified source=\(selectedAudioInputSelection?.source ?? "unknown") device_id=\(selectedAudioInput.id)"
                )
            } else {
                traceLogger.log(
                    "Audio input default promotion not active source=\(selectedAudioInputSelection?.source ?? "unknown") selected_device_id=\(selectedAudioInput.id) current_default_id=\(promotedDefaultID.map(String.init) ?? "none")"
                )
                if let currentDefault = coreAudioInputDevices().first(where: { $0.isDefault }) {
                    selectedAudioInputDescription = "system default (\(currentDefault.name) [id=\(currentDefault.id), transport=\(currentDefault.transportDescription), channels=\(currentDefault.inputChannels)])"
                }
            }
        }
        withStateLock {
            activeAudioInputDeviceDescription = selectedAudioInputDescription
        }
        let captureKit = self.audioCaptureKit
        let traceLogger = self.traceLogger
        let audioStartRequestedAt = Date()
        let task = Task(priority: .userInitiated) { [self] in
            guard let captureKit else { return }
            do {
                traceLogger.log(
                    announce
                        ? "Audio recording started mode=direct input_device=\(selectedAudioInputDescription)"
                        : "Audio recording started mode=direct input_device=\(selectedAudioInputDescription) (prearm)"
                )
                if usesFluidTrueStreamingBackend {
                    try await resetFluidTrueStreamingTranscriptState()
                    traceLogger.log("FluidAudio true streaming state reset for capture")
                }
                if let failure = Self.audioInputPreflightFailure() {
                    traceLogger.log("Audio input preflight FAILED: \(failure) -- refusing capture instead of aborting")
                    throw JarvisTapError.audioInputUnavailable(failure)
                }
                if let fixtureURL = Self.resolveFixtureAudioURL(config.fixtureAudioURL) {
                    // Replay mode. Everything downstream of capture -- freezing,
                    // recognition, cleanup, insertion, the latency spans -- runs
                    // exactly as it does for a real hold, but the samples are
                    // byte-identical between runs, so a timing or quality change
                    // means the code changed.
                    let samples = try Self.loadFixtureAudioSamples(at: fixtureURL)
                    traceLogger.log(
                        "Fixture audio loaded path=\(fixtureURL.path) samples=\(samples.count) seconds=\(String(format: "%.2f", Double(samples.count) / Double(WhisperKit.sampleRate)))")
                    appendLiveCapturedAudioSamples(samples, sessionID: captureSessionID)
                } else {
                    try captureKit.audioProcessor.startRecordingLive(inputDeviceID: nil) { [weak self] samples in
                        self?.appendLiveCapturedAudioSamples(samples, sessionID: captureSessionID)
                    }
                }
                let shouldContinue = withStateLock { () -> Bool in
                    guard activeCaptureSessionID == captureSessionID,
                          isRecording,
                          activeTrigger == trigger
                    else {
                        return false
                    }
                    activeCaptureEngineStarted = true
                    return true
                }
                guard shouldContinue, !Task.isCancelled else {
                    traceLogger.log("Audio recording engine started after session ended; stopping stale capture session=\(captureSessionID)")
                    safelyStopLiveAudioRecording(captureKit: captureKit, reason: "stale_capture_start")
                    return
                }
                let engineStartLatency = Date().timeIntervalSince(audioStartRequestedAt)
                withStateLock { activeEngineStartLatencySeconds = engineStartLatency }
                traceLogger.log(
                    "Audio recording engine started mode=direct start_latency_seconds=\(String(format: "%.3f", engineStartLatency)) session=\(captureSessionID)"
                )
                if usesFluidTrueStreamingBackend && config.streamingTranscriptionEnabled {
                    await runFluidTrueStreamingLoop()
                } else if config.streamingTranscriptionEnabled, let whisperKit = self.whisperKit {
                    await runRealtimeWhisperLoop(whisperKit: whisperKit)
                } else {
                    while !Task.isCancelled {
                        let stillRecording = withStateLock {
                            isRecording && activeCaptureSessionID == captureSessionID
                        }
                        if !stillRecording { break }
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                    traceLogger.log("Audio recording wait loop stopped mode=direct streaming=0")
                }
            } catch {
                let shouldReportFailure = self.withStateLock { () -> Bool in
                    guard self.activeCaptureSessionID == captureSessionID else { return false }
                    self.isRecording = false
                    self.activeTrigger = nil
                    self.activeTriggerSource = nil
                    self.activeTriggerStartedAt = nil
                    self.activeCaptureEngineStarted = false
                    self.streamTask = nil
                    return true
                }
                guard shouldReportFailure else {
                    traceLogger.log("Audio recording failed for stale capture session=\(captureSessionID) error=\(error)")
                    return
                }
                traceLogger.log("Audio recording failed mode=direct error=\(error)")
                self.restoreInputMethodPreselectionIfNeeded(reason: "audio_recording_failed")
                self.stopAmplitudeMonitoring()
                if announce {
                    self.present(.error("The audio capture stream failed."))
                    fputs("[PressTalk] Audio recording failed: \(error)\n", stderr)
                }
            }
        }
        withStateLock {
            streamTask = task
        }
        if announce {
            startAmplitudeMonitoring()
        }
    }

    private func handleRelease(_ trigger: Trigger, source: TriggerSource) {
        if shouldSuppressDuplicateTriggerEvent(phase: .release, source: source) {
            traceLogger.log("Trigger duplicate ignored trigger=\(trigger.rawValue) phase=release source=\(source.rawValue)")
            return
        }
        recordTriggerSource(source, phase: .release)

        var currentStreamTask: Task<Void, Never>?
        var capturedSnapshot = StreamingSnapshot()
        var captureDurationSeconds = 0.0
        var captureEngineStartedBeforeRelease = false
        var releasedCaptureSessionID: UInt64 = 0
        let shouldProcess = withStateLock { () -> Bool in
            guard isRecording, activeTrigger == trigger else { return false }
            if let activeTriggerStartedAt {
                captureDurationSeconds = Date().timeIntervalSince(activeTriggerStartedAt)
            }
            captureEngineStartedBeforeRelease = activeCaptureEngineStarted
            releasedCaptureSessionID = activeCaptureSessionID
            isRecording = false
            activeTrigger = nil
            activeTriggerSource = nil
            activeTriggerStartedAt = nil
            isProcessing = true
            currentStreamTask = streamTask
            streamTask = nil
            capturedSnapshot = latestStreamingState
            return true
        }
        guard shouldProcess else { return }

        let keyUpAt = Date()
        stopAmplitudeMonitoring()
        traceLogger.log(triggerReleaseLogMessage(for: trigger))
        present(.processing)
        print("🚀 [PressTalk] Finalizing transcript... [trigger=\(trigger.rawValue)]")
        fflush(stdout)

        let traceLogger = self.traceLogger
        let responder = self.responder
        let codexAgent = self.codexAgent
        let agentMode = self.config.agentMode
        let speaker = self.speaker
        let whisperKit = self.whisperKit
        let captureKit = self.audioCaptureKit
        let decodingOptions = self.decodingOptions
        let pasteAutomatically = self.settingsStore.pasteAutomatically
        let streamTaskToStop = currentStreamTask
        let initialCapturedSnapshot = capturedSnapshot
        let releaseTelemetryStart = keyUpAt

        let task = Task(priority: .userInitiated) { [self] in
            var processingSnapshot = initialCapturedSnapshot
            var streamShutdownCompleted = true

            func finishProcessing(reason: String, spokenText: String? = nil) {
                self.withStateLock {
                    self.isProcessing = false
                    self.processingTask = nil
                    if self.activeCaptureSessionID == releasedCaptureSessionID {
                        self.activeCaptureEngineStarted = false
                    }
                }
                self.restoreInputMethodPreselectionIfNeeded(reason: reason)
                traceLogger.log("Processing task finished reason=\(reason) state_reset=true")
                if let spokenText {
                    speaker.speak(spokenText)
                }
            }

            func fallbackTranscript() -> String {
                bestTranscriptCandidate(from: [
                    processingSnapshot.confirmedText,
                    processingSnapshot.unconfirmedText,
                    processingSnapshot.currentText,
                ])
            }

            let capturedAudioSamples: [Float]
            let normalizedSamples: [Float]
            let capturedSignalStats: (rms: Double, peak: Double)
            let frozenAudioDurationSeconds: Double
            await captureSilenceAwareReleaseTail(
                captureKit: captureKit,
                heldSeconds: captureDurationSeconds,
                engineStartLatencySeconds: withStateLock { activeEngineStartLatencySeconds })
            if let streamTaskToStop {
                if config.streamingTranscriptionEnabled {
                    // Do NOT block the paste on stream teardown.
                    //
                    // This used to `await awaitStreamShutdown(...)`, which waits up
                    // to streamShutdownTimeoutSeconds (2.0s) before the final pass
                    // can even start. Measured field smokes showed the cost:
                    // parakeet inference is 82-133 ms while release-to-insert was
                    // 245-1345 ms, so the model was 5-35% of the wait and pipeline
                    // overhead was the rest.
                    //
                    // The streaming text is only ever used as a FALLBACK when the
                    // final pass produces nothing, and a snapshot was already taken
                    // at release time. So cancel, keep that snapshot, and let
                    // teardown finish off the critical path.
                    let shutdownStartedAt = Date()
                    streamTaskToStop.cancel()
                    streamShutdownCompleted = true
                    Task.detached(priority: .utility) {
                        _ = await streamTaskToStop.result
                        // span: cancelIssued -> streamExit. Off the critical
                        // path, but logged so an abandoned task that never
                        // exits is visible rather than silently leaked.
                        traceLogger.log(
                            "latency span=cancel_to_stream_exit seconds=\(String(format: "%.3f", Date().timeIntervalSince(shutdownStartedAt)))")
                    }
                    traceLogger.log("Realtime stream cancelled without blocking paste")
                } else {
                    streamTaskToStop.cancel()
                    streamShutdownCompleted = true
                    traceLogger.log("Capture task cancelled without realtime stream")
                }
            }
            // Refresh the fallback snapshot with whatever the stream already
            // published. Not waiting for teardown means this can be marginally
            // staler than before -- it is only consulted if the final pass fails.
            processingSnapshot = withStateLock { latestStreamingState }

            if captureKit != nil {
                capturedAudioSamples = currentLiveCapturedAudioSamples()
                frozenAudioDurationSeconds = Double(capturedAudioSamples.count) / Double(WhisperKit.sampleRate)
                capturedSignalStats = audioLevelStats(for: capturedAudioSamples)
                let normalizedResult = normalizedAudioSamples(capturedAudioSamples)
                normalizedSamples = normalizedResult.0
                let normalizedStats = audioLevelStats(for: normalizedSamples)
                let audioInputDescription = withStateLock { activeAudioInputDeviceDescription }
                traceLogger.log(
                    "latency span=keyup_to_audio_frozen seconds=\(String(format: "%.3f", Date().timeIntervalSince(releaseTelemetryStart)))")
                traceLogger.log(
                    "Audio capture frozen samples=\(capturedAudioSamples.count) duration_seconds=\(String(format: "%.2f", frozenAudioDurationSeconds)) rms=\(String(format: "%.5f", capturedSignalStats.rms)) peak=\(String(format: "%.5f", capturedSignalStats.peak)) input_device=\(audioInputDescription)"
                )
                if capturedAudioSamples.isEmpty {
                    traceLogger.log("Audio capture unavailable reason=no_buffers input_device=\(audioInputDescription)")
                }
                traceLogger.log(
                    "Audio normalization gain=\(String(format: "%.2f", normalizedResult.1)) normalized_rms=\(String(format: "%.5f", normalizedStats.rms)) normalized_peak=\(String(format: "%.5f", normalizedStats.peak))"
                )
            } else {
                capturedAudioSamples = []
                normalizedSamples = []
                capturedSignalStats = (0, 0)
                frozenAudioDurationSeconds = 0
            }

            // What arrived, against what was asked for. Runs before any
            // recognizer sees the audio, because the recognizers are the part
            // that turns a broken recording into confident words.
            let captureVerdict = CaptureIntegrity.evaluate(
                capturedSeconds: frozenAudioDurationSeconds,
                heldSeconds: captureDurationSeconds,
                rms: capturedSignalStats.rms,
                peak: capturedSignalStats.peak)
            if !captureVerdict.isUsable {
                traceLogger.log(
                    "Capture integrity failed verdict=\(captureVerdict) "
                    + "captured_seconds=\(String(format: "%.2f", frozenAudioDurationSeconds)) "
                    + "held_seconds=\(String(format: "%.2f", captureDurationSeconds)) "
                    + "rms=\(String(format: "%.5f", capturedSignalStats.rms)) "
                    + "peak=\(String(format: "%.5f", capturedSignalStats.peak))")
            }

            func finalizeTranscript() async throws -> String {
                // A recording that failed integrity is not transcribed at all.
                // Handing it to the ladder is how "you you" reached a chat
                // window: every pass after the first is a retry with looser
                // decoding, so the worse the audio, the harder the app tries to
                // find words in it.
                if !captureVerdict.isUsable { return "" }
                let streamingTranscript = fallbackTranscript()
                let effectiveCaptureDurationSeconds = max(captureDurationSeconds, frozenAudioDurationSeconds)
                let acceptedStreamingTranscript = validatedFinalTranscriptCandidate(
                    streamingTranscript,
                    signalStats: capturedSignalStats,
                    captureDurationSeconds: effectiveCaptureDurationSeconds,
                    context: "streaming_fallback"
                )
                if usesFluidTrueStreamingBackend, !usesParakeetFinalBackend, !capturedAudioSamples.isEmpty {
                    traceLogger.log("Finalizing FluidAudio true streaming transcript samples=\(capturedAudioSamples.count)")
                    do {
                        if let acceptedFluidStreamingTranscript = try await finishFluidTrueStreamingTranscript(
                            samples: capturedAudioSamples,
                            signalStats: capturedSignalStats,
                            captureDurationSeconds: effectiveCaptureDurationSeconds
                        ) {
                            traceLogger.log("Using FluidAudio true streaming transcript as final transcript")
                            return acceptedFluidStreamingTranscript
                        }
                        traceLogger.log("FluidAudio true streaming transcript rejected; falling back to WhisperKit")
                    } catch {
                        traceLogger.log("FluidAudio true streaming transcript failed; falling back to WhisperKit error=\(error)")
                    }
                }
                if !usesParakeetFinalBackend,
                   let acceptedStreamingTranscript,
                   !usesFluidTrueStreamingBackend,
                   streamingSnapshotFreshEnoughForFinal(processingSnapshot, frozenAudioDurationSeconds: frozenAudioDurationSeconds) {
                    traceLogger.log("Using realtime Whisper streaming transcript as final transcript revision=\(processingSnapshot.revision)")
                    return acceptedStreamingTranscript
                }

                var acceptedParakeetTranscriptForFallback: String?
                var whisperCandidateDeferredForRecall = false
                if usesParakeetFinalBackend, !capturedAudioSamples.isEmpty {
                    traceLogger.log("Finalizing Parakeet v3 ANE transcript samples=\(capturedAudioSamples.count)")
                    do {
                        var parakeetAcceptedForQualityFallback = false
                        let finalInferenceStartedAt = Date()
                        let parakeetCandidate = try await transcribeParakeetV3ANE(samples: normalizedSamples)
                        traceLogger.log(
                            "latency span=final_inference seconds=\(String(format: "%.3f", Date().timeIntervalSince(finalInferenceStartedAt)))")
                        traceTranscriptCandidate("Parakeet v3 ANE transcript", text: parakeetCandidate.text)
                        if let acceptedParakeetTranscript = validatedFinalTranscriptCandidate(
                            parakeetCandidate.text,
                            signalStats: capturedSignalStats,
                            captureDurationSeconds: effectiveCaptureDurationSeconds,
                            context: "parakeet_v3_ane"
                        ) {
                            let acceptedCandidate = ParakeetTranscriptCandidate(
                                text: acceptedParakeetTranscript,
                                confidence: parakeetCandidate.confidence
                            )
                            if let fallbackReason = parakeetStreamingRecallFallbackReason(
                                parakeetTranscript: acceptedParakeetTranscript,
                                streamingTranscript: acceptedStreamingTranscript,
                                captureDurationSeconds: effectiveCaptureDurationSeconds,
                                context: "parakeet_v3_ane"
                            ) {
                                parakeetAcceptedForQualityFallback = true
                                traceLogger.log(
                                    "Parakeet v3 ANE transcript accepted but quality fallback requested reason=\(fallbackReason)"
                                )
                            } else if let fallbackReason = parakeetQualityFallbackReason(
                                for: acceptedCandidate,
                                captureDurationSeconds: effectiveCaptureDurationSeconds
                            ) {
                                acceptedParakeetTranscriptForFallback = acceptedParakeetTranscript
                                parakeetAcceptedForQualityFallback = true
                                traceLogger.log(
                                    "Parakeet v3 ANE transcript accepted but quality fallback requested reason=\(fallbackReason)"
                                )
                            } else {
                                traceLogger.log("Using Parakeet v3 ANE transcript as final transcript")
                                return acceptedParakeetTranscript
                            }
                        }
                        if !parakeetAcceptedForQualityFallback {
                            traceLogger.log("Parakeet v3 ANE transcript rejected; falling back to WhisperKit")
                        }
                    } catch {
                        traceLogger.log("Parakeet v3 ANE transcript failed; falling back to WhisperKit error=\(error)")
                    }
                }

                guard let whisperKit else {
                    if let acceptedParakeetTranscriptForFallback {
                        traceLogger.log("Whisper unavailable; using accepted Parakeet v3 ANE transcript fallback")
                        return acceptedParakeetTranscriptForFallback
                    }
                    if let acceptedStreamingTranscript {
                        traceLogger.log("Whisper unavailable; using streaming transcript fallback")
                        return acceptedStreamingTranscript
                    }
                    throw JarvisTapError.whisperUnavailable
                }

                if !streamShutdownCompleted {
                    traceLogger.log("Skipping offline Whisper finalize because realtime stream shutdown timed out")
                    if let acceptedParakeetTranscriptForFallback {
                        traceLogger.log("Using accepted Parakeet v3 ANE transcript after realtime shutdown timeout")
                        return acceptedParakeetTranscriptForFallback
                    }
                    return acceptedStreamingTranscript ?? ""
                }

                let whisperLadderStartedAt = Date()
                traceLogger.log("Finalizing offline Whisper transcript samples=\(capturedAudioSamples.count)")
                if capturedAudioSamples.isEmpty {
                    traceLogger.log("No captured audio samples; using filtered streaming transcript fallback")
                    return acceptedStreamingTranscript ?? ""
                }

                let primaryResults = try await whisperKit.transcribe(audioArray: normalizedSamples, decodeOptions: decodingOptions)
                let primaryTranscript = cleanedTranscriptText(
                    primaryResults
                        .map(\.text)
                        .joined(separator: " ")
                )
                traceTranscriptCandidate("Primary offline Whisper transcript", text: primaryTranscript)

                // Held outside the if-let so the retry budget below can fall back
                // to a candidate that was already validated, rather than to
                // nothing.
                var budgetFallbackTranscript: String? = acceptedParakeetTranscriptForFallback
                if let acceptedPrimaryTranscript = validatedFinalTranscriptCandidate(
                    primaryTranscript,
                    signalStats: capturedSignalStats,
                    captureDurationSeconds: effectiveCaptureDurationSeconds,
                    context: "offline_primary"
                ) {
                    if shouldRejectWhisperCandidateForRecallQuality(
                        whisperTranscript: acceptedPrimaryTranscript,
                        parakeetTranscript: acceptedParakeetTranscriptForFallback,
                        streamingTranscript: acceptedStreamingTranscript,
                        captureDurationSeconds: effectiveCaptureDurationSeconds,
                        context: "offline_primary"
                    ) {
                        budgetFallbackTranscript = acceptedPrimaryTranscript
                        traceLogger.log("Primary offline Whisper transcript accepted but implausible against recall; retrying with relaxed decoding")
                    } else if shouldDeferShortWhisperCandidateForRecall(
                        whisperTranscript: acceptedPrimaryTranscript,
                        parakeetTranscript: acceptedParakeetTranscriptForFallback,
                        streamingTranscript: acceptedStreamingTranscript,
                        captureDurationSeconds: effectiveCaptureDurationSeconds,
                        context: "offline_primary"
                    ) {
                        whisperCandidateDeferredForRecall = true
                        budgetFallbackTranscript = acceptedPrimaryTranscript
                        traceLogger.log("Primary offline Whisper transcript accepted but too short; retrying with relaxed decoding")
                    } else {
                        traceLogger.log("Using offline Whisper transcript as final transcript")
                        return acceptedPrimaryTranscript
                    }
                } else {
                    traceLogger.log("Primary offline Whisper transcript rejected; retrying with relaxed decoding")
                }

                                if whisperLadderBudgetExhausted(startedAt: whisperLadderStartedAt, context: "relaxed"),
                   let budgeted = budgetFallbackTranscript {
                    return budgeted
                }
let relaxedResults = try await whisperKit.transcribe(
                    audioArray: normalizedSamples,
                    decodeOptions: relaxedDecodingOptions()
                )
                let relaxedTranscript = cleanedTranscriptText(
                    relaxedResults
                        .map(\.text)
                        .joined(separator: " ")
                )
                traceTranscriptCandidate("Relaxed offline Whisper transcript", text: relaxedTranscript)
                if let acceptedRelaxedTranscript = validatedFinalTranscriptCandidate(
                    relaxedTranscript,
                    signalStats: capturedSignalStats,
                    captureDurationSeconds: effectiveCaptureDurationSeconds,
                    context: "offline_relaxed"
                ) {
                    if shouldRejectWhisperCandidateForRecallQuality(
                        whisperTranscript: acceptedRelaxedTranscript,
                        parakeetTranscript: acceptedParakeetTranscriptForFallback,
                        streamingTranscript: acceptedStreamingTranscript,
                        captureDurationSeconds: effectiveCaptureDurationSeconds,
                        context: "offline_relaxed"
                    ) {
                        traceLogger.log("Relaxed offline Whisper transcript accepted but implausible against recall; retrying with auto-detect decoding")
                    } else if shouldDeferShortWhisperCandidateForRecall(
                        whisperTranscript: acceptedRelaxedTranscript,
                        parakeetTranscript: acceptedParakeetTranscriptForFallback,
                        streamingTranscript: acceptedStreamingTranscript,
                        captureDurationSeconds: effectiveCaptureDurationSeconds,
                        context: "offline_relaxed"
                    ) {
                        whisperCandidateDeferredForRecall = true
                        traceLogger.log("Relaxed offline Whisper transcript accepted but too short; retrying with auto-detect decoding")
                    } else {
                        traceLogger.log("Relaxed offline Whisper transcript accepted")
                        return acceptedRelaxedTranscript
                    }
                } else {
                    traceLogger.log("Relaxed offline Whisper transcript rejected; retrying with auto-detect decoding")
                }

                let autoResults = try await whisperKit.transcribe(
                    audioArray: normalizedSamples,
                    decodeOptions: autoDetectDecodingOptions()
                )
                let autoTranscript = cleanedTranscriptText(
                    autoResults
                        .map(\.text)
                        .joined(separator: " ")
                )
                traceTranscriptCandidate("Auto-detect offline Whisper transcript", text: autoTranscript)
                if let acceptedAutoTranscript = validatedFinalTranscriptCandidate(
                    autoTranscript,
                    signalStats: capturedSignalStats,
                    captureDurationSeconds: effectiveCaptureDurationSeconds,
                    context: "offline_auto_detect"
                ) {
                    if shouldRejectWhisperCandidateForRecallQuality(
                        whisperTranscript: acceptedAutoTranscript,
                        parakeetTranscript: acceptedParakeetTranscriptForFallback,
                        streamingTranscript: acceptedStreamingTranscript,
                        captureDurationSeconds: effectiveCaptureDurationSeconds,
                        context: "offline_auto_detect"
                    ) {
                        traceLogger.log("Auto-detect offline Whisper transcript accepted but implausible against recall; using recall fallback if available")
                    } else if shouldDeferShortWhisperCandidateForRecall(
                        whisperTranscript: acceptedAutoTranscript,
                        parakeetTranscript: acceptedParakeetTranscriptForFallback,
                        streamingTranscript: acceptedStreamingTranscript,
                        captureDurationSeconds: effectiveCaptureDurationSeconds,
                        context: "offline_auto_detect"
                    ) {
                        whisperCandidateDeferredForRecall = true
                        traceLogger.log("Auto-detect offline Whisper transcript accepted but too short; using recall fallback if available")
                    } else {
                        traceLogger.log("Auto-detect offline Whisper transcript accepted")
                        return acceptedAutoTranscript
                    }
                }

                if whisperCandidateDeferredForRecall,
                   let acceptedChunkedTranscript = try await chunkedWhisperFallbackTranscript(
                    whisperKit: whisperKit,
                    samples: normalizedSamples,
                    signalStats: capturedSignalStats,
                    captureDurationSeconds: effectiveCaptureDurationSeconds,
                    context: "recall_deferred"
                   ) {
                    if shouldDeferShortWhisperCandidateForRecall(
                        whisperTranscript: acceptedChunkedTranscript,
                        parakeetTranscript: acceptedParakeetTranscriptForFallback,
                        streamingTranscript: acceptedStreamingTranscript,
                        captureDurationSeconds: effectiveCaptureDurationSeconds,
                        context: "chunked_whisper_fallback"
                    ) {
                        traceLogger.log("Chunked offline Whisper transcript still too short; using recall fallback if available")
                    } else {
                        traceLogger.log("Using chunked offline Whisper transcript after short-candidate recall deferral")
                        return acceptedChunkedTranscript
                    }
                }

                if let acceptedParakeetTranscriptForFallback {
                    traceLogger.log("Using accepted Parakeet v3 ANE transcript fallback after Whisper candidates were empty, implausible, or too short")
                    return acceptedParakeetTranscriptForFallback
                }

                if let acceptedStreamingTranscript {
                    traceLogger.log("Whisper transcription empty or implausible; using streaming transcript fallback")
                    return acceptedStreamingTranscript
                }

                traceLogger.log("Whisper transcription empty or implausible; no fallback transcript available")
                return ""
            }

            func backendErrorDescription(_ error: Error) -> String {
                if let urlError = error as? URLError {
                    return urlError.localizedDescription
                }

                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain {
                    return nsError.localizedDescription
                }

                return String(describing: error)
            }

            func spokenErrorMessage(for error: Error) -> String {
                if let jarvisError = error as? JarvisTapError {
                    switch jarvisError {
                    case .accessibilityPermissionMissing:
                        return "I could not paste the transcript."
                    case .eventSynthesisUnavailable:
                        return "I could not paste the transcript."
                    default:
                        break
                    }
                }

                if let codexError = error as? CodexCLIError {
                    switch codexError {
                    case .timedOut:
                        return "Codex timed out before it finished."
                    default:
                        return "Codex hit an execution error."
                    }
                }

                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                        return "The backend is not ready yet."
                    default:
                        break
                    }
                }

                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain {
                    switch nsError.code {
                    case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
                        return "The backend is not ready yet."
                    default:
                        break
                    }
                }

                if case let JarvisTapError.httpFailure(statusCode, _) = error, statusCode >= 500 {
                    return "The backend is not ready yet."
                }

                return "I hit a backend error."
            }

            traceLogger.log("Processing task started")

            do {
                let transcript = try await finalizeTranscript()
                guard !transcript.isEmpty else {
                    traceLogger.log("No speech captured after release")
                    if capturedAudioSamples.isEmpty {
                        let audioInputDescription = withStateLock { activeAudioInputDeviceDescription }
                        traceLogger.log(
                            "No speech captured because selected audio input produced no buffers input_device=\(audioInputDescription) held_seconds=\(String(format: "%.2f", captureDurationSeconds))"
                        )
                        present(.audioUnavailable("No audio received from \(audioInputDescription). Check the macOS input device."))
                        print("⚠️ [PressTalk] No audio buffers captured from \(audioInputDescription).")
                        fflush(stdout)
                        finishProcessing(reason: "audio_no_buffers")
                        return
                    }
                    if !captureEngineStartedBeforeRelease {
                        traceLogger.log(
                            "No speech captured because audio engine was not ready before release session=\(releasedCaptureSessionID) held_seconds=\(String(format: "%.2f", captureDurationSeconds))"
                        )
                        present(.error("The microphone was still starting. Hold again."))
                        print("⚠️ [PressTalk] Audio capture was not ready before release.")
                        fflush(stdout)
                        finishProcessing(reason: "capture_not_ready")
                        return
                    }
                    // A capture that failed integrity gets its own message.
                    // "I didn't catch any clear speech" blames the speaker for
                    // a microphone that was never delivering, and the person
                    // then repeats themselves louder into the same dead input.
                    if let integrityMessage = captureVerdict.userFacingMessage {
                        present(.error(integrityMessage))
                        print("⚠️ [PressTalk] \(integrityMessage)")
                        fflush(stdout)
                        finishProcessing(reason: "capture_integrity_failed")
                        return
                    }
                    if captureDurationSeconds >= shortHoldNoSpeechSuppressionSeconds {
                        present(.error("I didn’t catch any clear speech."))
                    } else {
                        traceLogger.log("Short no-speech hold suppressed; returning presentation to ready")
                        present(.ready)
                    }
                    print("⚠️ [PressTalk] No speech captured.")
                    fflush(stdout)
                    finishProcessing(
                        reason: captureDurationSeconds >= shortHoldNoSpeechSuppressionSeconds ? "no_speech" : "no_speech_suppressed_short_hold"
                    )
                    return
                }

                traceLogger.log("📝 Transkription abgeschlossen: \(TranscriptRedaction.loggable(transcript))")
                print("🗣️ [PressTalk recognized] \(TranscriptRedaction.loggable(transcript))")
                fflush(stdout)

                recordHarnessOutcome(transcript: transcript, releasedAt: releaseTelemetryStart)

                if agentMode == "dictation" {
                    if pasteAutomatically && !config.testHarnessSuppressesInsertion {
                        traceLogger.log("Pasting dictated transcript into focused app")
                        let insertStartedAt = Date()
                        let insertionResult = try insertTranscriptIntoFocusedApp(transcript, context: .dictation)
                        traceLogger.log(
                            "latency span=insert seconds=\(String(format: "%.3f", Date().timeIntervalSince(insertStartedAt)))")
                        traceLogger.log(
                            "latency span=keyup_to_inserted seconds=\(String(format: "%.3f", Date().timeIntervalSince(releaseTelemetryStart)))")
                        switch insertionResult {
                        case .inserted(let method):
                            traceLogger.log("Dictation inserted method=\(method)")
                            releaseLatchedAlternateModifierAfterInsertionIfNeeded(reason: method)
                            recordDelivery(transcript, reachedTargetApp: true)
                            present(.inserted(transcript))
                            finishProcessing(reason: "dictation_insert")
                        case .pasteCommandPosted:
                            traceLogger.log("Dictation paste command posted")
                            releaseLatchedAlternateModifierAfterInsertionIfNeeded(reason: "paste_command_posted")
                            recordDelivery(transcript, reachedTargetApp: true)
                            present(.inserted(transcript))
                            finishProcessing(reason: "dictation_paste")
                        case .copiedFallback(let reason):
                            traceLogger.log("Dictation copied because paste unavailable reason=\(reason)")
                            recordDelivery(transcript, reachedTargetApp: false)
                            present(.copied("Copied — could not paste. \(transcript)"))
                            finishProcessing(reason: "dictation_copy_fallback")
                        }
                    } else {
                        copyTranscriptToPasteboard(transcript)
                        traceLogger.log("Dictation copy completed")
                        recordDelivery(transcript, reachedTargetApp: false)
                        present(.copied(transcript))
                        finishProcessing(reason: "dictation_copy")
                    }
                    return
                }

                let reply: String
                if agentMode == "codex-confirm-execute" {
                    traceLogger.log("Routing transcript to Codex agent")
                    reply = try await codexAgent.respond(to: transcript)
                } else {
                    reply = try await responder.reply(to: transcript)
                }
                traceLogger.log("✅ Antwort erhalten: \(reply)")
                present(.inserted(reply))
                print("🧠 [PressTalk reply]\n\(reply)\n")
                fflush(stdout)
                finishProcessing(reason: "reply", spokenText: reply)
            } catch {
                traceLogger.log("❌ Fehler/Timeout beim Backend: \(backendErrorDescription(error))")
                present(.error(spokenErrorMessage(for: error)))
                fputs("[PressTalk] Failed to process command: \(error)\n", stderr)
                finishProcessing(reason: "error", spokenText: spokenErrorMessage(for: error))
            }
        }
        withStateLock {
            processingTask = task
        }
    }

    private func awaitStreamShutdown(for task: Task<Void, Never>) async -> Bool {
        let timeoutNanoseconds = UInt64(streamShutdownTimeoutSeconds * 1_000_000_000)

        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false

            func resumeOnce(_ completed: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: completed)
            }

            Task {
                _ = await task.result
                resumeOnce(true)
            }
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                resumeOnce(false)
            }
        }
    }

    private func handleStreamingStateChange(oldState: AudioStreamTranscriber.State, newState: AudioStreamTranscriber.State) {
        guard withStateLock({ isRecording }) else { return }

        var cleanedToLog: String?
        var shouldPrintPartial = false

        withStateLock {
            let filteredCurrentText = bestTranscriptCandidate(from: [newState.currentText])
            let filteredConfirmedText = bestTranscriptCandidate(
                from: [newState.confirmedSegments.map { $0.text }.joined(separator: " ")]
            )
            let filteredUnconfirmedText = bestTranscriptCandidate(
                from: [newState.unconfirmedSegments.map { $0.text }.joined(separator: " ")]
            )
            let nextRevision = latestStreamingState.revision + 1

            latestStreamingState = StreamingSnapshot(
                currentText: filteredCurrentText,
                confirmedText: filteredConfirmedText,
                unconfirmedText: filteredUnconfirmedText,
                updatedAt: Date(),
                audioDurationSeconds: Double(newState.lastBufferSize) / Double(WhisperKit.sampleRate),
                revision: nextRevision
            )

            let cleaned = filteredCurrentText
            guard !cleaned.isEmpty else { return }
            guard cleaned != lastPrintedPartial else { return }

            lastPrintedPartial = cleaned
            cleanedToLog = cleaned
            shouldPrintPartial = config.printPartials && cleaned != cleanedTranscriptText(oldState.currentText)
        }

        guard let cleanedToLog else { return }
        traceLogger.log("Partial transcript: \(TranscriptRedaction.loggable(cleanedToLog))")
        present(.listening(cleanedToLog))
        if shouldPrintPartial {
            print("📝 [PressTalk partial] \(TranscriptRedaction.loggable(cleanedToLog))")
            fflush(stdout)
        }
    }

    private func processCapturedCommand(preferFallbackTranscript: Bool) async {
        defer {
            withStateLock {
                self.isProcessing = false
                self.processingTask = nil
            }
            restoreInputMethodPreselectionIfNeeded(reason: "process_captured_command_finished")
        }

        do {
            let transcript = try await finalizeTranscript(preferFallbackTranscript: preferFallbackTranscript)
            guard !transcript.isEmpty else {
                traceLogger.log("No speech captured after release")
                print("⚠️ [PressTalk] No speech captured.")
                fflush(stdout)
                return
            }

            traceLogger.log("📝 Transkription abgeschlossen: \(TranscriptRedaction.loggable(transcript))")
            print("🗣️ [PressTalk recognized] \(TranscriptRedaction.loggable(transcript))")
            fflush(stdout)

            if config.agentMode == "dictation" {
                traceLogger.log("Pasting dictated transcript into focused app")
                let insertionResult = try insertTranscriptIntoFocusedApp(transcript, context: .dictation)
                switch insertionResult {
                case .inserted(let method):
                    traceLogger.log("Dictation inserted method=\(method)")
                    releaseLatchedAlternateModifierAfterInsertionIfNeeded(reason: method)
                case .pasteCommandPosted:
                    traceLogger.log("Dictation paste command posted")
                    releaseLatchedAlternateModifierAfterInsertionIfNeeded(reason: "paste_command_posted")
                case .copiedFallback(let reason):
                    traceLogger.log("Dictation copied because paste unavailable reason=\(reason)")
                }
                return
            }

            let reply: String
            if config.agentMode == "codex-confirm-execute" {
                traceLogger.log("Routing transcript to Codex agent")
                reply = try await codexAgent.respond(to: transcript)
            } else {
                reply = try await responder.reply(to: transcript)
            }
            traceLogger.log("✅ Antwort erhalten: \(reply)")
            print("🧠 [PressTalk reply]\n\(reply)\n")
            fflush(stdout)
            speaker.speak(reply)
        } catch {
            traceLogger.log("❌ Fehler/Timeout beim Backend: \(backendErrorDescription(error))")
            fputs("[PressTalk] Failed to process command: \(error)\n", stderr)
            speaker.speak(spokenErrorMessage(for: error))
        }
    }

    private func finalizeTranscript(preferFallbackTranscript: Bool) async throws -> String {
        guard let whisperKit else {
            throw JarvisTapError.whisperUnavailable
        }

        if preferFallbackTranscript {
            traceLogger.log("Skipping offline Whisper finalize because live stream shutdown timed out")
            return validatedFinalTranscriptCandidate(
                fallbackTranscript(),
                signalStats: (0, 0),
                captureDurationSeconds: 0,
                context: "streaming_timeout_fallback"
            ) ?? ""
        }

        let capturedSamples = currentLiveCapturedAudioSamples()
        let whisperLadderStartedAt = Date()
            traceLogger.log("Finalizing offline Whisper transcript samples=\(capturedSamples.count)")
        if capturedSamples.isEmpty {
            traceLogger.log("No captured audio samples; using filtered fallback transcript")
            return validatedFinalTranscriptCandidate(
                fallbackTranscript(),
                signalStats: (0, 0),
                captureDurationSeconds: 0,
                context: "empty_audio_fallback"
            ) ?? ""
        }

        let signalStats = audioLevelStats(for: capturedSamples)
        let captureDurationSeconds = Double(capturedSamples.count) / Double(WhisperKit.sampleRate)
        let normalizedResult = normalizedAudioSamples(capturedSamples)
        let normalizedSamples = normalizedResult.0
        let normalizedStats = audioLevelStats(for: normalizedSamples)
        traceLogger.log(
            "Audio normalization gain=\(String(format: "%.2f", normalizedResult.1)) normalized_rms=\(String(format: "%.5f", normalizedStats.rms)) normalized_peak=\(String(format: "%.5f", normalizedStats.peak))"
        )
        let acceptedStreamingTranscript = validatedFinalTranscriptCandidate(
            fallbackTranscript(),
            signalStats: signalStats,
            captureDurationSeconds: captureDurationSeconds,
            context: "streaming_fallback"
        )

        if usesFluidTrueStreamingBackend, !usesParakeetFinalBackend {
            traceLogger.log("Finalizing FluidAudio true streaming transcript samples=\(capturedSamples.count)")
            do {
                if let acceptedFluidStreamingTranscript = try await finishFluidTrueStreamingTranscript(
                    samples: capturedSamples,
                    signalStats: signalStats,
                    captureDurationSeconds: captureDurationSeconds
                ) {
                    traceLogger.log("Using FluidAudio true streaming transcript as final transcript")
                    return acceptedFluidStreamingTranscript
                }
                traceLogger.log("FluidAudio true streaming transcript rejected; falling back to WhisperKit")
            } catch {
                traceLogger.log("FluidAudio true streaming transcript failed; falling back to WhisperKit error=\(error)")
            }
        }

        var acceptedParakeetTranscriptForFallback: String?
        var whisperCandidateDeferredForRecall = false
        if usesParakeetFinalBackend {
            traceLogger.log("Finalizing Parakeet v3 ANE transcript samples=\(capturedSamples.count)")
            do {
                var parakeetAcceptedForQualityFallback = false
                let parakeetCandidate = try await transcribeParakeetV3ANE(samples: normalizedSamples)
                traceTranscriptCandidate("Parakeet v3 ANE transcript", text: parakeetCandidate.text)
                if let acceptedParakeetTranscript = validatedFinalTranscriptCandidate(
                    parakeetCandidate.text,
                    signalStats: signalStats,
                    captureDurationSeconds: captureDurationSeconds,
                    context: "parakeet_v3_ane"
                ) {
                    let acceptedCandidate = ParakeetTranscriptCandidate(
                        text: acceptedParakeetTranscript,
                        confidence: parakeetCandidate.confidence
                    )
                    if let fallbackReason = parakeetStreamingRecallFallbackReason(
                        parakeetTranscript: acceptedParakeetTranscript,
                        streamingTranscript: acceptedStreamingTranscript,
                        captureDurationSeconds: captureDurationSeconds,
                        context: "parakeet_v3_ane"
                    ) {
                        traceLogger.log(
                            "Parakeet v3 ANE transcript accepted but quality fallback requested reason=\(fallbackReason)"
                        )
                        parakeetAcceptedForQualityFallback = true
                    } else if let fallbackReason = parakeetQualityFallbackReason(
                        for: acceptedCandidate,
                        captureDurationSeconds: captureDurationSeconds
                    ) {
                        acceptedParakeetTranscriptForFallback = acceptedParakeetTranscript
                        traceLogger.log(
                            "Parakeet v3 ANE transcript accepted but quality fallback requested reason=\(fallbackReason)"
                        )
                        parakeetAcceptedForQualityFallback = true
                    } else {
                        traceLogger.log("Using Parakeet v3 ANE transcript as final transcript")
                        return acceptedParakeetTranscript
                    }
                }
                if !parakeetAcceptedForQualityFallback {
                    traceLogger.log("Parakeet v3 ANE transcript rejected; falling back to WhisperKit")
                }
            } catch {
                traceLogger.log("Parakeet v3 ANE transcript failed; falling back to WhisperKit error=\(error)")
            }
        }

        let primaryResults = try await whisperKit.transcribe(audioArray: normalizedSamples, decodeOptions: decodingOptions)
        let primaryTranscript = cleanedTranscriptText(
            primaryResults
                .map(\.text)
                .joined(separator: " ")
        )
        traceTranscriptCandidate("Primary offline Whisper transcript", text: primaryTranscript)

        if let acceptedPrimaryTranscript = validatedFinalTranscriptCandidate(
            primaryTranscript,
            signalStats: signalStats,
            captureDurationSeconds: captureDurationSeconds,
            context: "offline_primary"
        ) {
            if shouldRejectWhisperCandidateForRecallQuality(
                whisperTranscript: acceptedPrimaryTranscript,
                parakeetTranscript: acceptedParakeetTranscriptForFallback,
                streamingTranscript: acceptedStreamingTranscript,
                captureDurationSeconds: captureDurationSeconds,
                context: "offline_primary"
            ) {
                traceLogger.log("Primary offline Whisper transcript accepted but implausible against recall; retrying with relaxed decoding")
            } else if shouldDeferShortWhisperCandidateForRecall(
                whisperTranscript: acceptedPrimaryTranscript,
                parakeetTranscript: acceptedParakeetTranscriptForFallback,
                streamingTranscript: acceptedStreamingTranscript,
                captureDurationSeconds: captureDurationSeconds,
                context: "offline_primary"
            ) {
                whisperCandidateDeferredForRecall = true
                traceLogger.log("Primary offline Whisper transcript accepted but too short; retrying with relaxed decoding")
            } else {
                return acceptedPrimaryTranscript
            }
        } else {
            traceLogger.log("Primary offline Whisper transcript rejected; retrying with relaxed decoding")
        }

        let relaxedResults = try await whisperKit.transcribe(audioArray: normalizedSamples, decodeOptions: relaxedDecodingOptions())
        let relaxedTranscript = cleanedTranscriptText(
            relaxedResults
                .map(\.text)
                .joined(separator: " ")
        )
        traceTranscriptCandidate("Relaxed offline Whisper transcript", text: relaxedTranscript)
        if let acceptedRelaxedTranscript = validatedFinalTranscriptCandidate(
            relaxedTranscript,
            signalStats: signalStats,
            captureDurationSeconds: captureDurationSeconds,
            context: "offline_relaxed"
        ) {
            if shouldRejectWhisperCandidateForRecallQuality(
                whisperTranscript: acceptedRelaxedTranscript,
                parakeetTranscript: acceptedParakeetTranscriptForFallback,
                streamingTranscript: acceptedStreamingTranscript,
                captureDurationSeconds: captureDurationSeconds,
                context: "offline_relaxed"
            ) {
                traceLogger.log("Relaxed offline Whisper transcript accepted but implausible against recall; retrying with auto-detect decoding")
            } else if shouldDeferShortWhisperCandidateForRecall(
                whisperTranscript: acceptedRelaxedTranscript,
                parakeetTranscript: acceptedParakeetTranscriptForFallback,
                streamingTranscript: acceptedStreamingTranscript,
                captureDurationSeconds: captureDurationSeconds,
                context: "offline_relaxed"
            ) {
                whisperCandidateDeferredForRecall = true
                traceLogger.log("Relaxed offline Whisper transcript accepted but too short; retrying with auto-detect decoding")
            } else {
                traceLogger.log("Relaxed offline Whisper transcript accepted")
                return acceptedRelaxedTranscript
            }
        } else {
            traceLogger.log("Relaxed offline Whisper transcript rejected; retrying with auto-detect decoding")
        }

        let autoResults = try await whisperKit.transcribe(audioArray: normalizedSamples, decodeOptions: autoDetectDecodingOptions())
        let autoTranscript = cleanedTranscriptText(
            autoResults
                .map(\.text)
                .joined(separator: " ")
        )
        traceTranscriptCandidate("Auto-detect offline Whisper transcript", text: autoTranscript)
        if let acceptedAutoTranscript = validatedFinalTranscriptCandidate(
            autoTranscript,
            signalStats: signalStats,
            captureDurationSeconds: captureDurationSeconds,
            context: "offline_auto_detect"
        ) {
            if shouldRejectWhisperCandidateForRecallQuality(
                whisperTranscript: acceptedAutoTranscript,
                parakeetTranscript: acceptedParakeetTranscriptForFallback,
                streamingTranscript: acceptedStreamingTranscript,
                captureDurationSeconds: captureDurationSeconds,
                context: "offline_auto_detect"
            ) {
                traceLogger.log("Auto-detect offline Whisper transcript accepted but implausible against recall; using recall fallback if available")
            } else if shouldDeferShortWhisperCandidateForRecall(
                whisperTranscript: acceptedAutoTranscript,
                parakeetTranscript: acceptedParakeetTranscriptForFallback,
                streamingTranscript: acceptedStreamingTranscript,
                captureDurationSeconds: captureDurationSeconds,
                context: "offline_auto_detect"
            ) {
                whisperCandidateDeferredForRecall = true
                traceLogger.log("Auto-detect offline Whisper transcript accepted but too short; using recall fallback if available")
            } else {
                traceLogger.log("Auto-detect offline Whisper transcript accepted")
                return acceptedAutoTranscript
            }
        }

        if whisperCandidateDeferredForRecall,
           let acceptedChunkedTranscript = try await chunkedWhisperFallbackTranscript(
            whisperKit: whisperKit,
            samples: normalizedSamples,
            signalStats: signalStats,
            captureDurationSeconds: captureDurationSeconds,
            context: "recall_deferred"
           ) {
            if shouldDeferShortWhisperCandidateForRecall(
                whisperTranscript: acceptedChunkedTranscript,
                parakeetTranscript: acceptedParakeetTranscriptForFallback,
                streamingTranscript: acceptedStreamingTranscript,
                captureDurationSeconds: captureDurationSeconds,
                context: "chunked_whisper_fallback"
            ) {
                traceLogger.log("Chunked offline Whisper transcript still too short; using recall fallback if available")
            } else {
                traceLogger.log("Using chunked offline Whisper transcript after short-candidate recall deferral")
                return acceptedChunkedTranscript
            }
        }

        if let acceptedParakeetTranscriptForFallback {
            traceLogger.log("Using accepted Parakeet v3 ANE transcript fallback after Whisper candidates were empty, implausible, or too short")
            return acceptedParakeetTranscriptForFallback
        }

        if let acceptedFallbackTranscript = acceptedStreamingTranscript {
            traceLogger.log("Whisper transcription empty or implausible; using filtered fallback transcript")
            return acceptedFallbackTranscript
        }

        traceLogger.log("Whisper transcription empty or implausible; no fallback transcript available")
        return ""
    }

    private func fallbackTranscript() -> String {
        let snapshot = withStateLock { latestStreamingState }
        return bestTranscriptCandidate(from: [
            snapshot.confirmedText,
            snapshot.unconfirmedText,
            snapshot.currentText,
        ])
    }

    private func backendErrorDescription(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.localizedDescription
        }

        return String(describing: error)
    }

    private func spokenErrorMessage(for error: Error) -> String {
        if let jarvisError = error as? JarvisTapError {
            switch jarvisError {
            case .accessibilityPermissionMissing:
                return "I could not paste the transcript."
            case .eventSynthesisUnavailable:
                return "I could not paste the transcript."
            default:
                break
            }
        }

        if let codexError = error as? CodexCLIError {
            switch codexError {
            case .timedOut:
                return "Codex timed out before it finished."
            default:
                return "Codex hit an execution error."
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return "The backend is not ready yet."
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
                return "The backend is not ready yet."
            default:
                break
            }
        }

        if case let JarvisTapError.httpFailure(statusCode, _) = error, statusCode >= 500 {
            return "The backend is not ready yet."
        }

        return "I hit a backend error."
    }

    private func printAccessibilityHelp() {
        fputs(
            """
            [PressTalk] Paste event synthesis is unavailable.

            If macOS already shows PressTalk enabled in Accessibility, do not
            keep toggling the permission. Collect diagnostics and check the
            paste probe/runtime status first.

            """,
            stderr
        )
    }

    private func printMicrophoneHelp() {
        fputs(
            """
            [PressTalk] Microphone is not available to this PressTalk build.

            If macOS already shows PressTalk enabled in Microphone, do not keep
            toggling the permission. Collect diagnostics and check the code
            signature/TCC identity first.

            """,
            stderr
        )
    }

    private func printInputMonitoringHelp() {
        fputs(
            """
            [PressTalk] The input listener is not armed.

            If macOS already shows PressTalk enabled in Input Monitoring, do not
            keep toggling the permission. Collect diagnostics and check
            runtime.inputListener first.

            """,
            stderr
        )
    }

    private func printTapFailureHelp() {
        fputs(
            """
            [PressTalk] Failed to install the global event tap.

            Check:
            1. runtime.inputListener in the diagnostics status
            2. Whether another utility is intercepting the configured trigger key

            """,
            stderr
        )
    }
}

// Runs before any AppKit setup: the self-test must not race the dictation
// pipeline for the input device.
AudioCaptureProbe.runCommandLineSelfTestIfRequested(CommandLine.arguments)

private let jarvisTapApplication = NSApplication.shared
private let jarvisTapDelegate = JarvisTapApp()

jarvisTapApplication.setActivationPolicy(.accessory)
jarvisTapApplication.delegate = jarvisTapDelegate
jarvisTapApplication.run()
