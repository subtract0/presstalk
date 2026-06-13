import Foundation

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
