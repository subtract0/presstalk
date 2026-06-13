import Foundation

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
