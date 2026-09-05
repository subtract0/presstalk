import Darwin
import Foundation

struct JarvisTapConfig {
    let agentMode: String
    let apiURL: URL
    let apiKey: String?
    let chatModel: String?
    let codexCommand: String
    let codexModel: String?
    let codexPlanningReasoningEffort: String
    let codexExecutionReasoningEffort: String
    let codexWorkingDirectory: String
    let codexPlanningTimeoutSeconds: TimeInterval
    let codexExecutionTimeoutSeconds: TimeInterval
    let memoryStorePath: String
    let whisperModel: String
    let whisperLanguage: String?
    let whisperComputePreset: String
    let asrBackend: String
    let streamingASRBackend: String?
    let streamingTranscriptionEnabled: Bool
    let parakeetQualityFallbackEnabled: Bool
    let parakeetQualityFallbackMinConfidence: Double
    let qualityFallbackAutoDownload: Bool
    let testHarnessEnabled: Bool
    let fixtureAudioURL: URL?
    let harnessResultsURL: URL?
    /// Harness runs do not paste by default. A test that types into whatever
    /// window happens to be focused is a test that damages the operator's work.
    let testHarnessSuppressesInsertion: Bool
    let sayVoice: String?
    let printPartials: Bool
    let traceLogPath: String
    let launchdLabel: String
    let requestTimeoutSeconds: TimeInterval
    let releaseTailPaddingSeconds: TimeInterval
    let triggerKey: JarvisTapSettingsStore.TriggerKeyOption
    let enableNativeMicrophoneKey: Bool
    let autoShowSetupWindow: Bool
    let allowPermissionPaneOpen: Bool

