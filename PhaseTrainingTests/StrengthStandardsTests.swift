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
        // bestWeightLb is what the user actually LOGGED (+20), not the
        // bodyweight-inclusive figure used for the estimate. The card renders
        // it as "from your 20 × 8"; showing 200 presented an internal quantity
        // as a set the user entered. The doc comment always said "actually
        // logged" — the code and this assertion were the things out of step.
        XCTAssertEqual(rows.first?.bestWeightLb ?? 0, 20, accuracy: 0.5)
        // The estimate still includes bodyweight, so the 1RM stays well above
        // the logged load.
        XCTAssertGreaterThan(rows.first?.oneRepMaxLb ?? 0, 200)
    }

    /// A 95×5 warmup must not flag as the user's "best bench"; only the
    /// working set counts toward Epley + tier resolution.
    func test_rows_ignoresWarmupSets() {
        let logged = LoggedExercise(
            id: "Bench Press", name: "Bench Press", type: nil, unit: "lbs",
            targetSets: 2, targetReps: 5, rest: 90,
            sets: [
                LoggedSet(num: 1, weight: "95",  reps: "5", rpe: "", done: true, isWarmup: true),
                LoggedSet(num: 2, weight: "225", reps: "5", rpe: "", done: true, isWarmup: false),
            ],
            prevSets: []
        )
        let session = SavedSession(
            templateId: "t", name: "Bench Press", category: "",
            startTime: Date().addingTimeInterval(-3600),
            exercises: [logged], feel: nil, note: nil,
            endTime: Date(), duration: 3600
        )
        let rows = StrengthStandards.rows(
            from: [session],
            bodyweightKg: BodyMetrics.lbToKg(180),
            gender: .male
        )
        guard let row = rows.first else { return XCTFail("Expected a Bench Press row") }
        XCTAssertEqual(row.bestWeightLb, 225, accuracy: 0.5,
                       "Best lifted weight must come from the working set, not the warmup")
        XCTAssertEqual(row.bestReps, 5)
    }

    // MARK: - Prior best (self-delta)

    func test_rows_priorBest_readsOnlySessionsOnOrBeforeCutoff() {
        let now = Date()
        let old = savedSession(name: "Bench Press", sets: [("185", "5")], endingAt: now.addingTimeInterval(-100 * 86_400))
        let mid = savedSession(name: "Bench Press", sets: [("205", "5")], endingAt: now.addingTimeInterval(-50 * 86_400))
        let new = savedSession(name: "Bench Press", sets: [("225", "5")], endingAt: now)
        let cutoff = now.addingTimeInterval(-90 * 86_400)
        let rows = StrengthStandards.rows(from: [new, mid, old], bodyweightKg: 80, gender: .male, priorThrough: cutoff)
        let bench = rows.first { $0.lift == .bench }!
        XCTAssertEqual(bench.oneRepMaxLb, StrengthStandards.epley1RM(weight: 225, reps: 5), accuracy: 0.01)
        XCTAssertEqual(bench.priorOneRepMaxLb!, StrengthStandards.epley1RM(weight: 185, reps: 5), accuracy: 0.01,
                       "only the 100-day-old session is on or before the cutoff")
        XCTAssertEqual(bench.deltaLb!, StrengthStandards.epley1RM(weight: 225, reps: 5) - StrengthStandards.epley1RM(weight: 185, reps: 5), accuracy: 0.01)
    }

    func test_rows_priorBest_nilWithoutEarlierSessionsOrCutoff() {
        let now = Date()
        let new = savedSession(name: "Bench Press", sets: [("225", "5")], endingAt: now)
        let withCutoff = StrengthStandards.rows(from: [new], bodyweightKg: 80, gender: .male,
                                                priorThrough: now.addingTimeInterval(-90 * 86_400))
        XCTAssertNil(withCutoff.first { $0.lift == .bench }!.priorOneRepMaxLb, "nothing trained before the cutoff")
        let noCutoff = StrengthStandards.rows(from: [new], bodyweightKg: 80, gender: .male)
        XCTAssertNil(noCutoff.first { $0.lift == .bench }!.priorOneRepMaxLb, "no cutoff asked for")
        XCTAssertNil(noCutoff.first { $0.lift == .bench }!.deltaLb)
    }

    func test_rows_priorBest_neverExceedsCurrentBest() {
        // The prior walk is a subset of the full walk, so a regression reads
        // as a negative delta, never as a prior above the all-time best.
        let now = Date()
        let old = savedSession(name: "Back Squat", sets: [("315", "3")], endingAt: now.addingTimeInterval(-120 * 86_400))
        let new = savedSession(name: "Back Squat", sets: [("275", "3")], endingAt: now)
        let rows = StrengthStandards.rows(from: [old, new], bodyweightKg: 80, gender: .male,
                                          priorThrough: now.addingTimeInterval(-90 * 86_400))
        let squat = rows.first { $0.lift == .squat }!
        XCTAssertEqual(squat.priorOneRepMaxLb!, squat.oneRepMaxLb, accuracy: 0.01,
                       "the all-time best is the old session, so prior equals current")
        XCTAssertEqual(squat.deltaLb!, 0, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func savedSession(name: String, sets: [(weight: String, reps: String)],
                              endingAt end: Date = Date()) -> SavedSession {
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
            startTime: end.addingTimeInterval(-3600),
            exercises: [logged], feel: nil, note: nil,
            endTime: end, duration: 3600
        )
    }

    // MARK: - Canonical-lift name matching (T1-20)

    /// Table of REAL coach.db exercise names → the canonical lift each should
    /// resolve to (nil = must match nothing). Every row here is a name actually
    /// present in the shipped catalog, so this fails if either the matcher or
    /// the catalog drifts.
    func test_canonicalLiftMatching_realCatalogNames() {
        let cases: [(name: String, expected: StrengthStandards.CanonicalLift?)] = [
            // Squat — the plain barbell squat is the one the old " squat"
            // fragment (leading space) could never match.
            ("Barbell Back Squat",           .squat),
            // Merged into Barbell Back Squat in build 145; still an alias, so
            // logged history under this name must keep matching.
            ("Squat (Barbell)",              .squat),
            ("Back Squat",                   .squat),
            ("Barbell Squat",                .squat),
            // …and the variants that were silently scoring as Back Squat.
            ("Hack Squat (Machine)",         nil),
            ("Machine Hack Squat",           nil),
            ("Front Squat (Barbell)",        nil),
            ("Dumbbell Front Squat",         nil),
            ("Smith Machine Front Squat",    nil),
            ("Box Squat",                    nil),
            ("Squat (Bodyweight)",           nil),
            ("Squat (Band)",                 nil),
            ("Squat (Smith Machine)",        nil),
            ("Bulgarian Split Squat",        nil),
            ("Goblet Squat",                 nil),

            // Bench — flat barbell only.
            ("Barbell Bench Press",          .bench),
            ("Dumbbell Bench Press",         nil),   // logged per hand
            ("Incline Barbell Bench Press",  nil),
            ("Decline Bench Press (Barbell)", nil),
            ("Close-Grip Bench Press",       nil),
            ("Bench Press (Smith Machine)",  nil),
            ("Bench Press (Cable)",          nil),

            // Untouched lifts — guard against collateral damage.
            ("Deadlift (Barbell)",           .deadlift),
            ("Romanian Deadlift",            nil),
            ("Overhead Press",               .ohp),
            ("Seated Dumbbell Press",        nil),
        ]

        for (name, expected) in cases {
            let matched = StrengthStandards.CanonicalLift.allCases.first { $0.matches(name: name) }
            XCTAssertEqual(
                matched, expected,
                "\"\(name)\" resolved to \(matched.map(\.rawValue) ?? "nothing"), expected \(expected.map(\.rawValue) ?? "nothing")"
            )
        }
    }

    /// Every name in the table above that expects a match must also exist in
    /// the shipped catalog — otherwise the test passes against a name no user
    /// can ever log.
    func test_canonicalMatchTable_namesExistInCatalog() {
        let mustExist = ["Barbell Back Squat", "Barbell Bench Press", "Hack Squat (Machine)",
                         "Front Squat (Barbell)", "Dumbbell Bench Press",
                         "Incline Barbell Bench Press", "Close-Grip Bench Press"]
        let catalog = Set(CoachDatabase.shared.listExercises().map(\.name))
        for name in mustExist {
            XCTAssertTrue(catalog.contains(name),
                          "\"\(name)\" is no longer in coach.db — update the matcher table")
        }
    }
}
