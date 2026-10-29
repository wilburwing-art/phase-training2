import XCTest
@testable import PhaseTraining

/// Recovery reaches the season engine (MuscleRecovery): a blocked muscle's
/// prime movers never appear, a part-recovered one's give way inside their
/// demand and cap at RPE 7, and only the lift days whose recovery changed
/// are rebuilt.
final class SorenessSelectionTests: XCTestCase {

    // MARK: - Fixtures

    /// Fixed Monday anchor (2026-05-11).
    private func monday() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11; c.hour = 8
        return Calendar.current.date(from: c)!
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: monday())!
    }

    private func memory(sport slug: String, season: SeasonPhase, lifts: Int = 3) throws -> TrainingMemory {
        var m = TrainingMemory()
        m.equipment = [.fullGym]
        m.experience = .intermediate
        m.sessionMinutes = 60
        m.liftDaysPerWeek = lifts
        let sport = try XCTUnwrap(Sport.resolve(slug: slug))
        m.sports = [sport]
        m.primarySport = sport
        m.seasonsBySport = [sport: season]
        m.defaultSeason = season
        m.onboardedAt = monday()
        return m
    }

    private func entry(_ date: Date, _ severity: String, _ areas: [String], pain: Bool = false) -> SorenessEntry {
        SorenessEntry(date: date, energy: "normal", soreness: severity, pain: pain, areas: areas)
    }

    private func soreCount(_ w: GeneratedWorkout, _ area: String) -> Int {
        w.exercises.filter { WorkoutGenerator.primaryMuscleBuckets(exerciseId: $0.exerciseId).contains(area) }.count
    }

    private func demands(_ w: GeneratedWorkout) -> [String] {
        let tail = w.provenance.components(separatedBy: "demands: ").last ?? ""
        return tail.split(separator: "/").map(String.init).sorted()
    }

    private func session(_ m: TrainingMemory, index: Int, lifts: Int,
                         recovery: RecoveryStatus = .none) -> GeneratedWorkout {
        let athlete = AthleteState.from(m, variant: SportSeasonGenerator.defaultVariant(forSport: m.primarySport?.slug),
                                        recovery: recovery)
        return SportSeasonGenerator.generateSession(athlete, sessionIndex: index, sessionsInWeek: lifts)
    }

    private func freshStore() -> PlanStore {
        let suite = "SorenessSelectionTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return PlanStore(defaults: d, today: monday())
    }

    // MARK: - Check-in window

    private func status(_ date: Date, _ m: TrainingMemory,
                        exposures: [MuscleFreshness.Exposure] = []) -> RecoveryStatus {
        MuscleRecovery.status(on: date, exposures: exposures, soreness: m.soreness, now: monday())
    }

    func test_window_coversTheCheckInDayAndTheNext() throws {
        var m = try memory(sport: "alpine-skiing", season: .offSeason)
        m.soreness = [entry(monday(), "mild", ["quads"])]
        XCTAssertEqual(status(day(0), m).eased, ["quads"])
        XCTAssertEqual(status(day(1), m).eased, ["quads"])
        XCTAssertEqual(status(day(2), m).eased, [])
        XCTAssertEqual(status(day(-1), m).eased, [])
        XCTAssertEqual(status(day(0), m).blocked, [], "mild eases, it does not block")
    }

    func test_window_highOrPainBlocks_andANewerNoneClears() throws {
        var m = try memory(sport: "alpine-skiing", season: .offSeason)
        m.soreness = [entry(monday(), "high", ["quads", "glutes"])]
        XCTAssertEqual(status(day(0), m).blocked, ["quads", "glutes"])
        m.soreness = [entry(monday(), "none", ["back"], pain: true)]
        XCTAssertEqual(status(day(0), m).blocked, ["back"], "pain blocks")
        m.soreness = [entry(monday(), "high", ["quads"]), entry(day(1), "none", [])]
        XCTAssertEqual(status(day(1), m), RecoveryStatus.none, "Tuesday's 'none' replaces Monday's report")
    }

    func test_model_blocksTheDayAfterAHeavyLegSession_andANoneCheckInOverrides() throws {
        // Twelve sets of quads Monday evening: Tuesday noon is 18h into a
        // ~85h recovery, so quads are blocked; by Friday they are recovered.
        var m = try memory(sport: "alpine-skiing", season: .offSeason)
        let legs = [MuscleFreshness.Exposure(start: monday().addingTimeInterval(10 * 3600),
                                             loads: ["quadriceps": 12])]
        XCTAssertTrue(status(day(1), m, exposures: legs).blocked.contains("quads"))
        XCTAssertFalse(status(day(4), m, exposures: legs).blocked.contains("quads"))
        XCTAssertFalse(status(day(4), m, exposures: legs).eased.contains("quads"))

        m.soreness = [entry(day(1).addingTimeInterval(-3 * 3600), "none", [])]
        XCTAssertFalse(status(day(1), m, exposures: legs).blocked.contains("quads"),
                       "feeling fine after the session beats the estimate")
    }

    // MARK: - Engine

    /// Same demands served; never more sore prime movers; any that stay are
    /// capped at RPE 7. Prints the counts the plan asked to measure.
    func test_engine_soreTierKeepsDemands_andCapsWhatStays() throws {
        let cases: [(String, SeasonPhase, String)] = [
            ("alpine-skiing", .offSeason, "quads"),
            ("climbing", .inSeason, "chest"),
            ("climbing", .preSeason, "back"),
        ]
        var anyFewer = false
        for (slug, season, area) in cases {
            let m = try memory(sport: slug, season: season)
            var before = 0, after = 0
            for i in 0..<3 {
                let base = session(m, index: i, lifts: 3)
                let sore = session(m, index: i, lifts: 3, recovery: RecoveryStatus(eased: [area]))
                XCTAssertEqual(demands(sore), demands(base), "\(slug) \(season) s\(i): a demand was lost")
                XCTAssertLessThanOrEqual(soreCount(sore, area), soreCount(base, area))
                for ex in sore.exercises where WorkoutGenerator.primaryMuscleBuckets(exerciseId: ex.exerciseId).contains(area) {
                    XCTAssertEqual(capRPE(ex.rpe ?? "", to: 7.0), ex.rpe, "\(ex.name) not capped at RPE 7")
                }
                XCTAssertEqual(sore.soreAreas, [area])
                before += soreCount(base, area); after += soreCount(sore, area)
            }
            if after < before { anyFewer = true }
            print("SORE-MEASURE \(slug) \(season) \(area): \(before) -> \(after) sore prime movers over 3 sessions")
        }
        XCTAssertTrue(anyFewer, "the sore tier never substituted anything")
    }

    func test_engine_blockedMuscleNeverAppears_andTheSessionKeepsItsSize() throws {
        let cases: [(String, SeasonPhase, String)] = [
            ("alpine-skiing", .offSeason, "quads"),
            ("alpine-skiing", .preSeason, "glutes"),
            ("climbing", .preSeason, "forearms"),
            ("climbing", .inSeason, "back"),
        ]
        for (slug, season, area) in cases {
            let m = try memory(sport: slug, season: season)
            for i in 0..<3 {
                let base = session(m, index: i, lifts: 3)
                let gated = session(m, index: i, lifts: 3, recovery: RecoveryStatus(blocked: [area]))
                XCTAssertEqual(soreCount(gated, area), 0, "\(slug) \(season) s\(i) kept a \(area) prime mover")
                XCTAssertEqual(gated.blockedAreas, [area])
                if soreCount(base, area) > 0 {
                    XCTAssertEqual(gated.skippedAreas, [area])
                    XCTAssertTrue(gated.summary.contains("still recovering"), gated.summary)
                }
                print("GATE-MEASURE \(slug) \(season) s\(i) \(area): \(base.exercises.count) -> \(gated.exercises.count) movements, \(soreCount(base, area)) blocked")
            }
        }
    }

    // MARK: - PlanStore

    func test_generate_appliesTheCheckInToItsWindow() throws {
        var m = try memory(sport: "alpine-skiing", season: .offSeason)
        m.soreness = [entry(monday(), "mild", ["quads"])]
        let store = freshStore()
        _ = store.generate(from: m, today: monday())
        let days = try XCTUnwrap(store.plan?.days)
        for d in days where d.kind == .lift {
            let inWindow = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: monday()),
                                                           to: Calendar.current.startOfDay(for: d.date)).day! <= 1
            XCTAssertEqual(d.generatedWorkout?.soreAreas, inWindow ? ["quads"] : nil, "\(d.date)")
            XCTAssertNil(d.generatedWorkout?.blockedAreas)
        }
    }

    func test_applyRecovery_changesOnlyWindowDays_keepsSessions_andIsIdempotent() throws {
        var m = try memory(sport: "alpine-skiing", season: .offSeason)
        let store = freshStore()
        _ = store.generate(from: m, today: monday())
        let before = try XCTUnwrap(store.plan?.days)

        m.soreness = [entry(monday(), "high", ["quads"])]
        store.applyRecovery(memory: m, today: monday())
        let after = try XCTUnwrap(store.plan?.days)

        let cal = Calendar.current
        var changedAny = false
        for (b, a) in zip(before, after) {
            XCTAssertEqual(a.title, b.title, "the session changed on \(b.date)")
            let inWindow = cal.isDate(b.date, inSameDayAs: day(0)) || cal.isDate(b.date, inSameDayAs: day(1))
            if b.kind == .lift && inWindow {
                XCTAssertEqual(a.generatedWorkout?.blockedAreas, ["quads"])
                XCTAssertEqual(soreCount(try XCTUnwrap(a.generatedWorkout), "quads"), 0)
                if a.generatedWorkout != b.generatedWorkout { changedAny = true }
            } else {
                XCTAssertEqual(a, b, "a day outside the window changed: \(b.date)")
            }
        }
        XCTAssertTrue(changedAny || !before.contains { $0.kind == .lift && cal.startOfDay(for: $0.date) <= cal.startOfDay(for: day(1)) })

        store.applyRecovery(memory: m, today: monday())
        XCTAssertEqual(store.plan?.days, after, "a second apply changed something")
    }

    func test_applyRecovery_undoesAnExpiredCheckIn() throws {
        var m = try memory(sport: "alpine-skiing", season: .offSeason)
        m.soreness = [entry(monday(), "mild", ["quads"])]
        let store = freshStore()
        _ = store.generate(from: m, today: monday())
        XCTAssertTrue(store.plan?.days.contains { $0.generatedWorkout?.soreAreas != nil } ?? false)

        m.soreness = [entry(monday(), "none", [])]
        store.applyRecovery(memory: m, today: monday())
        XCTAssertFalse(store.plan?.days.contains { $0.generatedWorkout?.soreAreas != nil } ?? true)
        XCTAssertFalse(store.plan?.days.contains { $0.generatedWorkout?.blockedAreas != nil } ?? true)
    }

    func test_applyRecovery_skipsDuringAnActiveSession() throws {
        var m = try memory(sport: "alpine-skiing", season: .offSeason)
        let store = freshStore()
        _ = store.generate(from: m, today: monday())
        let before = store.plan
        let sessions = SessionStore(defaults: UserDefaults(suiteName: "soreness-session-\(UUID().uuidString)")!,
                                    userDB: UserDatabase(path: ":memory:"))
        sessions.active = ActiveSession(templateId: "t", name: "Lower A", category: "lift",
                                        startTime: monday(), exercises: [])
        store.sessionStore = sessions

        m.soreness = [entry(monday(), "high", ["quads"])]
        store.applyRecovery(memory: m, today: monday())
        XCTAssertEqual(store.plan, before)
    }

    func test_applyRecovery_afterALoggedLegSession_dropsQuadsFromTheNextLiftDay() throws {
        let m = try memory(sport: "alpine-skiing", season: .offSeason, lifts: 5)
        let store = freshStore()
        let sessions = SessionStore(defaults: UserDefaults(suiteName: "recovery-session-\(UUID().uuidString)")!,
                                    userDB: UserDatabase(path: ":memory:"))
        store.sessionStore = sessions
        _ = store.generate(from: m, today: monday())
        let cal = Calendar.current
        let next = try XCTUnwrap(store.plan?.days.first {
            $0.kind == .lift && cal.startOfDay(for: $0.date) > cal.startOfDay(for: monday())
                && cal.startOfDay(for: $0.date) <= cal.startOfDay(for: day(2))
        }, "fixture needs a lift day on Tuesday or Wednesday")

        // Twelve sets of quads at 6pm the evening before that day.
        let start = cal.startOfDay(for: next.date).addingTimeInterval(-6 * 3600)
        let squat = LoggedExercise(id: "x", name: "Barbell Back Squat", type: nil, unit: "lbs",
                                   targetSets: 6, targetReps: 5, rest: 120,
                                   sets: (1...6).map { LoggedSet(num: $0, weight: "185", reps: "5", rpe: "", done: true) },
                                   prevSets: [])
        let split = LoggedExercise(id: "y", name: "Bulgarian Split Squat", type: nil, unit: "lbs",
                                   targetSets: 6, targetReps: 8, rest: 90,
                                   sets: (1...6).map { LoggedSet(num: $0, weight: "40", reps: "8", rpe: "", done: true) },
                                   prevSets: [])
        sessions.savedSessions.insert(SavedSession(templateId: "t", name: "Legs", category: "lift",
                                                   startTime: start, exercises: [squat, split],
                                                   endTime: start.addingTimeInterval(3600), duration: 3600), at: 0)
        store.applyRecovery(memory: m, today: start.addingTimeInterval(3600))

        let rebuilt = try XCTUnwrap(store.plan?.days.first { $0.id == next.id }?.generatedWorkout)
        XCTAssertTrue(rebuilt.blockedAreas?.contains("quads") ?? false, "\(rebuilt.blockedAreas ?? [])")
        XCTAssertEqual(soreCount(rebuilt, "quads"), 0, rebuilt.exercises.map(\.name).joined(separator: ", "))
    }
}
