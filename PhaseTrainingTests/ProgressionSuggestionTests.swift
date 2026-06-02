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

    // MARK: - priorPerformance extraction (pyramid / top-set fix)

    private func set(_ weight: String, _ reps: String, done: Bool = true, warmup: Bool = false) -> LoggedSet {
        LoggedSet(num: 1, weight: weight, reps: reps, rpe: "", done: done, isWarmup: warmup)
    }

    func test_priorPerformance_pyramidPicksHeaviestSetThatMetTarget() {
        // Heavy top single 200×3 then working 185×8×8, target 8. The OLD
        // logic picked 200/3 -> "missed by 5 -> BACK OFF". The fix picks the
        // heaviest set that hit 8 reps (185) -> a clean bump.
        let prev = [set("200", "3"), set("185", "8"), set("185", "8")]
        let prior = ProgressionSuggestion.priorPerformance(from: prev, targetReps: 8)!
        XCTAssertEqual(prior.weight, 185)
        XCTAssertEqual(prior.repsAchieved, 8)
        let r = ProgressionSuggestion.suggest(prevSets: prev, targetReps: 8, exerciseName: "Bench Press", unit: "lb")!
        XCTAssertGreaterThan(r.delta, 0, "pyramid should suggest a bump, not a back-off")
    }

    func test_priorPerformance_straightSetsUnchanged() {
        let prev = [set("135", "5"), set("135", "5"), set("135", "5")]
        let prior = ProgressionSuggestion.priorPerformance(from: prev, targetReps: 5)!
        XCTAssertEqual(prior.weight, 135)
        XCTAssertEqual(prior.repsAchieved, 5)
    }

    func test_priorPerformance_allMissed_fallsBackToHeaviest() {
        // No set hit target 8 — user genuinely failed. Fall back to the
        // heaviest set so the suggestion is a hold/back-off.
        let prev = [set("185", "5"), set("185", "4"), set("175", "6")]
        let prior = ProgressionSuggestion.priorPerformance(from: prev, targetReps: 8)!
        XCTAssertEqual(prior.weight, 185)
        XCTAssertEqual(prior.repsAchieved, 5)  // the heaviest set's reps
    }

    func test_priorPerformance_excludesWarmupsAndUndone() {
        let prev = [
            set("225", "1", warmup: true),   // warmup — ignore even though heaviest
            set("185", "8"),
            set("205", "8", done: false),    // not done — ignore
        ]
        let prior = ProgressionSuggestion.priorPerformance(from: prev, targetReps: 8)!
        XCTAssertEqual(prior.weight, 185)
    }

    func test_priorPerformance_nilWhenNoUsableSets() {
        XCTAssertNil(ProgressionSuggestion.priorPerformance(from: [], targetReps: 5))
        XCTAssertNil(ProgressionSuggestion.priorPerformance(from: [set("", "")], targetReps: 5))
    }

    func test_suggestedWeightString_formatsTidily() {
        let bump = ProgressionSuggestion.PriorPerformance(weight: 185, repsAchieved: 5, targetReps: 5)
        let r = ProgressionSuggestion.suggest(prior: bump, exerciseName: "Bench Press", unit: "lb")!
        XCTAssertEqual(r.suggestedWeightString, "190")
        let iso = ProgressionSuggestion.PriorPerformance(weight: 25, repsAchieved: 10, targetReps: 10)
        let r2 = ProgressionSuggestion.suggest(prior: iso, exerciseName: "Lateral Raise", unit: "lb")!
        XCTAssertEqual(r2.suggestedWeightString, "27.5")
    }
}
