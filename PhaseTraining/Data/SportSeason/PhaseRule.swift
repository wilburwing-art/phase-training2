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

    /// This rule as a DELOAD week: the phase's own emphasis and demand mix,
    /// re-prescribed at deload volumes with the fatigue ceiling cut.
    ///
    /// `MesocycleProgression` computed a real cycle status (4-week meso off/pre,
    /// 6 in-season) and its only non-test consumer was the badge. `weekNumber`
    /// reached the generator and was used in exactly one place, the
    /// deterministic seed string, so week 4 of a block showed a DELOAD pill
    /// above the same sets, reps and RPE as week 1. Switching `progression`
    /// re-resolves every `DemandScheme`, which is where sets/reps/RPE come
    /// from, so the whole session lightens rather than one number.
    ///
    /// 0.6 on the ceiling is deliberate: it has to bite even when the deload
    /// scheme alone would still fit under the normal cap.
    func deloaded() -> PhaseRule {
        PhaseRule(
            objective: objective,
            sessionsPerWeek: sessionsPerWeek,
            demandWeights: demandWeights,
            progression: .deload,
            sessionVolumeCap: max(4, Int((Double(sessionVolumeCap) * 0.6).rounded())),
            deferToSport: deferToSport,
            sessionMinutesTarget: sessionMinutesTarget)
    }

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
                .maxStrength: 0.25, .upperStrength: 0.10, .eccentricLeg: 0.10, .legEndurance: 0.05,
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
                // R3-1: upperStrength was 0.05 here and realized 0.00. Four
                // demands tied at 0.05 with three remainder slots, and
                // allocateSlots breaks a tie alphabetically on rawValue, so
                // "upperStrength" lost every week. 0.10 clears the tie, funded
                // from legEndurance (owner's call): the week trades one
                // high-rep leg movement for one pull. legEndurance keeps a
                // slot, and the phase's lactate work is also carried by the
                // power and eccentric circuits.
                .maxStrength: 0.15, .eccentricLeg: 0.30, .upperStrength: 0.10, .legEndurance: 0.10,
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
                // R3-1: upperStrength is 0.00 here on purpose, and was 0.05.
                // In-season is 2 sessions under a sessionVolumeCap of 10, so
                // 0.05 of 8 weekly slots floored to 0.4 and never bought a
                // slot. Rather than take one from knee protection, the phase
                // spends nothing on pressing and says so. A weight the
                // allocator cannot pay is worse than a zero: it reads as
                // covered. The 0.05 returns to maxStrength, which is where 4b
                // took it from, so in-season is back to its pre-4b mix.
                .maxStrength: 0.20, .upperStrength: 0.00, .eccentricLeg: 0.20, .legEndurance: 0.10,
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
                // R3-8 (owner call, 2026-09-05): legEndurance and power at 0.05 were
                // funded and never realized (8 weekly slots, both floored to 0.4
                // and lost the remainder). A deload-and-restore block is not what
                // either is for; the 0.10 goes to kneeStability, whose 0.30 target
                // was realizing 0.12 because the signature guarantee kept taking
                // its slot. The phase objective is "protect knees"; now it pays.

                .maxStrength: 0.10, .eccentricLeg: 0.05, .legEndurance: 0.00,
                .power: 0.00, .kneeStability: 0.40, .core: 0.15,
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
            // "hypertrophy" was in this string while pullStrength's scheme
            // prescribes 4x4-6 at RPE 7-8, which is max strength. The string is
            // what the user reads, so it now says what is delivered. If the
            // INTENT was hypertrophy, the fix is DemandScheme, not this line.
            objective: "Pulling + finger base, strength, structural prep",
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
                // R3-8 (owner call, 2026-09-05): prehab and core at 0.05 were funded
                // and never realized. Pre-season is the highest finger-load phase
                // of the year and prehab (wrist, shoulder) is what keeps a climber
                // in it, so it goes to 0.10. core is redundant with bodyTension
                // for climbing and goes to zero, which is exactly the 0.05 prehab
                // needs; bodyTension stays at 0.20 (the owner's approved targets
                // were prehab 0.10 and core 0.00, and the sum has to stay 1.0).

                .pullStrength: 0.20, .fingerStrength: 0.30, .bodyTension: 0.20,
                .contactStrength: 0.10, .antagonist: 0.10, .core: 0.00, .prehab: 0.10,
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
                // R3-8 (owner call, 2026-09-05): prehab at 0.05 was funded and never
                // realized. In-season a climber gets contact strength from climbing;
                // the gym's job is antagonist and prehab, so prehab goes to 0.15
                // from contactStrength (to zero) and antagonist (0.40 to 0.35, which
                // was realizing 0.25 anyway).

                .pullStrength: 0.10, .fingerStrength: 0.15, .bodyTension: 0.10,
                .contactStrength: 0.00, .antagonist: 0.35, .core: 0.15, .prehab: 0.15,
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
