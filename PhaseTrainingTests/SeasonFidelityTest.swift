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

    func test_catalog_pools_are_healthy() {
        for f in sports {
            let pool = CoachDatabase.shared.sportMovements(sport: f.slug)
            XCTAssertGreaterThanOrEqual(pool.count, 20, "[\(f.slug)] pool unexpectedly small — empty-catalog flake? re-run")
            XCTAssertTrue(pool.allSatisfy { !$0.demands.isEmpty }, "[\(f.slug)] every movement must carry ≥1 demand")
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
                let drift = l1(slotDemandDistribution(sessions),
                               SportSeasonGenerator.intendedSlotDistribution(for: rule))
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
        let intended = SportSeasonGenerator.intendedSlotDistribution(for: rule)
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
        for f in sports {
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
