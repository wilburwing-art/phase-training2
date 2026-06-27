import XCTest
@testable import PhaseTraining

/// PR 1 of the option-D arc: the deterministic WorkoutGenerator finally
/// sees runtime history (logged sessions, soreness check-ins, feedback).
/// These tests pin the builder's derived signals + the generator's
/// integration of them.
final class GeneratorContextTests: XCTestCase {

    // MARK: - Builder: priorBest

    func test_priorBest_picksMostRecentSessionPerExercise() {
        let now = Date()
        let cal = Calendar.current
        let older = savedSession(
            name: "Bench Press",
            sets: [("200", "5")],
            startTime: cal.date(byAdding: .day, value: -14, to: now)!
        )
        let newer = savedSession(
            name: "Bench Press",
            sets: [("225", "5"), ("230", "3")],
            startTime: cal.date(byAdding: .day, value: -3, to: now)!
        )
        let ctx = GeneratorContext.from(
            sessions: [older, newer],
            soreness: [], feedback: [], now: now
        )
        let pb = ctx.priorBest["bench press"]
        XCTAssertEqual(pb?.weight, 230)
        XCTAssertEqual(pb?.reps, 3)
    }

    func test_priorBest_skipsZeroWeightOrUndoneSets() {
        let session = savedSession(
            name: "Squat",
            sets: [("0", "5", true), ("315", "5", false)]  // weight=0 ignored, undone ignored
        )
        let ctx = GeneratorContext.from(sessions: [session],
                                        soreness: [], feedback: [])
        XCTAssertNil(ctx.priorBest["squat"], "no completed weighted set → no priorBest entry")
    }

    /// T2.1 — a true bodyweight movement (unit "bw") logs reps with no external
    /// load. The builder captures the best reps as a PriorBest(weight: 0) so the
    /// generator can progress by reps. (The old path skipped weight==0 outright,
    /// leaving every bodyweight movement with no progression signal at all.)
    func test_priorBest_bodyweightTracksRepsNotWeight() {
        let bw = LoggedExercise(
            id: "Push-Up", name: "Push-Up", type: nil,
            unit: LoggedExercise.bodyweightUnit,
            targetSets: 3, targetReps: 12, rest: 60,
            sets: [
                LoggedSet(num: 1, weight: "BW", reps: "15", rpe: "", done: true),
                LoggedSet(num: 2, weight: "BW", reps: "12", rpe: "", done: true),
            ],
            prevSets: [])
        let start = Date().addingTimeInterval(-3600)
        let session = SavedSession(
            templateId: "t", name: "Push-Up", category: "",
            startTime: start, exercises: [bw], feel: nil, note: nil,
            endTime: start.addingTimeInterval(3600), duration: 3600)
        let ctx = GeneratorContext.from(sessions: [session], soreness: [], feedback: [])
        let pb = ctx.priorBest["push-up"]
        XCTAssertNotNil(pb, "bodyweight movement should produce a reps-based priorBest")
        XCTAssertEqual(pb?.weight, 0, "bodyweight priorBest carries weight 0 as the reps-mode signal")
        XCTAssertEqual(pb?.reps, 15, "best (max) reps across done working sets")
    }

    // MARK: - Builder: recentSoreAreas

    func test_recentSoreAreas_unionsSorenessAndFeedback() {
        // Build 107 switched soreness.areas from joint vocab to muscle-bucket
        // slugs. recentSoreAreas filters soreness entries to
        // MuscleBucket.sorenessPrimarySlugs; feedback.hurtAreas stays
        // unfiltered (pain vocab is still free-text).
        let now = Date()
        var sore = SorenessEntry(date: now.addingTimeInterval(-2 * 86400))
        sore.areas = ["quads", "back"]
        let fb = FeedbackEntry(
            date: now.addingTimeInterval(-1 * 86400),
            sessionId: "x",
            difficulty: "right",
            hurtAreas: ["Shoulder"],
            ranLong: false, notes: nil
        )
        let ctx = GeneratorContext.from(
            sessions: [], soreness: [sore], feedback: [fb], now: now
        )
        XCTAssertTrue(ctx.recentSoreAreas.contains("quads"))
        XCTAssertTrue(ctx.recentSoreAreas.contains("back"))
        XCTAssertTrue(ctx.recentSoreAreas.contains("shoulder"))
    }

