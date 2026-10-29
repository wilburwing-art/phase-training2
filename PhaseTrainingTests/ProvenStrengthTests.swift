import XCTest
@testable import PhaseTraining

/// The proven-strength rule: median of the 3 most recent workouts, each
/// discounted for age (none for 4 weeks, then 1%/week, floor 75%).
final class ProvenStrengthTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }
    private func ev(_ d: Double, _ w: Double, _ r: Int) -> ProvenStrength.Evidence {
        .init(date: daysAgo(d), weightLb: w, reps: r)
    }
    private func e1rm(_ p: PriorBest?) -> Double {
        p.map { StrengthStandards.epley1RM(weight: $0.weight, reps: $0.reps) } ?? 0
    }
    private func epley(_ w: Double, _ r: Int) -> Double { StrengthStandards.epley1RM(weight: w, reps: r) }

    func test_ageFactor_graceThenOnePercentAWeek_flooredAt75() {
        XCTAssertEqual(ProvenStrength.ageFactor(days: 0), 1)
        XCTAssertEqual(ProvenStrength.ageFactor(days: 28), 1)
        XCTAssertEqual(ProvenStrength.ageFactor(days: 35), 0.99, accuracy: 1e-9)
        XCTAssertEqual(ProvenStrength.ageFactor(days: 7 * 14), 0.90, accuracy: 1e-9)
        XCTAssertEqual(ProvenStrength.ageFactor(days: 7 * 200), 0.75)
    }

    func test_anOldPeakNeverComesBack() {
        // A 2017-style peak, then three recent ordinary workouts.
        let est = ProvenStrength.estimate([
            ev(3000, 397, 4),
            ev(20, 135, 10), ev(13, 135, 8), ev(6, 130, 10),
        ], now: now)
        XCTAssertEqual(e1rm(est), epley(130, 10), accuracy: 0.01, "median of 180, 171, 173.3; the peak is not among them")
    }

    func test_oneLightDayOrOneTypo_doesNotMoveTheMedian() {
        let light = ProvenStrength.estimate([ev(15, 225, 5), ev(8, 225, 5), ev(1, 135, 5)], now: now)
        XCTAssertEqual(e1rm(light), epley(225, 5), accuracy: 0.01)
        let typo = ProvenStrength.estimate([ev(15, 225, 5), ev(8, 225, 5), ev(1, 2250, 5)], now: now)
        XCTAssertEqual(e1rm(typo), epley(225, 5), accuracy: 0.01)
    }

    func test_twoWorkoutsAverage_oneWorkoutStands() {
        XCTAssertEqual(e1rm(ProvenStrength.estimate([ev(9, 200, 5), ev(2, 220, 5)], now: now)),
                       (epley(200, 5) + epley(220, 5)) / 2, accuracy: 0.01)
        XCTAssertEqual(e1rm(ProvenStrength.estimate([ev(2, 220, 5)], now: now)), epley(220, 5), accuracy: 0.01)
    }

    func test_aLongLayoffStartsLower_neverBelowTheFloor() {
        let est = ProvenStrength.estimate([ev(300, 180, 5), ev(293, 180, 5), ev(286, 180, 5)], now: now)
        XCTAssertEqual(e1rm(est), epley(180, 5) * 0.75, accuracy: 0.01)
    }

    func test_warmupsAndHighRepSetsAreNotEvidence() {
        XCTAssertNil(ProvenStrength.estimate([ev(2, 50, 20), ev(3, 0, 10)], now: now))
        // The workout's best is its best usable set.
        let est = ProvenStrength.estimate([ev(2, 100, 20), ev(2, 90, 10)], now: now)
        XCTAssertEqual(e1rm(est), epley(90, 10), accuracy: 0.01)
    }

    func test_estimateIsReadAtTheLatestWorkoutsReps() {
        let est = ProvenStrength.estimate([ev(9, 200, 3), ev(2, 180, 8)], now: now)
        XCTAssertEqual(est?.reps, 8)
        XCTAssertEqual(est?.date, daysAgo(2))
    }

    func test_index_poolsNativeAndImported_kgToLb() throws {
        let coach = CoachDatabase.shared
        guard let benchId = coach.exerciseId(forImportName: "Barbell Bench Press"),
              let name = coach.exercise(id: benchId)?.name else {
            throw XCTSkip("catalog does not resolve Barbell Bench Press")
        }
        let native = SavedSession(
            templateId: "t", name: "s", category: "c", startTime: daysAgo(2),
            exercises: [LoggedExercise(id: "a", name: name, type: nil, unit: "lbs", targetSets: 1, targetReps: 5, rest: 90,
                                       sets: [LoggedSet(num: 1, weight: "200", reps: "5", rpe: "", done: true)], prevSets: [])],
            feel: nil, note: nil, endTime: daysAgo(2), duration: 1800)
        let imported = [ImportedSet(id: "x", source: .fitbodCSV, exerciseId: benchId, exerciseNameRaw: "Barbell Bench Press",
                                    performedAt: daysAgo(9), setNum: 1, weight: 100, reps: 5, rir: nil, rpe: nil)]
        let index = HistoryProfile.build(sessions: [native], imported: imported, now: now).priorBest
        let est = try XCTUnwrap(ExerciseKey.lookup(index, name: name))
        let importedLb = 100 / ImportUnitCorrection.kgPerLb
        XCTAssertEqual(e1rm(est), (epley(200, 5) + epley(importedLb, 5)) / 2, accuracy: 0.01)
    }

    func test_fromHistory_mapsToTargetReps_andSnapsDown() throws {
        let prior = PriorBest(weight: 135, reps: 10, date: now)   // e1RM 180
        let lb = try XCTUnwrap(ProgressionSuggestion.fromHistory(prior, targetReps: 8, unit: "lbs"))
        XCTAssertEqual(lb.suggestedWeight, 140, "180 / (1 + 8/30) = 142.1, snapped down to 140")
        let kg = try XCTUnwrap(ProgressionSuggestion.fromHistory(prior, targetReps: 8, unit: "kg"))
        XCTAssertEqual(kg.suggestedWeight.truncatingRemainder(dividingBy: 1.25), 0, accuracy: 1e-9)
        XCTAssertNil(ProgressionSuggestion.fromHistory(PriorBest(weight: 0, reps: 12, date: now), targetReps: 8, unit: "lbs"))
        // A kg round-trip must not knock an exact load down a step.
        let roundTripped = 225 * ImportUnitCorrection.kgPerLb / ImportUnitCorrection.kgPerLb
        let exact = ProgressionSuggestion.fromHistory(PriorBest(weight: roundTripped, reps: 5, date: now),
                                                      targetReps: 5, unit: "lbs")
        XCTAssertEqual(exact?.suggestedWeight, 225)
    }
}
