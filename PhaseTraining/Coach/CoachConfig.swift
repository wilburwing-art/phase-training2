// CoachConfig.swift — Phase 13 LLM endpoint + cap constants.
//
// Anthropic-style /v1/messages requests are sent through the Cloudflare AI
// Gateway. The gateway has BYOK enabled and stores the upstream Anthropic
// key — clients never see or ship it. Authentication to the gateway is via
// the per-environment token in CoachSecrets.gatewayToken (build-generated).

import Foundation

enum CoachConfig {
    /// Cloudflare AI Gateway endpoint for the `phasetraining` gateway,
    /// `anthropic` provider route.
    static let baseURL = URL(string: "https://gateway.ai.cloudflare.com/v1/192ffcc4f56e84386ddc0875eab97826/phasetraining/anthropic")!

    /// BYOK alias registered in the CF AI Gateway dashboard for this app's
    /// upstream Anthropic key. Sent as `cf-aig-byok-alias` so CF substitutes
    /// the real key server-side.
    static let byokAlias = "phasetraining-anthropic"

    /// Default model for chat + tool calls.
    static let defaultModel = "claude-sonnet-4-6"

    /// Fallback model on slow primary response. Cheaper + faster, used with
    /// trimmed context.
    static let fallbackModel = "claude-haiku-4-5"

    /// Anthropic API version header. Pinned so future API tweaks don't
    /// silently break us.
    static let anthropicVersion = "2023-06-01"

    /// Soft daily turn cap per user. Above this we show a "slow down" banner
    /// but still complete the turn.
    static let softTurnCap = 50

    /// Hard daily turn cap. Above this we refuse to send and surface
    /// "Pause until tomorrow."
    static let hardTurnCap = 100

    /// Max tokens to request from the model per turn.
    static let maxOutputTokens = 1024
}
