import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox
import CoreML
import Darwin
import Foundation
import IOKit.hidsystem
import WhisperKit

private let fnModifierMask = CGEventFlags(rawValue: UInt64(NX_SECONDARYFNMASK))
private let leftOptionModifierMask = CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))
private let rightOptionModifierMask = CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK))

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

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
    let sayVoice: String?
    let printPartials: Bool
    let traceLogPath: String
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

        let traceLogPath =
            env["JARVISTAP_TRACE_LOG"] ??
            "\(homeDirectory)/Library/Logs/jarvistap_trace.log"

        let requestTimeoutSeconds =
            env["JARVISTAP_REQUEST_TIMEOUT_SECONDS"].flatMap(TimeInterval.init) ??
            30

        let releaseTailPaddingSeconds =
            env["JARVISTAP_RELEASE_TAIL_PADDING_SECONDS"].flatMap(TimeInterval.init) ??
            0.35

        let triggerKeyValue =
            env["PRESSTALK_TRIGGER_KEY"] ??
            env["JARVISTAP_TRIGGER_KEY"] ??
            "option_space"
        let triggerKey =
            JarvisTapSettingsStore.TriggerKeyOption(rawValue: triggerKeyValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ??
            .optionSpace

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
            sayVoice: env["JARVISTAP_SAY_VOICE"],
            printPartials: env["JARVISTAP_PRINT_PARTIALS"].map { $0 != "0" } ?? true,
            traceLogPath: traceLogPath,
            requestTimeoutSeconds: requestTimeoutSeconds,
            releaseTailPaddingSeconds: releaseTailPaddingSeconds,
            triggerKey: triggerKey,
            enableNativeMicrophoneKey: enableNativeMicrophoneKey,
            autoShowSetupWindow: autoShowSetupWindow,
            allowPermissionPaneOpen: allowPermissionPaneOpen
        )
    }
}

final class TraceLogger {
    private let logURL: URL
    private let queue = DispatchQueue(label: "com.am.jarvistap.trace-log")
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(path: String) {
        logURL = URL(fileURLWithPath: path)
        let directoryURL = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
    }

    func log(_ message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        queue.sync { [logURL] in
            guard let data = line.data(using: .utf8) else { return }
            do {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                fputs("[PressTalk] Trace log write failed: \(error)\n", stderr)
            }
        }
    }
}

private struct SimpleChatRequest: Encodable {
    let message: String
    let context_limit: Int
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let max_tokens: Int
    let temperature: Double
}

private struct SimpleChatResponse: Decodable {
    let response: String
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

final class RemoteResponder {
    private let config: JarvisTapConfig
    private let traceLogger: TraceLogger
    private let session: URLSession

    init(config: JarvisTapConfig, traceLogger: TraceLogger) {
        self.config = config
        self.traceLogger = traceLogger
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = config.requestTimeoutSeconds
        sessionConfiguration.timeoutIntervalForResource = max(config.requestTimeoutSeconds, 60)
        self.session = URLSession(configuration: sessionConfiguration)
    }

    func reply(to transcript: String) async throws -> String {
        let mode = shouldUseOpenAIStyle ? "openai-chat" : "simple-chat"
        let start = Date()
        traceLogger.log("Request started mode=\(mode) url=\(config.apiURL.absoluteString) transcript_chars=\(transcript.count)")

        if shouldUseOpenAIStyle {
            do {
                let reply = try await openAIReply(to: transcript)
                traceLogger.log("Request completed mode=\(mode) duration_seconds=\(String(format: "%.2f", Date().timeIntervalSince(start))) reply_chars=\(reply.count)")
                return reply
            } catch {
                traceLogger.log("Request failed mode=\(mode) duration_seconds=\(String(format: "%.2f", Date().timeIntervalSince(start))) error=\(error)")
                throw error
            }
        }

        do {
            let reply = try await simpleReply(to: transcript)
            traceLogger.log("Request completed mode=\(mode) duration_seconds=\(String(format: "%.2f", Date().timeIntervalSince(start))) reply_chars=\(reply.count)")
            return reply
        } catch {
            traceLogger.log("Request failed mode=\(mode) duration_seconds=\(String(format: "%.2f", Date().timeIntervalSince(start))) error=\(error)")
            throw error
        }
    }

    private var shouldUseOpenAIStyle: Bool {
        config.apiURL.path.contains("/v1/chat/completions") || config.chatModel != nil
    }

