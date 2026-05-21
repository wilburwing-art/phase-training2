import XCTest
@testable import PhaseTraining

final class MuscleVolumeTests: XCTestCase {

    // Test resolver — bypasses CoachDatabase so tests don't depend on the
    // bundled SQLite. Maps exercise names → muscle role tuples.
    private func resolver(_ map: [String: [(slug: String, role: String, label: String)]]) -> MuscleVolume.NameResolver {
        return { name in
            guard let muscles = map[name] else { return nil }
            return MuscleVolume.ResolvedExercise(muscles: muscles)
        }
    }

    func test_emptyWhenNoSessions() {
        XCTAssertTrue(MuscleVolume.rows(from: [], resolve: resolver([:])).isEmpty)
    }

    func test_singleSet_allocatesPrimaryAndSecondary() {
        let session = savedSession(name: "Bench Press", sets: [("225", "5")])
        let rows = MuscleVolume.rows(
            from: [session],
            resolve: resolver([
                "Bench Press": [
                    (slug: "chest", role: "primary", label: "Chest"),
                    (slug: "triceps", role: "secondary", label: "Triceps"),
                    (slug: "front_delt", role: "stabilizer", label: "Front Delt"),
                ]
            ])
        )
        // Volume = 225 × 5 = 1125. Allocation: primary 0.60 / secondary 0.25 /
        // stabilizer 0.15 (sum 1.0 already so normalisation is identity).
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].slug, "chest")
        XCTAssertEqual(rows[0].volume, 1125 * 0.60, accuracy: 0.5)
        XCTAssertEqual(rows[1].slug, "triceps")
        XCTAssertEqual(rows[1].volume, 1125 * 0.25, accuracy: 0.5)
        XCTAssertEqual(rows[2].slug, "front_delt")
        XCTAssertEqual(rows[2].volume, 1125 * 0.15, accuracy: 0.5)
    }

    func test_oldSessionsBeyondWindow_areIgnored() {
        let now = Date()
        // 6 weeks ago, with the default 4-week window.
        let old = savedSession(name: "Bench Press",
                               sets: [("225", "5")],
                               startTime: Calendar.current.date(byAdding: .weekOfYear, value: -6, to: now)!)
        let rows = MuscleVolume.rows(
            from: [old],
            weeks: 4,
            now: now,
            resolve: resolver([
                "Bench Press": [(slug: "chest", role: "primary", label: "Chest")]
            ])
        )
        XCTAssertTrue(rows.isEmpty)
    }

    func test_unknownExercise_isSilentlySkipped() {
        let session = savedSession(name: "Mystery Move", sets: [("100", "10")])
        let rows = MuscleVolume.rows(from: [session], resolve: resolver([:]))
        XCTAssertTrue(rows.isEmpty)
    }

    func test_multipleMusclesInSameRole_evenlySplitTheirShare() {
        // Two primary muscles share the 0.60 → 0.30 each. No other roles
        // present so normalisation brings each to 0.50 of total.
        let session = savedSession(name: "Deadlift", sets: [("315", "3")])
        let rows = MuscleVolume.rows(
            from: [session],
            resolve: resolver([
                "Deadlift": [
                    (slug: "glutes", role: "primary", label: "Glutes"),
                    (slug: "hamstrings", role: "primary", label: "Hamstrings"),
                ]
            ])
        )
        XCTAssertEqual(rows.count, 2)
        let totalVolume = 315.0 * 3.0
        for row in rows {
            XCTAssertEqual(row.volume, totalVolume * 0.5, accuracy: 0.5)
        }
    }

    func test_undoneSets_areIgnored() {
        let session = savedSession(name: "Bench Press",
                                   sets: [("225", "5", false)])
        let rows = MuscleVolume.rows(
            from: [session],
            resolve: resolver([
                "Bench Press": [(slug: "chest", role: "primary", label: "Chest")]
            ])
        )
        XCTAssertTrue(rows.isEmpty)
    }

    /// Warmup sets must NOT contribute to weekly muscle volume — otherwise
    /// a 5×95 warmup ramp would inflate chest volume next to the working
    /// top set, distorting the muscle-balance card.
    func test_warmupSets_areIgnored() {
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
        let rows = MuscleVolume.rows(
            from: [session],
            resolve: resolver([
                "Bench Press": [(slug: "chest", role: "primary", label: "Chest")]
            ])
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].volume, 225 * 5, accuracy: 0.5,
                       "Volume should reflect the working set only (warmup 95×5 excluded)")
    }

    // MARK: - Helpers

    private func savedSession(name: String,
                              sets: [(weight: String, reps: String)],
                              startTime: Date = Date().addingTimeInterval(-3600)) -> SavedSession {
        savedSession(name: name,
                     sets: sets.map { ($0.weight, $0.reps, true) },
                     startTime: startTime)
    }

    private func savedSession(name: String,
                              sets: [(weight: String, reps: String, done: Bool)],
                              startTime: Date = Date().addingTimeInterval(-3600)) -> SavedSession {
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
