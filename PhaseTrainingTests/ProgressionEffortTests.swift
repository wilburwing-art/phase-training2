import XCTest
@testable import PhaseTraining

/// Logged effort (RIR, or 10 minus RPE) on last session's top set steers the
/// next weight when the reps were hit, and RIR now survives a save.
final class ProgressionEffortTests: XCTestCase {

    private func set(_ w: String, _ r: String, rpe: String = "", rir: String = "", num: Int = 1) -> LoggedSet {
        LoggedSet(num: num, weight: w, reps: r, rpe: rpe, done: true, rir: rir)
    }

    private func suggest(_ sets: [LoggedSet], target: Int = 5, name: String = "Back Squat",
                         unit: String = "lbs") -> ProgressionSuggestion.Result? {
        ProgressionSuggestion.suggest(prevSets: sets, targetReps: target, exerciseName: name, unit: unit)
    }

    func test_effortReadsRIRFirst_thenTenMinusRPE() {
        XCTAssertEqual(set("225", "5", rpe: "8", rir: "3").effortRIR, 3)
        XCTAssertEqual(set("225", "5", rpe: "7").effortRIR, 3)
        XCTAssertEqual(set("225", "5", rpe: "9.5").effortRIR, 0.5)
        XCTAssertNil(set("225", "5").effortRIR)
        XCTAssertNil(set("225", "5", rpe: "12").effortRIR, "an RPE above 10 is a typo, not effort")
    }

    func test_easyHitDoublesTheStep() throws {
        let r = try XCTUnwrap(suggest([set("225", "5", rir: "3")]))
        XCTAssertEqual(r.suggestedWeight, 235)
        XCTAssertEqual(r.label, "+10")
        let viaRPE = try XCTUnwrap(suggest([set("225", "5", rpe: "7")]))
        XCTAssertEqual(viaRPE.suggestedWeight, 235, "RPE 7 reads as 3 in reserve")
    }

    func test_biggerJumpIsCapped_onALightLift() throws {
        // Isolation step 2.5; doubled 5 is within max(2 x 2.5, 10% of 20) = 5.
        let curl = try XCTUnwrap(suggest([set("20", "10", rir: "4")], target: 10, name: "Lateral Raise"))
        XCTAssertEqual(curl.suggestedWeight, 25)
        // A personal step of 10 on a 60 lb lift: doubled 20 exceeds max(10, 6) = 10, so the cap holds it.
        let prior = ProgressionSuggestion.PriorPerformance(weight: 60, repsAchieved: 8, targetReps: 8, rir: 4)
        let capped = try XCTUnwrap(ProgressionSuggestion.suggest(prior: prior, exerciseName: "Back Squat",
                                                                 unit: "lbs", bump: 10))
        XCTAssertEqual(capped.delta, 10, "never more than the personalStep ceiling")
    }

    func test_failureOnAHitHolds() throws {
        let r = try XCTUnwrap(suggest([set("225", "5", rpe: "10")]))
        XCTAssertEqual(r.suggestedWeight, 225)
        XCTAssertEqual(r.label, "hold")
        XCTAssertEqual(try XCTUnwrap(suggest([set("225", "5", rir: "0")])).label, "hold")
    }

    func test_moderateOrUnloggedEffortKeepsTheOldRule() throws {
        XCTAssertEqual(try XCTUnwrap(suggest([set("225", "5", rir: "2")])).suggestedWeight, 230)
        XCTAssertEqual(try XCTUnwrap(suggest([set("225", "5", rpe: "8")])).suggestedWeight, 230)
        XCTAssertEqual(try XCTUnwrap(suggest([set("225", "5")])).suggestedWeight, 230)
    }

    func test_aMissIgnoresEffort() throws {
        XCTAssertEqual(try XCTUnwrap(suggest([set("225", "4", rir: "4")])).label, "hold", "missed by 1 holds")
        XCTAssertEqual(try XCTUnwrap(suggest([set("225", "3", rir: "4")])).suggestedWeight, 220, "missed by 2 backs off")
    }

    func test_rirSurvivesASaveAndReload() throws {
        let db = UserDatabase(path: ":memory:")
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let ex = LoggedExercise(id: "e", name: "Back Squat", type: nil, unit: "lbs", targetSets: 2, targetReps: 5,
                                rest: 120, sets: [set("225", "5", rir: "3"), set("225", "5", num: 2)], prevSets: [])
        XCTAssertTrue(db.saveSession(SavedSession(templateId: "t", name: "Legs", category: "lift", startTime: start,
                                                  exercises: [ex], feel: nil, note: nil,
                                                  endTime: start.addingTimeInterval(3600), duration: 3600)))
        let back = try XCTUnwrap(db.listSavedSessions().first?.exercises.first)
        XCTAssertEqual(back.sets.map(\.rir), ["3", ""])
    }
}
