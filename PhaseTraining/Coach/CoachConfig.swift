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

    /// Daily ceiling on ALL gateway calls, not just drawer sends.
    ///
    /// `hardTurnCap` counts only user-initiated chat turns via
    /// `CoachConversationStore.recordTurn()`. Three other callers reach the
    /// gateway without touching it — CoachRequestScreen's "Ask coach to build",
    /// InsightGenerator's daily insight, and the background plan-refinement
    /// pass (one call PER LIFT DAY per regen) — so the documented cost guard
    /// did not bound actual spend at all. This is the backstop enforced inside
    /// CoachClient itself, the one chokepoint every caller shares.
    ///
    /// Set above hardTurnCap so normal chat still hits the friendlier
    /// per-conversation limit first; this only catches runaway non-chat spend.
    ///
    /// NOTE: this is a client-side guard in UserDefaults and is trivially
    /// bypassed by anyone who extracts the gateway token from the IPA. It
    /// limits accidental spend, not abuse — the real ceiling has to be a
    /// rate/spend limit configured on the Cloudflare AI Gateway itself.
    static let dailyRequestCeiling = 400

    /// Max tokens to request from the model per turn.
    static let maxOutputTokens = 1024

    /// Time-to-first-byte cap on Coach requests. URLSession's default is 60s
    /// which feels broken at a gym with flaky signal; this fails fast and
    /// surfaces a transport error the caller can show as "try again."
    /// For streaming, this only applies until the first byte arrives — once
    /// data starts flowing, URLSession keeps the connection open.
    static let requestTimeoutSeconds: TimeInterval = 20
}
