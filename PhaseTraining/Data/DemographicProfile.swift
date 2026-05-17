// DemographicProfile.swift — evidence-based defaults derived from
// TrainingMemory. Bridges what onboarding *gathers* with what the planner
// *uses* so age, experience, equipment, and constraints actually shape the
// week.
//
// Rules (sources: ACSM resistance-training guidelines, NSCA progression
// model, Mazzetti et al. on supervised training, Phillips on protein/
// recovery, Borst on aging muscle):
//
//   Lift days / week
//     beginner     → 2-3       (per ACSM; 2 is sufficient for novice gains)
//     intermediate → 3-4
//     advanced     → 4-5
//     age >= 55    → upper bound -1 (recovery-limited, not stimulus-limited)
//
//   Session minutes
//     beginner     → 30-45     (avoid early burnout; technique-limited)
//     intermediate → 45-60
//     advanced     → 60-90
//     age >= 55    → cap upper at 60
//
//   Recovery days between consecutive lifts (planner spacing nudge)
//     beginner            → 1   (skill-acquisition needs nervous-system recovery)
//     intermediate / adv  → 0
//     age >= 55           → bump to at least 1
//
//   Difficulty bias (ordered preference; planner tries first bucket first)
//     beginner     → [beginner]
//     intermediate → [intermediate, beginner]
//     advanced     → [advanced, intermediate, beginner]
//     age >= 60 + advanced → demote to [intermediate, advanced, beginner]
//     (older lifters can still go heavy but elite-tagged volume tends to
//     hide accessory burnout; intermediate routines are a safer default
//     they can manually swap out)
//
//   Equipment → coach.db environment whitelist
//     fullGym      → all
//     dumbbells    → home, anywhere, travel
//     bodyweight   → home, anywhere, outdoor, travel
//     custom       → all (user is responsible for picking the right routine)
//
//   Constraints
//     Each entry is tokenized (drop articles + side modifiers), tokens
//     length >= 3 added as exclude-by-name-substring. So "left knee" →
//     {knee}; "lower back tweak" → {lower, back, tweak}. False-positive
//     prone but cheap, and routines hiding behind names like
//     "Lower body strength" will be filtered for someone who said "lower
//     back tweak" — which is arguably the right call.
//
// Gender is *not* used here. Individual variation dominates gender-average
// effects on exercise selection in the literature, and prescriptive gender
// programming risks reinforcing stereotype rather than performance. Gender
// is retained in TrainingMemory for future per-user calorie / recovery /
// 1RM-prediction models, where the evidence is stronger.

import Foundation

struct DemographicProfile: Equatable {
    /// Sane lift-days range for this demographic. The user's
    /// `liftDaysPerWeek` is still authoritative — this is a recommendation
    /// surface for the Profile screen.
    let recommendedLiftDays: ClosedRange<Int>

    /// Same idea for session length. Compared against `memory.sessionMinutes`
    /// in the Profile screen.
    let recommendedSessionMinutes: ClosedRange<Int>

    /// Minimum rest days the planner should try to leave between lifts. The
    /// adjustForLiftBudget pass uses this as a soft preference when promoting
    /// rest slots → lift slots.
    let minRecoveryDaysBetweenLifts: Int

    /// Difficulty preference, ordered. Planner walks this in order: try
    /// routines whose difficulty == first bucket; if none, try second; etc.
    let preferredDifficulties: [String]

    /// coach.db `routines.environment` values acceptable to this user's
    /// equipment. Empty = no filter.
    let allowedEnvironments: Set<String>

    /// Substring matches (case-insensitive) used to exclude routines whose
    /// name brushes against any user-declared constraint.
    let excludedNameKeywords: [String]

    /// Human-readable bullets explaining *why* the planner is structured
    /// the way it is. Surfaced in Profile.
    let rationale: [String]
}

extension DemographicProfile {

    static func from(_ m: TrainingMemory) -> DemographicProfile {

        // --- Lift days ---
        let baseLifts: (Int, Int)
        switch m.experience {
        case .beginner:     baseLifts = (2, 3)
        case .intermediate: baseLifts = (3, 4)
        case .advanced:     baseLifts = (4, 5)
        }
        let ageDelta = (m.age ?? 0) >= 55 ? -1 : 0
        let liftLow  = max(1, baseLifts.0 + min(0, ageDelta))
        let liftHigh = max(liftLow, baseLifts.1 + ageDelta)
        let liftRange = liftLow...liftHigh

        // --- Session minutes ---
        let baseSess: (Int, Int)
        switch m.experience {
        case .beginner:     baseSess = (30, 45)
        case .intermediate: baseSess = (45, 60)
        case .advanced:     baseSess = (60, 90)
        }
        let sessHigh = (m.age ?? 0) >= 55 ? min(60, baseSess.1) : baseSess.1
        let sessLow  = min(baseSess.0, sessHigh)
        let sessRange = sessLow...sessHigh

        // --- Recovery between lifts ---
        var recovery = 0
        if m.experience == .beginner { recovery = 1 }
        if (m.age ?? 0) >= 55 { recovery = max(recovery, 1) }

        // --- Difficulty bias ---
        let difficulties: [String]
        switch m.experience {
        case .beginner:
            difficulties = ["beginner"]
        case .intermediate:
            difficulties = ["intermediate", "beginner"]
        case .advanced:
            if (m.age ?? 0) >= 60 {
                difficulties = ["intermediate", "advanced", "beginner"]
            } else {
                difficulties = ["advanced", "intermediate", "beginner"]
            }
        }

        // --- Equipment → environment whitelist ---
        let envs: Set<String> = {
            if m.equipment.contains(.fullGym) { return [] }
            if m.equipment.contains(.dumbbells) {
                return ["home", "anywhere", "travel"]
            }
            if m.equipment.contains(.bodyweight) {
                return ["home", "anywhere", "outdoor", "travel"]
            }
            return []
        }()

        // --- Constraints → keyword excludes ---
        let stopWords: Set<String> = ["left", "right", "both", "the", "my",
                                      "a", "an", "and", "or", "with"]
        let excludes = m.constraints.flatMap { s -> [String] in
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && $0.count >= 3 && !stopWords.contains($0) }
        }

        // --- Rationale ---
        var why: [String] = []
        why.append("\(m.experience.label) lifters do best with \(liftLow)-\(liftHigh) lift days at \(sessLow)-\(sessHigh) min per session.")
        if let age = m.age, age >= 55 {
            why.append("Age \(age) — capping volume and adding recovery between hard days.")
        }
        if !envs.isEmpty {
            why.append("Equipment-aware routine pool: only \(envs.sorted().joined(separator: ", ")) routines.")
        }
        if !excludes.isEmpty {
            why.append("Avoiding routines that mention: \(excludes.sorted().joined(separator: ", ")).")
        }
        if let sport = m.primarySport {
            why.append("Sport-aware shape from \(sport.name) × \(m.seasonForPlanner.label).")
        }
        if m.gender != nil {
            why.append("Gender is recorded for future recovery / intensity models but isn't used to shape exercise selection.")
        }

        return DemographicProfile(
            recommendedLiftDays: liftRange,
            recommendedSessionMinutes: sessRange,
            minRecoveryDaysBetweenLifts: recovery,
            preferredDifficulties: difficulties,
            allowedEnvironments: envs,
            excludedNameKeywords: excludes,
            rationale: why
        )
    }
}
