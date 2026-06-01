// StrengthStandards.swift — pure logic backing the Progress strength-ratio
// card. Given a list of saved sessions, surfaces a row per canonical lift
// (Bench, Squat, Deadlift, Overhead Press, Pull-Up) with:
//   - the user's best estimated 1RM (Epley formula)
//   - that 1RM as a multiple of bodyweight
//   - a tier label when gender is known
//
// All math is value-typed and gender thresholds live in a static table so
// the rest of the app can render a row without touching the formula.
//
// Tier thresholds are commonly-cited multiples of bodyweight at a 1RM,
// rounded for legibility. Sources vary slightly — these are intentionally
// conservative middle-of-the-road numbers, not a clinical claim. They're a
// directional signal, not a diagnosis.

import Foundation

enum StrengthStandards {

    // MARK: - Canonical lifts

    /// The lifts we surface tier labels for. The "matches" function does a
    /// permissive name match so generated workouts (which sometimes title
    /// variations like "Back Squat" or "Pause Bench Press") still find a home.
    enum CanonicalLift: String, CaseIterable, Hashable {
        case bench, squat, deadlift, ohp, pullup

        var label: String {
            switch self {
            case .bench:    return "Bench Press"
            case .squat:    return "Back Squat"
            case .deadlift: return "Deadlift"
            case .ohp:      return "Overhead Press"
            case .pullup:   return "Pull-Up"
            }
        }

        /// Lower-cased name fragments that count as this lift. Order doesn't
        /// matter; first match wins via `matches(name:)`.
        var nameFragments: [String] {
            switch self {
            case .bench:
                // Avoid matching "Incline Bench Row" by also requiring "bench"
                // AND "press" OR a bare "bench press" pattern. Negative match:
                // any name containing "row" disqualifies (incline bench row).
                return ["bench press"]
            case .squat:
                return ["back squat", "barbell squat", " squat"]
            case .deadlift:
                return ["deadlift"]
            case .ohp:
                return ["overhead press", "ohp", "military press", "strict press"]
            case .pullup:
                return ["pull-up", "pull up", "pullup", "chin-up", "chinup", "chin up", "weighted pull"]
            }
        }

        /// Disqualifying fragments — block lifts that share keywords with
        /// the canonical name but aren't the canonical movement (e.g. "bench
        /// row" shouldn't count as a bench press).
        var disqualifiers: [String] {
            switch self {
            case .bench:    return ["row"]
            case .squat:    return ["jump", "split", "goblet", "bulgarian", "pistol"]
            case .deadlift: return ["romanian", "stiff", "single-leg", "single leg"]
            case .ohp:      return ["seated", "dumbbell", "kettlebell"]
            case .pullup:   return []
            }
        }

        /// True when `name` looks like this canonical lift. Case-insensitive,
        /// fragment-based — see nameFragments / disqualifiers.
        func matches(name: String) -> Bool {
            let lower = name.lowercased()
            if disqualifiers.contains(where: lower.contains) { return false }
            return nameFragments.contains(where: lower.contains)
        }

        /// True if pull-ups should add bodyweight to the lifted weight.
        var addsBodyweight: Bool { self == .pullup }
    }

    // MARK: - Epley 1RM

