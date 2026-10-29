import XCTest
@testable import PhaseTraining

/// A soreness check-in reaches the season engine: sore prime movers give way
/// inside their demand, the ones that stay get a lighter dose, and only the
/// lift days in the check-in's window change.
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
                         sore: (areas: Set<String>, heavy: Set<String>) = ([], [])) -> GeneratedWorkout {
        let athlete = AthleteState.from(m, variant: SportSeasonGenerator.defaultVariant(forSport: m.primarySport?.slug),
                                        soreness: sore)
        return SportSeasonGenerator.generateSession(athlete, sessionIndex: index, sessionsInWeek: lifts)
    }

    private func freshStore() -> PlanStore {
        let suite = "SorenessSelectionTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return PlanStore(defaults: d, today: monday())
    }

    // MARK: - Window

    func test_window_coversTheCheckInDayAndTheNext() throws {
        var m = try memory(sport: "alpine-skiing", season: .offSeason)
        m.soreness = [entry(monday(), "mild", ["quads"])]
        XCTAssertEqual(Planner.soreness(for: day(0), memory: m).areas, ["quads"])
        XCTAssertEqual(Planner.soreness(for: day(1), memory: m).areas, ["quads"])
        XCTAssertEqual(Planner.soreness(for: day(2), memory: m).areas, [])
        XCTAssertEqual(Planner.soreness(for: day(-1), memory: m).areas, [])
        XCTAssertEqual(Planner.soreness(for: day(0), memory: m).heavy, [], "mild is not heavy")
    }

    func test_window_highOrPainIsHeavy_andANewerNoneClears() throws {
        var m = try memory(sport: "alpine-skiing", season: .offSeason)
        m.soreness = [entry(monday(), "high", ["quads", "glutes"])]
        XCTAssertEqual(Planner.soreness(for: day(0), memory: m).heavy, ["quads", "glutes"])
        m.soreness = [entry(monday(), "none", ["back"], pain: true)]
        XCTAssertEqual(Planner.soreness(for: day(0), memory: m).heavy, ["back"], "pain counts as heavy")
        m.soreness = [entry(monday(), "high", ["quads"]), entry(day(1), "none", [])]
        XCTAssertEqual(Planner.soreness(for: day(1), memory: m).areas, [], "Tuesday's 'none' replaces Monday's report")
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
                let sore = session(m, index: i, lifts: 3, sore: ([area], []))
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

    func test_engine_heavySorenessCutsSetsOnWhatStays() throws {
        let m = try memory(sport: "alpine-skiing", season: .offSeason)
        let base = session(m, index: 0, lifts: 3)
        let sore = session(m, index: 0, lifts: 3, sore: (["quads"], ["quads"]))
        let baseSets = Dictionary(base.exercises.map { ($0.exerciseId, $0.sets) }, uniquingKeysWith: { a, _ in a })
        let kept = sore.exercises.filter {
            WorkoutGenerator.primaryMuscleBuckets(exerciseId: $0.exerciseId).contains("quads") && baseSets[$0.exerciseId] != nil
        }
        XCTAssertFalse(kept.isEmpty, "fixture needs a quad prime mover that stays")
        for ex in kept {
            XCTAssertLessThan(ex.sets, try XCTUnwrap(baseSets[ex.exerciseId]), "\(ex.name) kept its full sets")
        }
        XCTAssertTrue(sore.summary.contains("eased for sore quads"), sore.summary)
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
        }
    }

    func test_applySoreness_changesOnlyWindowDays_keepsSessions_andIsIdempotent() throws {
        var m = try memory(sport: "alpine-skiing", season: .offSeason)
        let store = freshStore()
        _ = store.generate(from: m, today: monday())
        let before = try XCTUnwrap(store.plan?.days)

        m.soreness = [entry(monday(), "high", ["quads"])]
        store.applySoreness(memory: m, today: monday())
        let after = try XCTUnwrap(store.plan?.days)

        let cal = Calendar.current
        var changedAny = false
        for (b, a) in zip(before, after) {
            XCTAssertEqual(a.title, b.title, "the session changed on \(b.date)")
            let inWindow = cal.isDate(b.date, inSameDayAs: day(0)) || cal.isDate(b.date, inSameDayAs: day(1))
            if b.kind == .lift && inWindow {
                XCTAssertEqual(a.generatedWorkout?.soreAreas, ["quads"])
                if a.generatedWorkout != b.generatedWorkout { changedAny = true }
            } else {
                XCTAssertEqual(a, b, "a day outside the window changed: \(b.date)")
            }
        }
        XCTAssertTrue(changedAny || !before.contains { $0.kind == .lift && cal.startOfDay(for: $0.date) <= cal.startOfDay(for: day(1)) })

        store.applySoreness(memory: m, today: monday())
        XCTAssertEqual(store.plan?.days, after, "a second apply changed something")
    }

    func test_applySoreness_undoesAnExpiredCheckIn() throws {
        var m = try memory(sport: "alpine-skiing", season: .offSeason)
        m.soreness = [entry(monday(), "mild", ["quads"])]
        let store = freshStore()
        _ = store.generate(from: m, today: monday())
        XCTAssertTrue(store.plan?.days.contains { $0.generatedWorkout?.soreAreas != nil } ?? false)

        m.soreness = [entry(monday(), "none", [])]
        store.applySoreness(memory: m, today: monday())
        XCTAssertFalse(store.plan?.days.contains { $0.generatedWorkout?.soreAreas != nil } ?? true)
    }

    func test_applySoreness_skipsDuringAnActiveSession() throws {
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
        store.applySoreness(memory: m, today: monday())
        XCTAssertEqual(store.plan, before)
    }
}
