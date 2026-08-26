// CoachContext+MovementBlocks.swift
//
// Extracted from CoachContext.swift (Tier-3 god-object split). Movement-pattern / muscle-balance / familiarity blocks.
// `snapshot(...)` in CoachContext.swift composes these section builders.

import Foundation

extension CoachContext {
    /// Movement-pattern frequency over the last 4 weeks. Counts how many
    /// distinct training days hit each pattern (squat, hip-hinge, etc.) and
    /// flags any CANONICAL lifting pattern with zero hits so the coach can
    /// prioritise it on the next workout. Returns nil if no sessions in the
    /// window have any resolvable patterns.
    static func patternFrequencySection(sessions: [SavedSession],
                                        weeks: Int = 4,
                                        now: Date = Date()) -> String? {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .weekOfYear, value: -weeks, to: now) ?? now
        let recent = sessions.filter { $0.startTime >= cutoff }
        guard !recent.isEmpty else { return nil }

        // Memoise name → pattern slugs across the call.
        var resolved: [String: [String]] = [:]
        let db = CoachDatabase.shared

        // For each session, gather the unique pattern slugs it contains,
        // then increment per-pattern session counts. Sessions, not sets —
        // hitting "squat" 4 times in one day is still one session for this
        // signal.
        var byPattern: [String: Int] = [:]
        for session in recent {
            var sessionPatterns: Set<String> = []
            for ex in session.exercises {
                if let cached = resolved[ex.name] {
                    sessionPatterns.formUnion(cached)
                    continue
                }
                let exact = db.listExercises(search: ex.name)
                    .first { $0.name.caseInsensitiveCompare(ex.name) == .orderedSame }
                let patterns = exact.map { db.patternsForExercise($0.id) } ?? []
                resolved[ex.name] = patterns
                sessionPatterns.formUnion(patterns)
            }
            for p in sessionPatterns { byPattern[p, default: 0] += 1 }
        }

        if byPattern.isEmpty { return nil }

        // Top patterns by count, plus a "missing" list of canonical patterns
        // not seen. The canonical set is the same one the WorkoutGenerator's
        // recipes anchor on.
        let canonical: [String] = [
            "squat", "hip-hinge",
            "horizontal-push", "vertical-push",
            "horizontal-pull", "vertical-pull",
        ]
        let top = byPattern.sorted { $0.value > $1.value }.prefix(8)
        let plural = recent.count == 1 ? "session" : "sessions"
        var lines = top.map { (slug, count) in
            "- \(formatPattern(slug)): \(count) \(count == 1 ? "session" : "sessions")"
        }
        let missing = canonical.filter { byPattern[$0] == nil }
        if !missing.isEmpty {
            lines.append("- missing (no training in last \(weeks)w): \(missing.map(formatPattern).joined(separator: ", "))")
        }
        return "PATTERN FREQUENCY — last \(weeks)w across \(recent.count) \(plural)\n" + lines.joined(separator: "\n")
    }

    /// "horizontal-push" → "Horizontal push". Cheap display formatting.
    private static func formatPattern(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// Muscle-balance snapshot over the last 4 weeks. Surfaces the top 5
    /// muscle groups by allocated volume + flags any group whose volume is
    /// < 1/3 the top group's (a coarse imbalance signal the coach can act on).
    /// Returns nil when there's no resolvable session volume.
    static func muscleBalanceSection(sessions: [SavedSession], now: Date) -> String? {
        let rows = MuscleVolume.rows(from: sessions, weeks: 4, limit: 5, now: now)
        guard !rows.isEmpty else { return nil }
        let top = rows[0].volume
        guard top > 0 else { return nil }
        var lines: [String] = []
        for row in rows {
            let pct = Int((row.volume / top * 100).rounded())
            var line = "- \(row.label): \(Int(row.volume.rounded())) (\(pct)% of top)"
            if row.volume * 3 < top {
                line += " · underdone"
            }
            lines.append(line)
        }
        return "MUSCLE BALANCE — last 4w (weight × reps, role-allocated)\n" + lines.joined(separator: "\n")
    }

    /// Top exercises the user has actually trained recently. Different signal
    /// than strength — strength only covers the canonical 5 lifts. This
    /// includes everything (accessories, isolations, mobility) so the coach
    /// can speak to what's familiar. Returns nil if the user has < 3 unique
    /// completed exercises in the window.
    static func familiaritySection(sessions: [SavedSession], now: Date, days: Int = 90, limit: Int = 10) -> String? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now

        struct Stat { var setCount: Int = 0; var sessionDates: Set<DateComponents> = [] }
        var stats: [String: Stat] = [:]
        let cal = Calendar.current
        for session in sessions where session.startTime >= cutoff {
            let day = cal.dateComponents([.year, .month, .day], from: session.startTime)
            for ex in session.exercises {
                let done = ex.sets.filter(\.done).count
                guard done > 0 else { continue }
                var s = stats[ex.name] ?? Stat()
                s.setCount += done
                s.sessionDates.insert(day)
                stats[ex.name] = s
            }
        }
        guard stats.count >= 3 else { return nil }
        let top = stats
            .map { (name: $0.key, sets: $0.value.setCount, sessions: $0.value.sessionDates.count) }
            .sorted { $0.sets > $1.sets }
            .prefix(limit)
        let lines = top.map { row -> String in
            let plural = row.sessions == 1 ? "session" : "sessions"
            return "- \(CoachContext.sanitizeFreeText(row.name, max: 80)): \(row.sets) sets across \(row.sessions) \(plural)"
        }
        return "EXERCISE FAMILIARITY — last \(days)d\n" + lines.joined(separator: "\n")
    }
}
