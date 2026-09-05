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

    func test_everyPlannableSportSurvivesInjuryAndEquipmentTogether() {
        let plannable = SportCatalog.outdoorAuthoredSlugs.sorted()
            + ["alpine-skiing", "climbing"]
        var checked = 0, declaredEmpty = 0

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

                    for phase in SeasonPhase.allCases {
                        memory.defaultSeason = phase
                        if let s = memory.primarySport { memory.seasonsBySport = [s: phase] }
                        for slot in 0..<3 {
                            let w = WorkoutGenerator.generateLift(
                                liftIndex: slot, totalLifts: 3, memory: memory, profile: profile,
                                hashSeed: "compose-\(slug)-\(injury)-\(phase.rawValue)-\(slot)")
                            let ctx = "[\(slug)/\(injury)/\(equipment.map(\.rawValue).joined(separator: "+"))"
                                    + "/\(phase.rawValue)/slot \(slot)]"
                            checked += 1

                            if w.exercises.isEmpty {
                                declaredEmpty += 1
                                XCTAssertTrue(
                                    Self.declaredEmptyStates.contains(w.provenance),
                                    "\(ctx) empty day with provenance '\(w.provenance)' — an empty day "
                                    + "has to be one the app declares and explains")
                                XCTAssertFalse(w.summary.isEmpty, "\(ctx) empty day with no explanation")
                                continue
                            }

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
                        }
                    }
                }
            }
        }
        print("FILTER-COMPOSITION checked \(checked) days, \(declaredEmpty) of them declared-empty")
        XCTAssertGreaterThan(checked, 5000, "grid collapsed — the fixture is not exercising what it claims")
    }
}
