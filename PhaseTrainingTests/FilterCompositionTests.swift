import XCTest
@testable import PhaseTraining

/// The cross product nothing covered before this build.
///
/// Two filters shipped in two days and each got its own test with the other
/// one switched off. `testAuthoredPathNeverServesEquipmentTheUserLacks` runs
/// equipment tiers with no injuries. `testInjuryFilterNeverLeavesASession...`
/// runs injuries with `.fullGym`. `SeasonInvariantTests`'s 10-sport grid
/// carries an equipment dimension and no injury dimension at all.
///
/// So the user who declares both -- bodyweight only AND a bad knee, which is
/// an ordinary person, not an edge case -- was exercised by nothing. That is
/// where the ~3,187 injury rows from 1b and the substitute-or-drop pass from
/// R2-05 compose: a substitute has to clear the injury filter as well as the
/// equipment one, and a routine that survives either filter alone can still
/// fall under the movement floor once both run.
///
/// The contract asserted here is the whole promise the app makes about a
/// generated day, in one place:
///   1. a real session of at least `minimumMovements`, or
///   2. an empty day the app DECLARES and explains.
/// Anything else -- a two-movement session, a silent empty, a contraindicated
/// exercise, gear the user said they do not have -- fails.
final class FilterCompositionTests: XCTestCase {

    private static let declaredEmptyStates = ["authored-no-fit", "no-supported-sport"]

    /// The five common ones the grid started with, plus the twelve R3-11 gave
    /// rule coverage to on 2026-09-05 (they had one to ten curated rows each
    /// and nothing generated, so the filter barely fired for them before).
    private static let injuries = ["pfps", "lumbar-disc-herniation", "acl-injury",
                                   "shoulder-impingement", "achilles-tendinopathy",
                                   "rotator-cuff-injury", "wrist-sprain", "patellar-tendinopathy",
                                   "slap-tear", "hip-flexor-strain", "hip-labral-tear",
                                   "tennis-elbow", "golfers-elbow", "whiplash", "stinger-burner"]

    private static let gear: [[Equipment]] = [[.bodyweight], [.dumbbells], [.dumbbells, .pullUpBar]]

    /// Injuries the grid carries with fewer than `thinTagFloor` contraindication
    /// rows, and the count measured on 2026-11-18. Under the floor the filter
    /// removes so little that the grid passing says little about it. Each one
    /// needs curated rows before it leaves this list; one that reaches the
    /// floor has to come off it.
    private static let thinTagFloor = 20
    private static let thinTagReviewList: [String: Int] = [
        "tennis-elbow": 4, "stinger-burner": 5, "hip-flexor-strain": 10,
        "hip-labral-tear": 14, "wrist-sprain": 17, "golfers-elbow": 18,
    ]

    /// The recovery axis: no check-in, a mild one (eases the legs) and a high
    /// one (blocks them). Dated the session day so `MuscleRecovery` counts it.
    private enum Soreness: String, CaseIterable { case none, eased, blocked }
    private static let soreAreas = ["quads", "glutes"]

