// CoachInsight.swift — Phase 13e proactive coach observation.
//
// A short reflection the coach writes when the user foregrounds the app and
// has fresh signal worth reflecting on (recent feedback, pain flags, days
// since last session, plan drift). Persisted in TrainingMemory.coachInsights
// with a rolling 30-day retention window.
//
// Surfaces: today (TodayScreen InsightCard). Tapping the card opens the
// CoachDrawer with the insight body pre-loaded as a follow-up prompt — the
// existing InsightCard → CoachConversationStore.present(withPrefill:) wiring.

import Foundation

struct CoachInsight: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var body: String
    /// "today" only in v1. Future surfaces: "week", "post-workout".
    var surface: String = "today"
    /// Reserved for a future "review in coach" tap-through to a specific
    /// archived conversation. Phase 13e doesn't populate it.
    var sourceConversationId: UUID? = nil
}

extension CoachInsight {
    /// Trim insights older than 30 days. Called from MemoryStore on append.
    static func prune(_ insights: [CoachInsight], now: Date = Date()) -> [CoachInsight] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        return insights.filter { $0.date >= cutoff }
    }
}
