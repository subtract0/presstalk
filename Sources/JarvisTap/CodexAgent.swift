import Foundation

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
