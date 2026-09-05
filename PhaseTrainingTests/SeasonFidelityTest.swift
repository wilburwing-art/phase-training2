// SeasonFidelityTest — the season-aware generator's eval (SPEC §6).
//
// Where GeneratorSweepReportTest asks "is each knob wired" and
// GeneratorInvariantTest asks "does direction hold", this asks the question the
// whole rearchitecture exists to answer: does a generated session actually
// MATCH ITS SEASON PHASE? Each check is a hard, oracle-free assertion over an
// athlete grid (sport × phase × experience). It also writes
// /tmp/season-fidelity/report.md so the demand mix + session contents can be
// eyeballed and the PhaseRule weights tuned against felt sense.

import XCTest
@testable import PhaseTraining

final class SeasonFidelityTest: XCTestCase {

    /// The sports the engine covers, with their default variant + signature demand.
    private struct SportFixture {
        let slug: String; let name: String; let variant: SportVariant; let signature: Demand
    }
    private let sports = [
        SportFixture(slug: "alpine-skiing", name: "Alpine Skiing", variant: .inbounds, signature: .eccentricLeg),
        SportFixture(slug: "climbing", name: "Climbing", variant: .sportRoute, signature: .fingerStrength),
    ]
    private let phases: [SeasonPhase] = [.offSeason, .preSeason, .inSeason, .maintenance, .eventPrep]

    // MARK: - 3a: max hangs at most twice a week

    /// Three off-season climbing sessions used to each carry
    /// `Hangboard Max Hang` or `Repeaters`. Standard protocols cap max hangs
    /// at two sessions a week. Every session must STILL carry fingerStrength
    /// (check-2), so the third fills it from pinch / dead-hang work.
    func test_hangboardAppearsInAtMostTwoSessionsAWeek() {
        let climb = sports[1]
        for phase in [SeasonPhase.offSeason, .preSeason] {
            var a = athlete(climb, season: phase)
            let week = (0..<3).map {
                SportSeasonGenerator.generateSession(a, sessionIndex: $0, sessionsInWeek: 3)
            }
            let hangboardSessions = week.filter { w in
                w.exercises.contains { $0.name.localizedCaseInsensitiveContains("hangboard") }
            }.count
            XCTAssertLessThanOrEqual(hangboardSessions, 2,
                "[\(phase.rawValue)] hangboard work in \(hangboardSessions) of 3 sessions")
            for (i, w) in week.enumerated() {
                let hasFinger = w.provenance.contains("fingerStrength")
                    || w.exercises.contains { ["pinch", "hang", "hangboard"].contains(where: $0.name.lowercased().contains) }
                XCTAssertTrue(hasFinger, "[\(phase.rawValue)] session \(i) lost its finger slot")
            }
            _ = a
        }
    }

    // MARK: - T2-10: readiness must reach the season engine

    /// The app asked for a soreness check-in and a readiness signal and served
    /// the identical session either way. Same lerp(0.6, 1.0) curve
    /// makePickedRow has used since Phase 2.
    func test_readiness_scalesSetsInTheSeasonEngine() {
        for f in sports {
            var low = athlete(f, season: .offSeason);  low.readinessScore = 0.0
            var high = athlete(f, season: .offSeason); high.readinessScore = 1.0
            let none = athlete(f, season: .offSeason)  // nil = no data
            let sets: (AthleteState) -> Int = {
                SportSeasonGenerator.generateSession($0, sessionIndex: 0).exercises.reduce(0) { $0 + $1.sets }
            }
            XCTAssertLessThan(sets(low), sets(high), "[\(f.slug)] readiness 0 must prescribe fewer sets than readiness 1")
            XCTAssertEqual(sets(none), sets(high), "[\(f.slug)] no readiness data must equal the unscaled dose")
        }
    }

    // MARK: - T1-6: the coach's strategy must reach the season engine