    private static func sessionDay() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11; c.hour = 8
        return Calendar.current.date(from: c)!
    }

    private static func checkIns(_ level: Soreness, on date: Date) -> [SorenessEntry] {
        switch level {
        case .none: return []
        case .eased: return [SorenessEntry(date: date, energy: "normal", soreness: "mild", areas: soreAreas)]
        case .blocked: return [SorenessEntry(date: date, energy: "normal", soreness: "high", areas: soreAreas)]
        }
    }

    func test_everyPlannableSportSurvivesInjuryAndEquipmentTogether() {
        // Snowboarding plans on the ski engine since Phase 3b and left the
        // authored-only list; it stays in the grid as the second engine ski.
        // Since 11e 1.1 the authored list holds every family sport, most with
        // no routines yet, so the grid takes the ones the picker offers.
        let plannable = SportCatalog.outdoorAuthoredSlugs.sorted().filter(SportCatalog.isPlannable)
            + ["alpine-skiing", "snowboarding", "climbing"]
        var checked = 0, declaredEmpty = 0
        let date = Self.sessionDay()
        var checkedBySoreness: [Soreness: Int] = [:]

        for slug in plannable {
            guard SportCatalog.isPlannable(slug) else {
                XCTFail("[\(slug)] listed as plannable content but isPlannable() says no")
                continue
            }
            for injury in Self.injuries {
                for equipment in Self.gear {
                    var memory = TrainingMemory()
                    memory.primarySport = Sport.resolve(slug: slug)
                    memory.userInjuries = [UserInjury(slug: injury)]
                    memory.equipment = equipment
                    let profile = DemographicProfile.from(memory)
                    let allowed = profile.allowedEquipmentSlugs
                    let excluded = profile.excludedExerciseIds

                    // Soreness rotates with slot and phase instead of
                    // multiplying the grid: every (sport, injury, gear, phase)
                    // cell still sees all three levels, and blocked lands on
                    // every slot across phases. The full product took 467 s
                    // and pushed CI past its 25-minute budget (2026-11-19).
                    for (phaseIndex, phase) in SeasonPhase.allCases.enumerated() {
                        memory.defaultSeason = phase
                        if let s = memory.primarySport { memory.seasonsBySport = [s: phase] }
                        for slot in 0..<3 {
                            let soreness = Soreness.allCases[(slot + phaseIndex) % Soreness.allCases.count]
                            memory.soreness = Self.checkIns(soreness, on: date)
                            let w = WorkoutGenerator.generateLift(
                                liftIndex: slot, totalLifts: 3, memory: memory, profile: profile,
                                hashSeed: "compose-\(slug)-\(injury)-\(phase.rawValue)-\(slot)",
                                date: date)
                            let ctx = "[\(slug)/\(injury)/\(equipment.map(\.rawValue).joined(separator: "+"))"
                                    + "/\(phase.rawValue)/\(soreness.rawValue)/slot \(slot)]"
                            checked += 1
                            checkedBySoreness[soreness, default: 0] += 1

                            if w.exercises.isEmpty {
                                declaredEmpty += 1
                                print("FILTER-COMPOSITION empty \(ctx) \(w.provenance)")
                                XCTAssertTrue(
                                    Self.declaredEmptyStates.contains(w.provenance),
                                    "\(ctx) empty day with provenance '\(w.provenance)' — an empty day "
                                    + "has to be one the app declares and explains")
                                XCTAssertFalse(w.summary.isEmpty, "\(ctx) empty day with no explanation")
                                continue
                            }

                            // Bodyweight ski days with quads and glutes blocked
                            // served two movements until 11c 3.7 topped them up.
                            XCTAssertGreaterThanOrEqual(
                                w.exercises.count, AuthoredRoutineSelector.minimumMovements,
                                "\(ctx) served \(w.exercises.count) movements: '\(w.title)'")

                            let reqs = CoachDatabase.shared.requiredEquipmentSlugs(
                                forExerciseIds: Set(w.exercises.map(\.exerciseId)))
                            for ex in w.exercises where ex.exerciseId > 0 {
                                XCTAssertFalse(excluded.contains(ex.exerciseId),
                                               "\(ctx) served contraindicated '\(ex.name)'")
                                let need = reqs[ex.exerciseId] ?? []
                                XCTAssertTrue(need.isEmpty || need.isSubset(of: allowed),
                                              "\(ctx) served '\(ex.name)' needing \(need)")
                            }
                            XCTAssertEqual(Set(w.exercises.map(\.exerciseId)).count, w.exercises.count,
                                           "\(ctx) duplicate movement in one session")
                            if soreness == .blocked {
                                let blocked = Set(Self.soreAreas)
                                let hit = w.exercises.filter {
                                    !WorkoutGenerator.primaryMuscleBuckets(exerciseId: $0.exerciseId)
                                        .isDisjoint(with: blocked)
                                }
                                XCTAssertTrue(hit.isEmpty,
                                              "\(ctx) served blocked prime movers \(hit.map(\.name))")
                            }
                        }
                    }
                }
            }
        }
        print("FILTER-COMPOSITION checked \(checked) days, \(declaredEmpty) of them declared-empty")
        XCTAssertGreaterThan(checked, 5000, "grid collapsed — the fixture is not exercising what it claims")
        for level in Soreness.allCases {
            XCTAssertEqual(checkedBySoreness[level], checked / Soreness.allCases.count,
                           "soreness axis '\(level.rawValue)' did not run its share of the grid")
        }
    }

    /// The recovery axis has to change something, or the blocked assertion
    /// above passes on a check-in nobody reads. Somewhere in the grid's
    /// sports, the same day without a check-in loads the legs.
    func test_sorenessAxisIsNotVacuous() {
        let date = Self.sessionDay()
        let legs = Set(Self.soreAreas)
        var openHits = 0, blockedHits = 0
        for slug in ["alpine-skiing", "snowboarding", "climbing"] {
            for level in [Soreness.none, .blocked] {
                var memory = TrainingMemory()
                memory.primarySport = Sport.resolve(slug: slug)
                memory.equipment = [.fullGym]
                memory.soreness = Self.checkIns(level, on: date)
                let profile = DemographicProfile.from(memory)
                for phase in SeasonPhase.allCases {
                    memory.defaultSeason = phase
                    if let s = memory.primarySport { memory.seasonsBySport = [s: phase] }
                    for slot in 0..<3 {
                        let w = WorkoutGenerator.generateLift(
                            liftIndex: slot, totalLifts: 3, memory: memory, profile: profile,
                            hashSeed: "sore-\(slug)-\(phase.rawValue)-\(slot)", date: date)
                        let n = w.exercises.filter {
                            !WorkoutGenerator.primaryMuscleBuckets(exerciseId: $0.exerciseId).isDisjoint(with: legs)
                        }.count
                        if level == .none { openHits += n } else { blockedHits += n }
                    }
                }
            }
        }
        XCTAssertGreaterThan(openHits, 0, "no session loads quads or glutes, so blocking them proves nothing")
        XCTAssertEqual(blockedHits, 0)
    }

    /// Every grid injury carries at least `thinTagFloor` contraindication rows,
    /// or sits on the review list with its measured count.
    func test_gridInjuriesCarryEnoughContraindicationRows() {
        let counts = CoachDatabase.shared.contraindicatedExerciseIds(bySlug: Set(Self.injuries))
        for injury in Self.injuries {
            let n = counts[injury]?.count ?? 0
            if let listed = Self.thinTagReviewList[injury] {
                XCTAssertLessThan(n, Self.thinTagFloor,
                                  "[\(injury)] has \(n) rows now; take it off thinTagReviewList")
                XCTAssertGreaterThanOrEqual(n, listed,
                                            "[\(injury)] lost rows: \(n), listed at \(listed)")
            } else {
                XCTAssertGreaterThanOrEqual(n, Self.thinTagFloor,
                                            "[\(injury)] has \(n) contraindication rows, under \(Self.thinTagFloor), "
                                            + "and is not on thinTagReviewList")
            }
        }
        for listed in Self.thinTagReviewList.keys {
            XCTAssertTrue(Self.injuries.contains(listed), "[\(listed)] on the review list but not in the grid")
        }
    }

    /// The lumbar filter removes something real: with no injury declared, the
    /// grid's sessions serve at least one exercise the lumbar rows
    /// contraindicate. Without that, "never serves a contraindicated
    /// exercise" holds for a filter that had nothing to remove.
    func test_lumbarFilterHasSomethingToRemove() {
        let injury = "lumbar-disc-herniation"
        let contraindicated = CoachDatabase.shared.contraindicatedExerciseIds(forInjurySlugs: [injury])
        XCTAssertFalse(contraindicated.isEmpty)
        let plannable = SportCatalog.outdoorAuthoredSlugs.sorted().filter(SportCatalog.isPlannable)
            + ["alpine-skiing", "snowboarding", "climbing"]
        var served: Set<Int> = []
        for slug in plannable {
            var memory = TrainingMemory()
            memory.primarySport = Sport.resolve(slug: slug)
            memory.equipment = [.fullGym]
            let profile = DemographicProfile.from(memory)
            for phase in SeasonPhase.allCases {
                memory.defaultSeason = phase
                if let s = memory.primarySport { memory.seasonsBySport = [s: phase] }
                for slot in 0..<3 {
                    let w = WorkoutGenerator.generateLift(
                        liftIndex: slot, totalLifts: 3, memory: memory, profile: profile,
                        hashSeed: "compose-\(slug)-none-\(phase.rawValue)-\(slot)")
                    served.formUnion(w.exercises.map(\.exerciseId))
                }
            }
        }
        let hit = served.intersection(contraindicated)
        print("FILTER-COMPOSITION lumbar filter off: \(hit.count) of \(contraindicated.count) contraindicated ids served")
        XCTAssertFalse(hit.isEmpty, "no lumbar-contraindicated exercise is served with the filter off")
    }
}
