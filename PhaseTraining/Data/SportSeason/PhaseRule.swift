// PhaseRule.swift — the "brain": per (sport, variant, season-phase) ruleset
// that governs objective, volume, intensity, demand mix, and progression
// (SPEC §3.2 / §3.4). Kept as a Swift static table (not DB seed) because it is
// small and tuned by hand against felt sense — editing a weight and re-running
// SeasonFidelityTest is the inner loop, with no DB rebuild.
//
// Phase mapping (SPEC 4-phase ↔ app 5-case SeasonPhase):
//   .offSeason   ← offSeasonBuild     .inSeason    ← inSeasonMaintain
//   .preSeason   ← preSeasonSpecific  .maintenance ← transitionRecovery
//   .eventPrep   = pre-season weights + autoregulateHold; the existing
//                  MesocycleProgression (daysUntilPeak-gated) drives the taper.

import Foundation

struct PhaseRule: Equatable {
    let objective: String
    let sessionsPerWeek: ClosedRange<Int>
    /// Sums to ~1.0; drives demand-weighted slot allocation.
    let demandWeights: [Demand: Double]
    let progression: ProgressionMode
    /// Max total fatigue points (Σ SetScheme.fatigueCost) per session.
    let sessionVolumeCap: Int
    /// When true, lighten/skip near sport days (SPEC §1 invariant 2).
    let deferToSport: Bool
    let sessionMinutesTarget: ClosedRange<Int>

    /// Resolve the rule for an athlete. Skiing + climbing are implemented;
    /// other sports fall back to the low-fatigue transition rule.
    static func resolve(sportSlug: String, variant: SportVariant, season: SeasonPhase) -> PhaseRule {
        if skiSlugs.contains(sportSlug) {
            return (skiing[season] ?? skiing[.maintenance]!).applyingVariantOverride(variant)
        }
        if climbingSlugs.contains(sportSlug) {
            return (climbing[season] ?? climbing[.maintenance]!).applyingVariantOverride(variant)
        }
        return skiing[.maintenance]!   // safe low-fatigue default for unsupported sports
    }

    static let skiSlugs: Set<String> = ["alpine-skiing", "ski-mountaineering", "snow-sports"]
    static let climbingSlugs: Set<String> = ["climbing", "bouldering", "sport-climbing",
                                             "trad-climbing", "alpine-climbing", "ice-climbing",
                                             "mixed-climbing"]

    // MARK: - Skiing / inbounds baseline (SPEC §3.2)

    static let skiing: [SeasonPhase: PhaseRule] = [
        .offSeason: PhaseRule(
            objective: "Build max strength + muscle base, fix imbalances",
            sessionsPerWeek: 3...4,
            demandWeights: [
                .maxStrength: 0.35, .eccentricLeg: 0.10, .legEndurance: 0.05,
                .power: 0.10, .kneeStability: 0.15, .core: 0.15,
                .hipLateral: 0.05, .prehab: 0.05,
            ],
            progression: .progressiveOverload,
            sessionVolumeCap: 24,
            deferToSport: false,
            sessionMinutesTarget: 50...75),

        .preSeason: PhaseRule(
            objective: "Convert to eccentric + power + lactate; peak for opening day",
            sessionsPerWeek: 3...3,
            demandWeights: [
                .maxStrength: 0.15, .eccentricLeg: 0.30, .legEndurance: 0.20,
                .power: 0.20, .kneeStability: 0.05, .core: 0.05,
                .hipLateral: 0.05, .prehab: 0.00,
            ],
            progression: .autoregulateHold,
            sessionVolumeCap: 22,
            deferToSport: false,
            sessionMinutesTarget: 45...70),

        .inSeason: PhaseRule(
            objective: "Preserve strength/power, minimal fatigue, protect knees",
            sessionsPerWeek: 2...2,
            demandWeights: [
                .maxStrength: 0.20, .eccentricLeg: 0.20, .legEndurance: 0.10,
                .power: 0.15, .kneeStability: 0.15, .core: 0.10,
                .hipLateral: 0.10, .prehab: 0.00,
            ],
            progression: .maintainMinimal,
            sessionVolumeCap: 10,
            deferToSport: true,
            sessionMinutesTarget: 30...45),

        // transitionRecovery
        .maintenance: PhaseRule(
            objective: "Deload, rehab the season's wear, restore",
            sessionsPerWeek: 2...2,
            demandWeights: [
                .maxStrength: 0.10, .eccentricLeg: 0.05, .legEndurance: 0.05,
                .power: 0.05, .kneeStability: 0.30, .core: 0.15,
                .hipLateral: 0.10, .prehab: 0.20,
            ],
            progression: .deload,
            sessionVolumeCap: 8,
            deferToSport: true,
            sessionMinutesTarget: 30...45),

        // eventPrep = pre-season emphasis, tapered: same demand mix, volume cap
        // dropped hard, progression holds — MesocycleProgression peaks it.
        .eventPrep: PhaseRule(
            objective: "Taper to the objective — keep sharp qualities, shed fatigue",
            sessionsPerWeek: 3...3,
            demandWeights: [
                .maxStrength: 0.15, .eccentricLeg: 0.30, .legEndurance: 0.20,
                .power: 0.20, .kneeStability: 0.05, .core: 0.05,
                .hipLateral: 0.05, .prehab: 0.00,
            ],
            progression: .autoregulateHold,
            sessionVolumeCap: 14,
            deferToSport: true,
            sessionMinutesTarget: 35...55),
    ]

