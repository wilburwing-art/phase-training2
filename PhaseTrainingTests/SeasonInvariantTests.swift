import XCTest
@testable import PhaseTraining

/// T2-4. `GeneratorInvariantTest` (312 lines) was deleted in 449bd8d with the
/// legacy selection engine and never replaced for the season engine, which is
/// now the only generator. The injury-contraindication half was ported to
/// AuthoredRoutineTests on 2026-09-04; this is the rest: must-hold-for-ALL-
/// inputs properties over a grid, run through `WorkoutGenerator.generateLift`
/// so they cover whichever path a request routes to.
///
/// Every assertion here is oracle-free. A failure names the cell.
final class SeasonInvariantTests: XCTestCase {

    private struct Cell: CustomStringConvertible {
        let sport: String, phase: SeasonPhase, experience: ExperienceLevel
        let equipment: [Equipment], minutes: Int, slot: Int, totalLifts: Int
        var description: String {
            "\(sport)/\(phase.rawValue)/\(experience.rawValue)/\(equipment.map(\.rawValue).joined(separator: "+"))/\(minutes)min/slot\(slot)of\(totalLifts)"
        }
    }

    /// Ten plannable sports x 5 phases x 3 experience x 3 equipment tiers x
    /// 2 session lengths x 3 slots. ~2,700 cells; runs in seconds.
    private var grid: [Cell] {
        let sports = ["alpine-skiing", "snow-sports", "ski-mountaineering", "climbing",
                      "snowboarding", "mountain-biking", "mountaineering",
                      "trail-running", "hiking-trekking", "thru-hiking"]
        let equipment: [[Equipment]] = [[.fullGym], [.dumbbells, .pullUpBar], [.bodyweight]]
        var out: [Cell] = []
        for s in sports { for p in SeasonPhase.allCases { for e in ExperienceLevel.allCases {
            for eq in equipment { for m in [30, 75] { for slot in 0..<3 {
                out.append(Cell(sport: s, phase: p, experience: e, equipment: eq,
                                minutes: m, slot: slot, totalLifts: 3))
            } } }
        } } }
        return out
    }

    private func generate(_ c: Cell) -> GeneratedWorkout {
        var memory = TrainingMemory()
        memory.primarySport = Sport.resolve(slug: c.sport)
        memory.defaultSeason = c.phase
        if let sport = memory.primarySport { memory.seasonsBySport = [sport: c.phase] }
        memory.experience = c.experience
        memory.equipment = c.equipment
        memory.sessionMinutes = c.minutes
        memory.liftDaysPerWeek = c.totalLifts
        let profile = DemographicProfile.from(memory)
        return WorkoutGenerator.generateLift(
            liftIndex: c.slot, totalLifts: c.totalLifts, memory: memory, profile: profile,
            hashSeed: "inv-\(c)")
    }

    // MARK: - Part A: structural invariants

    func test_noPlannableCellProducesAnEmptyWorkout() {
        // The "Rest / No supported sport set" branch is a safety net for a
        // nil primary sport. Every sport in the grid is plannable, so it must
        // never be reached from here.
        for c in grid where c.equipment != [.bodyweight] {
            let w = generate(c)
            XCTAssertFalse(w.exercises.isEmpty, "[\(c)] empty workout: '\(w.title)' / \(w.provenance)")
        }
    }

    func test_setsAreInRange() {
        for c in grid {
            for ex in generate(c).exercises {
                XCTAssertTrue((1...8).contains(ex.sets), "[\(c)] '\(ex.name)' sets=\(ex.sets)")
            }
        }
    }

    func test_noDuplicateMovementInASession() {
        for c in grid {
            let ids = generate(c).exercises.map(\.exerciseId).filter { $0 > 0 }
            XCTAssertEqual(ids.count, Set(ids).count, "[\(c)] duplicate movement")
        }
    }

