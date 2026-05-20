// GeneratorStrategy.swift — the LLM's lever on the deterministic generator.
//
// PR 2 of the option-D arc. PR 1 fed runtime history into the generator
// (GeneratorContext). This is the other half: the LLM coach picks the
// parameters a smart coach would pick — focus, duration, pattern emphasis,
// intensity, target weight overrides — and the generator executes
// deterministically using those parameters.
//
// Strategy is always optional. `.auto` (the default) is identity — the
// generator behaves exactly as before. The LLM populates a strategy only
// when the user explicitly asks the coach to build a workout.
//
// The LLM never writes a workout token-by-token. It can only pick the
// parameters this struct exposes. Generator validation prevents hallucinated
// exercises (LLM can only emphasize/deprioritize patterns from a fixed
// list; weights are bounded; intensityBias is an enum). That makes the
// failure mode degradation-graceful: if the LLM goes haywire, the generator
// just runs with default parameters and the app still produces a workout.

import Foundation

struct GeneratorStrategy: Codable, Equatable, Hashable {

    /// When non-nil, override the focus the planner would normally derive
    /// from (liftIndex, totalLifts). Used when the user asks for a specific
    /// day shape ("push day", "mobility flow", "full-body").
    var focus: WorkoutFocus?

    /// When non-nil, override `memory.sessionMinutes` for this workout only.
    /// Clamped to [15, 180] downstream.
    var durationMinutes: Int?

    /// movement_patterns.slug values to prioritize when picking exercises.
    /// Boosts the alternative-ordering inside each slot — a pattern in this
    /// list comes BEFORE others, regardless of frequency-based reordering.
    var emphasizePatterns: [String]

    /// movement_patterns.slug values to SKIP when picking. Slots whose
    /// alternatives are entirely deprioritized fall through with no pick.
    /// Used for "no squats today, knee is sore" style requests.
    var deprioritizePatterns: [String]

    /// Per-exercise target-weight overrides keyed by lower-cased name.
    /// Replaces the priorBest-derived note when present. Used for explicit
    /// deload / push prescriptions ("bench at 90% today").
    var targetWeightOverrides: [String: Double]

    /// Sets multiplier — `.deload` (×0.7), `.normal` (×1.0), `.push` (×1.15).
    /// Applied to the prescription's sets count after the existing experience
    /// and age clamps. Caps at the formula default to avoid runaway volume.
    var intensityBias: IntensityBias

    enum IntensityBias: String, Codable, Equatable {
        case deload, normal, push

        var setsMultiplier: Double {
            switch self {
            case .deload: return 0.7
            case .normal: return 1.0
            case .push:   return 1.15
            }
        }
    }

    static let auto = GeneratorStrategy(
        focus: nil,
        durationMinutes: nil,
        emphasizePatterns: [],
        deprioritizePatterns: [],
        targetWeightOverrides: [:],
        intensityBias: .normal
    )

    var isAuto: Bool {
        focus == nil && durationMinutes == nil &&
        emphasizePatterns.isEmpty && deprioritizePatterns.isEmpty &&
        targetWeightOverrides.isEmpty && intensityBias == .normal
    }
}