    /// `CoachRequestScreen` builds a `GeneratorStrategy` from a billed LLM call
    /// and hands it to `generateLift`, which dropped it on both paths. The user
    /// saw the model's reasoning above a workout it had not influenced.
    func test_strategy_reachesTheSeasonEngine() {
        for f in sports {
            let a = athlete(f, season: .offSeason)
            let base = SportSeasonGenerator.generateSession(a, sessionIndex: 0)

            var push = GeneratorStrategy.auto
            push.intensityBias = .push
            let pushed = SportSeasonGenerator.generateSession(a, sessionIndex: 0, strategy: push)
            XCTAssertGreaterThan(
                pushed.exercises.reduce(0) { $0 + $1.sets },
                base.exercises.reduce(0) { $0 + $1.sets },
                "[\(f.slug)] intensityBias .push must add sets")

            var down = GeneratorStrategy.auto
            down.intensityBias = .deload
            XCTAssertLessThan(
                SportSeasonGenerator.generateSession(a, sessionIndex: 0, strategy: down)
                    .exercises.reduce(0) { $0 + $1.sets },
                base.exercises.reduce(0) { $0 + $1.sets },
                "[\(f.slug)] intensityBias .deload must remove sets")

            // Per-exercise overrides land on the movement the coach named.
            guard let first = base.exercises.first else {
                return XCTFail("[\(f.slug)] no baseline session to override")
            }
            var over = GeneratorStrategy.auto
            over.rpeOverrides = [first.name.lowercased(): "9"]
            over.tempoOverrides = [first.name.lowercased(): "5-0-1-0"]
            over.targetWeightOverrides = [first.name.lowercased(): 185]
            let o = SportSeasonGenerator.generateSession(a, sessionIndex: 0, strategy: over)
            let row = o.exercises.first { $0.name == first.name }
            XCTAssertEqual(row?.rpe, "9", "[\(f.slug)] rpe override should apply")
            XCTAssertEqual(row?.tempo, "5-0-1-0", "[\(f.slug)] tempo override should apply")
            XCTAssertTrue(row?.notes?.contains("target: 185 lb") ?? false,
                          "[\(f.slug)] load target should reach the notes, got \(row?.notes ?? "nil")")
        }
    }

    // MARK: - T1-8: the deload must actually deload

    /// Week 4 of a 4-week off-season meso is a deload week. Before T1-8 the
    /// badge said DELOAD and the session carried the same sets, reps and RPE
    /// as week 1, because `weekNumber` reached the generator only as part of
    /// the deterministic seed string.
    func test_deloadWeek_reducesVolumeAgainstAnEarlyWeek() {
        for f in sports {
            for phase in [SeasonPhase.offSeason, .preSeason] {
                let cycle = MesocycleProgression.cycleLength(for: phase)
                XCTAssertGreaterThan(cycle, 0, "[\(f.slug)] \(phase.rawValue) should run a meso")

                let build = SportSeasonGenerator.generateSession(
                    athlete(f, season: phase, weekNumber: 1), sessionIndex: 0)
                let deload = SportSeasonGenerator.generateSession(
                    athlete(f, season: phase, weekNumber: cycle), sessionIndex: 0)

                XCTAssertEqual(
                    MesocycleProgression.status(phase: phase, weeksInPhase: cycle,
                                                daysUntilPeak: nil).state,
                    .deload,
                    "[\(f.slug)] week \(cycle) of \(phase.rawValue) should BE the deload week")

                let buildSets = build.exercises.reduce(0) { $0 + $1.sets }
                let deloadSets = deload.exercises.reduce(0) { $0 + $1.sets }
                XCTAssertLessThan(
                    deloadSets, buildSets,
                    "[\(f.slug)/\(phase.rawValue)] deload week must prescribe fewer total sets "
                    + "than week 1 (build \(buildSets), deload \(deloadSets))")
            }
        }
    }

    /// A normal week inside the cycle is untouched — the deload must not leak
    /// into every session.
    func test_buildWeek_isNotDeloaded() {
        for f in sports {
            let w1 = SportSeasonGenerator.generateSession(
                athlete(f, season: .offSeason, weekNumber: 1), sessionIndex: 0)
            let w2 = SportSeasonGenerator.generateSession(
                athlete(f, season: .offSeason, weekNumber: 2), sessionIndex: 0)
            XCTAssertEqual(w1.exercises.reduce(0) { $0 + $1.sets },
                           w2.exercises.reduce(0) { $0 + $1.sets },
                           "[\(f.slug)] weeks 1 and 2 are both build weeks")
        }
    }

    // MARK: - Fixtures

    private func mem(_ f: SportFixture, season: SeasonPhase,
                     experience: ExperienceLevel = .intermediate,
                     days: Int = 3, peak: Date? = nil) -> TrainingMemory {
        var m = TrainingMemory()
        let sport = Sport(slug: f.slug, name: f.name)
        m.primarySport = sport
        m.seasonsBySport = [sport: season]
        m.defaultSeason = season
        m.experience = experience
        m.equipment = [.fullGym]
        m.liftDaysPerWeek = days
        m.age = 32
        m.gender = .male
        m.peakDate = peak
        return m
    }

    private func athlete(_ f: SportFixture, season: SeasonPhase,
                         experience: ExperienceLevel = .intermediate,
                         recent: Set<Int> = [], weekNumber: Int = 1) -> AthleteState {
        AthleteState.from(mem(f, season: season, experience: experience),
                          variant: f.variant, weekNumber: weekNumber, recentMovementIDs: recent)
    }

    private func primaryDemandMap(_ slug: String) -> [Int: Demand] {
        var out: [Int: Demand] = [:]
        for m in CoachDatabase.shared.sportMovements(sport: slug) {
            if let d = m.primaryDemand { out[m.exerciseId] = d }
        }
        return out
    }