    func test_everyRowHasRepsAndRest() {
        for c in grid {
            for ex in generate(c).exercises {
                XCTAssertFalse(ex.reps.trimmingCharacters(in: .whitespaces).isEmpty, "[\(c)] '\(ex.name)' empty reps")
                // 5, not 15: the MTI-distilled "Leg Blaster" circuit rows are
                // real prescriptions at 20 sec work / 10 sec rest, and the
                // first run of this harness failed on exactly that. The bound
                // exists to catch a zero, a negative or a parse fall-through,
                // not to outlaw a circuit.
                XCTAssertGreaterThanOrEqual(ex.restSeconds, 5, "[\(c)] '\(ex.name)' rest \(ex.restSeconds)s")
            }
        }
    }

    func test_generationIsDeterministic() {
        for c in grid.prefix(200) {
            XCTAssertEqual(generate(c), generate(c), "[\(c)] same inputs, different output")
        }
    }

    // MARK: - Part B: metamorphic (expected-direction) invariants, non-strict

    func test_shorterSessionNeverAddsMovements() {
        for c in grid where c.minutes == 75 {
            let long = generate(c)
            let short = generate(Cell(sport: c.sport, phase: c.phase, experience: c.experience,
                                      equipment: c.equipment, minutes: 30, slot: c.slot,
                                      totalLifts: c.totalLifts))
            XCTAssertLessThanOrEqual(short.exercises.count, long.exercises.count,
                                     "[\(c)] 30 min produced MORE movements than 75")
        }
    }

    func test_bodyweightOnlyNeverPrescribesLoadedEquipment() {
        // The oracle is the engine's OWN rule (SportSeasonGenerator.filteredPool):
        // a movement is usable when its required slugs are a subset of the
        // athlete's allowed slugs, and an EMPTY allowed set means full gym.
        // `"bodyweight"` is itself a coach.db equipment slug, so "needs
        // nothing" is not the test — the first draft of this assertion failed
        // on Side Plank "needing [bodyweight]".
        //
        // The authored path applies the same rule since R2-05 (2026-09-04):
        // a row the user cannot equip is swapped for a curated substitute or
        // dropped, so both paths are asserted. Before that it served 2,382 of
        // 3,264 rows to a bodyweight-only user with gear they did not have.
        var swapped = 0
        for c in grid where c.equipment == [.bodyweight] {
            var memory = TrainingMemory()
            memory.equipment = c.equipment
            let allowed = DemographicProfile.from(memory).allowedEquipmentSlugs
            let w = generate(c)
            let isAuthored = w.provenance.hasPrefix("Authored")
            let reqs = CoachDatabase.shared.requiredEquipmentSlugs(
                forExerciseIds: Set(w.exercises.map(\.exerciseId)))
            for ex in w.exercises {
                let need = reqs[ex.exerciseId] ?? []
                let usable = need.isEmpty || allowed.isEmpty || need.isSubset(of: allowed)
                if isAuthored, ex.notes?.hasPrefix("Swapped in for") == true { swapped += 1 }
                XCTAssertTrue(usable, "[\(c)] \(isAuthored ? "authored routine" : "season engine") prescribed '\(ex.name)' needing \(need) to a user with \(allowed)")
            }
        }
        print("SEASON-INVARIANT authored rows swapped for a bodyweight-only user: \(swapped)")
    }

    // MARK: - Part C: a rep keeps the catalog's unit

    func test_repsForCatalog_keepsUnitsAndSides() {
        let core = SetScheme(setsLow: 2, setsHigh: 3, repsLow: 10, repsHigh: 15, restSeconds: 60)
        let hold = SetScheme(setsLow: 4, setsHigh: 6, holdSeconds: 8, restSeconds: 120)
        // A plain count, or nothing, leaves the demand's band alone.
        XCTAssertEqual(core.reps(forCatalog: nil), "10-15")
        XCTAssertEqual(core.reps(forCatalog: "8-12"), "10-15")
        XCTAssertEqual(core.reps(forCatalog: "3-5 reps"), "10-15")
        XCTAssertEqual(hold.reps(forCatalog: nil), "8s hold")
        // Timed, hold and distance strings are served verbatim.
        XCTAssertEqual(core.reps(forCatalog: "20-45 sec per side"), "20-45 sec per side")
        XCTAssertEqual(core.reps(forCatalog: "40-60 ft"), "40-60 ft")
        XCTAssertEqual(core.reps(forCatalog: "8-6-4 x 10 sec holds per side"), "8-6-4 x 10 sec holds per side")
        XCTAssertEqual(hold.reps(forCatalog: "30-90 min"), "30-90 min")
        XCTAssertEqual(hold.reps(forCatalog: "6 hangs (7s on / 3s off)"), "6 hangs (7s on / 3s off)")
        // A per-side count keeps the demand's band and the catalog's suffix.
        XCTAssertEqual(core.reps(forCatalog: "8-10 per side"), "10-15 per side")
        XCTAssertEqual(core.reps(forCatalog: "10-12/side"), "10-15 per side")
        XCTAssertEqual(core.reps(forCatalog: "8-10 per position"), "10-15 per position")
        XCTAssertEqual(hold.reps(forCatalog: "3-4 per hand"), "3-4 per hand")
    }

