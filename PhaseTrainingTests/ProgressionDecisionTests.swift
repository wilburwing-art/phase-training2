import XCTest
@testable import PhaseTraining

/// T2-9. `progressiveOverloadHint` stepped the load up 2.5% from the all-time
/// best on every call, with no branch for a missed attempt, soreness or a
/// deload. This is the decision table that now sits in front of the step.
final class ProgressionDecisionTests: XCTestCase {

    private let prior = PriorBest(weight: 200, reps: 5, date: Date())
    private func last(_ w: Double, _ reps: Int, target: Int = 5) -> LastAttempt {
        LastAttempt(weight: w, reps: reps, targetReps: target, date: Date())
    }

    func test_noHistoryStepsUp() {
        XCTAssertEqual(ProgressionDecision.decide(prior: prior, last: nil), .stepUp)
    }

    func test_hitTargetAtBestWeightStepsUp() {
        XCTAssertEqual(ProgressionDecision.decide(prior: prior, last: last(200, 5)), .stepUp)
        XCTAssertEqual(ProgressionDecision.decide(prior: prior, last: last(205, 6)), .stepUp)
    }

    func test_missedByOneHolds() {
        XCTAssertEqual(ProgressionDecision.decide(prior: prior, last: last(200, 4)), .hold)
    }

    func test_missedByTwoOrMoreStepsDown() {
        XCTAssertEqual(ProgressionDecision.decide(prior: prior, last: last(200, 3)), .stepDown)
        XCTAssertEqual(ProgressionDecision.decide(prior: prior, last: last(200, 1)), .stepDown)
    }

    func test_lighterDayIsNotEvidenceAboutTheBest() {
        // A deload, travel day or accessory-weight session at 150 for 3 says
        // nothing about whether 200 is still there.
        XCTAssertEqual(ProgressionDecision.decide(prior: prior, last: last(150, 3)), .stepUp)
    }

    func test_zeroTargetRepsIsIgnored() {
        XCTAssertEqual(ProgressionDecision.decide(prior: prior, last: last(200, 0, target: 0)), .stepUp)
    }

    func test_targetLb_appliesTheDecision() {
        let up   = WorkoutGenerator.targetLb(priorWeight: 200, priorReps: 5, prescribedReps: "8", decision: .stepUp)
        let hold = WorkoutGenerator.targetLb(priorWeight: 200, priorReps: 5, prescribedReps: "8", decision: .hold)
        let down = WorkoutGenerator.targetLb(priorWeight: 200, priorReps: 5, prescribedReps: "8", decision: .stepDown)
        XCTAssertGreaterThan(up, hold)
        XCTAssertGreaterThan(hold, down)
        for v in [up, hold, down] {
            XCTAssertEqual(v.truncatingRemainder(dividingBy: 2.5), 0, "loads land on a 2.5-lb plate step")
        }
    }

    func test_buildLastAttempt_takesHeaviestWorkingSetOfMostRecentSession() {
        func set(_ w: String, _ r: String, warm: Bool = false) -> LoggedSet {
            LoggedSet(num: 1, weight: w, reps: r, rpe: "", done: true, isWarmup: warm)
        }
        func ex(_ sets: [LoggedSet], target: Int) -> LoggedExercise {
            LoggedExercise(id: "sq", name: "Back Squat", type: "Barbell", unit: "lbs",
                           targetSets: sets.count, targetReps: target, rest: 120,
                           sets: sets, prevSets: [])
        }
        let older = SavedSession(templateId: "t", name: "n", category: "c",
                                 startTime: Date(timeIntervalSince1970: 1_000),
                                 exercises: [ex([set("225", "5")], target: 5)],
                                 feel: nil, note: nil, endTime: Date(timeIntervalSince1970: 2_000), duration: 1_000)
        let newer = SavedSession(templateId: "t", name: "n", category: "c",
                                 startTime: Date(timeIntervalSince1970: 5_000),
                                 exercises: [ex([set("135", "8", warm: true), set("230", "3"), set("230", "4")], target: 5)],
                                 feel: nil, note: nil, endTime: Date(timeIntervalSince1970: 6_000), duration: 1_000)
        let la = GeneratorContext.buildLastAttempt(sessions: [older, newer])["back squat"]
        XCTAssertEqual(la?.weight, 230)
        XCTAssertEqual(la?.reps, 4, "best reps AT the heaviest weight, warmup excluded")
        XCTAssertEqual(la?.targetReps, 5)
    }
}
