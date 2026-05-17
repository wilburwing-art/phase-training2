// CoachClient.swift — Phase 13a: one-shot, non-streaming /v1/messages call.
//
// Sends an Anthropic-shaped request to the Cloudflare AI Gateway. Streaming
// (SSE → SwiftUI Text) lands in 13b; this client is sufficient to prove the
// full path (consent → secrets → gateway → BYOK key substitution → upstream
// → response) end-to-end before any chat UI exists.
//
// Auth headers:
//   cf-aig-authorization: Bearer <gateway token>   (authenticated gateway)
//   cf-aig-byok-alias:    phasetraining-anthropic  (CF appends Anthropic key)
//   anthropic-version:    2023-06-01
//   content-type:         application/json
//
// No x-api-key header is sent — that's the whole point of BYOK in the gateway.

import Foundation

actor CoachClient {
    enum CoachError: Error, LocalizedError {
        case missingGatewayToken
        case http(status: Int, body: String)
        case decode(Error)
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .missingGatewayToken:
                return "No Cloudflare AI Gateway token configured. Set PHASETRAINING_CF_AIG_DEV_TOKEN in ~/.config/phase-training/cf-aigateway-tokens.env and rebuild."
            case .http(let status, let body):
                return "Gateway returned HTTP \(status): \(body)"
            case .decode(let err):
                return "Couldn't decode response: \(err.localizedDescription)"
            case .transport(let err):
                return "Network error: \(err.localizedDescription)"
            }
        }
    }

    struct PingResult {
        let text: String
        let inputTokens: Int
        let outputTokens: Int
        let latencyMs: Int
        let model: String
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Conversation turn — assistant or user message used in the chat history.
    struct Turn: Sendable {
        let role: String      // "user" or "assistant"
        let text: String
    }

    /// Round-trip a single user message. Returns the model's full reply
    /// (no streaming) plus token + latency metadata for the debug ping.
    func send(
        userMessage: String,
        system: String? = nil,
        model: String = CoachConfig.defaultModel
    ) async throws -> PingResult {
        guard !CoachSecrets.gatewayToken.isEmpty else {
            throw CoachError.missingGatewayToken
        }

        var req = URLRequest(url: CoachConfig.baseURL.appendingPathComponent("v1/messages"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(CoachConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("Bearer \(CoachSecrets.gatewayToken)", forHTTPHeaderField: "cf-aig-authorization")
        req.setValue(CoachConfig.byokAlias, forHTTPHeaderField: "cf-aig-byok-alias")

        let body = MessagesRequest(
            model: model,
            maxTokens: CoachConfig.maxOutputTokens,
            system: system.map { [SystemBlock(text: $0, cacheControl: nil)] },
            messages: [.init(role: "user", content: userMessage)],
            stream: false
        )
        req.httpBody = try JSONEncoder().encode(body)

        let started = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw CoachError.transport(error)
        }
        let latencyMs = Int(Date().timeIntervalSince(started) * 1000)

        guard let http = response as? HTTPURLResponse else {
            throw CoachError.http(status: -1, body: "no HTTPURLResponse")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? "<binary>"
            throw CoachError.http(status: http.statusCode, body: String(snippet.prefix(512)))
        }

        let decoded: MessagesResponse
        do {
            decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw CoachError.decode(error)
        }

        let text = decoded.content.compactMap { block -> String? in
            block.type == "text" ? block.text : nil
        }.joined()

        return PingResult(
            text: text,
            inputTokens: decoded.usage.inputTokens,
            outputTokens: decoded.usage.outputTokens,
            latencyMs: latencyMs,
            model: decoded.model
        )
    }

    /// Streaming chat. Yields text deltas as they arrive. Caller composes
    /// system blocks (long cached header + per-turn context) and the full
    /// `history` of previous turns.
    nonisolated func stream(
        cachedSystem: String,
        perTurnContext: String,
        history: [Turn],
        userMessage: String,
        model: String = CoachConfig.defaultModel
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard !CoachSecrets.gatewayToken.isEmpty else {
                    continuation.finish(throwing: CoachError.missingGatewayToken)
                    return
                }

                var req = URLRequest(url: CoachConfig.baseURL.appendingPathComponent("v1/messages"))
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "content-type")
                req.setValue(CoachConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
                req.setValue("Bearer \(CoachSecrets.gatewayToken)", forHTTPHeaderField: "cf-aig-authorization")
                req.setValue(CoachConfig.byokAlias, forHTTPHeaderField: "cf-aig-byok-alias")
                req.setValue("text/event-stream", forHTTPHeaderField: "accept")

                var messages = history.map { MessagesRequest.Message(role: $0.role, content: $0.text) }
                messages.append(.init(role: "user", content: userMessage))

                let body = MessagesRequest(
                    model: model,
                    maxTokens: CoachConfig.maxOutputTokens,
                    system: [
                        SystemBlock(text: cachedSystem, cacheControl: .init(type: "ephemeral")),
                        SystemBlock(text: perTurnContext, cacheControl: nil),
                    ],
                    messages: messages,
                    stream: true
                )
                do {
                    req.httpBody = try JSONEncoder().encode(body)
                } catch {
                    continuation.finish(throwing: CoachError.decode(error))
                    return
                }

                do {
                    let (bytes, response) = try await self.session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        var snippet = ""
                        for try await line in bytes.lines {
                            snippet += line
                            if snippet.count > 512 { break }
                        }
                        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                        continuation.finish(throwing: CoachError.http(status: status, body: snippet))
                        return
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish(throwing: CancellationError())
                            return
                        }
                        // SSE: only data lines carry the JSON payload.
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst("data: ".count))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else { continue }
                        if event.type == "content_block_delta",
                           let delta = event.delta,
                           delta.type == "text_delta",
                           let text = delta.text {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: CoachError.transport(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Anthropic /v1/messages wire shapes (minimal subset)

private struct SystemBlock: Encodable {
    let type = "text"
    let text: String
    let cacheControl: CacheControl?

    struct CacheControl: Encodable {
        let type: String  // "ephemeral"
    }

    enum CodingKeys: String, CodingKey {
        case type, text
        case cacheControl = "cache_control"
    }
}

private struct MessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: [SystemBlock]?
    let messages: [Message]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case stream
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct StreamEvent: Decodable {
    let type: String
    let delta: Delta?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }
}

private struct MessagesResponse: Decodable {
    let model: String
    let content: [ContentBlock]
    let usage: Usage

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens  = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}