    func test_seasonEngineRowsKeepTheCatalogUnit() {
        // The 2026-11-10 sweep found Side Plank served as "10-15", Hollow Body
        // Hold as "3x6-10" and Farmer's Carry as "10-15": 5,465 of 51,991
        // season-engine rows, with "per side" dropped on 14,299 more. The fix
        // for this lived in the legacy generator deleted in 449bd8d.
        let plainBand = #"^\d+(\s*-\s*\d+)?$"#
        let sides = ["per side", "/side", "each side", "per position", "per hand", "per arm", "per leg"]
        var checked = 0
        for c in grid {
            let w = generate(c)
            guard !w.provenance.hasPrefix("Authored") else { continue }
            let rows = w.exercises.filter { $0.id.hasPrefix("ss-") && $0.exerciseId > 0 }
            let catalog = CoachDatabase.shared.exerciseLoggingMeta(forExerciseIds: Set(rows.map(\.exerciseId)))
            for ex in rows {
                guard let raw = catalog[ex.exerciseId]?.defaultReps?.lowercased(), !raw.isEmpty else { continue }
                let isPlain = raw.range(of: #"^\d+(\s*-\s*\d+)?(\s*reps?)?$"#, options: .regularExpression) != nil
                guard !isPlain else { continue }
                checked += 1
                XCTAssertNil(ex.reps.range(of: plainBand, options: .regularExpression),
                             "[\(c)] '\(ex.name)' is '\(raw)' in the catalog and was served as '\(ex.reps)'")
                if sides.contains(where: { raw.hasSuffix($0) }) {
                    XCTAssertTrue(ex.reps.lowercased().contains("per "),
                                  "[\(c)] '\(ex.name)' lost its side: catalog '\(raw)', served '\(ex.reps)'")
                }
            }
        }
        XCTAssertGreaterThan(checked, 1000, "the grid should reach many unit-carrying rows; \(checked) means the check is not running")
    }

    // MARK: - Part D: experience and age change the prescription

    func test_adjusted_beginnerIsCapped() {
        let strength = SetScheme(setsLow: 3, setsHigh: 5, repsLow: 4, repsHigh: 6,
                                 intensityRPELow: 7, intensityRPEHigh: 8, restSeconds: 120)
        let b = strength.adjusted(experience: .beginner, age: nil, mainLift: true)
        XCTAssertLessThanOrEqual(b.setsHigh, 3)
        XCTAssertLessThanOrEqual(b.intensityRPEHigh ?? 0, 7)
        XCTAssertGreaterThanOrEqual(b.repsLow ?? 0, 6)
        // Power keeps its own reps.
        let power = SetScheme(setsLow: 4, setsHigh: 6, repsLow: 2, repsHigh: 3,
                              intensityRPELow: 7, intensityRPEHigh: 7,
                              explosiveConcentric: true, restSeconds: 120)
        XCTAssertEqual(power.adjusted(experience: .beginner, age: nil, mainLift: false).repsLow, 2)
        // Holds keep their seconds.
        let hold = SetScheme(setsLow: 4, setsHigh: 6, holdSeconds: 8, restSeconds: 120)
        XCTAssertEqual(hold.adjusted(experience: .beginner, age: nil, mainLift: false).repsString, "8s hold")
    }

    func test_adjusted_totalSetsRiseWithExperienceAndFallWithAge() {
        let strength = SetScheme(setsLow: 3, setsHigh: 5, repsLow: 4, repsHigh: 6,
                                 intensityRPELow: 7, intensityRPEHigh: 8, restSeconds: 120)
        func sets(_ e: ExperienceLevel, _ age: Int?) -> Int {
            strength.adjusted(experience: e, age: age, mainLift: true).setsMid
        }
        XCTAssertLessThan(sets(.beginner, nil), sets(.intermediate, nil))
        XCTAssertLessThan(sets(.intermediate, nil), sets(.advanced, nil))
        let power = SetScheme(setsLow: 4, setsHigh: 6, repsLow: 2, repsHigh: 3,
                              intensityRPELow: 7, intensityRPEHigh: 7,
                              explosiveConcentric: true, restSeconds: 120)
        let old = power.adjusted(experience: .intermediate, age: 68, mainLift: false)
        let young = power.adjusted(experience: .intermediate, age: 25, mainLift: false)
        XCTAssertLessThan(old.setsMid, young.setsMid)
        XCTAssertGreaterThan(old.restSeconds, young.restSeconds)
    }

    func test_seasonEngine_beginnerPlansCarryLessThanAdvanced() {
        var total: [ExperienceLevel: Int] = [:]
        for c in grid where c.sport == "alpine-skiing" && c.equipment == [.fullGym] && c.minutes == 75 {
            let w = generate(c)
            guard !w.provenance.hasPrefix("Authored") else { continue }
            total[c.experience, default: 0] += w.exercises.reduce(0) { $0 + $1.sets }
        }
        XCTAssertLessThan(total[.beginner] ?? 0, total[.advanced] ?? 0)
    }

    func test_beginnerClimberNeverGetsAdvancedAuthoredRoutine() {
        for phase in SeasonPhase.allCases {
            for i in 0..<4 {
                guard let id = AuthoredRoutineSelector.select(sportSlug: "climbing", phase: phase,
                                                              sessionIndex: i, experience: .beginner) else { continue }
                let d = CoachDatabase.shared.routineDifficulty(forIds: [id])[id]
                XCTAssertEqual(d, "beginner", "\(phase) slot \(i) served a \(d ?? "?") routine to a beginner")
            }
        }
    }

    func test_apparatusExercisesAreNotTaggedBodyweightOnly() {
        // 2026-11-10 sweep: Ab Wheel Rollout and two sled pushes were tagged
        // bodyweight, so a no-equipment user was prescribed them.
        let needs = CoachDatabase.shared.requiredEquipmentSlugs(forExerciseIds: [7, 533, 682])
        XCTAssertTrue(needs[7]?.contains("ab-wheel") == true, "Ab Wheel Rollout needs an ab wheel")
        XCTAssertTrue(needs[533]?.contains("sled") == true && needs[682]?.contains("sled") == true)
        XCTAssertFalse(needs[7]?.contains("bodyweight") == true)
    }

    // MARK: - Part C: cross-week variety (11c 2.3)

    /// One week N to N+1 pair. Week N runs with no recent picks, week N+1
    /// with week N's picks as `recentlyPicked` (the app passes the last 28
    /// days from `RecentPicksStore`). Season-engine sessions only.
    private struct WeekPair {
        let cell: String, sport: String, tier: String, phase: SeasonPhase
        /// Week N+1 accessory picks (slot demand outside `anchorDemands`).
        let accessories: [(id: Int, demand: Demand, session: Set<Int>, pool: [SportMovement])]
        let weekN: Set<Int>
        var repeated: Int { Set(accessories.map(\.id)).intersection(weekN).count }
        var share: Double { Double(repeated) / Double(Set(accessories.map(\.id)).count) }
    }

    private static var pairCache: [WeekPair]?

    /// Engine sports only: pilot sports serve authored routines, which repeat
    /// as written. 3 sports x 5 phases x 3 experience x 3 equipment tiers x
    /// 3 lift counts x 4 week pairs.
    private func weekPairs() -> [WeekPair] {
        if let c = Self.pairCache { return c }
        let sports = Sport.catalog.map(\.slug).filter {
            SportSeasonGenerator.supports($0) && !AuthoredRoutineSelector.pilotSports.contains($0)
        }
        let equipment: [(String, [Equipment])] = [
            ("gym", [.fullGym]), ("homebar", [.dumbbells, .pullUpBar, .bands]), ("bw", [.bodyweight])]
        typealias Week = (ids: Set<Int>, accessories: [(id: Int, demand: Demand, session: Set<Int>, pool: [SportMovement])])
        var out: [WeekPair] = []
        for s in sports { for p in SeasonPhase.allCases { for e in ExperienceLevel.allCases {
            for eq in equipment { for days in [2, 3, 4] { for week in 1...4 {
                func run(week w: Int, recent: Set<Int>) -> Week? {
                    var m = TrainingMemory()
                    let sport = Sport.catalog.first { $0.slug == s }!
                    m.primarySport = sport
                    m.sports = [sport]
                    m.seasonsBySport = [sport: p]
                    m.defaultSeason = p
                    m.experience = e
                    m.equipment = eq.1
                    m.liftDaysPerWeek = days
                    m.sessionMinutes = 45
                    m.phaseStartedAt = Calendar.current.date(byAdding: .day, value: -7 * (w - 1), to: Date())
                    if p == .eventPrep { m.peakDate = Calendar.current.date(byAdding: .day, value: 40, to: Date()) }
                    let profile = DemographicProfile.from(m)
                    let athlete = AthleteState.from(m, variant: m.primaryVariant, weekNumber: m.weeksInCurrentPhase ?? 1,
                                                    recentMovementIDs: recent)
                    var ids: Set<Int> = []
                    var acc: [(id: Int, demand: Demand, session: Set<Int>, pool: [SportMovement])] = []
                    for i in 0..<days {
                        let g = WorkoutGenerator.generateLift(
                            liftIndex: i, totalLifts: days, memory: m, profile: profile,
                            hashSeed: "var-\(s)-\(p.rawValue)-wk\(w)", recentlyPicked: recent)
                        guard !g.provenance.hasPrefix("Authored"), !g.exercises.isEmpty,
                              g.exercises.allSatisfy({ $0.id.hasPrefix("ss-") }) else { continue }
                        let session = Set(g.exercises.map(\.exerciseId))
                        ids.formUnion(session)
                        let demands = g.provenance.components(separatedBy: "demands: ").last?
                            .split(separator: "/").compactMap { Demand(rawValue: String($0)) } ?? []
                        XCTAssertEqual(demands.count, g.exercises.count, "[\(s)] provenance demands misaligned: \(g.provenance)")
                        // Complement days filter the general-fitness pool by
                        // focus as well, so only sport sessions get the
                        // accessory check, against the exact engine pool.
                        guard !g.provenance.hasPrefix("complement") else { continue }
                        let pool = SportSeasonGenerator.filteredPool(athlete, phase: p)
                        for (x, d) in zip(g.exercises, demands) where !SportSeasonGenerator.anchorDemands.contains(d) {
                            acc.append((x.exerciseId, d, session, pool))
                        }
                    }
                    return ids.isEmpty ? nil : (ids, acc)
                }
                guard let a = run(week: week, recent: []), let b = run(week: week + 1, recent: a.ids),
                      !b.accessories.isEmpty else { continue }
                out.append(WeekPair(
                    cell: "\(s)/\(p.rawValue)/\(e.rawValue)/\(eq.0)/\(days)lift/wk\(week)->\(week + 1)",
                    sport: s, tier: eq.0, phase: p, accessories: b.accessories, weekN: a.ids))
            } } }
        } } }
        Self.pairCache = out
        return out
    }

    /// Sport, phase and equipment cells where the shortfall backfill
    /// (`SportSeasonGenerator.swift:296-313`) fills a slot with last week's
    /// movement while a fresh one with the slot's primary demand is in the
    /// pool: backfill sorts on rejection, soreness and seed and has no
    /// recency tier. 403 of 3,294 repeats on 2026-11-18; adding
    /// `rotationTier` to that sort cleared all of them. Filed as 11c 3.8.
    /// A cell outside this list that breaks the contract fails, and a listed
    /// cell that holds fails so the list shrinks with the fix.
    static let knownBackfillRepeatCells: Set<String> = [
        "alpine-skiing/event_prep/homebar", "alpine-skiing/in_season/bw", "alpine-skiing/in_season/homebar",
        "alpine-skiing/maintenance/gym", "alpine-skiing/pre_season/bw",
        "ski-mountaineering/event_prep/bw", "ski-mountaineering/event_prep/homebar",
        "ski-mountaineering/maintenance/gym", "ski-mountaineering/maintenance/homebar",
        "ski-mountaineering/pre_season/homebar",
        "snow-sports/event_prep/bw", "snow-sports/event_prep/homebar", "snow-sports/in_season/bw",
        "snow-sports/in_season/homebar", "snow-sports/maintenance/gym", "snow-sports/maintenance/homebar",
        "snow-sports/pre_season/bw",
    ]

    /// The rotation contract (`SportSeasonGenerator` candidate sort): recency
    /// ranks below the primary-demand match, so a sport-session accessory may
    /// repeat from last week only when no movement whose primary demand is
    /// that slot's demand is fresh, unused in the session, no costlier than
    /// the repeat, and not cut by the in-season cost-5 cap. Holds on every
    /// tier, including bodyweight, where the pool is thin and repeats are
    /// common.
    func test_accessoryRepeatsOnlyWhenNoFreshPrimaryMovementExists() {
        let pairs = weekPairs()
        XCTAssertGreaterThan(pairs.count, 1000, "grid collapsed to \(pairs.count) week pairs")
        var checked = 0
        var badByCell: [String: [String]] = [:]
        for w in pairs {
            for a in w.accessories where w.weekN.contains(a.id) {
                checked += 1
                let cost = a.pool.first { $0.exerciseId == a.id }?.fatigueCost ?? 0
                let capsCostFive = w.phase == .inSeason || w.phase == .maintenance
                let fresh = a.pool.filter {
                    $0.primaryDemand == a.demand && !w.weekN.contains($0.exerciseId) && !a.session.contains($0.exerciseId)
                        && $0.fatigueCost <= cost && !(capsCostFive && $0.fatigueCost >= 5)
                }
                if !fresh.isEmpty {
                    badByCell["\(w.sport)/\(w.phase.rawValue)/\(w.tier)", default: []].append(
                        "\(w.cell) repeated \(a.id) for \(a.demand.rawValue) over fresh \(fresh.prefix(3).map(\.name))")
                }
            }
        }
        XCTAssertGreaterThan(checked, 0, "no repeated accessory anywhere: the check is vacuous")
        let unexpected = badByCell.filter { !Self.knownBackfillRepeatCells.contains($0.key) }.values.flatMap { $0 }
        XCTAssertTrue(unexpected.isEmpty, "\(unexpected.count) of \(checked) repeats had a fresh option:\n"
                      + unexpected.prefix(20).joined(separator: "\n"))
        for cell in Self.knownBackfillRepeatCells.sorted() where badByCell[cell] == nil {
            XCTFail("[\(cell)] no longer repeats over a fresh option: remove it from knownBackfillRepeatCells")
        }
    }

    /// With a gym or a home bar, the pool is deep enough that most accessories
    /// change week to week. Measured 2026-11-18 over 540 pairs per sport:
    /// gym max 0.44, home bar max 0.82, median 0.17 and 0.25 to 0.33.
    /// Bodyweight is out of scope for the share (median 0.60, max 1.0 on
    /// two-lift beginner weeks) and is held by the contract test above.
    func test_accessoryRepeatShareStaysUnderBound() {
        let bounds: [String: (median: Double, max: Double)] = ["gym": (0.25, 0.5), "homebar": (0.4, 0.85)]
        let pairs = weekPairs()
        for sport in Set(pairs.map(\.sport)).sorted() {
            for (tier, bound) in bounds {
                let cells = pairs.filter { $0.sport == sport && $0.tier == tier }
                XCTAssertFalse(cells.isEmpty, "[\(sport)/\(tier)] no week pairs")
                let shares = cells.map(\.share).sorted()
                let median = shares[shares.count / 2]
                XCTAssertLessThanOrEqual(median, bound.median, "[\(sport)/\(tier)] median repeat share \(median)")
                for c in cells where c.share > bound.max {
                    XCTFail("[\(c.cell)] repeated \(c.repeated) of \(Set(c.accessories.map(\.id)).count) accessories")
                }
            }
        }
    }
}