    /// The demand each movement was SELECTED for (the slot demand), recovered
    /// from provenance — distinct from a movement's primary demand.
    private func slotDemandDistribution(_ sessions: [GeneratedWorkout]) -> [Demand: Double] {
        var all: [Demand] = []
        for w in sessions {
            guard let r = w.provenance.range(of: "demands: ") else { continue }
            all += w.provenance[r.upperBound...].split(separator: "/")
                .compactMap { Demand(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
        }
        guard !all.isEmpty else { return [:] }
        var hist: [Demand: Double] = [:]
        for d in all { hist[d, default: 0] += 1 }
        return hist.mapValues { $0 / Double(all.count) }
    }

    private func l1(_ a: [Demand: Double], _ b: [Demand: Double]) -> Double {
        Set(a.keys).union(b.keys).reduce(0.0) { $0 + abs((a[$1] ?? 0) - (b[$1] ?? 0)) }
    }

    // MARK: - Sanity

    /// A pool must not list the same catalog exercise twice. It did for one
    /// day (Loaded Step-Up appeared twice in the ski pool after a retire-and-
    /// remap), and `Dictionary(uniqueKeysWithValues:)` in the generator
    /// crashed the whole test host on it rather than failing one test.
    /// Weights that are funded, servable, and still buy no slot. Found by the
    /// assertion below once `upperStrength` exposed the class; each is a
    /// coaching call about which demand gives up a slot, so they are carried
    /// as backlog R3-8 rather than changed under a test. The set is asserted
    /// EXACTLY: fixing one without removing it here fails, and a new one fails
    /// too, so the debt can only shrink deliberately.
    static let knownInertWeights: Set<String> = [
        // Emptied 2026-09-05 (R3-8): the five entries were resolved by weight
        // changes in PhaseRule. Add a key here only with a filed backlog item.
    ]

    /// R3-1. `upperStrength` shipped with a 0.05 weight in ski pre-season and
    /// in-season and realized ZERO slots in both: `allocateSlots` breaks a
    /// remainder tie alphabetically on rawValue, and anything under
    /// 1/weekSlots floors away. A weight the allocator cannot pay reads as
    /// covered and is not.
    ///
    /// Measured against the REAL generated week rather than a reimplementation
    /// of the allocator, so the slot budget is whatever generation actually
    /// used. Skips a demand the pool cannot serve: that is a content gap, and
    /// `test_check1_phase_fidelity` already owns it.
    func test_everyFundedDemandRealizesASlot() {
        for f in sports {
            let pool = CoachDatabase.shared.sportMovements(
                sport: SportSeasonGenerator.poolSlug(for: f.slug))
            for phase in phases {
                let rule = PhaseRule.resolve(sportSlug: f.slug, variant: f.variant, season: phase)
                var sessions: [GeneratedWorkout] = []
                for wk in 1...3 {
                    sessions += SportSeasonGenerator.generateWeek(athlete(f, season: phase, weekNumber: wk))
                }
                let realized = slotDemandDistribution(sessions)
                for (demand, w) in rule.demandWeights where w > 0 {
                    guard pool.contains(where: { $0.serves(demand) }) else { continue }
                    let key = "\(f.slug)/\(phase.rawValue)/\(demand.rawValue)"
                    if Self.knownInertWeights.contains(key) {
                        XCTAssertNil(realized[demand],
                                     "\(key) now realizes — remove it from knownInertWeights")
                        continue
                    }
                    XCTAssertNotNil(
                        realized[demand],
                        "[\(f.slug)/\(phase.rawValue)] \(demand.rawValue) carries weight \(w) and the "
                        + "pool can serve it, but it buys no slot in three generated weeks")
                }
            }
        }
    }

    /// A movement cannot be both `rehab_early` for an injury and
    /// contraindicated by it: one says "this is what you do now", the other
    /// says "do not do this", and the filter reads only the second.
    ///
    /// The narrow role matters and cost a round to get right. `prehab` means
    /// the movement PREVENTS the injury and `rehab_late` means you progress TO
    /// it; neither says it is safe while symptomatic, so pairing either with a
    /// contraindication is coherent. A Nordic curl prevents hamstring strains
    /// and is exactly wrong during one. Only 3 of the 17 pairs the 1b rule
    /// pass created were true contradictions; the first version of this test
    /// flagged all 17 and the fix following it removed 14 contraindications
    /// that were right.
    func test_noExerciseIsBothContraindicatedAndRehabForTheSameInjury() {
        let clashes = CoachDatabase.shared.contradictoryInjuryRoles()
        XCTAssertTrue(clashes.isEmpty,
                      "\(clashes.count) (exercise, injury) pairs are both contraindicated and "
                      + "rehab_early; the filter reads only contraindicated, so the athlete loses "
                      + "the exercise that treats the injury: \(clashes.prefix(5))")
    }

    /// R3-9. The engine prescribes by demand, which is right for a generic
    /// squat and wrong for a movement that carries a cited protocol. When a
    /// protocol movement is served, its own sets, reps and rest come through;
    /// a movement without one still gets the scheme.
    func test_citedProtocolSurvivesTheDemandScheme() {
        let pool = CoachDatabase.shared.sportMovements(sport: "climbing")
        guard let pull = pool.first(where: { $0.exerciseId == 1196 }) else { return XCTFail("no-hang pull missing from the climbing pool") }
        XCTAssertEqual(pull.protocolSets, 5); XCTAssertEqual(pull.protocolReps, "3-4 x 3 sec holds per hand"); XCTAssertEqual(pull.protocolRestSeconds, 180)
        XCTAssertNil(pool.first(where: { $0.exerciseId == 2 })?.protocolSets, "Max Hang has no cited protocol and must stay scheme-driven")
        var served = 0
        for f in sports where f.slug == "climbing" {
            for phase in phases {
                for wk in 1...3 {
                    for w in SportSeasonGenerator.generateWeek(athlete(f, season: phase, weekNumber: wk)) {
                        for ex in w.exercises where ex.exerciseId == 1196 {
                            served += 1
                            XCTAssertEqual(ex.sets, 5, "[\(phase.rawValue)] no-hang pull sets")
                            XCTAssertEqual(ex.reps, "3-4 x 3 sec holds per hand", "[\(phase.rawValue)] no-hang pull reps")
                            XCTAssertEqual(ex.restSeconds, 180, "[\(phase.rawValue)] no-hang pull rest")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(served, 0, "the no-hang pull never appeared in three generated climbing weeks; the assertion above ran on nothing")
    }

    func test_pools_have_no_duplicate_exercise_ids() {
        // R3-5: driven from the database rather than a hardcoded pair, so a
        // sport added later is checked instead of silently skipped.
        let slugs = CoachDatabase.shared.sportMovementSportSlugs()
        XCTAssertFalse(slugs.isEmpty, "no sport pools found — the query or the db is wrong")
        for slug in slugs {
            let ids = CoachDatabase.shared.sportMovements(sport: slug).map(\.exerciseId)
            let dupes = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys
            XCTAssertTrue(dupes.isEmpty, "[\(slug)] duplicate exercise ids in pool: \(Array(dupes))")
        }
    }

    func test_catalog_pools_are_healthy() {
        for f in sports {
            let pool = CoachDatabase.shared.sportMovements(sport: f.slug)
            XCTAssertGreaterThanOrEqual(pool.count, 20, "[\(f.slug)] pool unexpectedly small — empty-catalog flake? re-run")
            XCTAssertTrue(pool.allSatisfy { !$0.demands.isEmpty }, "[\(f.slug)] every movement must carry ≥1 demand")
        }
    }

    /// T0-7 regression gate. The fixture grid above is hardcoded to the two
    /// slugs that HAVE seeded rows, so it could never catch a sport the engine
    /// claims to support but has no movements for. `snow-sports` and
    /// `ski-mountaineering` are both in Sport.catalog, both pass `supports()`,
    /// and both had zero rows — every lift day generated "0 movements · ~0 min".
    ///
    /// Iterate what a USER can actually pick, and assert through the aliasing
    /// seam rather than the raw slug.
    func test_everyPlannableSeasonSport_resolvesToANonEmptyPool() {
        let plannable = Sport.catalog
            .map(\.slug)
            .filter { SportSeasonGenerator.supports($0) }
        XCTAssertFalse(plannable.isEmpty, "catalog should expose season-engine sports")

        for slug in plannable {
            let pool = CoachDatabase.shared.sportMovements(
                sport: SportSeasonGenerator.poolSlug(for: slug))
            XCTAssertGreaterThanOrEqual(
                pool.count, 20,
                "[\(slug)] resolves to an empty/thin movement pool — a user picking this sport "
                + "gets 0-exercise workouts on every lift day. Seed sport_movements for it or "
                + "alias it in SportSeasonGenerator.poolSlug(for:).")
        }
    }

    /// Every slug the engine claims — including ones not yet in the catalog —
    /// must resolve somewhere real, so adding a variant to Sport.catalog can
    /// never silently ship an empty pool.
    func test_everySupportedSlug_aliasesToASeededPool() {
        for slug in PhaseRule.skiSlugs.union(PhaseRule.climbingSlugs) {
            let resolved = SportSeasonGenerator.poolSlug(for: slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.sportMovements(sport: resolved).count, 20,
                "[\(slug)] → '\(resolved)' has no seeded movements")
        }
    }

    // MARK: - SPEC §6 checks (both sports)

    /// Check 1 — phase fidelity: realized slot mix tracks the generator's
    /// INTENDED allocation (the quantization-limited best match to the weights).
    func test_check1_phase_fidelity() {
        for f in sports {
            for phase in phases {
                let rule = PhaseRule.resolve(sportSlug: f.slug, variant: f.variant, season: phase)
                var sessions: [GeneratedWorkout] = []
                for wk in 1...3 { sessions += SportSeasonGenerator.generateWeek(athlete(f, season: phase, weekNumber: wk)) }
                // Same session size the generator used — the fixture athlete
                // carries TrainingMemory's default sessionMinutes, which T2-7
                // now honors.
                // Slots are apportioned across the WEEK now (T1-3), so the
                // intent has to be computed at the same grain or it describes a
                // coarser session than the one produced.
                let a = athlete(f, season: phase)
                let n = max(1, min(a.sessionsPerWeek, rule.sessionsPerWeek.upperBound))
                let drift = l1(slotDemandDistribution(sessions),
                               SportSeasonGenerator.intendedSlotDistribution(
                                   for: rule,
                                   preferredMinutes: a.preferredSessionMinutes,
                                   sessionsInWeek: n,
                                   signature: SportSeasonGenerator.signatureDemand(f.slug),
                                   pool: CoachDatabase.shared.sportMovements(
                                       sport: SportSeasonGenerator.poolSlug(for: f.slug))))
                XCTAssertLessThan(drift, 0.20,
                    "[\(f.slug)/\(phase.rawValue)] realized drifts from intended allocation by L1=\(String(format: "%.2f", drift)) — pool coverage gap?")
            }
        }
    }

    /// Check 2 — signature coverage: every pre/in/eventPrep session covers the
    /// sport's signature demand (ski=eccentricLeg, climb=fingerStrength).
    func test_check2_signature_coverage() {
        for f in sports {
            let map = primaryDemandMap(f.slug)
            for phase in [SeasonPhase.preSeason, .inSeason, .eventPrep] {
                for (i, s) in SportSeasonGenerator.generateWeek(athlete(f, season: phase)).enumerated() {
                    let hasSig = s.exercises.contains { map[$0.exerciseId] == f.signature }
                    XCTAssertTrue(hasSig, "[\(f.slug)/\(phase.rawValue)] session \(i) missing signature \(f.signature.rawValue)")
                }
            }
        }
    }

    /// Check 3 — in-season fatigue ceiling: Σ fatigueCost ≤ cap, no cost-5 move.
    func test_check3_in_season_fatigue_ceiling() {
        for f in sports {
            let costMap = Dictionary(uniqueKeysWithValues:
                CoachDatabase.shared.sportMovements(sport: f.slug).map { ($0.exerciseId, $0.fatigueCost) })
            for phase in [SeasonPhase.inSeason, .maintenance] {
                let cap = PhaseRule.resolve(sportSlug: f.slug, variant: f.variant, season: phase).sessionVolumeCap
                for s in SportSeasonGenerator.generateWeek(athlete(f, season: phase)) {
                    let costs = s.exercises.compactMap { costMap[$0.exerciseId] }
                    XCTAssertLessThanOrEqual(costs.reduce(0, +), cap, "[\(f.slug)/\(phase.rawValue)] over fatigue cap \(cap)")
                    XCTAssertFalse(costs.contains { $0 >= 5 }, "[\(f.slug)/\(phase.rawValue)] cost-5 movement in-season")
                }
            }
        }
    }

    /// Check 4 — defer-to-sport: an in-season session adjacent to a sport day is lighter.
    func test_check4_defer_to_sport() {
        for f in sports {
            let a = athlete(f, season: .inSeason)
            let normal = SportSeasonGenerator.generateSession(a, sessionIndex: 0, adjacentSportDay: false)
            let lightened = SportSeasonGenerator.generateSession(a, sessionIndex: 0, adjacentSportDay: true)
            XCTAssertLessThanOrEqual(lightened.exercises.count, normal.exercises.count, "[\(f.slug)] not lightened")
            XCTAssertLessThanOrEqual(lightened.estimatedMinutes, normal.estimatedMinutes, "[\(f.slug)] lighter ≠ shorter")
        }
    }

    /// Check 5 — injury logic: a contraindicated exercise never appears.
    func test_check5_injury_gate() {
        for f in sports {
            let pool = CoachDatabase.shared.sportMovements(sport: f.slug)
            guard let victim = pool.first(where: { $0.allowedPhases.contains(.offSeason) }) else { continue }
            let base = athlete(f, season: .offSeason)
            let injured = AthleteState(
                sportSlug: base.sportSlug, variant: base.variant, experience: base.experience,
                season: base.season, availableEquipmentSlugs: base.availableEquipmentSlugs,
                sessionsPerWeek: base.sessionsPerWeek, targetObjectiveDate: base.targetObjectiveDate,
                weekNumber: base.weekNumber, recentMovementIDs: base.recentMovementIDs,
                contraindicatedExerciseIDs: [victim.exerciseId], flaggedDemands: [], profile: base.profile)
            for s in SportSeasonGenerator.generateWeek(injured) {
                XCTAssertFalse(s.exercises.contains { $0.exerciseId == victim.exerciseId },
                    "[\(f.slug)] contraindicated \(victim.name) leaked into the session")
            }
        }
    }

    /// Check 6 — antagonist inversion (climbing): in-season the gym counterbalances
    /// the wall, so antagonist is the single most-emphasized demand.
    func test_check6_antagonist_inversion_climbing() {
        let climb = sports[1]
        let rule = PhaseRule.resolve(sportSlug: climb.slug, variant: climb.variant, season: .inSeason)
        let a = athlete(climb, season: .inSeason)
        let intended = SportSeasonGenerator.intendedSlotDistribution(
            for: rule, preferredMinutes: a.preferredSessionMinutes,
            sessionsInWeek: max(1, min(a.sessionsPerWeek, rule.sessionsPerWeek.upperBound)),
            signature: SportSeasonGenerator.signatureDemand(climb.slug),
            pool: CoachDatabase.shared.sportMovements(
                sport: SportSeasonGenerator.poolSlug(for: climb.slug)))
        XCTAssertEqual(intended[.antagonist], intended.values.max(),
            "in-season climbing must allocate antagonist the largest share")
        let realized = slotDemandDistribution(SportSeasonGenerator.generateWeek(athlete(climb, season: .inSeason)))
        XCTAssertEqual(realized[.antagonist], realized.values.max(),
            "realized in-season climbing should be antagonist-dominant, was \(realized)")
    }

    /// Check 7 — rotation without coverage loss: recent picks deprioritized,
    /// every demand the phase allocates still covered.
    func test_check7_rotation_preserves_coverage() {
        for f in sports {
            let map = primaryDemandMap(f.slug)
            let fresh = SportSeasonGenerator.generateWeek(athlete(f, season: .preSeason))
            let freshIds = Set(fresh.flatMap { $0.exercises }.map { $0.exerciseId })
            let rotated = SportSeasonGenerator.generateWeek(athlete(f, season: .preSeason, recent: freshIds))
            let fd = Set(fresh.flatMap { $0.exercises }.compactMap { map[$0.exerciseId] })
            let rd = Set(rotated.flatMap { $0.exercises }.compactMap { map[$0.exerciseId] })
            XCTAssertTrue(fd.isSubset(of: rd), "[\(f.slug)] rotation dropped demand coverage: \(fd.subtracting(rd))")
        }
    }

    /// Finger-injury redistribution (SPEC §4.1/§5): a flagged finger injury
    /// zeroes finger + contact demand; the freed weight lands on antagonist/prehab.
    func test_finger_injury_redistribution() {
        let weights = PhaseRule.resolve(sportSlug: "climbing", variant: .sportRoute, season: .preSeason).demandWeights
        let after = SportSeasonGenerator.applyInjuryRedistribution(weights, flagged: [.fingerStrength, .contactStrength])
        XCTAssertEqual(after[.fingerStrength], 0)
        XCTAssertEqual(after[.contactStrength], 0)
        XCTAssertGreaterThan(after[.prehab] ?? 0, weights[.prehab] ?? 0)
        XCTAssertGreaterThan(after[.antagonist] ?? 0, weights[.antagonist] ?? 0)
        XCTAssertEqual(after.values.reduce(0, +), 1.0, accuracy: 0.001, "weights must still sum to 1")
    }

    // MARK: - M2a injection (Planner routes supported sports to the season engine)

    func test_planner_routes_supported_sport_to_season_engine() {
        // Phase 2: pilot sports (climbing) are deliberately served authored
        // routines, not the season engine — covered by the companion test
        // below + AuthoredRoutineTests. This check covers the supported sports
        // that still route to the season engine (ski).
        for f in sports where !AuthoredRoutineSelector.pilotSports.contains(f.slug) {
            let m = mem(f, season: .offSeason, days: 3)
            let plan = Planner.generate(memory: m, routines: [])
            let liftDays = plan.days.filter { $0.kind == .lift }
            XCTAssertFalse(liftDays.isEmpty, "[\(f.slug)] no lift days generated")
            for d in liftDays {
                let w = d.generatedWorkout
                XCTAssertNotNil(w, "[\(f.slug)] lift day missing workout")
                // Season-engine provenance carries the slot demands; legacy doesn't.
                XCTAssertTrue(w?.provenance.contains("demands:") ?? false,
                    "[\(f.slug)] lift day NOT from season engine: \(w?.provenance ?? "nil")")
                XCTAssertEqual(w?.focus, .fullBodyA, "[\(f.slug)] season day should carry a focus")
                XCTAssertTrue(w?.exercises.allSatisfy { $0.exerciseId > 0 } ?? false,
                    "[\(f.slug)] season exercises must have real catalog ids")
            }
        }
    }

    /// Phase 2 contract: a pilot sport's lift days are filled from curated
    /// authored coach.db routines (provenance "Authored …"), not the season
    /// engine — with real catalog exercise ids so they log/complete normally.
    func test_planner_routes_pilot_sport_to_authored() {
        guard let climbing = sports.first(where: { AuthoredRoutineSelector.pilotSports.contains($0.slug) }) else {
            return XCTFail("expected a pilot sport in the fixture")
        }
        let m = mem(climbing, season: .offSeason, days: 3)
        let plan = Planner.generate(memory: m, routines: [])
        let liftDays = plan.days.filter { $0.kind == .lift }
        XCTAssertFalse(liftDays.isEmpty, "[\(climbing.slug)] no lift days generated")
        for d in liftDays {
            let w = d.generatedWorkout
            XCTAssertTrue(w?.provenance.contains("Authored") ?? false,
                "[\(climbing.slug)] pilot lift day should be authored: \(w?.provenance ?? "nil")")
            XCTAssertTrue(w?.exercises.allSatisfy { $0.exerciseId > 0 } ?? false,
                "[\(climbing.slug)] authored exercises must have real catalog ids")
        }
    }

    // MARK: - M2b migration gate (unsupported sport → re-onboard, no loop)

    func test_migration_reonboards_unsupported_sport_without_loop() {
        let suite = "season-migration-test"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = MemoryStore(defaults: defaults)

        // Onboarded user on an unsupported sport → re-onboard, strip the sport.
        store.update {
            $0.sports = [Sport(slug: "running", name: "Running")]
            $0.primarySport = Sport(slug: "running", name: "Running")
            $0.onboardedAt = Date()
        }
        store.migrateToSupportedSportGate()
        XCTAssertNil(store.memory.onboardedAt, "unsupported user should be re-onboarded")
        XCTAssertTrue(store.memory.sports.isEmpty, "unsupported sport must be stripped (else gate loops)")
        XCTAssertNil(store.memory.primarySport)

        // Idempotent: once re-onboarding, the guard short-circuits.
        store.migrateToSupportedSportGate()
        XCTAssertNil(store.memory.onboardedAt)

        // A supported user is never re-onboarded.
        store.update {
            $0.sports = [Sport(slug: "climbing", name: "Climbing")]
            $0.primarySport = Sport(slug: "climbing", name: "Climbing")
            $0.onboardedAt = Date()
        }
        store.migrateToSupportedSportGate()
        XCTAssertNotNil(store.memory.onboardedAt, "supported user must NOT be re-onboarded")
    }

    func test_migration_keeps_outdoor_authored_primary() {
        // Snowboarding isn't season-engine supported but is now plannable
        // (authored coverage) → the gate must keep it, not re-onboard.
        let suite = "season-migration-outdoor-test"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = MemoryStore(defaults: defaults)
        store.update {
            $0.sports = [Sport.resolve(slug: "snowboarding")]
            $0.primarySport = Sport.resolve(slug: "snowboarding")
            $0.onboardedAt = Date()
        }
        store.migrateToSupportedSportGate()
        XCTAssertNotNil(store.memory.onboardedAt, "snowboarding is plannable — must NOT be re-onboarded")
        XCTAssertEqual(store.memory.primarySport?.slug, "snowboarding")
    }

    // MARK: - Prescription tracks the slot demand (not the generic catalog)

    /// (demand, exercise) pairs in selection order — the provenance demand list
    /// zips with `exercises` because `assemble` preserves pick order.
    private func demandExercisePairs(_ w: GeneratedWorkout) -> [(Demand, GeneratedExercise)] {
        guard let r = w.provenance.range(of: "demands: ") else { return [] }
        let demands = w.provenance[r.upperBound...].split(separator: "/")
            .compactMap { Demand(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
        return Array(zip(demands, w.exercises))
    }

    /// Reps/rest/RPE/tempo must follow the DEMAND the slot was allocated to —
    /// the whole reason the season engine exists. Before DemandScheme these came
    /// from each movement's generic catalog default and were demand-blind.
    func test_check8_prescription_tracks_demand() throws {
        var pairs: [(Demand, GeneratedExercise)] = []
        for f in sports {
            for phase in phases {
                for wk in 1...3 {
                    for w in SportSeasonGenerator.generateWeek(athlete(f, season: phase, weekNumber: wk)) {
                        pairs += demandExercisePairs(w)
                    }
                }
            }
        }
        XCTAssertFalse(pairs.isEmpty, "no sessions generated — empty-catalog flake? re-run")

        func repsLow(_ s: String) -> Int? { Int(s.split(whereSeparator: { !$0.isNumber }).first ?? "") }

        for (demand, ex) in pairs {
            switch demand {
            case .power, .contactStrength:
                XCTAssertEqual(ex.tempo, "2-0-X-0",
                    "\(demand.rawValue) (\(ex.name)) must be explosive, got tempo \(ex.tempo ?? "nil")")
                if let lo = repsLow(ex.reps) {
                    XCTAssertLessThanOrEqual(lo, 5, "\(demand.rawValue) reps should be low, got \(ex.reps)")
                }
            case .eccentricLeg:
                XCTAssertEqual(ex.tempo, "4-0-1-0",
                    "eccentricLeg (\(ex.name)) must carry the 4s eccentric tempo, got \(ex.tempo ?? "nil")")
            case .legEndurance, .pullEndurance:
                if let lo = repsLow(ex.reps) {
                    XCTAssertGreaterThanOrEqual(lo, 10, "\(demand.rawValue) reps should be high, got \(ex.reps)")
                }
            case .fingerStrength:
                XCTAssertTrue(ex.reps.contains("hold"),
                    "fingerStrength (\(ex.name)) should prescribe a hold, got \(ex.reps)")
            default:
                break
            }
        }
    }

    /// Progression shrinks volume + intensity off the demand's base band.
    func test_modulation_shrinks_under_lower_phases() {
        let base = DemandScheme.scheme(for: .maxStrength, progression: .progressiveOverload)
        let maintain = DemandScheme.scheme(for: .maxStrength, progression: .maintainMinimal)
        let deload = DemandScheme.scheme(for: .maxStrength, progression: .deload)
        XCTAssertGreaterThan(base.setsMid, deload.setsMid, "deload must cut sets vs overload")
        XCTAssertGreaterThanOrEqual(base.setsMid, maintain.setsMid)
        XCTAssertGreaterThanOrEqual(maintain.setsMid, deload.setsMid)
        XCTAssertGreaterThan(base.intensityRPEHigh ?? 0, deload.intensityRPEHigh ?? 0, "deload must cut RPE")
        XCTAssertGreaterThanOrEqual(deload.intensityRPELow ?? 0, 5, "RPE floors at 5")
    }

    // MARK: - Report

    func test_write_season_fidelity_report() {
        var md = "# Season-fidelity report — skiing + climbing\n\n"
        md += "Per phase: realized demand mix vs PhaseRule target, then the session dump.\n"
        md += "Tune `PhaseRule` weights + `sessionVolumeCap` against felt sense, re-run.\n\n"
        for f in sports {
            let map = primaryDemandMap(f.slug)
            let costMap = Dictionary(uniqueKeysWithValues:
                CoachDatabase.shared.sportMovements(sport: f.slug).map { ($0.exerciseId, $0.fatigueCost) })
            md += "# \(f.name) (\(f.variant.rawValue))\n\n"
            for phase in phases {
                let rule = PhaseRule.resolve(sportSlug: f.slug, variant: f.variant, season: phase)
                let week = SportSeasonGenerator.generateWeek(athlete(f, season: phase))
                let dist = slotDemandDistribution(week)
                md += "## \(phase.label) — \(rule.objective)\n"
                md += "cap \(rule.sessionVolumeCap) fp · \(rule.progression.rawValue) · defer-to-sport \(rule.deferToSport)\n\n"
                md += "| demand | target | realized (slot) |\n|---|---|---|\n"
                for d in rule.demandWeights.keys.sorted(by: { (rule.demandWeights[$0] ?? 0) > (rule.demandWeights[$1] ?? 0) }) {
                    md += "| \(d.rawValue) | \(String(format: "%.2f", rule.demandWeights[d] ?? 0)) | \(String(format: "%.2f", dist[d] ?? 0)) |\n"
                }
                md += "\n"
                for (i, s) in week.enumerated() {
                    let fp = s.exercises.reduce(0) { $0 + (costMap[$1.exerciseId] ?? 0) }
                    md += "**Session \(i + 1)** — \(s.exercises.count) ex · ~\(s.estimatedMinutes)m · \(fp) fp\n"
                    for e in s.exercises {
                        let demand = map[e.exerciseId].map { " · \($0.rawValue)" } ?? ""
                        let tempo = e.tempo.map { " · tempo \($0)" } ?? ""
                        md += "- \(e.name) — \(e.sets)×\(e.reps), \(e.restSeconds)s · RPE \(e.rpe ?? "—")\(tempo)\(demand)\n"
                    }
                    md += "\n"
                }
            }
        }
        let dir = URL(fileURLWithPath: "/tmp/season-fidelity")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("report.md")
        try? md.write(to: out, atomically: true, encoding: .utf8)
        print("[SeasonFidelity] report: \(out.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
    }
}
