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

/// 03 F7. The per-exercise maps were keyed by lowercased display name only, so
/// a session logged under a shorthand ("Bench Press") and a generated row
/// carrying the catalog's canonical name never matched. The fix is additive:
/// the raw key still works (every older test reads it) and an `id:` key is
/// mirrored when the catalog resolves the name.
@MainActor
final class ExerciseKeyTests: XCTestCase {

    func test_rawKeyStillWorks() {
        var map: [String: Int] = [:]
        ExerciseKey.store(1, name: "Totally Unknown Movement XYZ", into: &map)
        XCTAssertEqual(map["totally unknown movement xyz"], 1)
        XCTAssertEqual(ExerciseKey.lookup(map, name: "Totally Unknown Movement XYZ"), 1)
        XCTAssertEqual(map.count, 1, "no id key for a name the catalog cannot resolve")
    }

    func test_shorthandAndCanonicalNameShareAnEntry() throws {
        // Find a shorthand the catalog resolves to a DIFFERENT display name.
        let shorthand = "Bench Press"
        let resolved = try XCTUnwrap(ExerciseLookupCache.shared.exercise(forName: shorthand),
                                     "fixture needs a resolvable shorthand")
        var map: [String: Int] = [:]
        ExerciseKey.store(7, name: shorthand, into: &map)
        XCTAssertEqual(ExerciseKey.lookup(map, name: resolved.name), 7,
                       "'\(resolved.name)' must find the entry written as '\(shorthand)'")
        XCTAssertEqual(ExerciseKey.lookup(map, name: shorthand), 7)
    }

    func test_idKeyNeverOverwritesAnEarlierEntry() throws {
        let shorthand = "Bench Press"
        let resolved = try XCTUnwrap(ExerciseLookupCache.shared.exercise(forName: shorthand))
        var map: [String: Int] = [:]
        ExerciseKey.store(1, name: shorthand, into: &map)       // newest session, written first
        ExerciseKey.store(2, name: resolved.name, into: &map)   // older session under the canonical name
        XCTAssertEqual(map["id:\(resolved.id)"], 1, "the id key keeps the first (newest) entry")
        XCTAssertEqual(map[resolved.name.lowercased()], 2, "the raw key is per display name")
    }
}
