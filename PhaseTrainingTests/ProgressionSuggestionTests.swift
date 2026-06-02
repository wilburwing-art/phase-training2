import XCTest
@testable import PhaseTraining

/// Build 103 — ProgressionSuggestion turns last-session top-set into a
/// concrete +5 / hold / -5 hint so the user sees progressive overload as a
/// visible story on the Today exercise tile.
final class ProgressionSuggestionTests: XCTestCase {

    func test_compoundDetection_byKeyword() {
        XCTAssertTrue(ProgressionSuggestion.isCompound(name: "Barbell Back Squat"))
        XCTAssertTrue(ProgressionSuggestion.isCompound(name: "Conventional Deadlift"))
        XCTAssertTrue(ProgressionSuggestion.isCompound(name: "Bench Press"))
        XCTAssertTrue(ProgressionSuggestion.isCompound(name: "Pull-Up"))
        XCTAssertFalse(ProgressionSuggestion.isCompound(name: "Lateral Raise"))
        XCTAssertFalse(ProgressionSuggestion.isCompound(name: "Bicep Curl"))
        XCTAssertFalse(ProgressionSuggestion.isCompound(name: "Tricep Pushdown"))
    }

    func test_bumpTable_byUnitAndCompound() {
        XCTAssertEqual(ProgressionSuggestion.bumpFor(unit: "lb", compound: true), 5.0)
        XCTAssertEqual(ProgressionSuggestion.bumpFor(unit: "lb", compound: false), 2.5)
        XCTAssertEqual(ProgressionSuggestion.bumpFor(unit: "kg", compound: true), 2.5)
        XCTAssertEqual(ProgressionSuggestion.bumpFor(unit: "kg", compound: false), 1.25)
        // Unknown unit falls back to lb.
        XCTAssertEqual(ProgressionSuggestion.bumpFor(unit: "stone", compound: true), 5.0)
    }

    func test_suggest_nilWithoutPrior() {
        XCTAssertNil(ProgressionSuggestion.suggest(prior: nil, exerciseName: "Bench Press", unit: "lb"))
    }

    func test_suggest_hitRepsExactly_bumpsCompound5() {
        let prior = ProgressionSuggestion.PriorPerformance(weight: 185, repsAchieved: 5, targetReps: 5)
        let r = ProgressionSuggestion.suggest(prior: prior, exerciseName: "Bench Press", unit: "lb")!
        XCTAssertEqual(r.suggestedWeight, 190)
        XCTAssertEqual(r.delta, 5)
        XCTAssertEqual(r.label, "+5")
    }

    func test_suggest_hitRepsExactly_bumpsIsolation2_5() {
        let prior = ProgressionSuggestion.PriorPerformance(weight: 25, repsAchieved: 10, targetReps: 10)
        let r = ProgressionSuggestion.suggest(prior: prior, exerciseName: "Lateral Raise", unit: "lb")!
        XCTAssertEqual(r.suggestedWeight, 27.5)
        XCTAssertEqual(r.delta, 2.5)
        XCTAssertEqual(r.label, "+2.5")
    }

    func test_suggest_beatReps_stillBumps() {
        // User did 6 when target was 5 — that's still a bump.
        let prior = ProgressionSuggestion.PriorPerformance(weight: 185, repsAchieved: 6, targetReps: 5)
        let r = ProgressionSuggestion.suggest(prior: prior, exerciseName: "Bench Press", unit: "lb")!
        XCTAssertEqual(r.delta, 5)
    }

    func test_suggest_missedByOne_holds() {
        let prior = ProgressionSuggestion.PriorPerformance(weight: 185, repsAchieved: 4, targetReps: 5)
        let r = ProgressionSuggestion.suggest(prior: prior, exerciseName: "Bench Press", unit: "lb")!
        XCTAssertEqual(r.suggestedWeight, 185)
        XCTAssertEqual(r.delta, 0)
        XCTAssertEqual(r.label, "hold")
    }

    func test_suggest_missedByTwo_backsOff() {
        let prior = ProgressionSuggestion.PriorPerformance(weight: 185, repsAchieved: 3, targetReps: 5)
        let r = ProgressionSuggestion.suggest(prior: prior, exerciseName: "Bench Press", unit: "lb")!
        XCTAssertEqual(r.suggestedWeight, 180)
        XCTAssertEqual(r.delta, -5)
        XCTAssertEqual(r.label, "−5")
    }

    func test_suggest_metricUnits_compoundUses2_5kg() {
        let prior = ProgressionSuggestion.PriorPerformance(weight: 80, repsAchieved: 5, targetReps: 5)
        let r = ProgressionSuggestion.suggest(prior: prior, exerciseName: "Squat", unit: "kg")!
        XCTAssertEqual(r.suggestedWeight, 82.5)
        XCTAssertEqual(r.delta, 2.5)
    }

    func test_suggest_metricUnits_isolationUses1_25kg() {
        let prior = ProgressionSuggestion.PriorPerformance(weight: 10, repsAchieved: 12, targetReps: 12)
        let r = ProgressionSuggestion.suggest(prior: prior, exerciseName: "Lateral Raise", unit: "kg")!
        XCTAssertEqual(r.suggestedWeight, 11.25)
        XCTAssertEqual(r.delta, 1.25)
    }

    func test_backoff_clampsAtZero() {
        let prior = ProgressionSuggestion.PriorPerformance(weight: 2, repsAchieved: 0, targetReps: 5)
        let r = ProgressionSuggestion.suggest(prior: prior, exerciseName: "Lateral Raise", unit: "lb")!
        XCTAssertGreaterThanOrEqual(r.suggestedWeight, 0)
    }
}
