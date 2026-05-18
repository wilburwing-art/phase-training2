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