    func test_recentSoreAreas_excludesOlderThanSevenDays() {
        let now = Date()
        var oldSore = SorenessEntry(date: now.addingTimeInterval(-10 * 86400))
        oldSore.areas = ["quads"]
        let ctx = GeneratorContext.from(sessions: [], soreness: [oldSore],
                                        feedback: [], now: now)
        XCTAssertFalse(ctx.recentSoreAreas.contains("quads"))
    }

    // MARK: - Builder: stagnantExercises

    func test_stagnantExercises_flagsNoProgressionOver4w() {
        let now = Date()
        let cal = Calendar.current
        // Same exact 1RM input over 5 sessions in the last 4 weeks → flagged
        let sessions: [SavedSession] = (1...5).map { idx in
            savedSession(
                name: "Bench Press",
                sets: [("225", "5")],
                startTime: cal.date(byAdding: .day, value: -idx * 5, to: now)!
            )
        }
        let ctx = GeneratorContext.from(sessions: sessions, soreness: [],
                                        feedback: [], now: now)
        XCTAssertTrue(ctx.stagnantExercises.contains("bench press"))
    }

    func test_stagnantExercises_skipsSparseHistory() {
        // 2 sessions = below the 3-session noise threshold → not flagged
        let now = Date()
        let cal = Calendar.current
        let sessions: [SavedSession] = [1, 5].map { idx in
            savedSession(
                name: "Bench Press",
                sets: [("225", "5")],
                startTime: cal.date(byAdding: .day, value: -idx, to: now)!
            )
        }
        let ctx = GeneratorContext.from(sessions: sessions, soreness: [],
                                        feedback: [], now: now)
        XCTAssertFalse(ctx.stagnantExercises.contains("bench press"),
                       "2-session history is too thin to call stagnant")
    }

    func test_stagnantExercises_skipsProgressingLifters() {
        let now = Date()
        let cal = Calendar.current
        // Three sessions with rising weight → progressing, not flagged.
        let weights = ["205", "215", "225"]
        let sessions: [SavedSession] = weights.enumerated().map { i, w in
            savedSession(
                name: "Bench Press",
                sets: [(w, "5")],
                startTime: cal.date(byAdding: .day, value: -(15 - i * 5), to: now)!
            )
        }
        let ctx = GeneratorContext.from(sessions: sessions, soreness: [],
                                        feedback: [], now: now)
        XCTAssertFalse(ctx.stagnantExercises.contains("bench press"))
    }

    // MARK: - Empty case

    func test_empty_isIdentityForNoInputs() {
        let ctx = GeneratorContext.from(sessions: [], soreness: [], feedback: [])
        XCTAssertTrue(ctx.isEmpty)
        XCTAssertTrue(ctx.priorBest.isEmpty)
        XCTAssertTrue(ctx.recentSoreAreas.isEmpty)
        XCTAssertTrue(ctx.stagnantExercises.isEmpty)
    }

    // MARK: - Generator integration

    /// Empty context = no notes (existing behavior unchanged).
    func test_generator_emitsNoNotesWithEmptyContext() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        let p = DemographicProfile.from(m)
        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: "noctx"
        )
        for ex in workout.exercises {
            XCTAssertNil(ex.notes, "no context should mean no notes — got \(String(describing: ex.notes)) on \(ex.name)")
        }
    }

    // MARK: - Helpers

    private func savedSession(
        name: String,
        sets: [(weight: String, reps: String)],
        startTime: Date = Date().addingTimeInterval(-3600)
    ) -> SavedSession {
        savedSession(
            name: name,
            sets: sets.map { ($0.weight, $0.reps, true) },
            startTime: startTime
        )
    }

    private func savedSession(
        name: String,
        sets: [(weight: String, reps: String, done: Bool)],
        startTime: Date = Date().addingTimeInterval(-3600)
    ) -> SavedSession {
        let logged = LoggedExercise(
            id: name, name: name, type: nil, unit: "lbs",
            targetSets: sets.count, targetReps: 5, rest: 90,
            sets: sets.enumerated().map { i, s in
                LoggedSet(num: i + 1, weight: s.weight, reps: s.reps, rpe: "", done: s.done)
            },
            prevSets: []
        )
        return SavedSession(
            templateId: "t", name: name, category: "",
            startTime: startTime,
            exercises: [logged], feel: nil, note: nil,
            endTime: startTime.addingTimeInterval(3600), duration: 3600
        )
    }
}