    static func load() -> JarvisTapConfig {
        let env = ProcessInfo.processInfo.environment
        let homeDirectory = env["HOME"] ?? NSHomeDirectory()
        let apiURLString = env["JARVISTAP_API_URL"] ?? "http://127.0.0.1:8080/v1/chat/completions"
        guard let apiURL = URL(string: apiURLString) else {
            fputs("[PressTalk] Invalid JARVISTAP_API_URL: \(apiURLString)\n", stderr)
            exit(10)
        }

        let agentMode =
            env["JARVISTAP_AGENT_MODE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ??
            "dictation"

        let codexCommand =
            env["JARVISTAP_CODEX_COMMAND"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ??
            "codex"

        let codexWorkingDirectory =
            env["JARVISTAP_CODEX_WORKDIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ??
            homeDirectory

        let codexModel = env["JARVISTAP_CODEX_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty

        let codexPlanningReasoningEffort =
            env["JARVISTAP_CODEX_PLAN_REASONING_EFFORT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ??
            "medium"

        let codexExecutionReasoningEffort =
            env["JARVISTAP_CODEX_EXEC_REASONING_EFFORT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ??
            "high"

        let codexPlanningTimeoutSeconds =
            env["JARVISTAP_CODEX_PLAN_TIMEOUT_SECONDS"].flatMap(TimeInterval.init) ??
            120

        let codexExecutionTimeoutSeconds =
            env["JARVISTAP_CODEX_EXEC_TIMEOUT_SECONDS"].flatMap(TimeInterval.init) ??
            600

        let memoryStorePath =
            env["JARVISTAP_MEMORY_PATH"] ??
            "\(homeDirectory)/Library/Application Support/JarvisTap/conversation_memory.json"

        let whisperModel =
            env["JARVISTAP_WHISPERKIT_MODEL"] ??
            env["JARVISTAP_WHISPER_MODEL"] ??
            "openai_whisper-large-v3-v20240930_turbo_632MB"

        let whisperLanguage = env["JARVISTAP_WHISPER_LANGUAGE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let whisperComputePreset =
            (env["PRESSTALK_WHISPER_COMPUTE"] ??
            env["JARVISTAP_WHISPER_COMPUTE"] ??
            "cpu-gpu-no-ane")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nonEmpty ??
            "cpu-gpu-no-ane"

        let asrBackend =
            (env["PRESSTALK_ASR_BACKEND"] ??
            env["JARVISTAP_ASR_BACKEND"] ??
            "parakeet-v3-ane")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nonEmpty ??
            "parakeet-v3-ane"

        let parakeetFinalBackendAliases = ["parakeet", "parakeet-v3", "parakeet-v3-ane", "ane", "npu"]
        let streamingASRBackend: String? = {
            let rawValue = env["PRESSTALK_STREAMING_ASR_BACKEND"] ??
                env["JARVISTAP_STREAMING_ASR_BACKEND"]
            if let rawValue {
                let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if value.isEmpty || ["0", "false", "no", "none", "off", "disabled"].contains(value) {
                    return nil
                }
                return value
            }
            if parakeetFinalBackendAliases.contains(asrBackend) {
                return "parakeet-eou-320"
            }
            return nil
        }()

        let streamingTranscriptionEnabled: Bool = {
            if let streamingValue = env["PRESSTALK_ENABLE_STREAMING_TRANSCRIPTION"] ??
                env["JARVISTAP_ENABLE_STREAMING_TRANSCRIPTION"] {
                let value = streamingValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return value != "0" && value != "false" && value != "no"
            }
            // Live partials default OFF as of 2026-09-04.
            //
            // They cost rather than save: PressTalk is push-to-talk, so key
            // release already supplies the endpoint, and the preview never
            // shortens key-up-to-paste -- it only added teardown work to the
            // release path. The default streaming model (parakeet-eou-320) is
            // also English-only and emits no punctuation or capitalisation, so
            // for German dictation the preview was actively wrong-looking even
            // though the final parakeet-v3 pass repaired it.
            //
            // The capability is intact: set PRESSTALK_ENABLE_STREAMING_TRANSCRIPTION=1
            // to turn partials back on (useful for debugging, which is what they
            // were mostly serving).
            return false
        }()

        let parakeetQualityFallbackEnabled: Bool = {
            guard let rawValue = env["PRESSTALK_PARAKEET_QUALITY_FALLBACK"] ??
                env["JARVISTAP_PARAKEET_QUALITY_FALLBACK"] else {
                return true
            }
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return value != "0" && value != "false" && value != "no"
        }()

        // The quality-fallback model is a 619 MB download that the default
        // recognizer never needs. Fetching it behind someone's back on first
        // launch is the difference between a 461 MB setup and a 1.1 GB one, so
        // it is opt-in.
        let qualityFallbackAutoDownload: Bool = {
            guard let rawValue = env["PRESSTALK_QUALITY_FALLBACK_AUTODOWNLOAD"] else { return false }
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return value == "1" || value == "true" || value == "yes"
        }()

        // Headless end-to-end testing. Neither of these does anything unless
        // explicitly set, and both are absent from every shipped launch path;
        // they exist so the trigger-to-paste journey can be exercised without a
        // human holding a key.
        let testHarnessEnabled: Bool = {
            let rawValue = env["PRESSTALK_TEST_HARNESS"] ?? "0"
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return value == "1" || value == "true" || value == "yes"
        }()

        let fixtureAudioURL: URL? = {
            guard testHarnessEnabled,
                  let path = env["PRESSTALK_FIXTURE_AUDIO"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nonEmpty
            else { return nil }
            return URL(fileURLWithPath: path)
        }()

        let harnessResultsURL: URL? = {
            guard testHarnessEnabled,
                  let path = env["PRESSTALK_HARNESS_RESULTS"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nonEmpty
            else { return nil }
            return URL(fileURLWithPath: path)
        }()

        let testHarnessSuppressesInsertion: Bool = {
            guard testHarnessEnabled else { return false }
            let rawValue = env["PRESSTALK_HARNESS_ALLOW_INSERT"] ?? "0"
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !(value == "1" || value == "true" || value == "yes")
        }()

        let parakeetQualityFallbackMinConfidence = min(
            1.0,
            max(
                0.0,
                (env["PRESSTALK_PARAKEET_MIN_CONFIDENCE"] ??
                    env["JARVISTAP_PARAKEET_MIN_CONFIDENCE"])
                    .flatMap(Double.init) ??
                    0.96
            )
        )

        let traceLogPath =
            env["PRESSTALK_TRACE_LOG"] ??
            env["JARVISTAP_TRACE_LOG"] ??
            "\(homeDirectory)/Library/Logs/presstalk_trace.log"

        let launchdLabel =
            env["PRESSTALK_LAUNCHD_LABEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ??
            "com.am.presstalk"

        let requestTimeoutSeconds =
            env["JARVISTAP_REQUEST_TIMEOUT_SECONDS"].flatMap(TimeInterval.init) ??
            30

        let releaseTailPaddingSeconds =
            env["JARVISTAP_RELEASE_TAIL_PADDING_SECONDS"].flatMap(TimeInterval.init) ??
            0.50

        let triggerKeyValue =
            env["PRESSTALK_TRIGGER_KEY"] ??
            env["JARVISTAP_TRIGGER_KEY"] ??
            "fn"
        let triggerKey =
            JarvisTapSettingsStore.TriggerKeyOption(rawValue: triggerKeyValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ??
            .fn

        let enableNativeMicrophoneKey =
            env["PRESSTALK_ENABLE_NATIVE_MICROPHONE_KEY"] == "1" ||
            env["JARVISTAP_ENABLE_NATIVE_MICROPHONE_KEY"] == "1"
        let autoShowSetupWindow =
            env["PRESSTALK_AUTO_SHOW_SETUP_WINDOW"] == "1" ||
            env["JARVISTAP_AUTO_SHOW_SETUP_WINDOW"] == "1"
        let allowPermissionPaneOpen =
            env["PRESSTALK_OPEN_PERMISSION_PANES"] == "1" ||
            env["JARVISTAP_OPEN_PERMISSION_PANES"] == "1"

        return JarvisTapConfig(
            agentMode: agentMode,
            apiURL: apiURL,
            apiKey: env["JARVISTAP_API_KEY"],
            chatModel: env["JARVISTAP_CHAT_MODEL"],
            codexCommand: codexCommand,
            codexModel: codexModel,
            codexPlanningReasoningEffort: codexPlanningReasoningEffort,
            codexExecutionReasoningEffort: codexExecutionReasoningEffort,
            codexWorkingDirectory: codexWorkingDirectory,
            codexPlanningTimeoutSeconds: codexPlanningTimeoutSeconds,
            codexExecutionTimeoutSeconds: codexExecutionTimeoutSeconds,
            memoryStorePath: memoryStorePath,
            whisperModel: whisperModel,
            whisperLanguage: (whisperLanguage?.isEmpty == false) ? whisperLanguage : nil,
            whisperComputePreset: whisperComputePreset,
            asrBackend: asrBackend,
            streamingASRBackend: streamingASRBackend,
            streamingTranscriptionEnabled: streamingTranscriptionEnabled,
            parakeetQualityFallbackEnabled: parakeetQualityFallbackEnabled,
            parakeetQualityFallbackMinConfidence: parakeetQualityFallbackMinConfidence,
            qualityFallbackAutoDownload: qualityFallbackAutoDownload,
            testHarnessEnabled: testHarnessEnabled,
            fixtureAudioURL: fixtureAudioURL,
            harnessResultsURL: harnessResultsURL,
            testHarnessSuppressesInsertion: testHarnessSuppressesInsertion,
            sayVoice: env["JARVISTAP_SAY_VOICE"],
            printPartials: env["JARVISTAP_PRINT_PARTIALS"].map { $0 != "0" } ?? true,
            traceLogPath: traceLogPath,
            launchdLabel: launchdLabel,
            requestTimeoutSeconds: requestTimeoutSeconds,
            releaseTailPaddingSeconds: releaseTailPaddingSeconds,
            triggerKey: triggerKey,
            enableNativeMicrophoneKey: enableNativeMicrophoneKey,
            autoShowSetupWindow: autoShowSetupWindow,
            allowPermissionPaneOpen: allowPermissionPaneOpen
        )
    }
}
