// AutoregulationEngine.swift — PR 10B of the weekly-coach roadmap:
// autoregulation of prescribed loads.
//
// The planner used to prescribe weights from a single rule: priorBest →
// e1RM → rep-band target → +2.5% step (ProgressionDecision). That rule
// is per-exercise and per-attempt: it can't see a PATTERN across sessions.
// A user whose last 2 sessions on an exercise hit <80% of the asked
// completion keeps getting stepped up 2.5% into a wall. Symmetrically, a
// user who hit target reps at 100%+ completion two weeks running is
// earning more than +2.5%.
//
// This engine computes a per-exercise adjustment from the completed-set
// history and folds it into the existing progression path as a multiplier.
// Pure logic — no persistence, no store dependency. The caller builds the
// per-exercise history from SavedSession rows.
//
// Spec: PLAN-weekly-coach.md §6.2.
//
//   - <80% mean completion on 2+ most-recent attempts → −5% next week
//   - ≥100% completion with target reps hit on 2+ attempts → +5 lb next week
//   - Anything else → neutral (the existing ProgressionDecision path
//     owns the load; this engine only amplifies or softens it)
//
// IMPORTANT: this NEVER overrides ProgressionDecision.stepDown. A step-down
// means the user missed reps at their best weight — that injury-risk
// signal outranks the optimistic aggregate. Autoregulation can only
// soften a stepUp (−5%) or amplify one (+5 lb); it can never turn a
// stepDown into a hold or a hold into a stepUp.

import Foundation

enum AutoregulationEngine {

    /// One completed attempt at an exercise: how much of the asked work
    /// landed, and whether the target reps were reached.
    struct Attempt: Equatable {
        /// done sets / target sets for this exercise in that session,
        /// 0.0–1.0.
        let completion: Double
        /// Best reps at the heaviest weight in that attempt.
        let reps: Int
        /// What the session asked for (per-set target).
        let targetReps: Int
    }

    /// The adjustment for an exercise's next prescription.
    enum Adjustment: Equatable {
        /// −5% on the computed target load.
        case soften      // multiplier 0.95
        /// No change — the base progression path decides.
        case neutral     // multiplier 1.0
        /// +5 lb flat on top of the computed target.
        case amplify     // handled as a flat add, see applyLoad
    }

    /// Mean completion under which recent attempts read as "falling behind".
    static let softenCompletionBar = 0.80
    /// How many recent attempts the engine looks at.
    static let attemptWindow = 2
    /// Amplify bonus, in lb.
    static let amplifyBonusLb: Double = 5.0

    /// Classify from the most recent `attemptWindow` attempts (ordered
    /// newest-first by the caller).
    static func classify(_ attempts: [Attempt]) -> Adjustment {
        let recent = attempts.prefix(attemptWindow)
        guard recent.count == attemptWindow else { return .neutral }

        // Amplify: every attempt in the window hit target reps at full
        // (≥100%) completion. Two solid weeks = earning the +5.
        let allHitTarget = recent.allSatisfy {
            $0.completion >= 1.0 && $0.reps >= $0.targetReps && $0.targetReps > 0
        }
        if allHitTarget { return .amplify }

        // Soften: MEAN completion across the window under the bar. Mean
        // (not min) so one blown session among two decent ones doesn't
        // trigger — the miss path already has ProgressionDecision.stepDown.
        let mean = recent.map(\.completion).reduce(0, +) / Double(recent.count)
        if mean < softenCompletionBar { return .soften }

        return .neutral
    }
}

extension AutoregulationEngine.Adjustment {
    /// Multiplier on the rep-mapped target load.
    var loadMultiplier: Double {
        switch self {
        case .soften: return 0.95
        case .neutral: return 1.0
        case .amplify: return 1.0
        }
    }

    /// Flat lb added after the multiplier + rounding (amplify only).
    var flatAddLb: Double {
        switch self {
        case .amplify: return AutoregulationEngine.amplifyBonusLb
        default: return 0
        }
    }

    /// True when the adjustment changes anything.
    var isActive: Bool { self != .neutral }
}
