// CoachContext+LoadBlocks.swift
//
// Extracted from CoachContext.swift (Tier-3 god-object split). Recovery / last-session / week-adherence load blocks.
// `snapshot(...)` in CoachContext.swift composes these section builders.

import Foundation

extension CoachContext {
    /// Soreness / energy rollup over the last 7 days. Surfaces recurring
    /// hurt areas (a knee mentioned 3 days running is a different signal
    /// than one off mention) and aggregate energy/pain reports.
    static func recoveryTrendSection(soreness: [SorenessEntry], now: Date = Date()) -> String? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let recent = soreness.filter { $0.date >= cutoff }
        guard recent.count >= 2 else { return nil }   // single entry already shown as "today's check-in"

        // energy + soreness are bucket strings ("low"/"normal"/"high",
        // "none"/"mild"/"high"). Roll them up as bucket histograms.
        var areaCounts: [String: Int] = [:]
        var energyBuckets: [String: Int] = [:]
        var sorenessBuckets: [String: Int] = [:]
        var painDays = 0
        for entry in recent {
            if entry.pain { painDays += 1 }
            for area in entry.areas where MuscleBucket.sorenessPrimarySlugs.contains(area) {
                areaCounts[area, default: 0] += 1
            }
            if let e = entry.energy { energyBuckets[e, default: 0] += 1 }
            if let s = entry.soreness { sorenessBuckets[s, default: 0] += 1 }
        }
        var lines: [String] = []
        lines.append("- days reporting: \(recent.count) of 7")
        if !energyBuckets.isEmpty {
            lines.append("- energy: " + histogramSummary(energyBuckets))
        }
        if !sorenessBuckets.isEmpty {
            lines.append("- soreness: " + histogramSummary(sorenessBuckets))
        }
        if painDays > 0 {
            lines.append("- pain days: \(painDays)")
        }
        // Areas mentioned 2+ times look like recurrence — flag them.
        let recurring = areaCounts.filter { $0.value >= 2 }.sorted { $0.value > $1.value }
        if !recurring.isEmpty {
            let rendered = recurring.map { "\($0.key) (\($0.value)x)" }.joined(separator: ", ")
            lines.append("- recurring hurt areas: \(rendered)")
        }
        return "RECOVERY TREND — last 7d\n" + lines.joined(separator: "\n")
    }

    /// "{normal: 4, high: 2, low: 1}" → "normal (4), high (2), low (1)".
    /// Most-common bucket first so the coach reads the modal answer up top.
    private static func histogramSummary(_ counts: [String: Int]) -> String {
        counts.sorted { $0.value > $1.value }
            .map { "\($0.key) (\($0.value))" }
            .joined(separator: ", ")
    }

    /// Per-set detail of the last 2 completed sessions. The high-level
    /// RECENT SESSIONS block tells the coach what happened ("Push Day,
    /// 16 sets, 42 min"); this block tells the coach the *numbers*
    /// (weight × reps per set, top RPE) so it can decide whether to push
    /// or hold each lift today.
    ///
    /// Working sets only — warmups + un-done sets are filtered out.
    /// Sessions older than 14 days are skipped (signal stales fast).
    /// Compact format: weights collapse when constant ("185 × 5,5,5,4,3"),
    /// expand when varied ("185×5, 190×3, 195×1").
    static func lastSessionDetailSection(sessions: [SavedSession],
                                         now: Date = Date(),
                                         maxSessions: Int = 2) -> String? {
        guard !sessions.isEmpty else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? .distantPast
        let recent = sessions
            .filter { $0.startTime >= cutoff }
            .sorted { $0.startTime > $1.startTime }
            .prefix(maxSessions)
        guard !recent.isEmpty else { return nil }

        var sessionBlocks: [String] = []
        for session in recent {
            var lines: [String] = []
            for ex in session.exercises {
                let workingSets = ex.sets.filter { $0.done && !$0.isWarmup }
                guard !workingSets.isEmpty else { continue }
                // T2-9: exercise names are user-authorable (ad-hoc adds,
                // custom routines) and reached the prompt raw.
                lines.append("  • \(CoachContext.sanitizeFreeText(ex.name, max: 80)): \(renderWorkingSets(workingSets, unit: ex.displayUnit))")
            }
            guard !lines.isEmpty else { continue }
            let header = "\(short(session.startTime)) · \(CoachContext.sanitizeFreeText(session.name, max: 80))"
            sessionBlocks.append(([header] + lines).joined(separator: "\n"))
        }
        guard !sessionBlocks.isEmpty else { return nil }
        return "LAST SESSION DETAIL (working sets only)\n" + sessionBlocks.joined(separator: "\n\n")
    }

    /// Render a list of working sets compactly. Collapses the weight when
    /// every set used the same value ("185 × 5,5,5,4,3"); otherwise lists
    /// each set explicitly ("185×5, 190×3, 195×1"). Appends top RPE when
    /// the user logged one for any set.
    private static func renderWorkingSets(_ sets: [LoggedSet], unit: String) -> String {
        let weights = Set(sets.map { $0.weight.trimmingCharacters(in: .whitespaces) })
        let unitSuffix = unit.isEmpty ? "" : " \(unit)"
        let body: String
        if weights.count == 1, let w = weights.first, !w.isEmpty {
            let reps = sets.map(\.reps).joined(separator: ",")
            body = "\(w)\(unitSuffix) × \(reps)"
        } else {
            body = sets.map { s in
                let w = s.weight.trimmingCharacters(in: .whitespaces)
                return w.isEmpty ? "BW×\(s.reps)" : "\(w)\(unitSuffix)×\(s.reps)"
            }.joined(separator: ", ")
        }
        let rpes = sets.compactMap { Double($0.rpe.trimmingCharacters(in: .whitespaces)) }
        if let topRpe = rpes.max() {
            let rpeStr = topRpe.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(topRpe))
                : String(format: "%.1f", topRpe)
            return "\(body) (top RPE \(rpeStr))"
        }
        return body
    }

    /// Planned vs completed for the last 7 days. Lets the coach see at a
    /// glance "user skipped Tuesday's pull day" and reshape the week's
    /// volume accordingly. Days listed in chronological order, oldest
    /// first, ending at today. Today shows as `(today)` regardless of
    /// completion status — the coach shouldn't penalize a planned day
    /// that hasn't happened yet.
    static func weekAdherenceSection(plan: WeekPlan,
                                     sessions: [SavedSession],
                                     now: Date = Date()) -> String? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        // Last 7 days inclusive of today: days -6..0 relative to today.
        let dates: [Date] = (0..<7).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today)
        }
        var lines: [String] = []
        var plannedSessions = 0
        var completedSessions = 0
        for date in dates {
            let label = weekday(date)
            let isToday = cal.isDate(date, inSameDayAs: today)
            let planned = plan.days.first { cal.isDate($0.date, inSameDayAs: date) }
            let session = sessions
                .filter { cal.isDate($0.startTime, inSameDayAs: date) }
                .max(by: { $0.startTime < $1.startTime })

            let status: String
            switch planned?.kind {
            case .lift:
                if isToday {
                    status = session != nil ? "✓ completed" : "planned (today)"
                } else if session != nil {
                    let done = session?.exercises.flatMap(\.sets).filter(\.done).count ?? 0
                    status = "✓ completed (\(done) sets)"
                    completedSessions += 1
                } else {
                    status = "✗ skipped"
                }
                if !isToday { plannedSessions += 1 }
            case .sport:
                status = "sport"
            case .rest:
                status = "rest"
            case .event:
                status = "event"
            case .none:
                status = session != nil ? "✓ unplanned session" : "—"
            }
            let title = planned?.title ?? "—"
            lines.append("- \(label) \(short(date)) · \(title) → \(status)")
        }
        let summary = plannedSessions == 0
            ? "no past planned sessions this window"
            : "\(completedSessions)/\(plannedSessions) past planned sessions completed"
        return "WEEK ADHERENCE (last 7 days)\n" + lines.joined(separator: "\n") + "\n→ \(summary)"
    }
}
