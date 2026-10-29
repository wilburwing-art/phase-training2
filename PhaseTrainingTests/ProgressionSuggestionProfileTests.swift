import XCTest
@testable import PhaseTraining

/// The history-aware suggestion behind the Log pill and the Today tile:
/// rep-gap remap, plateau "add a rep", and the lifter's own weight step.
final class ProgressionSuggestionProfileTests: XCTestCase {

    private let now = Date()

    private func sets(_ w: Double, _ r: Int, count: Int = 3) -> [LoggedSet] {
        (1...count).map { LoggedSet(num: $0, weight: "\(w)", reps: "\(r)", rpe: "", done: true) }
    }

    private func profile(estimate: PriorBest? = nil, step: Double? = nil, plateau: Bool = false)
        -> HistoryProfile.ExerciseProfile {
        .init(name: "x", estimate: estimate, trend: plateau ? .flat(0) : .unknown, plateau: plateau,
              typicalStepLb: step, lastTrained: now, bestE1RM: 0, bestDate: now, workouts: 6, excludedSets: 0,
              latestBest: .init(date: now, weightLb: 0, reps: 0), recentBests: [])
    }

    private func suggest(_ prev: [LoggedSet], target: Int, name: String = "Barbell Back Squat",
                         unit: String = "lbs", profile p: HistoryProfile.ExerciseProfile?) -> ProgressionSuggestion.Result? {
        ProgressionSuggestion.suggest(prevSets: prev, targetReps: target, exerciseName: name, unit: unit, profile: p)
    }

    func test_noProfile_isTheOldRule() {
        let old = ProgressionSuggestion.suggest(prevSets: sets(185, 5), targetReps: 5, exerciseName: "Barbell Back Squat", unit: "lbs")
        XCTAssertEqual(suggest(sets(185, 5), target: 5, profile: nil), old)
        XCTAssertEqual(old?.suggestedWeight, 190)
    }

    func test_sameReps_useTheLinearRule() {
        let r = suggest(sets(185, 5), target: 6, profile: profile(estimate: PriorBest(weight: 185, reps: 5, date: now)))
        XCTAssertEqual(r?.basis, .lastSession)
        XCTAssertEqual(r?.suggestedWeight, 185, "5 reps against a 6-rep target is a miss by 1: hold")
    }

    func test_aRepGap_mapsTheEstimateToTodaysReps() throws {
        // Last time 135 x 10 (e1RM 180); today asks for 5.
        let est = PriorBest(weight: 135, reps: 10, date: now)
        let r = try XCTUnwrap(suggest(sets(135, 10), target: 5, profile: profile(estimate: est)))
        XCTAssertEqual(r.basis, .repRemap)
        XCTAssertEqual(r.label, "for 5 reps")
        XCTAssertEqual(r.suggestedWeight, ProgressionSuggestion.fromHistory(est, targetReps: 5, unit: "lbs")?.suggestedWeight)
        XCTAssertGreaterThan(r.suggestedWeight, 140, "the old rule said 140, too light for 5 reps")
        // The other direction: a lighter load for more reps.
        let more = try XCTUnwrap(suggest(sets(225, 5), target: 12, profile: profile(estimate: PriorBest(weight: 225, reps: 5, date: now))))
        XCTAssertEqual(more.basis, .repRemap)
        XCTAssertLessThan(more.suggestedWeight, 225)
    }

    func test_personalStep_replacesTheTable() {
        // Dumbbell curl: table says +2.5, the lifter's dumbbells go up by 5.
        let r = suggest(sets(25, 10), target: 10, name: "Dumbbell Curl", profile: profile(step: 5))
        XCTAssertEqual(r?.suggestedWeight, 30)
        XCTAssertEqual(r?.label, "+5")
        let backOff = suggest(sets(25, 6), target: 10, name: "Dumbbell Curl", profile: profile(step: 5))
        XCTAssertEqual(backOff?.suggestedWeight, 20)
    }

    func test_personalStep_capsAJumpTooBigForTheWeight() {
        // A 20 lb step on a 60 lb lift: bigger than 2x table (5) and 10% (6) -> table.
        XCTAssertEqual(ProgressionSuggestion.personalStep(profile: profile(step: 20), workingWeight: 60, unit: "lbs", compound: false), 2.5)
        // On a 225 lb squat a 10 lb step is fine (<= 22.5).
        XCTAssertEqual(ProgressionSuggestion.personalStep(profile: profile(step: 10), workingWeight: 225, unit: "lbs", compound: true), 10)
    }

    func test_personalStep_inKg_snapsTo1_25() {
        XCTAssertEqual(ProgressionSuggestion.personalStep(profile: profile(step: 5), workingWeight: 60, unit: "kg", compound: true), 2.5)
        XCTAssertEqual(ProgressionSuggestion.personalStep(profile: profile(step: 2.5), workingWeight: 20, unit: "kg", compound: false), 1.25)
    }

    func test_plateau_addsARep_onlyWhenTheTargetWasHit() {
        let hit = suggest(sets(185, 5), target: 5, profile: profile(step: 5, plateau: true))
        XCTAssertEqual(hit?.basis, .addRep)
        XCTAssertEqual(hit?.suggestedWeight, 185)
        let missed = suggest(sets(185, 3), target: 5, profile: profile(step: 5, plateau: true))
        XCTAssertEqual(missed?.basis, .lastSession)
        XCTAssertEqual(missed?.suggestedWeight, 180, "missed by 2 backs off as before")
    }
}
