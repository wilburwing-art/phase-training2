// InsightGenerator.swift — Phase 13e proactive observation pass.
//
// Runs on app foreground (scenePhase = .active). Guards:
//   1. AI Coach consent granted.
//   2. No insight already written today (one per calendar day).
//   3. There's something worth saying: recent feedback (last 7d),
//      pain-flagged soreness, OR a session in the last 3 days.
//
// On success appends to memory.coachInsights, prunes to a rolling 30-day
// window. Non-streaming round-trip via CoachClient.send to keep this cheap
// and avoid juggling SSE here.
//
// The insight body is read by TodayScreen as the active insightCopy and
// surfaced via InsightCard; tapping it opens CoachDrawer with the body as
// the prefill prompt (using the existing tap-to-coach affordance).

import Foundation

@MainActor
enum InsightGenerator {
    private static let client = CoachClient()

    /// True while a generation round-trip is in flight. Rapid foreground/
    /// background cycles would otherwise race hasInsightForToday (the insight
    /// is only appended once the request returns) and double-generate.
    private static var inFlight = false

    /// Top-level entry. Safe to call repeatedly — internal guards make it idempotent
    /// across multiple foreground events on the same day.
    static func runIfDue(
        memoryStore: MemoryStore,
        planStore: PlanStore,
        sessionStore: SessionStore,
        consentGranted: Bool,
        now: Date = Date()
    ) {
        guard consentGranted, CoachEntitlement.proSatisfied() else { return }
        guard !inFlight else { return }
        guard !hasInsightForToday(memory: memoryStore.memory, now: now) else { return }
        guard hasSignal(memory: memoryStore.memory, sessions: sessionStore.savedSessions, now: now) else { return }

        let snapshot = CoachContext.snapshot(
            now: now,
            activeTab: .today,
            memory: memoryStore.memory,
            plan: planStore.plan,
            recentSessions: sessionStore.savedSessions,
            recentFeedback: memoryStore.memory.feedback,
            recentSoreness: memoryStore.memory.soreness
        )

        inFlight = true
        Task {
            defer { inFlight = false }
            do {
                let result = try await client.send(
                    userMessage: insightUserPrompt,
                    system: insightSystemPrompt(snapshot: snapshot)
                )
                let body = sanitize(result.text)
                guard !body.isEmpty else { return }
                memoryStore.update { mem in
                    mem.coachInsights.append(
                        CoachInsight(date: now, body: body, surface: "today")
                    )
                    mem.coachInsights = CoachInsight.prune(mem.coachInsights, now: now)
                }
            } catch {
                // Swallow network/decode failures — this is a background nicety,
                // not a user-visible operation, so no error UI. runIfDue re-fires
                // on every app foreground, and hasInsightForToday stays false
                // until an append succeeds, so failures self-heal on retry.
                #if DEBUG
                print("[InsightGenerator] skipped: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Guards

    private static func hasInsightForToday(memory: TrainingMemory, now: Date) -> Bool {
        memory.coachInsights.contains {
            Calendar.current.isDate($0.date, inSameDayAs: now)
        }
    }

    private static func hasSignal(memory: TrainingMemory, sessions: [SavedSession], now: Date) -> Bool {
        let cal = Calendar.current
        let last7 = cal.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        let last3 = cal.date(byAdding: .day, value: -3, to: now) ?? .distantPast

        if memory.feedback.contains(where: { $0.date >= last7 }) { return true }
        if memory.soreness.contains(where: { $0.date >= last7 && $0.pain }) { return true }
        if sessions.contains(where: { $0.startTime >= last3 }) { return true }
        return false
    }

    // MARK: - Prompts

    private static let insightUserPrompt =
        "Write the insight now."

    private static func insightSystemPrompt(snapshot: String) -> String {
        """
        You write a SHORT coaching observation for an iOS workout app's Today screen. Output rules:
        - 1 to 2 sentences, ≤240 characters TOTAL, plain text (no markdown, no quotes, no emoji).
        - OBSERVATION first, then ONE concrete takeaway is okay — but don't be preachy.
        - Cite something specific from the context (a date, an exercise, soreness flag, sport) when possible.
        - If you have nothing meaningful to say, output the empty string.

        CONTEXT:

        \(snapshot)
        """
    }

    // MARK: - Sanitize

    /// Strip surrounding whitespace / quotes / trailing junk. Models sometimes
    /// reach for "Sure! Here's an insight: ..." despite the prompt; if the
    /// reply opens with throat-clearing, take only the last sentence.
    /// Internal (not private) so T1-47's regression — a two-sentence insight
    /// reduced to its last sentence — stays pinned by a test.
    static func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "\u{201C}", with: "")   // “
        s = s.replacingOccurrences(of: "\u{201D}", with: "")   // ”
        s = s.replacingOccurrences(of: "\"", with: "")
        // Truncate, don't decapitate. This used to keep only the LAST sentence
        // whenever the reply exceeded 140 characters — but the prompt asks for
        // "OBSERVATION first, then ONE concrete takeaway" within 280, so a
        // well-formed two-sentence insight was reduced to the takeaway with the
        // evidence that justified it stripped off ("Add a set next week." with
        // no mention of what the user did to earn it).
        //
        // 280 is the real budget; only trim past it, and trim at a sentence
        // boundary so we never cut mid-word.
        if s.count > 280 {
            let sentences = s
                .split(whereSeparator: { ".!?".contains($0) })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var kept = ""
            for sentence in sentences {
                let candidate = kept.isEmpty ? sentence : kept + ". " + sentence
                if candidate.count > 280 { break }
                kept = candidate
            }
            s = kept.isEmpty ? String(s.prefix(280)) : kept
        }
        return s
    }
}
