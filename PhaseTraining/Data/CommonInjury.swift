// CommonInjury.swift — bridge to the coach.db common_injuries table.
//
// 56 evidence-curated injuries grouped by body_region (knee, shoulder, back,
// hip, ankle, elbow, wrist, neck). Replaces the previous free-text
// constraint -> name-keyword filter, which over-matched ("Knee-to-Chest
// Stretch" got filtered for someone with a knee injury even though it's
// REHAB for that) and under-matched (a deep squat slipped through for a
// patellar tendinopathy user because "squat" doesn't contain "knee").
//
// Now: the user picks specific injuries (or types free-text fallback), the
// planner looks up exercise_injury_relevance.role='contraindicated' joins
// and excludes those exercise ids precisely. Prehab / rehab_late exercises
// aren't blocked — they're often the *right* thing for the injury.

import Foundation

struct CommonInjury: Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let bodyRegion: String?
    let description: String?

    /// Title-cased body region for display ("knee" → "Knee").
    var bodyRegionLabel: String {
        (bodyRegion ?? "Other").capitalized
    }
}

/// One prehab or rehab exercise for an injury, from
/// `exercise_injury_relevance`. Read-only display data for the injury card;
/// the generator does not pick from it yet.
struct InjurySupportExercise: Hashable {
    enum Role: String, CaseIterable {
        case prehab
        case rehabEarly = "rehab_early"
        case rehabLate = "rehab_late"

        var label: String {
            switch self {
            case .prehab: return "Prehab"
            case .rehabEarly: return "Early rehab"
            case .rehabLate: return "Late rehab"
            }
        }

        var order: Int {
            switch self {
            case .prehab: return 0
            case .rehabEarly: return 1
            case .rehabLate: return 2
            }
        }
    }

    let exerciseId: Int
    let name: String
    let role: Role
}

/// One sport's typical recovery from coach.db `sport_recovery_profiles`.
/// `ideal_supplement_timing` is left out on purpose (backlog 11c 6.7).
struct SportRecoveryProfile: Hashable {
    let sportSlug: String
    let typicalRecoveryHours: Int?
    /// Raw tokens, e.g. "heavy_squat".
    let avoidBeforeSession: [String]

    /// "heavy_squat" -> "Heavy squat"; the word "cns" renders "CNS".
    static func label(forToken token: String) -> String {
        let words = token.split(separator: "_").map { $0 == "cns" ? "CNS" : String($0) }
        guard let first = words.first else { return token }
        let head = first == "CNS" ? first : first.prefix(1).uppercased() + first.dropFirst()
        return ([head] + words.dropFirst()).joined(separator: " ")
    }

    var avoidLabels: [String] { avoidBeforeSession.map(Self.label(forToken:)) }
}

/// How often an injury shows up in one sport, from `injury_sport_prevalence`.
struct InjuryPrevalence: Hashable {
    enum Level: String, CaseIterable {
        case common, occasional, rare

        var label: String {
            switch self {
            case .common: return "Common"
            case .occasional: return "Occasional"
            case .rare: return "Rare"
            }
        }

        var order: Int {
            switch self {
            case .common: return 0
            case .occasional: return 1
            case .rare: return 2
            }
        }
    }

    let sportSlug: String
    let level: Level
}