    private var backendBaseURL: String {
        guard let scheme = config.apiURL.scheme, let host = config.apiURL.host else {
            return config.apiURL.absoluteString
        }
        if let port = config.apiURL.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private func simpleReply(to transcript: String) async throws -> String {
        traceLogger.log("🚀 Sende Request an Backend (\(backendBaseURL))...")
        var request = URLRequest(url: config.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(SimpleChatRequest(message: transcript, context_limit: 3))

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(SimpleChatResponse.self, from: data)
        return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openAIReply(to transcript: String) async throws -> String {
        traceLogger.log("🚀 Sende Request an Backend (\(backendBaseURL))...")
        var request = URLRequest(url: config.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let model = config.chatModel ?? "gpt-4.1-mini"
        let body = OpenAIChatRequest(
            model: model,
            messages: [
                .init(role: "user", content: transcript),
            ],
            max_tokens: 512,
            temperature: 0
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        if let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
           let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty
        {
            return content
        }

        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let choices = raw?["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String,
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw JarvisTapError.invalidRemotePayload
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw JarvisTapError.invalidHTTPResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw JarvisTapError.httpFailure(http.statusCode, body)
        }
    }
}

final class NativeSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    private var configuredVoice: AVSpeechSynthesisVoice?

    func configure(voiceIdentifier: String?) {
        if let voiceIdentifier, !voiceIdentifier.isEmpty {
            configuredVoice = resolvedVoice(for: voiceIdentifier)
        }

        if configuredVoice == nil {
            configuredVoice = defaultEnglishVoice()
        }
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = configuredVoice ?? defaultEnglishVoice()
        synthesizer.speak(utterance)
    }

    private func resolvedVoice(for requestedVoice: String) -> AVSpeechSynthesisVoice? {
        if let voice = AVSpeechSynthesisVoice(identifier: requestedVoice) {
            return voice
        }

        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let voice = voices.first(where: { $0.name.caseInsensitiveCompare(requestedVoice) == .orderedSame }) {
            return voice
        }
        if let voice = voices.first(where: { $0.language.caseInsensitiveCompare(requestedVoice) == .orderedSame }) {
            return voice
        }
        return nil
    }

    private func defaultEnglishVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let preferredVoices = [
            ("Samantha", "en_US"),
            ("Daniel", "en_GB"),
            ("Karen", "en_AU"),
            ("Moira", "en_IE"),
        ]

        for (name, language) in preferredVoices {
            if let voice = voices.first(where: { $0.name == name && $0.language == language }) {
                return voice
            }
        }

        return voices.first(where: { $0.language.lowercased().hasPrefix("en") })
    }
}

enum JarvisTapError: Error, CustomStringConvertible {
    case invalidHTTPResponse
    case invalidRemotePayload
    case httpFailure(Int, String)
    case whisperUnavailable
    case tokenizerUnavailable(String)
    case accessibilityPermissionMissing
    case eventSynthesisUnavailable

    var description: String {
        switch self {
        case .invalidHTTPResponse:
            return "invalid HTTP response"
        case .invalidRemotePayload:
            return "remote endpoint returned an unsupported payload"
        case let .httpFailure(code, body):
            return "HTTP \(code): \(body)"
        case .whisperUnavailable:
            return "WhisperKit was not initialized"
        case .tokenizerUnavailable(let message):
            return "Whisper tokenizer unavailable: \(message)"
        case .accessibilityPermissionMissing:
            return "Paste permission preflight is unavailable"
        case .eventSynthesisUnavailable:
            return "Failed to synthesize keyboard events"
        }
    }
}

enum TranscriptInsertionResult {
    case inserted(method: String)
    case pasteCommandPosted
    case copiedFallback(reason: String)
}

struct MemoryTurn: Codable {
    let timestamp: String
    let role: String
    let kind: String
    let text: String
}

struct PendingCommand: Codable {
    let timestamp: String
    let transcript: String
    let confirmationPrompt: String
    let executionPrompt: String
}

struct ConversationMemoryState: Codable {
    var turns: [MemoryTurn] = []
    var pendingCommand: PendingCommand?
}

final class ConversationMemoryStore {
    private let url: URL
    private let traceLogger: TraceLogger
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var state: ConversationMemoryState

    init(path: String, traceLogger: TraceLogger) {
        self.url = URL(fileURLWithPath: path)
        self.traceLogger = traceLogger

        let directoryURL = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: url),
           let loadedState = try? decoder.decode(ConversationMemoryState.self, from: data)
        {
            state = loadedState
        } else {
            state = ConversationMemoryState()
            persistLocked()
        }
    }

    func appendTurn(role: String, kind: String, text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        state.turns.append(
            MemoryTurn(
                timestamp: formatter.string(from: Date()),
                role: role,
                kind: kind,
                text: cleaned
            )
        )
        if state.turns.count > 60 {
            state.turns.removeFirst(state.turns.count - 60)
        }
        persistLocked()
    }

    func recentTurns(limit: Int) -> [MemoryTurn] {
        lock.lock()
        defer { lock.unlock() }
        return Array(state.turns.suffix(max(limit, 0)))
    }

    func formattedRecentTurns(limit: Int) -> String {
        let turns = recentTurns(limit: limit)
        guard !turns.isEmpty else { return "None." }
        return turns
            .map { "[\($0.timestamp)] \($0.role)/\($0.kind): \($0.text)" }
            .joined(separator: "\n")
    }

    func pendingCommand() -> PendingCommand? {
        lock.lock()
        defer { lock.unlock() }
        return state.pendingCommand
    }

    func setPendingCommand(_ pendingCommand: PendingCommand?) {
        lock.lock()
        defer { lock.unlock() }
        state.pendingCommand = pendingCommand
        persistLocked()
    }

    @discardableResult
    func clearPendingCommand() -> PendingCommand? {
        lock.lock()
        defer { lock.unlock() }
        let pendingCommand = state.pendingCommand
        state.pendingCommand = nil
        persistLocked()
        return pendingCommand
    }

    private func persistLocked() {
        do {
            let data = try encoder.encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            traceLogger.log("Conversation memory persist failed error=\(error)")
        }
    }
}

struct CodexPlanningResponse: Decodable {
    let mode: String
    let spokenResponse: String
    let executionPrompt: String?

    private enum CodingKeys: String, CodingKey {
        case mode
        case spokenResponse = "spoken_response"
        case executionPrompt = "execution_prompt"
    }
}

struct CodexExecutionResponse: Decodable {
    let spokenResponse: String

    private enum CodingKeys: String, CodingKey {
        case spokenResponse = "spoken_response"
    }
}

enum CodexCLIError: Error, CustomStringConvertible {
    case timedOut(TimeInterval)
    case launchFailure(String)
    case nonZeroExit(Int32, String)
    case invalidPayload(String)

    var description: String {
        switch self {
        case let .timedOut(timeout):
            return "Codex timed out after \(Int(timeout)) seconds"
        case let .launchFailure(message):
            return "failed to launch Codex: \(message)"
        case let .nonZeroExit(code, stderr):
            return "Codex exited with status \(code): \(stderr)"
        case let .invalidPayload(message):
            return "Codex returned an invalid payload: \(message)"
        }
    }
}

final class CodexAgent {
    private enum PlanningMode: String {
        case confirm
        case ask
        case answer
    }

    private let config: JarvisTapConfig
    private let traceLogger: TraceLogger
    private let memoryStore: ConversationMemoryStore

    init(config: JarvisTapConfig, traceLogger: TraceLogger, memoryStore: ConversationMemoryStore) {
        self.config = config
        self.traceLogger = traceLogger
        self.memoryStore = memoryStore
    }

    func respond(to transcript: String) async throws -> String {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { return "" }

        memoryStore.appendTurn(role: "user", kind: "transcript", text: cleanedTranscript)

        if let pendingCommand = memoryStore.pendingCommand() {
            if isAffirmative(cleanedTranscript) {
                traceLogger.log("Pending command confirmed transcript=\(cleanedTranscript)")
                memoryStore.clearPendingCommand()
                return try await execute(pendingCommand)
            }

            if isNegative(cleanedTranscript) {
                traceLogger.log("Pending command cancelled transcript=\(cleanedTranscript)")
                memoryStore.clearPendingCommand()
                let spokenResponse = "Cancelled. I did not execute anything."
                memoryStore.appendTurn(role: "assistant", kind: "confirmation", text: spokenResponse)
                return spokenResponse
            }

            traceLogger.log("Pending command replaced by new transcript")
            memoryStore.clearPendingCommand()
        } else if isAffirmative(cleanedTranscript) || isNegative(cleanedTranscript) {
            let spokenResponse = "There is nothing pending to confirm right now."
            memoryStore.appendTurn(role: "assistant", kind: "answer", text: spokenResponse)
            return spokenResponse
        }

        let planningResponse = try await plan(for: cleanedTranscript)
        let mode = PlanningMode(rawValue: planningResponse.mode.lowercased()) ?? .ask
        let spokenResponse = planningResponse.spokenResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .confirm:
            let executionPrompt = planningResponse.executionPrompt?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !executionPrompt.isEmpty else {
                throw CodexCLIError.invalidPayload("planning response was missing execution_prompt")
            }

            let pendingCommand = PendingCommand(
                timestamp: timestamp(),
                transcript: cleanedTranscript,
                confirmationPrompt: spokenResponse,
                executionPrompt: executionPrompt
            )
            memoryStore.setPendingCommand(pendingCommand)
            memoryStore.appendTurn(role: "assistant", kind: "confirmation_request", text: spokenResponse)
            return spokenResponse
        case .ask:
            memoryStore.appendTurn(role: "assistant", kind: "clarification", text: spokenResponse)
            return spokenResponse
        case .answer:
            memoryStore.appendTurn(role: "assistant", kind: "answer", text: spokenResponse)
            return spokenResponse
        }
    }

    private func plan(for transcript: String) async throws -> CodexPlanningResponse {
        traceLogger.log("Codex planning started transcript_chars=\(transcript.count)")
        let prompt = """
        You are JarvisTap's planning brain running on the user's Mac.

        Your job in this phase is to understand the user's latest spoken request, use the recent conversation memory, and decide the next spoken response. Do not execute anything in this phase.

        Rules:
        - Speak in English only.
        - If the latest request is actionable on the local computer, return mode \"confirm\".
        - In confirm mode, paraphrase the intended task briefly, ask the user to say yes or no, and provide an execution_prompt for a later confirmed Codex run.
        - If the request is ambiguous or missing a critical detail, return mode \"ask\" and ask one concise clarification question. Do not provide an execution_prompt.
        - If the request should be answered directly without changing anything on the computer, return mode \"answer\" and answer briefly. Do not provide an execution_prompt.
        - Resolve references like \"that\", \"it\", or \"the repo\" from the recent conversation when possible.
        - Keep spoken_response concise because it will be spoken aloud.

        Current date: \(currentDateString())
        Working directory: \(config.codexWorkingDirectory)

        Recent conversation:
        \(memoryStore.formattedRecentTurns(limit: 12))

        Latest spoken transcript:
        \(transcript)
        """

        let result = try await runCodex(
            prompt: prompt,
            schema: Self.planningSchema,
            sandboxMode: "read-only",
            reasoningEffort: config.codexPlanningReasoningEffort,
            timeout: config.codexPlanningTimeoutSeconds
        )

        traceLogger.log(
            "Codex planning finished stdout_chars=\(result.stdout.count) stderr_chars=\(result.stderr.count)"
        )

        guard let data = result.lastMessage.data(using: .utf8) else {
            throw CodexCLIError.invalidPayload("planning output was not valid UTF-8")
        }

        do {
            return try JSONDecoder().decode(CodexPlanningResponse.self, from: data)
        } catch {
            traceLogger.log("Codex planning decode failed payload=\(result.lastMessage)")
            throw error
        }
    }

    private func execute(_ pendingCommand: PendingCommand) async throws -> String {
        traceLogger.log("Codex execution started prompt_chars=\(pendingCommand.executionPrompt.count)")

        let prompt = """
        You are Codex running on the user's Mac. The user already confirmed the task below, so you should execute it directly.

        Rules:
        - Speak in English only.
        - Carry out the confirmed task using the local filesystem and tools as needed.
        - Use the recent conversation for context when it helps resolve references.
        - Your final response will be spoken aloud, so keep it concise and outcome-focused.
        - If you hit a blocker, say exactly what blocked execution.

        Current date: \(currentDateString())
        Working directory: \(config.codexWorkingDirectory)

        Recent conversation:
        \(memoryStore.formattedRecentTurns(limit: 16))

        Confirmed task:
        \(pendingCommand.executionPrompt)
        """

        let result = try await runCodex(
            prompt: prompt,
            schema: Self.executionSchema,
            sandboxMode: "workspace-write",
            reasoningEffort: config.codexExecutionReasoningEffort,
            timeout: config.codexExecutionTimeoutSeconds
        )

        traceLogger.log(
            "Codex execution finished stdout_chars=\(result.stdout.count) stderr_chars=\(result.stderr.count)"
        )

        guard let data = result.lastMessage.data(using: .utf8) else {
            throw CodexCLIError.invalidPayload("execution output was not valid UTF-8")
        }

        let decoded: CodexExecutionResponse
        do {
            decoded = try JSONDecoder().decode(CodexExecutionResponse.self, from: data)
        } catch {
            traceLogger.log("Codex execution decode failed payload=\(result.lastMessage)")
            throw error
        }

        let spokenResponse = decoded.spokenResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        memoryStore.appendTurn(role: "assistant", kind: "execution_result", text: spokenResponse)
        return spokenResponse
    }

    private func runCodex(
        prompt: String,
        schema: String,
        sandboxMode: String,
        reasoningEffort: String,
        timeout: TimeInterval
    ) async throws -> (lastMessage: String, stdout: String, stderr: String) {
        let codexWorkingDirectory = config.codexWorkingDirectory
        let codexCommand = config.codexCommand
        let codexModel = config.codexModel

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("jarvistap-codex-\(UUID().uuidString)", isDirectory: true)

                do {
                    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

                    let schemaURL = tempDirectory.appendingPathComponent("schema.json")
                    let outputURL = tempDirectory.appendingPathComponent("last_message.json")
                    let stdoutURL = tempDirectory.appendingPathComponent("stdout.txt")
                    let stderrURL = tempDirectory.appendingPathComponent("stderr.txt")

                    try schema.write(to: schemaURL, atomically: true, encoding: .utf8)
                    FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
                    FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

                    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
                    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
                    defer {
                        try? stdoutHandle.close()
                        try? stderrHandle.close()
                        try? FileManager.default.removeItem(at: tempDirectory)
                    }

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.currentDirectoryURL = URL(fileURLWithPath: codexWorkingDirectory, isDirectory: true)

                    var arguments = [
                        codexCommand,
                        "exec",
                        "--skip-git-repo-check",
                        "--sandbox",
                        sandboxMode,
                        "-c",
                        "model_reasoning_effort=\"\(reasoningEffort)\"",
                        "-C",
                        codexWorkingDirectory,
                        "--output-schema",
                        schemaURL.path,
                        "-o",
                        outputURL.path,
                    ]
                    if let codexModel {
                        arguments.append(contentsOf: ["-m", codexModel])
                    }
                    arguments.append(prompt)

                    process.arguments = arguments
                    process.standardOutput = stdoutHandle
                    process.standardError = stderrHandle

                    do {
                        try process.run()
                    } catch {
                        throw CodexCLIError.launchFailure(error.localizedDescription)
                    }

                    let deadline = Date().addingTimeInterval(timeout)
                    while process.isRunning, Date() < deadline {
                        Thread.sleep(forTimeInterval: 0.1)
                    }

                    if process.isRunning {
                        process.terminate()
                        Thread.sleep(forTimeInterval: 0.5)
                        if process.isRunning {
                            process.interrupt()
                        }
                        process.waitUntilExit()
                        throw CodexCLIError.timedOut(timeout)
                    }

                    process.waitUntilExit()

                    let stdout = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
                    let stderr = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
                    let lastMessage = try String(contentsOf: outputURL, encoding: .utf8)
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    guard process.terminationStatus == 0 else {
                        throw CodexCLIError.nonZeroExit(
                            process.terminationStatus,
                            stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }

                    continuation.resume(returning: (lastMessage: lastMessage, stdout: stdout, stderr: stderr))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func isAffirmative(_ text: String) -> Bool {
        let normalized = normalizedDecision(text)
        let affirmativePhrases = [
            "yes", "yeah", "yep", "confirm", "confirmed", "ok", "okay", "sure",
            "do it", "go ahead", "proceed", "ja", "jawohl", "mach", "weiter",
        ]
        return affirmativePhrases.contains(normalized) ||
            affirmativePhrases.contains(where: { normalized.hasPrefix("\($0) ") })
    }

    private func isNegative(_ text: String) -> Bool {
        let normalized = normalizedDecision(text)
        let negativePhrases = [
            "no", "nope", "cancel", "stop", "dont", "don t", "do not", "never mind",
            "nein", "abbrechen", "stopp",
        ]
        return negativePhrases.contains(normalized) ||
            negativePhrases.contains(where: { normalized.hasPrefix("\($0) ") })
    }

    private func normalizedDecision(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        return formatter.string(from: Date())
    }

    private static let planningSchema = """
    {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "mode": {
          "type": "string",
          "enum": ["confirm", "ask", "answer"]
        },
        "spoken_response": {
          "type": "string"
        },
        "execution_prompt": {
          "type": ["string", "null"]
        }
      },
      "required": ["mode", "spoken_response", "execution_prompt"]
    }
    """

    private static let executionSchema = """
    {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "spoken_response": {
          "type": "string"
        }
      },
      "required": ["spoken_response"]
    }
    """
}

final class JarvisTapApp: NSObject, NSApplicationDelegate {
    private struct StreamingSnapshot {
        var currentText = ""
        var confirmedText = ""
        var unconfirmedText = ""
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

    private let config = JarvisTapConfig.load()
    private lazy var settingsStore = JarvisTapSettingsStore(config: config)
    private lazy var licenseStore = PressTalkLicenseStore()
    private lazy var traceLogger = TraceLogger(path: config.traceLogPath)
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
    private let trackpadHoldDelaySeconds: TimeInterval = 0.50
    private let trackpadHoldCancelDistancePoints: CGFloat = 15.0
    private let shortHoldNoSpeechSuppressionSeconds: TimeInterval = 1.50
    private let trackpadPreviewTickSeconds: TimeInterval = 1.0 / 30.0
    private let nativePointerCancellationWindowSeconds: TimeInterval = 0.20
    private let setupRetryIntervalSeconds: TimeInterval = 5.0
    private let stateLock = NSLock()

    private var eventTap: CFMachPort?
    private var eventTapInstallSummary = "not_installed"
    private var runLoopSource: CFRunLoopSource?
    private var registeredHotKeyRef: EventHotKeyRef?
    private var registeredHotKeyEventHandler: EventHandlerRef?
    private var specialKeyMonitor: Any?
    private var whisperKit: WhisperKit?
    private var streamTranscriber: AudioStreamTranscriber?
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
    private var lastInputDebugSignature = ""
    private var darwinNotificationObserverInstalled = false
    private var productionInsertionProbeObserverInstalled = false
    private var whisperLoadState: WhisperLoadState = .idle
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
    private var microphonePermissionRequestInFlight = false
    private var microphonePermissionRequestAttempted = false

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

        completeStartupIfPossible(
            showSetupWindowOnFailure: shouldPresentSetupGuide,
            forcePresentSetupWindow: false
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

        let statusSummaryMenuItem = NSMenuItem(title: "PressTalk 0.1.5", action: nil, keyEquivalent: "")
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
        guard let whisperKit else {
            return VoiceLightBands(low: 0.04, mid: 0.04, high: 0.04)
        }

        let sampleWindow = Int(Double(WhisperKit.sampleRate) * 0.12)
        let recentSamples = Array(whisperKit.audioProcessor.audioSamples.suffix(sampleWindow))
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
        withStateLock {
            trackpadHoldState?.downLocation
        }
    }

    private func currentHoldlightVerticalLift() -> CGFloat {
        0
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
            uiState = ("PressTalk 0.1.5", "Warming up the local speech model…", "hourglass.circle.fill", .warming, nil)
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
                !status.accessibilityGranted &&
                status.inputMethodFallbackStatus != "ready" {
                uiState = (
                    "Paste Fallback Blocked",
                    "Transcription ready. Input method status: \(status.inputMethodFallbackStatus).",
                    "exclamationmark.triangle.fill",
                    .warming,
                    nil
                )
            } else {
                uiState = ("PressTalk 0.1.5", "Ready. Hold \(settingsStore.triggerKey.displayName) to dictate.", "waveform.badge.mic", .ready, 1.1)
            }
        case .listening(let partial):
            uiState = ("Listening", partial?.nonEmpty ?? "Speak now. Release when finished.", "mic.fill", .listening, nil)
        case .processing:
            uiState = ("Processing", "Cleaning and finalizing your dictation…", "ellipsis.circle.fill", .processing, nil)
        case .inserted(let transcript):
            uiState = ("Inserted", transcript, "checkmark.circle.fill", .inserted, 1.5)
        case .copied(let transcript):
            uiState = ("Copied to Clipboard", transcript, "doc.on.clipboard.fill", .copied, 1.5)
        case .aborted(let message):
            uiState = ("Transcription Aborted", message, "hand.raised.fill", .error, 4.0)
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

        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: uiState.symbol, accessibilityDescription: uiState.summary)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "\(uiState.summary) — \(uiState.detail)"
        }

        guard settingsStore.showHUD else {
            hudController?.hide()
            return
        }

        switch state {
        case .listening:
            hudController?.showListeningLight(
                bands: currentLiveListeningLightBands(),
                anchorPoint: currentHoldlightAnchorPoint(),
                verticalLift: currentHoldlightVerticalLift(),
                alpha: 1
            )
        case .setupRequired:
            hudController?.hide()
        case .aborted, .error, .diagnosticStarted:
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
            Launch label (internal): com.am.jarvistap

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
        let launchLabel = "gui/\(getuid())/com.am.jarvistap"
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

    private struct WhisperComputeSelection {
        let label: String
        let options: ModelComputeOptions?
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

    private func resetStreamingSession() throws {
        guard let whisperKit else {
            throw JarvisTapError.whisperUnavailable
        }

        traceLogger.log("Resetting Whisper streaming session")
        whisperKit.clearState()
        whisperKit.audioProcessor.purgeAudioSamples(keepingLast: 0)
        streamTranscriber = try makeStreamTranscriber(using: whisperKit)
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
            guard settingsStore.triggerKey == .f5 else {
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

                let result = try insertTranscriptIntoFocusedApp(payload)
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
        beginTrackpadPrearmCaptureIfPossible()
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

    private func beginTrackpadPrearmCaptureIfPossible() {
        guard currentWhisperReadinessMessage() == nil else { return }
        handlePress(.trackpadHold, source: .trackpadHold, announce: false)
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
            streamTaskToCancel = streamTask
            streamTask = nil
            latestStreamingState = StreamingSnapshot()
            lastPrintedPartial = ""
            shouldResetStreamingSession = true
        }

        guard shouldResetStreamingSession else { return }

        traceLogger.log("Trackpad prearm capture cancelled before visible arm")
        streamTaskToCancel?.cancel()
        if let transcriber = streamTranscriber {
            Task(priority: .userInitiated) { [weak self] in
                await transcriber.stopStreamTranscription()
                try? self?.resetStreamingSession()
            }
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
        if let transcriber = streamTranscriber {
            Task(priority: .userInitiated) { [weak self] in
                await transcriber.stopStreamTranscription()
                try? self?.resetStreamingSession()
            }
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
        guard let whisperKit else { return (0, false, false) }
        let samples = Array(whisperKit.audioProcessor.audioSamples)
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
        if let transcriber = streamTranscriber {
            Task(priority: .userInitiated) { [weak self] in
                await transcriber.stopStreamTranscription()
                try? self?.resetStreamingSession()
            }
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

    private func cleanedTranscriptText(_ text: String) -> String {
        let trimmedOriginal = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let suppressedNonSpeechTerms = [
            "music", "musik", "gibberish", "humming", "hum", "hums", "noise", "noises",
            "background noise", "background noises", "ambient noise", "static", "buzz", "buzzing",
            "rustling", "rustle", "crackling", "distortion", "inaudible", "unclear", "silence",
            "giggle", "giggles", "laugh", "laughs", "laughing", "laughter", "kiss", "kisses",
            "cough", "coughs", "coughing", "clear throat", "clears throat", "clearing throat",
            "sigh", "sighs", "sighing", "breathes", "breathing", "mumbling", "mumbles",
            "whistle", "whistles", "whistling", "applause", "clapping", "typing", "tapping",
            "clicking", "clicks", "beep", "beeps", "beeping", "sniff", "sniffs", "sniffing",
            "sneeze", "sneezes", "sneezing"
        ]
        let suppressedNonSpeechPhrases = Set(suppressedNonSpeechTerms)
        let suppressedNonSpeechTokens = Set(
            suppressedNonSpeechTerms
                .flatMap { $0.components(separatedBy: CharacterSet.alphanumerics.inverted) }
                .filter { !$0.isEmpty }
        )

        let fullWrappedStageDirectionPatterns = [
            #"^\s*(?:\*+|_+)\s*.+?\s*(?:\*+|_+)\s*$"#,
            #"^\s*[\[(]\s*.+?\s*[\])]\s*$"#
        ]
        if fullWrappedStageDirectionPatterns.contains(where: {
            trimmedOriginal.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }) {
            return ""
        }

        var cleaned = text

        let stageDirectionPatterns = [
            #"[(*\[]\s*(?:musik|music|gibberish|humming|hums?|summt|summen|räusper(?:t|n)?|räuspert sich|hust(?:e|en|et)?|lacht|lachen|laugh(?:s|ing)?|giggles?|cough(?:s|ing)?|clears? throat|räuspern|seufzt|sigh(?:s|ing)?|atmet|breath(?:es|ing)?|mumbling|mumbles?|whistl(?:e|es|ing)|applause|clapping|noise|background noise|ambient noise|static|buzz(?:ing)?|rustl(?:e|ing)|crackl(?:e|ing)|distortion|inaudible|unclear|typing|tapping|click(?:ing|s)?|beep(?:ing|s)?|sniff(?:ing|s)?|sneez(?:e|es|ing)?)\s*[*)\]]"#,
            #"(?:\*+|_+)\s*(?:musik|music|gibberish|humming|hums?|summt|summen|räusper(?:t|n)?|räuspert sich|hust(?:e|en|et)?|lacht|lachen|laugh(?:s|ing)?|giggles?|cough(?:s|ing)?|clears? throat|räuspern|seufzt|sigh(?:s|ing)?|atmet|breath(?:es|ing)?|mumbling|mumbles?|whistl(?:e|es|ing)|applause|clapping|noise|background noise|ambient noise|static|buzz(?:ing)?|rustl(?:e|ing)|crackl(?:e|ing)|distortion|inaudible|unclear|typing|tapping|click(?:ing|s)?|beep(?:ing|s)?|sniff(?:ing|s)?|sneez(?:e|es|ing)?)\s*(?:\*+|_+)"#
        ]

        for pattern in stageDirectionPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([(\[])\s+"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([)\]])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        cleaned = cleaned.replacingOccurrences(
            of: #"^[,.;:!?…\-\s]+"#,
            with: "",
            options: .regularExpression
        )

        let normalizedStandalonePhrase = cleaned
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if suppressedNonSpeechPhrases.contains(normalizedStandalonePhrase) {
            return ""
        }

        let normalizedTokens = normalizedStandalonePhrase
            .split(separator: " ")
            .map(String.init)
        if !normalizedTokens.isEmpty,
           normalizedTokens.count <= 5,
           normalizedTokens.allSatisfy({ suppressedNonSpeechTokens.contains($0) }) {
            return ""
        }

        return cleaned
    }

    private func normalizedTranscriptPhrase(_ text: String) -> String {
        cleanedTranscriptText(text)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func isLikelySilenceHallucination(
        _ text: String,
        signalStats: (rms: Double, peak: Double),
        captureDurationSeconds: TimeInterval
    ) -> Bool {
        let normalizedPhrase = normalizedTranscriptPhrase(text)
        guard !normalizedPhrase.isEmpty else { return false }

        let silenceHallucinationPhrases: Set<String> = [
            "you",
            "thank you",
            "thanks",
            "thank you very much",
            "thank you so much",
        ]
        guard silenceHallucinationPhrases.contains(normalizedPhrase) else { return false }

        let weakAudio = signalStats.rms < 0.0035 && signalStats.peak < 0.045
        let shortCapture = captureDurationSeconds < shortHoldNoSpeechSuppressionSeconds
        return weakAudio || shortCapture
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
                "Rejected likely silence hallucination context=\(context) transcript=\(cleaned) rms=\(String(format: "%.5f", signalStats.rms)) peak=\(String(format: "%.5f", signalStats.peak)) duration_seconds=\(String(format: "%.2f", captureDurationSeconds))"
            )
            return nil
        }

        return cleaned
    }

    private func isPlausibleTranscript(_ text: String) -> Bool {
        let cleaned = cleanedTranscriptText(text)
        guard !cleaned.isEmpty, cleaned != "Waiting for speech..." else { return false }

        let scalars = cleaned.unicodeScalars
        let letterOrDigitCount = scalars.filter(CharacterSet.alphanumerics.contains).count
        guard letterOrDigitCount >= 2 else { return false }

        let punctuationCount = scalars.filter(CharacterSet.punctuationCharacters.contains).count
        if punctuationCount > letterOrDigitCount {
            return false
        }

        let lowercasedTokens = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }

        guard !lowercasedTokens.isEmpty else { return false }
        if lowercasedTokens.count <= 3 {
            return true
        }

        let uniqueTokenCount = Set(lowercasedTokens).count
        let uniqueTokenRatio = Double(uniqueTokenCount) / Double(lowercasedTokens.count)
        let mostCommonTokenCount = Dictionary(grouping: lowercasedTokens, by: { $0 })
            .values
            .map(\.count)
            .max() ?? 0

        if lowercasedTokens.count >= 5 && uniqueTokenRatio < 0.45 {
            return false
        }
        if lowercasedTokens.count >= 5 && Double(mostCommonTokenCount) / Double(lowercasedTokens.count) > 0.55 {
            return false
        }
        if cleaned.contains(",,,") || cleaned.contains("...") {
            return false
        }

        return true
    }

    private func bestTranscriptCandidate(from texts: [String]) -> String {
        texts
            .map(cleanedTranscriptText)
            .filter(isPlausibleTranscript)
            .max(by: { $0.count < $1.count }) ?? ""
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

    private func captureSilenceAwareReleaseTail(
        transcriber: AudioStreamTranscriber,
        whisperKit: WhisperKit?
    ) async {
        let maximumTailSeconds = max(0.15, settingsStore.releaseTailMaxSeconds)
        let minimumTailSeconds = min(0.22, maximumTailSeconds)
        let silenceWindowSeconds = min(0.22, maximumTailSeconds)
        let silenceRMSThreshold = 0.011
        let pollNanoseconds: UInt64 = 50_000_000

        traceLogger.log(
            "Applying silence-aware release tail min_seconds=\(String(format: "%.2f", minimumTailSeconds)) max_seconds=\(String(format: "%.2f", maximumTailSeconds)) silence_window_seconds=\(String(format: "%.2f", silenceWindowSeconds)) silence_rms=\(String(format: "%.4f", silenceRMSThreshold))"
        )

        let start = Date()
        var lastMeasuredRMS = 0.0

        while Date().timeIntervalSince(start) < maximumTailSeconds {
            try? await Task.sleep(nanoseconds: pollNanoseconds)

            let elapsed = Date().timeIntervalSince(start)
            guard elapsed >= minimumTailSeconds else { continue }
            guard let whisperKit else { break }

            let requiredSamples = Int(Double(WhisperKit.sampleRate) * silenceWindowSeconds)
            let recentSamples = Array(whisperKit.audioProcessor.audioSamples.suffix(requiredSamples))
            let stats = audioLevelStats(for: recentSamples)
            lastMeasuredRMS = stats.rms

            if !recentSamples.isEmpty, stats.rms <= silenceRMSThreshold {
                traceLogger.log(
                    "Release tail silence detected elapsed_seconds=\(String(format: "%.2f", elapsed)) recent_rms=\(String(format: "%.5f", stats.rms))"
                )
                break
            }
        }

        let elapsed = Date().timeIntervalSince(start)
        if elapsed >= maximumTailSeconds {
            traceLogger.log(
                "Release tail hit max_seconds=\(String(format: "%.2f", maximumTailSeconds)) last_recent_rms=\(String(format: "%.5f", lastMeasuredRMS))"
            )
        }

        traceLogger.log("Requesting live stream stop")
        await transcriber.stopStreamTranscription()
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

    private func traceTranscriptCandidate(_ label: String, text: String) {
        let cleaned = cleanedTranscriptText(text)
        let rendered = cleaned.isEmpty ? "<empty>" : cleaned
        traceLogger.log("\(label): \(rendered)")
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
                traceLogger.log("Loading WhisperKit model=\(config.whisperModel)")
                traceLogger.log("Whisper decode language=\(settingsStore.preferredLanguage.whisperLanguageCode ?? "auto")")
                try await loadWhisperKit()
                traceLogger.log("WhisperKit ready")
                print("WhisperKit ready.")
                fflush(stdout)

                withStateLock {
                    whisperLoadState = .ready
                    whisperWarmupTask = nil
                }
                traceLogger.log("Whisper warmup skipped; model ready for live use")
                refreshRuntimeStatusUI()
                present(.ready)
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

    private func snapshotPasteboardItems() -> [[NSPasteboard.PasteboardType: Data]] {
        let pasteboard = NSPasteboard.general
        return (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    private func restorePasteboardItems(_ items: [[NSPasteboard.PasteboardType: Data]], expectedChangeCount: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == expectedChangeCount else { return }

            pasteboard.clearContents()
            guard !items.isEmpty else { return }

            let restoredItems = items.map { dataByType -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in dataByType {
                    item.setData(data, forType: type)
                }
                return item
            }
            _ = pasteboard.writeObjects(restoredItems)
        }
    }

    private func copyTranscriptToPasteboard(_ transcript: String) {
        let preparedTranscript = transcriptForInsertion(transcript)
        guard !preparedTranscript.isEmpty else { return }

        copyPreparedTranscriptToPasteboard(preparedTranscript)
    }

    private func copyPreparedTranscriptToPasteboard(_ preparedTranscript: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(preparedTranscript, forType: .string)
    }

    private func inputSourceProperty(_ source: TISInputSource, _ key: CFString) -> Any? {
        guard let unmanaged = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(unmanaged).takeUnretainedValue()
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
        guard let list = TISCreateInputSourceList(properties, includeAllInstalled) else {
            return []
        }
        return (list.takeRetainedValue() as NSArray as Array).compactMap { object in
            guard CFGetTypeID(object as CFTypeRef) == TISInputSourceGetTypeID() else { return nil }
            return (object as! TISInputSource)
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

    private func currentInputMethodFallbackStatus() -> String {
        guard settingsStore.pasteAutomatically else {
            return "not_used"
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

    private func inputMethodInsertionAcknowledgementInserted(at url: URL) -> Bool? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object["inserted"] as? Bool
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
            return "ax_false_input_method_fallback_ready"
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

    private func insertPreparedTranscriptUsingInputMethod(_ preparedTranscript: String) -> String? {
        guard let bundleURL = ensureInputMethodInstalledForInsertion() else {
            return nil
        }

        let registerStatus = TISRegisterInputSource(bundleURL as CFURL)
        guard registerStatus == 0 else {
            traceLogger.log("Input method insertion unavailable reason=register_failed status=\(registerStatus)")
            return nil
        }

        let originalSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let enabledBeforeKeys = Set(pressTalkInputMethodSources(includeAllInstalled: false).map(inputSourceIdentityKey))
        var allSources = pressTalkInputMethodSources(includeAllInstalled: true)
        guard let candidate = preferredPressTalkInputMethodSource(from: allSources) else {
            traceLogger.log("Input method insertion unavailable reason=source_not_recognized")
            return nil
        }

        func disableIfEnabledOnlyForInsertion(_ sources: [TISInputSource]) {
            var disabled = Set<String>()
            for source in sources {
                let key = inputSourceIdentityKey(source)
                guard !enabledBeforeKeys.contains(key), !disabled.contains(key) else { continue }
                disabled.insert(key)
                let disableStatus = TISDisableInputSource(source)
                if disableStatus != 0 {
                    traceLogger.log("Input method insertion disable failed status=\(disableStatus)")
                }
            }
        }

        let candidateWasEnabledBefore = enabledBeforeKeys.contains(inputSourceIdentityKey(candidate))
        if !candidateWasEnabledBefore {
            let enableStatus = TISEnableInputSource(candidate)
            guard enableStatus == 0 else {
                traceLogger.log("Input method insertion unavailable reason=enable_failed status=\(enableStatus)")
                return nil
            }
        }

        allSources = pressTalkInputMethodSources(includeAllInstalled: false)
        let enabledSource = preferredPressTalkInputMethodSource(from: allSources) ?? candidate
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

        let selectStatus = TISSelectInputSource(enabledSource)
        guard selectStatus == 0 else {
            let reason = enableNoEffect ? "enable_no_effect" : "select_failed"
            traceLogger.log("Input method insertion unavailable reason=\(reason) status=\(selectStatus)")
            disableIfEnabledOnlyForInsertion([enabledSource, candidate])
            return nil
        }
        defer {
            let restoreStatus = TISSelectInputSource(originalSource)
            if restoreStatus != 0 {
                traceLogger.log("Input method insertion restore failed status=\(restoreStatus)")
            }
            disableIfEnabledOnlyForInsertion([enabledSource, candidate])
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

        func waitForInsertionAcknowledgement(timeout: TimeInterval) -> Bool? {
            let acknowledgementDeadline = Date().addingTimeInterval(timeout)
            while Date() < acknowledgementDeadline {
                if let inserted = inputMethodInsertionAcknowledgementInserted(at: acknowledgementURL) {
                    return inserted
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            return nil
        }

        for attempt in 1...3 {
            Thread.sleep(forTimeInterval: attempt == 1 ? 0.75 : 0.35)
            postInsertionNotification(attempt: attempt)
            Thread.sleep(forTimeInterval: 0.25)

            if let inserted = waitForInsertionAcknowledgement(timeout: attempt == 1 ? 2.0 : 3.0) {
                if inserted {
                    traceLogger.log("Input method insertion acknowledgement inserted=1 attempt=\(attempt)")
                    return "input_method_notification"
                }
                traceLogger.log("Input method insertion unavailable reason=input_method_ack_false")
                return nil
            }

            guard attempt < 3 else { break }
            traceLogger.log("Input method insertion acknowledgement retrying reason=input_method_ack_timeout attempt=\(attempt)")
            let restoreStatus = TISSelectInputSource(originalSource)
            if restoreStatus != 0 {
                traceLogger.log("Input method insertion retry restore failed status=\(restoreStatus)")
            }
            Thread.sleep(forTimeInterval: 0.2)
            let reselectStatus = TISSelectInputSource(enabledSource)
            if reselectStatus != 0 {
                traceLogger.log("Input method insertion unavailable reason=retry_select_failed status=\(reselectStatus)")
                return nil
            }
        }

        traceLogger.log("Input method insertion unavailable reason=input_method_ack_timeout")
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

        guard CFGetTypeID(focusedObject) == AXUIElementGetTypeID() else {
            traceLogger.log("AX direct insertion unavailable reason=focused_object_not_ax_element")
            return nil
        }

        let focusedElement = unsafeBitCast(focusedObject, to: AXUIElement.self)
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
        var selectedRange = CFRange(location: 0, length: 0)
        let hasSelectedRange = selectedRangeError == .success
            && selectedRangeObject.map { CFGetTypeID($0) == AXValueGetTypeID() } == true
            && AXValueGetValue(unsafeBitCast(selectedRangeObject!, to: AXValue.self), .cfRange, &selectedRange)

        var valueObject: CFTypeRef?
        let valueError = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &valueObject
        )
        guard valueError == .success, let currentValue = valueObject as? String, hasSelectedRange else {
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

    private func postPasteShortcut() throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            throw JarvisTapError.eventSynthesisUnavailable
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private func insertTranscriptIntoFocusedApp(_ transcript: String) throws -> TranscriptInsertionResult {
        let preparedTranscript = transcriptForInsertion(transcript)
        guard !preparedTranscript.isEmpty else {
            return .copiedFallback(reason: "empty_transcript")
        }

        guard AXIsProcessTrusted() else {
            if let method = insertPreparedTranscriptUsingInputMethod(preparedTranscript) {
                return .inserted(method: method)
            }
            traceLogger.log("Accessibility preflight unavailable and input method insertion unavailable; copying transcript")
            copyPreparedTranscriptToPasteboard(preparedTranscript)
            return .copiedFallback(reason: "accessibility_preflight_unavailable")
        }

        if let method = insertPreparedTranscriptUsingAccessibility(preparedTranscript) {
            return .inserted(method: method)
        }

        let pasteboardSnapshot = snapshotPasteboardItems()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(preparedTranscript, forType: .string)
        let pasteboardChangeCount = pasteboard.changeCount

        try postPasteShortcut()
        restorePasteboardItems(pasteboardSnapshot, expectedChangeCount: pasteboardChangeCount)
        return .pasteCommandPosted
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

        enum PressDecision {
            case ignoreSilently
            case ignoreStillProcessing
            case start
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
            activeTrigger = trigger
            activeTriggerSource = source
            isRecording = true
            activeTriggerStartedAt = Date()
            return .start
        }

        switch decision {
        case .ignoreSilently:
            return
        case .ignoreStillProcessing:
            traceLogger.log("Trigger ignored trigger=\(trigger.rawValue) reason=still_processing")
            print("⏳ [PressTalk] Still processing the previous dictation. Ignoring trigger.")
            fflush(stdout)
            return
        case .start:
            break
        }

        if let readinessMessage = currentWhisperReadinessMessage() {
            withStateLock {
                isRecording = false
                activeTrigger = nil
                activeTriggerSource = nil
                activeTriggerStartedAt = nil
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
            }
            traceLogger.log("Trigger failed trigger=\(trigger.rawValue) reason=stream_transcriber_unavailable error=\(error)")
            fputs("[PressTalk] Stream transcriber unavailable: \(error)\n", stderr)
            return
        }

        if announce {
            traceLogger.log(triggerStartLogMessage(for: trigger))
            present(.listening(nil))
            print("🎤 [PressTalk] Listening... [trigger=\(trigger.rawValue)]")
            fflush(stdout)
        } else {
            traceLogger.log("Trackpad prearm capture started")
        }

        let transcriber = streamTranscriber
        let traceLogger = self.traceLogger
        let task = Task(priority: .userInitiated) { [self] in
            guard let transcriber else { return }
            do {
                traceLogger.log(announce ? "Audio recording started" : "Audio recording started (prearm)")
                traceLogger.log("Live stream task started")
                try await transcriber.startStreamTranscription()
                traceLogger.log("Live stream task finished")
            } catch {
                traceLogger.log("Streaming transcription failed error=\(error)")
                self.withStateLock {
                    self.isRecording = false
                    self.activeTrigger = nil
                    self.activeTriggerSource = nil
                    self.activeTriggerStartedAt = nil
                    self.streamTask = nil
                }
                self.stopAmplitudeMonitoring()
                if announce {
                    self.present(.error("The live capture stream failed."))
                    fputs("[PressTalk] Streaming transcription failed: \(error)\n", stderr)
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
        let shouldProcess = withStateLock { () -> Bool in
            guard isRecording, activeTrigger == trigger else { return false }
            if let activeTriggerStartedAt {
                captureDurationSeconds = Date().timeIntervalSince(activeTriggerStartedAt)
            }
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
        let decodingOptions = self.decodingOptions
        let transcriber = self.streamTranscriber
        let pasteAutomatically = self.settingsStore.pasteAutomatically

        let task = Task(priority: .userInitiated) { [self] in
            func finishProcessing(reason: String, spokenText: String? = nil) {
                self.withStateLock {
                    self.isProcessing = false
                    self.processingTask = nil
                }
                traceLogger.log("Processing task finished reason=\(reason) state_reset=true")
                if let spokenText {
                    speaker.speak(spokenText)
                }
            }

            func fallbackTranscript() -> String {
                bestTranscriptCandidate(from: [
                    capturedSnapshot.confirmedText,
                    capturedSnapshot.unconfirmedText,
                    capturedSnapshot.currentText,
                ])
            }

            let capturedAudioSamples: [Float]
            let normalizedSamples: [Float]
            let capturedSignalStats: (rms: Double, peak: Double)
            let frozenAudioDurationSeconds: Double
            if let transcriber {
                await captureSilenceAwareReleaseTail(transcriber: transcriber, whisperKit: whisperKit)
            }
            if let whisperKit {
                capturedAudioSamples = Array(whisperKit.audioProcessor.audioSamples)
                frozenAudioDurationSeconds = Double(capturedAudioSamples.count) / Double(WhisperKit.sampleRate)
                capturedSignalStats = audioLevelStats(for: capturedAudioSamples)
                let normalizedResult = normalizedAudioSamples(capturedAudioSamples)
                normalizedSamples = normalizedResult.0
                let normalizedStats = audioLevelStats(for: normalizedSamples)
                traceLogger.log(
                    "Audio capture frozen samples=\(capturedAudioSamples.count) duration_seconds=\(String(format: "%.2f", frozenAudioDurationSeconds)) rms=\(String(format: "%.5f", capturedSignalStats.rms)) peak=\(String(format: "%.5f", capturedSignalStats.peak))"
                )
                traceLogger.log(
                    "Audio normalization gain=\(String(format: "%.2f", normalizedResult.1)) normalized_rms=\(String(format: "%.5f", normalizedStats.rms)) normalized_peak=\(String(format: "%.5f", normalizedStats.peak))"
                )
            } else {
                capturedAudioSamples = []
                normalizedSamples = []
                capturedSignalStats = (0, 0)
                frozenAudioDurationSeconds = 0
            }
            currentStreamTask?.cancel()

            func finalizeTranscript() async throws -> String {
                let streamingTranscript = fallbackTranscript()
                let effectiveCaptureDurationSeconds = max(captureDurationSeconds, frozenAudioDurationSeconds)
                let acceptedStreamingTranscript = validatedFinalTranscriptCandidate(
                    streamingTranscript,
                    signalStats: capturedSignalStats,
                    captureDurationSeconds: effectiveCaptureDurationSeconds,
                    context: "streaming_fallback"
                )
                guard let whisperKit else {
                    if let acceptedStreamingTranscript {
                        traceLogger.log("Whisper unavailable; using streaming transcript fallback")
                        return acceptedStreamingTranscript
                    }
                    throw JarvisTapError.whisperUnavailable
                }

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

                if let acceptedPrimaryTranscript = validatedFinalTranscriptCandidate(
                    primaryTranscript,
                    signalStats: capturedSignalStats,
                    captureDurationSeconds: effectiveCaptureDurationSeconds,
                    context: "offline_primary"
                ) {
                    traceLogger.log("Using offline Whisper transcript as final transcript")
                    return acceptedPrimaryTranscript
                }

                traceLogger.log("Primary offline Whisper transcript rejected; retrying with relaxed decoding")
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
                    traceLogger.log("Relaxed offline Whisper transcript accepted")
                    return acceptedRelaxedTranscript
                }

                traceLogger.log("Relaxed offline Whisper transcript rejected; retrying with auto-detect decoding")
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
                    traceLogger.log("Auto-detect offline Whisper transcript accepted")
                    return acceptedAutoTranscript
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
                    if captureDurationSeconds >= shortHoldNoSpeechSuppressionSeconds {
                        present(.error("I didn’t catch any clear speech."))
                    }
                    print("⚠️ [PressTalk] No speech captured.")
                    fflush(stdout)
                    finishProcessing(
                        reason: captureDurationSeconds >= shortHoldNoSpeechSuppressionSeconds ? "no_speech" : "no_speech_suppressed_short_hold"
                    )
                    return
                }

                traceLogger.log("📝 Transkription abgeschlossen: \(transcript)")
                print("🗣️ [PressTalk recognized] \(transcript)")
                fflush(stdout)

                if agentMode == "dictation" {
                    if pasteAutomatically {
                        traceLogger.log("Pasting dictated transcript into focused app")
                        let insertionResult = try insertTranscriptIntoFocusedApp(transcript)
                        switch insertionResult {
                        case .inserted(let method):
                            traceLogger.log("Dictation inserted method=\(method)")
                            present(.inserted(transcript))
                            finishProcessing(reason: "dictation_insert")
                        case .pasteCommandPosted:
                            traceLogger.log("Dictation paste command posted")
                            present(.inserted(transcript))
                            finishProcessing(reason: "dictation_paste")
                        case .copiedFallback(let reason):
                            traceLogger.log("Dictation copied because paste unavailable reason=\(reason)")
                            present(.copied(transcript))
                            finishProcessing(reason: "dictation_copy_fallback")
                        }
                    } else {
                        copyTranscriptToPasteboard(transcript)
                        traceLogger.log("Dictation copy completed")
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

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = await task.result
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }

            let finished = await group.next() ?? true
            group.cancelAll()
            return finished
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

            latestStreamingState = StreamingSnapshot(
                currentText: filteredCurrentText,
                confirmedText: filteredConfirmedText,
                unconfirmedText: filteredUnconfirmedText
            )

            let cleaned = filteredCurrentText
            guard !cleaned.isEmpty else { return }
            guard cleaned != lastPrintedPartial else { return }

            lastPrintedPartial = cleaned
            cleanedToLog = cleaned
            shouldPrintPartial = config.printPartials && cleaned != cleanedTranscriptText(oldState.currentText)
        }

        guard let cleanedToLog else { return }
        traceLogger.log("Partial transcript: \(cleanedToLog)")
        present(.listening(cleanedToLog))
        if shouldPrintPartial {
            print("📝 [PressTalk partial] \(cleanedToLog)")
            fflush(stdout)
        }
    }

    private func processCapturedCommand(preferFallbackTranscript: Bool) async {
        defer {
            withStateLock {
                self.isProcessing = false
                self.processingTask = nil
            }
        }

        do {
            let transcript = try await finalizeTranscript(preferFallbackTranscript: preferFallbackTranscript)
            guard !transcript.isEmpty else {
                traceLogger.log("No speech captured after release")
                print("⚠️ [PressTalk] No speech captured.")
                fflush(stdout)
                return
            }

            traceLogger.log("📝 Transkription abgeschlossen: \(transcript)")
            print("🗣️ [PressTalk recognized] \(transcript)")
            fflush(stdout)

            if config.agentMode == "dictation" {
                traceLogger.log("Pasting dictated transcript into focused app")
                let insertionResult = try insertTranscriptIntoFocusedApp(transcript)
                switch insertionResult {
                case .inserted(let method):
                    traceLogger.log("Dictation inserted method=\(method)")
                case .pasteCommandPosted:
                    traceLogger.log("Dictation paste command posted")
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

        let capturedSamples = Array(whisperKit.audioProcessor.audioSamples)
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
            return acceptedPrimaryTranscript
        }

        traceLogger.log("Primary offline Whisper transcript rejected; retrying with relaxed decoding")
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
            traceLogger.log("Relaxed offline Whisper transcript accepted")
            return acceptedRelaxedTranscript
        }

        traceLogger.log("Relaxed offline Whisper transcript rejected; retrying with auto-detect decoding")
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
            traceLogger.log("Auto-detect offline Whisper transcript accepted")
            return acceptedAutoTranscript
        }

        let acceptedFallbackTranscript = validatedFinalTranscriptCandidate(
            fallbackTranscript(),
            signalStats: signalStats,
            captureDurationSeconds: captureDurationSeconds,
            context: "streaming_fallback"
        )
        if let acceptedFallbackTranscript {
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

private let jarvisTapApplication = NSApplication.shared
private let jarvisTapDelegate = JarvisTapApp()

jarvisTapApplication.setActivationPolicy(.accessory)
jarvisTapApplication.delegate = jarvisTapDelegate
jarvisTapApplication.run()
