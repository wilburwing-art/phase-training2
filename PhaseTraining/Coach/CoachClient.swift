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
        case dailyCeilingReached
        case http(status: Int, body: String)
        case decode(Error)
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .missingGatewayToken:
                return "No Cloudflare AI Gateway token configured. Set PHASETRAINING_CF_AIG_DEV_TOKEN in ~/.config/phase-training/cf-aigateway-tokens.env and rebuild."
            case .dailyCeilingReached:
                return "The coach has reached today's request limit. It'll pick back up tomorrow."
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

    // MARK: - Daily request ceiling (cost backstop)

    private static let ceilingCountKey = "pt_coach_gateway_requests_today"
    private static let ceilingDayKey   = "pt_coach_gateway_requests_day"

    /// Count one outbound gateway request and report whether it's allowed.
    /// Enforced HERE rather than at each call site because this is the single
    /// chokepoint every caller shares — the drawer, "Ask coach to build", the
    /// daily insight, and the per-lift-day refinement pass. Rolls over on
    /// calendar day.
    static func consumeDailyRequestBudget(
        defaults: UserDefaults = .standard,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let today = calendar.startOfDay(for: now).timeIntervalSince1970
        let storedDay = defaults.double(forKey: ceilingDayKey)
        var count = defaults.integer(forKey: ceilingCountKey)
        if storedDay != today {
            count = 0
            defaults.set(today, forKey: ceilingDayKey)
        }
        guard count < CoachConfig.dailyRequestCeiling else { return false }
        defaults.set(count + 1, forKey: ceilingCountKey)
        return true
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
        guard Self.consumeDailyRequestBudget() else {
            throw CoachError.dailyCeilingReached
        }

        var req = URLRequest(url: CoachConfig.baseURL.appendingPathComponent("v1/messages"))
        req.httpMethod = "POST"
        // Cap the wait so a flaky gym signal can't hang the call indefinitely.
        // Default URLSession is 60s — too long for mid-workout UX.
        req.timeoutInterval = CoachConfig.requestTimeoutSeconds
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

    /// Stream events the drawer consumes. Text deltas during normal output;
    /// toolCall once for each tool_use block as it completes.
    enum StreamPart: Sendable {
        case textDelta(String)
        case toolCall(id: String, name: String, input: Data)
    }

    /// Streaming chat. Yields text deltas + tool calls as they arrive.
    nonisolated func stream(
        cachedSystem: String,
        perTurnContext: String,
        history: [Turn],
        userMessage: String,
        model: String = CoachConfig.defaultModel,
        tools: [AnthropicTool]? = nil
    ) -> AsyncThrowingStream<StreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard Self.consumeDailyRequestBudget() else {
                    continuation.finish(throwing: CoachError.dailyCeilingReached)
                    return
                }
                guard !CoachSecrets.gatewayToken.isEmpty else {
                    continuation.finish(throwing: CoachError.missingGatewayToken)
                    return
                }

                var req = URLRequest(url: CoachConfig.baseURL.appendingPathComponent("v1/messages"))
                req.httpMethod = "POST"
                // Time-to-first-byte cap. Once streaming begins, URLSession keeps
                // the connection open — this only fires if the gateway never
                // responds at all (typical at a gym with flaky signal).
                req.timeoutInterval = CoachConfig.requestTimeoutSeconds
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
                    stream: true,
                    tools: tools
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

                    // Per-block scratch state. Indexed by content_block.index.
                    var toolUseScratch: [Int: (id: String, name: String, json: String)] = [:]

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish(throwing: CancellationError())
                            return
                        }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst("data: ".count))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else { continue }

                        switch event.type {
                        case "content_block_start":
                            if let cb = event.contentBlock, cb.type == "tool_use",
                               let idx = event.index, let id = cb.id, let name = cb.name {
                                toolUseScratch[idx] = (id, name, "")
                            }

                        case "content_block_delta":
                            guard let delta = event.delta, let idx = event.index else { continue }
                            if delta.type == "text_delta", let text = delta.text {
                                continuation.yield(.textDelta(text))
                            } else if delta.type == "input_json_delta", let partial = delta.partialJson {
                                toolUseScratch[idx]?.json += partial
                            }

                        case "content_block_stop":
                            guard let idx = event.index, let scratch = toolUseScratch[idx] else { continue }
                            toolUseScratch.removeValue(forKey: idx)
                            if let inputData = scratch.json.data(using: .utf8) {
                                continuation.yield(.toolCall(id: scratch.id, name: scratch.name, input: inputData))
                            }

                        default:
                            break
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
    let tools: [AnthropicTool]?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case stream
        case tools
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    init(
        model: String,
        maxTokens: Int,
        system: [SystemBlock]?,
        messages: [Message],
        stream: Bool,
        tools: [AnthropicTool]? = nil
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
        self.stream = stream
        self.tools = tools
    }
}

private struct StreamEvent: Decodable {
    let type: String
    let index: Int?
    let delta: Delta?
    let contentBlock: ContentBlock?

    enum CodingKeys: String, CodingKey {
        case type, index, delta
        case contentBlock = "content_block"
    }

    struct Delta: Decodable {
        let type: String?
        let text: String?
        let partialJson: String?

        enum CodingKeys: String, CodingKey {
            case type, text
            case partialJson = "partial_json"
        }
    }

    struct ContentBlock: Decodable {
        let type: String
        let id: String?
        let name: String?
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
