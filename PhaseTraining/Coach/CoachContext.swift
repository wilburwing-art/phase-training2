// CoachContext.swift — serialize live app state into a compact text block
// the model reads as part of its system prompt.
//
// Two-block strategy:
//   1. CoachSystemPrompt.cachedHeader — long, static, marked cache_control:
//      ephemeral so prompt-cache hits on every turn after the first.
//   2. CoachContext.snapshot(...)     — short, per-turn, contains today's
//      date, the active tab, plan, recent feedback. Sent fresh each call.

import Foundation

enum CoachContext {
    /// Build the per-turn context block. Caller passes everything explicitly
    /// so this stays a pure function and CoachDrawer can mock it for tests.
    static func snapshot(
        now: Date = Date(),
        activeTab: AppTab,
        memory: TrainingMemory,
        plan: WeekPlan?,
        recentSessions: [SavedSession],
        recentFeedback: [FeedbackEntry],
        recentSoreness: [SorenessEntry]
    ) -> String {
        var blocks: [String] = []

        blocks.append("Today is \(longDate(now)) (\(weekday(now))).")
        blocks.append("The user is currently viewing the \(activeTab.label) tab.")

        // Profile summary — what the planner reads.
        var profile: [String] = []
        if let sport = memory.primarySport { profile.append("primary sport: \(sport.name)") }
        if !memory.sports.isEmpty {
            let others = memory.sports.filter { $0.id != memory.primarySport?.id }.map(\.name)
            if !others.isEmpty { profile.append("other sports: \(others.joined(separator: ", "))") }
        }
        profile.append("focus: \(memory.primaryFocus.label)")
        profile.append("experience: \(memory.experience.label)")
        profile.append("equipment: \(memory.equipment.map(\.label).joined(separator: ", "))")
        profile.append("target lifts/wk: \(memory.liftDaysPerWeek)")
        profile.append("session length: \(memory.sessionMinutes) min")
        blocks.append("USER PROFILE\n" + profile.map { "- \($0)" }.joined(separator: "\n"))

        if let body = bodySection(memory: memory) {
            blocks.append(body)
        }
        if let strength = strengthSection(memory: memory, sessions: recentSessions) {
            blocks.append(strength)
        }
        if let balance = muscleBalanceSection(sessions: recentSessions, now: now) {
            blocks.append(balance)
        }

        if !memory.dislikes.isEmpty {
            blocks.append("DISLIKES\n" + memory.dislikes.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !memory.constraints.isEmpty {
            blocks.append("CONSTRAINTS\n" + memory.constraints.map { "- \($0)" }.joined(separator: "\n"))
        }

        // Current plan
        if let plan {
            let today = plan.today(now: now)
            var planLines: [String] = []
            planLines.append("range: \(plan.rangeLabel)")
            if let t = today {
                var hero = "today (\(weekday(t.date))): \(t.kind.label) — \(t.title)"
                if t.protected { hero += " [protected]" }
                if let mins = t.durationMinutes { hero += " · \(mins) min" }
                planLines.append(hero)
            }
            for day in plan.days where !Calendar.current.isDate(day.date, inSameDayAs: now) {
                let prefix = day.protected ? "[protected] " : ""
                planLines.append("- \(weekday(day.date)) \(short(day.date)): \(prefix)\(day.kind.label) — \(day.title)")
            }
            blocks.append("CURRENT WEEK PLAN\n" + planLines.joined(separator: "\n"))
        } else {
            blocks.append("CURRENT WEEK PLAN\n(no plan generated yet — user hasn't completed onboarding or hasn't generated one)")
        }

        // Recent sessions (last 5)
        let sessions = recentSessions.suffix(5).reversed()
        if !sessions.isEmpty {
            var lines: [String] = []
            for s in sessions {
                let done = s.exercises.flatMap(\.sets).filter(\.done).count
                let feel = s.feel.map { " · felt: \($0.lowercased())" } ?? ""
                lines.append("- \(short(s.startTime)) · \(s.name) · \(done) sets · \(s.duration / 60) min\(feel)")
            }
            blocks.append("RECENT SESSIONS\n" + lines.joined(separator: "\n"))
        }

        if let familiarity = familiaritySection(sessions: recentSessions, now: now) {
            blocks.append(familiarity)
        }

        // Recent feedback (last 5)
        let feedback = recentFeedback.suffix(5).reversed()
        if !feedback.isEmpty {
            var lines: [String] = []
            for f in feedback {
                var parts: [String] = ["\(short(f.date))"]
                if let d = f.difficulty { parts.append("felt \(d.replacingOccurrences(of: "_", with: " "))") }
                if f.ranLong { parts.append("ran long") }
                if !f.hurtAreas.isEmpty { parts.append("hurt: \(f.hurtAreas.joined(separator: ", "))") }
                if let n = f.notes, !n.isEmpty { parts.append("note: \(n)") }
                lines.append("- " + parts.joined(separator: " · "))
            }
            blocks.append("RECENT POST-WORKOUT FEEDBACK\n" + lines.joined(separator: "\n"))
        }

        // Today's pre-workout check-in (if any)
        if let today = recentSoreness.last,
           Calendar.current.isDate(today.date, inSameDayAs: now) {
            var parts: [String] = []
            if let e = today.energy { parts.append("energy: \(e)") }
            if let s = today.soreness { parts.append("soreness: \(s)") }
            if today.pain { parts.append("pain: yes") }
            if !today.areas.isEmpty { parts.append("areas: \(today.areas.joined(separator: ", "))") }
            if let t = today.timeBudget { parts.append("time: \(t) min") }
            if today.equipmentChanged { parts.append("equipment changed: yes") }
            if !parts.isEmpty {
                blocks.append("TODAY'S PRE-WORKOUT CHECK-IN\n- " + parts.joined(separator: ", "))
            }
        }

        return blocks.joined(separator: "\n\n")
    }

    // MARK: - Section builders (build 62: richer profile signal for the coach)

    /// Height / weight / gender block. Returns nil when none are set — keeps
    /// the snapshot tight for users who skipped the optional fields.
    static func bodySection(memory: TrainingMemory) -> String? {
        var lines: [String] = []
        if let cm = memory.heightCm {
            lines.append("- height: \(BodyMetrics.formatHeight(cm: cm, imperial: memory.usesImperial))")
        }
        if let kg = memory.weightKg {
            lines.append("- weight: \(BodyMetrics.formatWeight(kg: kg, imperial: memory.usesImperial))")
        }
        if let g = memory.gender {
            lines.append("- gender: \(g.label.lowercased())")
        }
        if lines.isEmpty { return nil }
        return "BODY\n" + lines.joined(separator: "\n")
    }

    /// Strength-ratio snapshot for canonical lifts (Bench/Squat/Deadlift/OHP/
    /// Pull-Up). Emits one line per lift with the user's est. 1RM × bodyweight
    /// ratio and a tier label when gender is set. Hidden when bodyweight is
    /// missing — the ratio is undefined without it.
    static func strengthSection(memory: TrainingMemory, sessions: [SavedSession]) -> String? {
        guard memory.weightKg != nil else { return nil }
        let rows = StrengthStandards.rows(
            from: sessions,
            bodyweightKg: memory.weightKg,
            gender: memory.gender
        )
        guard !rows.isEmpty else { return nil }
        let unitLabel = memory.usesImperial ? "lb" : "kg"
        let lines = rows.map { row -> String in
            let oneRm: Int
            if memory.usesImperial {
                oneRm = Int(row.oneRepMaxLb.rounded())
            } else {
                oneRm = Int(BodyMetrics.lbToKg(row.oneRepMaxLb).rounded())
            }
            let ratio = String(format: "%.2f", row.ratio)
            let tier = row.tier.map { " · \($0.label.lowercased())" } ?? ""
            return "- \(row.lift.label): est 1RM \(oneRm) \(unitLabel) · \(ratio)× BW\(tier)"
        }
        var section = "STRENGTH (est 1RM × bodyweight)\n" + lines.joined(separator: "\n")
        if memory.gender == nil {
            section += "\n(gender not set — no tier labels)"
        }
        return section
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
            return "- \(row.name): \(row.sets) sets across \(row.sessions) \(plural)"
        }
        return "EXERCISE FAMILIARITY — last \(days)d\n" + lines.joined(separator: "\n")
    }

    // MARK: - Date helpers

    private static func longDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d, yyyy"
        return f.string(from: d)
    }

    private static func weekday(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: d)
    }

    private static func short(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

extension AppTab {
    var label: String {
        switch self {
        case .today:    return "Today"
        case .week:     return "Week"
        case .library:  return "Library"
        case .progress: return "Progress"
        case .profile:  return "Profile"
        }
    }
}
