import Foundation

/// Talks to the Anthropic Messages API directly over HTTPS with streaming (server-sent events).
/// The user's own API key is read from the Keychain and sent only to api.anthropic.com.
struct AnthropicClient {
    struct Message: Encodable {
        let role: String   // "user" or "assistant"
        let content: String
    }

    enum StreamEvent {
        /// More text for the reply.
        case text(String)
        /// The server switched to a fallback model mid-reply; discard text shown so far.
        case reset
    }

    enum ClientError: LocalizedError {
        case noAPIKey
        case offline
        case invalidKey
        case noCredit(String)
        case rateLimited
        case overloaded
        case refused
        case server(Int, String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: "No API key. Add your Anthropic API key in Settings."
            case .offline: "You're offline. The trainer chat needs an internet connection. Logging still works."
            case .invalidKey: "Your API key was rejected. Check it in Settings, or create a new one at console.anthropic.com."
            case .noCredit(let msg): "The API declined the request: \(msg). Check billing at console.anthropic.com."
            case .rateLimited: "Too many requests right now. Wait a moment and try again."
            case .overloaded: "Claude is busy right now. Try again in a minute."
            case .refused: "The trainer couldn't answer that one. Try rephrasing."
            case .server(let code, let msg): "API error \(code): \(msg)"
            }
        }
    }

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"

    /// Models that support server-side fallback when a safety classifier declines a request.
    private static let fallbackModels: Set<String> = [
        "claude-sonnet-5-5", "claude-opus-5-5", "claude-opus-5", "claude-fable-5-2", "claude-fable-5-1",
    ]

    var model: String = AppSettings.model
    var maxTokens: Int = 16000

    func stream(stableSystem: String, contextSystem: String, messages: [Message]) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(stableSystem: stableSystem, contextSystem: contextSystem, messages: messages, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Convenience: collect a full reply as one string.
    func complete(stableSystem: String, contextSystem: String, messages: [Message]) async throws -> String {
        var text = ""
        for try await event in stream(stableSystem: stableSystem, contextSystem: contextSystem, messages: messages) {
            switch event {
            case .text(let t): text += t
            case .reset: text = ""
            }
        }
        return text
    }

    // MARK: - Internals

    private func run(stableSystem: String, contextSystem: String, messages: [Message],
                     continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) async throws {
        guard let key = KeychainStore.apiKey else { throw ClientError.noAPIKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            // The persona is identical every time, so it is cached; the data snapshot changes and sits after it.
            "system": [
                ["type": "text", "text": stableSystem, "cache_control": ["type": "ephemeral"]],
                ["type": "text", "text": contextSystem],
            ],
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            // Chat replies are conversational: low effort keeps them quick and cheap.
            "output_config": ["effort": "low"],
        ]
        if Self.fallbackModels.contains(model) {
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.server(0, "No response") }

        if http.statusCode != 200 {
            var raw = Data()
            for try await byte in bytes { raw.append(byte); if raw.count > 16_000 { break } }
            throw Self.httpError(status: http.statusCode, body: raw)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            switch type {
            case "content_block_start":
                if let block = json["content_block"] as? [String: Any], block["type"] as? String == "fallback" {
                    continuation.yield(.reset)
                }
            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any],
                   delta["type"] as? String == "text_delta",
                   let text = delta["text"] as? String {
                    continuation.yield(.text(text))
                }
            case "message_delta":
                if let delta = json["delta"] as? [String: Any], delta["stop_reason"] as? String == "refusal" {
                    throw ClientError.refused
                }
            case "error":
                let err = json["error"] as? [String: Any]
                let errType = err?["type"] as? String ?? ""
                let message = err?["message"] as? String ?? "Unknown error"
                if errType == "overloaded_error" { throw ClientError.overloaded }
                throw ClientError.server(0, message)
            case "message_stop":
                return
            default:
                continue
            }
        }
    }

    private static func httpError(status: Int, body: Data) -> ClientError {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: status)
        switch status {
        case 401: return .invalidKey
        case 402, 403: return .noCredit(message)
        case 429: return .rateLimited
        case 529: return .overloaded
        default:
            if message.localizedCaseInsensitiveContains("credit balance") { return .noCredit(message) }
            return .server(status, message)
        }
    }

    private static func map(_ error: Error) -> Error {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost, .cannotConnectToHost:
                return ClientError.offline
            default:
                return urlError
            }
        }
        return error
    }
}