    /// Epley formula. Returns 1RM-equivalent weight in the same unit as
    /// input. At 1 rep this is a no-op. Above ~10 reps the formula loses
    /// accuracy quickly — for our use (tier comparison) that's acceptable.
    static func epley1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0, weight > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30.0)
    }

    // MARK: - Tier thresholds

    /// Tier of a lift expressed as how the user's 1RM-to-bodyweight ratio
    /// compares to commonly-cited consensus levels. Order is the strength
    /// axis: novice → elite.
    enum Tier: String, CaseIterable, Hashable {
        case novice, beginner, intermediate, advanced, elite

        var label: String {
            switch self {
            case .novice:       return "NOVICE"
            case .beginner:     return "BEGINNER"
            case .intermediate: return "INTERMEDIATE"
            case .advanced:     return "ADVANCED"
            case .elite:        return "ELITE"
            }
        }
    }

    /// Map (lift, gender) → ascending tier thresholds. Each array is FIVE
    /// values: minimum ratio for [novice, beginner, intermediate, advanced,
    /// elite]. Values < first threshold map to nil (no tier).
    ///
    /// Sources: commonly-cited middle of strengthlevel.com / Symmetric
    /// Strength tables, rounded for readability. Conservative side.
    private static let maleThresholds: [CanonicalLift: [Double]] = [
        .bench:    [0.50, 0.75, 1.25, 1.75, 2.25],
        .squat:    [0.75, 1.25, 1.75, 2.50, 3.00],
        .deadlift: [1.00, 1.50, 2.25, 2.75, 3.25],
        .ohp:      [0.35, 0.55, 0.90, 1.20, 1.50],
        .pullup:   [0.80, 1.00, 1.25, 1.50, 1.75],
    ]

    private static let femaleThresholds: [CanonicalLift: [Double]] = [
        .bench:    [0.25, 0.50, 0.75, 1.00, 1.50],
        .squat:    [0.50, 0.75, 1.25, 1.75, 2.25],
        .deadlift: [0.75, 1.00, 1.50, 2.00, 2.50],
        .ohp:      [0.20, 0.35, 0.55, 0.75, 1.00],
        .pullup:   [0.60, 0.80, 1.00, 1.25, 1.50],
    ]

    /// Resolve the tier for a given (lift, ratio, gender). Returns nil when:
    /// - gender is nil (we don't pick a curve without consent)
    /// - the ratio is below the novice threshold for the curve
    static func tier(for lift: CanonicalLift, ratio: Double, gender: Gender?) -> Tier? {
        guard let gender else { return nil }
        let curve: [CanonicalLift: [Double]]
        switch gender {
        case .male:                  curve = maleThresholds
        case .female, .nonbinary,
             .preferNotToSay:        curve = femaleThresholds
        }
        guard let thresholds = curve[lift], thresholds.count == Tier.allCases.count else {
            return nil
        }
        var resolved: Tier? = nil
        for (idx, threshold) in thresholds.enumerated() {
            if ratio >= threshold {
                resolved = Tier.allCases[idx]
            } else {
                break
            }
        }
        return resolved
    }

    // MARK: - Row computation

    /// One row's worth of strength-ratio data, ready for the Progress card.
    struct LiftRow: Identifiable, Equatable {
        var id: String { lift.rawValue }
        let lift: CanonicalLift
        /// Estimated 1RM in lb. Always lb for display simplicity — the card
        /// renders in the user's preferred unit at the boundary.
        let oneRepMaxLb: Double
        /// 1RM ÷ bodyweight (matching units).
        let ratio: Double
        /// Best (weight, reps) actually logged — for the "from your 145×5"
        /// subtitle.
        let bestWeightLb: Double
        let bestReps: Int
        let tier: Tier?
    }

    /// Walk completed sets across all saved sessions; for each canonical
    /// lift, find the (weight, reps) pair with the highest estimated 1RM,
    /// then compute the ratio against bodyweight. Returns one row per lift
    /// with data, in the order CanonicalLift.allCases declares.
    ///
    /// `bodyweightKg` and `unitImperial`: bodyweight comes from
    /// TrainingMemory.weightKg; the card calls in metric and the function
    /// internally treats all weights as lb (saved sets store lb strings —
    /// the data layer doesn't distinguish). Bodyweight is converted to lb
    /// here for the ratio math.
    ///
    /// `addPullupBodyweight`: when true (default), pull-up rows treat the
    /// loaded weight as ADDITIONAL to bodyweight — bodyweight pull-ups still
    /// produce a ratio of 1.0, weighted pull-ups produce >1.0.
    static func rows(from sessions: [SavedSession],
                     bodyweightKg: Double?,
                     gender: Gender?,
                     addPullupBodyweight: Bool = true) -> [LiftRow] {
        guard let bodyweightKg, bodyweightKg > 0 else { return [] }
        let bodyweightLb = BodyMetrics.kgToLb(bodyweightKg)

        // For each canonical lift, find the (weight, reps) maximising
        // estimated 1RM across all completed sets.
        var bestPerLift: [CanonicalLift: (weight: Double, reps: Int, oneRm: Double)] = [:]

        for session in sessions {
            for ex in session.exercises {
                guard let lift = CanonicalLift.allCases.first(where: { $0.matches(name: ex.name) }) else {
                    continue
                }
                // Warmup sets excluded — Epley 1RM estimation must only see
                // working sets. A 95-lb warmup at 5 reps would otherwise
                // tank a 225-lb working top set's tier label.
                for set in ex.sets where set.done && !set.isWarmup {
                    let reps = set.repsValue ?? 0
                    let weight = set.weightValue ?? 0
                    guard reps > 0 else { continue }
                    let effectiveWeight = (lift.addsBodyweight && addPullupBodyweight)
                        ? weight + bodyweightLb
                        : weight
                    guard effectiveWeight > 0 else { continue }
                    let oneRm = epley1RM(weight: effectiveWeight, reps: reps)
                    if oneRm > (bestPerLift[lift]?.oneRm ?? 0) {
                        bestPerLift[lift] = (effectiveWeight, reps, oneRm)
                    }
                }
            }
        }

        return CanonicalLift.allCases.compactMap { lift in
            guard let best = bestPerLift[lift] else { return nil }
            let ratio = best.oneRm / bodyweightLb
            return LiftRow(
                lift: lift,
                oneRepMaxLb: best.oneRm,
                ratio: ratio,
                bestWeightLb: best.weight,
                bestReps: best.reps,
                tier: tier(for: lift, ratio: ratio, gender: gender)
            )
        }
    }
}
