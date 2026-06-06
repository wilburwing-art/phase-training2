// CoachContext+ProfileBlocks.swift
//
// Extracted from CoachContext.swift (Tier-3 god-object split). Season / body / strength profile blocks.
// `snapshot(...)` in CoachContext.swift composes these section builders.

import Foundation

extension CoachContext {
    static func seasonSummary(memory: TrainingMemory) -> String {
        // No sports — single default season is the whole signal.
        if memory.sports.isEmpty {
            return memory.defaultSeason.label.lowercased()
        }
        let phases = memory.sports.map { sport -> (Sport, SeasonPhase) in
            (sport, memory.seasonsBySport[sport] ?? memory.defaultSeason)
        }
        // All sports in the same phase → render once.
        let distinct = Set(phases.map(\.1))
        if distinct.count == 1, let only = distinct.first {
            return only.label.lowercased()
        }
        // Mixed — show each sport's phase explicitly + default fallback.
        let pieces = phases.map { "\($0.0.name.lowercased()) \($0.1.label.lowercased())" }
        return pieces.joined(separator: ", ") + " (otherwise: \(memory.defaultSeason.label.lowercased()))"
    }

    /// Height / weight / gender / age block. Returns nil when none are set
    /// — keeps the snapshot tight for users who skipped the optional fields.
    /// Age was missing from the coach's view until build 65 even though the
    /// generator already used it — without age the coach would program the
    /// same workout for a 28- and 58-year-old.
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
        if let age = memory.age {
            lines.append("- age: \(age)")
        }
        if lines.isEmpty { return nil }
        return "BODY\n" + lines.joined(separator: "\n")
    }

    /// Strength-ratio snapshot for canonical lifts (Bench/Squat/Deadlift/OHP/
    /// Pull-Up). Emits one line per lift with the user's est. 1RM × bodyweight
    /// ratio and a tier label when gender is set. Hidden when bodyweight is
    /// missing — the ratio is undefined without it.
    ///
    /// Build 65 adds VELOCITY — each row compares the user's best est-1RM in
    /// the LAST 4 weeks against the best from the 4 weeks before that. The
    /// coach now sees "+12 lb / 4w" (progressing) vs "≈" (plateaued) vs
    /// "-8 lb / 4w" (regressed). Drives the obvious "deload / change rep
    /// scheme" decisions without the LLM having to date-math over sessions.
    static func strengthSection(memory: TrainingMemory, sessions: [SavedSession], now: Date = Date()) -> String? {
        guard memory.weightKg != nil else { return nil }
        let rows = StrengthStandards.rows(
            from: sessions,
            bodyweightKg: memory.weightKg,
            gender: memory.gender
        )
        guard !rows.isEmpty else { return nil }
        let unitLabel = memory.usesImperial ? "lb" : "kg"
        // Split sessions into "current 4w" vs "prior 4w" for velocity.
        let cal = Calendar.current
        let recentCutoff = cal.date(byAdding: .weekOfYear, value: -4, to: now) ?? now
        let priorCutoff = cal.date(byAdding: .weekOfYear, value: -8, to: now) ?? now
        let recentWindow = sessions.filter { $0.startTime >= recentCutoff }
        let priorWindow = sessions.filter { $0.startTime >= priorCutoff && $0.startTime < recentCutoff }

        let recentBest = StrengthStandards.rows(from: recentWindow,
                                                bodyweightKg: memory.weightKg,
                                                gender: memory.gender)
        let priorBest = StrengthStandards.rows(from: priorWindow,
                                               bodyweightKg: memory.weightKg,
                                               gender: memory.gender)
        let recentBestById = Dictionary(uniqueKeysWithValues: recentBest.map { ($0.id, $0.oneRepMaxLb) })
        let priorBestById = Dictionary(uniqueKeysWithValues: priorBest.map { ($0.id, $0.oneRepMaxLb) })

        let lines = rows.map { row -> String in
            let oneRm: Int
            if memory.usesImperial {
                oneRm = Int(row.oneRepMaxLb.rounded())
            } else {
                oneRm = Int(BodyMetrics.lbToKg(row.oneRepMaxLb).rounded())
            }
            let ratio = String(format: "%.2f", row.ratio)
            let tier = row.tier.map { " · \($0.label.lowercased())" } ?? ""
            // Velocity: only when we have BOTH windows of data for this lift.
            var velocity = ""
            if let recent = recentBestById[row.id], let prior = priorBestById[row.id] {
                let deltaLb = recent - prior
                let deltaDisplay = memory.usesImperial
                    ? Int(deltaLb.rounded())
                    : Int(BodyMetrics.lbToKg(deltaLb).rounded())
                // ≈ when the change is below the smallest plate increment
                // (5 lb). Below the noise floor it's noise, not signal.
                if abs(deltaLb) < 5 {
                    velocity = " · ≈ /4w"
                } else if deltaLb > 0 {
                    velocity = " · +\(deltaDisplay) /4w"
                } else {
                    velocity = " · \(deltaDisplay) /4w"  // negative number formats with the minus
                }
            }
            return "- \(row.lift.label): est 1RM \(oneRm) \(unitLabel) · \(ratio)× BW\(tier)\(velocity)"
        }
        var section = "STRENGTH (est 1RM × bodyweight)\n" + lines.joined(separator: "\n")
        if memory.gender == nil {
            section += "\n(gender not set — no tier labels)"
        }
        return section
    }
}