    // MARK: - Climbing / sportRoute baseline (SPEC §4.2)
    //
    // The defining inversion vs skiing: ANTAGONIST scales UP in-season (0.40)
    // and in transition (0.40) — the climber gets plenty of pulling on the wall,
    // so the gym's in-season job is to balance it (push/extensor/shoulder
    // health), not add pulling fatigue. Finger work goes to ZERO in transition
    // (tendon rest). The generator owns structured finger/pull/tension +
    // antagonist/prehab; on-wall limit work is deferred to the sport (SPEC §4.1).

    static let climbing: [SeasonPhase: PhaseRule] = [
        .offSeason: PhaseRule(
            objective: "Pulling + finger base, hypertrophy, structural prep",
            sessionsPerWeek: 2...3,
            demandWeights: [
                .pullStrength: 0.30, .fingerStrength: 0.20, .bodyTension: 0.15,
                .contactStrength: 0.00, .antagonist: 0.20, .core: 0.10, .prehab: 0.05,
            ],
            progression: .progressiveOverload,
            sessionVolumeCap: 18,
            deferToSport: false,
            sessionMinutesTarget: 45...75),

        .preSeason: PhaseRule(
            objective: "Max finger strength + power + lock-off + tension",
            sessionsPerWeek: 2...2,
            demandWeights: [
                .pullStrength: 0.20, .fingerStrength: 0.30, .bodyTension: 0.20,
                .contactStrength: 0.10, .antagonist: 0.10, .core: 0.05, .prehab: 0.05,
            ],
            progression: .autoregulateHold,
            sessionVolumeCap: 16,
            deferToSport: false,
            sessionMinutesTarget: 45...70),

        // The antagonist inversion: gym = preserve + protect, antagonist dominant.
        .inSeason: PhaseRule(
            objective: "Climb hard; gym preserves + protects (antagonist dominant)",
            sessionsPerWeek: 1...2,
            demandWeights: [
                .pullStrength: 0.10, .fingerStrength: 0.15, .bodyTension: 0.10,
                .contactStrength: 0.05, .antagonist: 0.40, .core: 0.15, .prehab: 0.05,
            ],
            progression: .maintainMinimal,
            sessionVolumeCap: 10,
            deferToSport: true,
            sessionMinutesTarget: 30...45),

        // transitionRecovery — rest fingers/tendons, rebalance, deload. Finger
        // work is ZERO here (overuse-injury prevention).
        .maintenance: PhaseRule(
            objective: "Rest fingers/tendons, rebalance, deload",
            sessionsPerWeek: 1...2,
            demandWeights: [
                .pullStrength: 0.10, .fingerStrength: 0.00, .bodyTension: 0.05,
                .contactStrength: 0.00, .antagonist: 0.40, .core: 0.15, .prehab: 0.30,
            ],
            progression: .deload,
            sessionVolumeCap: 8,
            deferToSport: true,
            sessionMinutesTarget: 30...45),

        // eventPrep = sharp qualities present but low-volume; antagonist carries
        // the health load while projecting (the owner's prescribed column).
        .eventPrep: PhaseRule(
            objective: "Taper to the send — sharp qualities low-volume, stay healthy",
            sessionsPerWeek: 2...2,
            demandWeights: [
                .fingerStrength: 0.20, .contactStrength: 0.10, .pullStrength: 0.10,
                .bodyTension: 0.10, .antagonist: 0.30, .core: 0.10, .prehab: 0.10,
            ],
            progression: .autoregulateHold,
            sessionVolumeCap: 12,
            deferToSport: true,
            sessionMinutesTarget: 35...55),
    ]

    // MARK: - Variant overrides (SPEC §3.4 ski / §4.4 climbing)

    /// Nudge the demand mix per ski variant, then renormalize to sum 1.0.
    func applyingVariantOverride(_ variant: SportVariant) -> PhaseRule {
        let deltas: [Demand: Double]
        switch variant {
        case .inbounds:
            return self
        case .backcountry:   // needs to climb to ski — add the uphill engine
            deltas = [.aerobicUphill: 0.10, .maxStrength: -0.10]
        case .skimo:         // aerobic dominant — cap heavy strength
            deltas = [.aerobicUphill: 0.15, .legEndurance: 0.05,
                      .maxStrength: -0.15, .power: -0.05]
        case .park:          // reactive strength + landing durability
            deltas = [.power: 0.10, .kneeStability: 0.05,
                      .maxStrength: -0.10, .legEndurance: -0.05]
        case .sportRoute:    // climbing baseline
            return self
        case .boulder:       // max strength + power + contact strength
            deltas = [.fingerStrength: 0.05, .contactStrength: 0.05, .antagonist: -0.10]
        case .tradAlpine:    // endurance + durability — less max-effort finger/contact
            deltas = [.fingerStrength: -0.05, .contactStrength: -0.05,
                      .core: 0.05, .antagonist: 0.05]
        }
        var w = demandWeights
        for (d, delta) in deltas {
            w[d, default: 0] = max(0, (w[d] ?? 0) + delta)
        }
        let sum = w.values.reduce(0, +)
        if sum > 0 { for k in w.keys { w[k]! /= sum } }
        return PhaseRule(
            objective: objective, sessionsPerWeek: sessionsPerWeek,
            demandWeights: w, progression: progression,
            sessionVolumeCap: sessionVolumeCap, deferToSport: deferToSport,
            sessionMinutesTarget: sessionMinutesTarget)
    }
}
