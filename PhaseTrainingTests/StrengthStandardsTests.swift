import XCTest
@testable import PhaseTraining

final class StrengthStandardsTests: XCTestCase {

    // MARK: - Epley 1RM

    func test_epley_singleRep_isNoOp() {
        XCTAssertEqual(StrengthStandards.epley1RM(weight: 225, reps: 1), 225, accuracy: 0.001)
    }

    func test_epley_5rep_scalesUpByOneSixth() {
        // 225 × 5: Epley = 225 × (1 + 5/30) = 225 × 7/6 = 262.5
        XCTAssertEqual(StrengthStandards.epley1RM(weight: 225, reps: 5), 262.5, accuracy: 0.001)
    }

    func test_epley_zeroReps_returnsZero() {
        XCTAssertEqual(StrengthStandards.epley1RM(weight: 225, reps: 0), 0)
    }

    // MARK: - Lift matching

    func test_canonicalLift_matchesPermissively() {
        XCTAssertTrue(StrengthStandards.CanonicalLift.bench.matches(name: "Bench Press"))
        XCTAssertTrue(StrengthStandards.CanonicalLift.bench.matches(name: "Pause Bench Press"))
        XCTAssertTrue(StrengthStandards.CanonicalLift.squat.matches(name: "Back Squat"))
        XCTAssertTrue(StrengthStandards.CanonicalLift.deadlift.matches(name: "Conventional Deadlift"))
        XCTAssertTrue(StrengthStandards.CanonicalLift.pullup.matches(name: "Weighted Pull-Up"))
    }

    func test_canonicalLift_rejectsDisqualifiers() {
        // Anything that says "row" isn't a bench press.
        XCTAssertFalse(StrengthStandards.CanonicalLift.bench.matches(name: "Bench Row"))
        // Romanian deadlift is its own movement.
        XCTAssertFalse(StrengthStandards.CanonicalLift.deadlift.matches(name: "Romanian Deadlift"))
        // Goblet squat is a different stimulus.
        XCTAssertFalse(StrengthStandards.CanonicalLift.squat.matches(name: "Goblet Squat"))
    }

    // MARK: - Tier resolution

    func test_tier_nilWhenGenderSkipped() {
        XCTAssertNil(StrengthStandards.tier(for: .bench, ratio: 2.0, gender: nil))
    }

    func test_tier_climbsWithRatio_male() {
        // Male bench thresholds: 0.5, 0.75, 1.25, 1.75, 2.25
        XCTAssertNil(StrengthStandards.tier(for: .bench, ratio: 0.4, gender: .male))
        XCTAssertEqual(StrengthStandards.tier(for: .bench, ratio: 0.5, gender: .male), .novice)
        XCTAssertEqual(StrengthStandards.tier(for: .bench, ratio: 1.25, gender: .male), .intermediate)
        XCTAssertEqual(StrengthStandards.tier(for: .bench, ratio: 2.30, gender: .male), .elite)
    }

    // MARK: - rows()

    func test_rows_emptyWithoutBodyweight() {
        let sessions = [savedSession(name: "Bench Press", sets: [("225", "5")])]
        XCTAssertTrue(StrengthStandards.rows(from: sessions, bodyweightKg: nil, gender: .male).isEmpty)
    }

    func test_rows_findsBestEpleyAcrossSessions() {
        // 200×5 → Epley 233.3 ; 225×3 → Epley 247.5 → the 3-rep should win.
        let sessions = [
            savedSession(name: "Bench Press", sets: [("200", "5")]),
            savedSession(name: "Bench Press", sets: [("225", "3")]),
        ]
        let rows = StrengthStandards.rows(
            from: sessions,
            bodyweightKg: BodyMetrics.lbToKg(180), // 180 lb body
            gender: .male
        )
        XCTAssertEqual(rows.count, 1)
        guard let row = rows.first else { return XCTFail() }
        XCTAssertEqual(row.lift, .bench)
        XCTAssertEqual(row.bestWeightLb, 225, accuracy: 0.5)
        XCTAssertEqual(row.bestReps, 3)
        // 247.5 / 180 ≈ 1.375
        XCTAssertEqual(row.ratio, 1.375, accuracy: 0.01)
    }

    func test_rows_pullupAddsBodyweight() {
        // 20×8 added to 180lb body, Epley(200, 8) = 200 × (1 + 8/30) = 253.3.
        let sessions = [savedSession(name: "Weighted Pull-Up", sets: [("20", "8")])]
        let rows = StrengthStandards.rows(
            from: sessions,
            bodyweightKg: BodyMetrics.lbToKg(180),
            gender: .male
        )
        XCTAssertEqual(rows.first?.lift, .pullup)
        // bestWeightLb stores the BW-added weight per the doc-comment.
        XCTAssertEqual(rows.first?.bestWeightLb ?? 0, 200, accuracy: 0.5)
    }

    // MARK: - Helpers

    private func savedSession(name: String, sets: [(weight: String, reps: String)]) -> SavedSession {
        let logged = LoggedExercise(
            id: name, name: name, type: nil, unit: "lbs",
            targetSets: sets.count, targetReps: 5, rest: 90,
            sets: sets.enumerated().map { i, s in
                LoggedSet(num: i + 1, weight: s.weight, reps: s.reps, rpe: "", done: true)
            },
            prevSets: []
        )
        return SavedSession(
            templateId: "t", name: name, category: "",
            startTime: Date().addingTimeInterval(-3600),
            exercises: [logged], feel: nil, note: nil,
            endTime: Date(), duration: 3600
        )
    }
}
