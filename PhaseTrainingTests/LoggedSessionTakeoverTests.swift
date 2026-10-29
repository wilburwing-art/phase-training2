import XCTest
@testable import PhaseTraining

/// What a saved session changes about the week: rotation follows logged
/// exercises, and an off-plan session takes over the later day it covered.
final class LoggedSessionTakeoverTests: XCTestCase {

    private func monday() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11; c.hour = 8
        return Calendar.current.date(from: c)!
    }

    private func memory(lifts: Int = 5) throws -> TrainingMemory {
        var m = TrainingMemory()
        m.equipment = [.fullGym]
        m.experience = .intermediate
        m.sessionMinutes = 60
        m.liftDaysPerWeek = lifts
        let sport = try XCTUnwrap(Sport.resolve(slug: "alpine-skiing"))
        m.sports = [sport]
        m.primarySport = sport
        m.seasonsBySport = [sport: .preSeason]
        m.defaultSeason = .preSeason
        m.onboardedAt = monday()
        return m
    }

    private func store() -> (PlanStore, SessionStore, RecentPicksStore) {
        let suite = "LoggedSessionTakeover.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let store = PlanStore(defaults: d, today: monday())
        let sessions = SessionStore(defaults: UserDefaults(suiteName: suite + ".s")!,
                                    userDB: UserDatabase(path: ":memory:"))
        let picks = RecentPicksStore(defaults: UserDefaults(suiteName: suite + ".p")!)
        store.sessionStore = sessions
        store.recentPicks = picks
        return (store, sessions, picks)
    }

    private func exercise(_ name: String, sets: Int, done: Bool = true) -> LoggedExercise {
        LoggedExercise(id: name, name: name, type: nil, unit: "lbs",
                       targetSets: sets, targetReps: 6, rest: 120,
                       sets: (1...sets).map { LoggedSet(num: $0, weight: "135", reps: "6", rpe: "", done: done) },
                       prevSets: [])
    }

    private func legSession(on date: Date) -> SavedSession {
        let start = Calendar.current.startOfDay(for: date).addingTimeInterval(17 * 3600)
        return SavedSession(templateId: "custom", name: "Legs", category: "lift", startTime: start,
                            exercises: [exercise("Barbell Back Squat", sets: 5),
                                        exercise("Bulgarian Split Squat", sets: 4),
                                        exercise("Romanian Deadlift (Barbell)", sets: 4)],
                            endTime: start.addingTimeInterval(3600), duration: 3600)
    }

    // MARK: - Coverage

    func test_coverage_countsSetsOnCoveredPrimeMovers() {
        let w = GeneratedWorkout(title: "t", summary: "", exercises: [
            GeneratedExercise(id: "a", exerciseId: 57, name: "Barbell Back Squat", isCompound: true, sets: 3, reps: "5", restSeconds: 120),
            GeneratedExercise(id: "b", exerciseId: 62, name: "Bulgarian Split Squat", isCompound: true, sets: 1, reps: "8", restSeconds: 90),
        ], estimatedMinutes: 30, provenance: "")
        XCTAssertEqual(PlanStore.coverage(of: w, by: ["quads"]), 1.0, accuracy: 1e-9)
        XCTAssertEqual(PlanStore.coverage(of: w, by: ["chest"]), 0.0, accuracy: 1e-9)
    }

    func test_coveredBuckets_needEnoughLoad() {
        let light = SavedSession(templateId: "t", name: "x", category: "lift", startTime: monday(),
                                 exercises: [exercise("Barbell Back Squat", sets: 2)],
                                 endTime: monday(), duration: 0)
        XCTAssertFalse(PlanStore.coveredBuckets(by: light).contains("quads"), "two sets is not a leg day")
        XCTAssertTrue(PlanStore.coveredBuckets(by: legSession(on: monday())).contains("quads"))
    }

    // MARK: - Takeover

    /// The first lift day whose workout a leg session does not cover, followed
    /// by a later lift day it does.
    private func fixtureDays(_ plan: WeekPlan, buckets: Set<String>) throws -> (DayPlan, DayPlan) {
        let lifts = plan.days.filter { $0.kind == .lift && $0.generatedWorkout != nil }
        for (i, d) in lifts.enumerated() where PlanStore.coverage(of: d.generatedWorkout!, by: buckets) < PlanStore.coveredShare {
            if let x = lifts[(i + 1)...].first(where: { PlanStore.coverage(of: $0.generatedWorkout!, by: buckets) >= PlanStore.coveredShare }) {
                return (d, x)
            }
        }
        throw XCTSkip("no upper day followed by a leg day in this week")
    }

    func test_offPlanLegSession_takesOverTheLaterLegDay() throws {
        let m = try memory()
        let (store, _, _) = store()
        _ = store.generate(from: m, today: monday())
        let session0 = legSession(on: monday())
        let (logDay, legDay) = try fixtureDays(try XCTUnwrap(store.plan), buckets: PlanStore.coveredBuckets(by: session0))
        let session = legSession(on: logDay.date)

        store.recordOutcome(for: session, abandoned: false)
        let moved = store.takeOverCoveredDay(for: session, abandoned: false, memory: m, today: monday())

        let cal = Calendar.current
        XCTAssertTrue(moved.map { cal.isDate($0, inSameDayAs: legDay.date) } ?? false)
        let after = try XCTUnwrap(store.plan)
        let newLog = try XCTUnwrap(after.days.first { cal.isDate($0.date, inSameDayAs: logDay.date) })
        let newLeg = try XCTUnwrap(after.days.first { cal.isDate($0.date, inSameDayAs: legDay.date) })
        XCTAssertEqual(newLeg.title, logDay.title, "the skipped session moves to the covered day")
        XCTAssertEqual(newLog.title, legDay.title, "the log day now carries the session it covered")
        XCTAssertEqual(store.lastMove?.coveredTitle, legDay.title)
        XCTAssertEqual(store.lastMove?.title, logDay.title)

        // Survives a full rebuild: the swap lives in the overrides.
        _ = store.generate(from: m, today: monday())
        XCTAssertEqual(store.plan?.days.first { cal.isDate($0.date, inSameDayAs: legDay.date) }?.title, logDay.title)
    }

    func test_noTakeover_whenAbandoned_asPlanned_orCoveringItsOwnDay() throws {
        let m = try memory()
        let (store, _, _) = store()
        _ = store.generate(from: m, today: monday())
        let probe = legSession(on: monday())
        let buckets = PlanStore.coveredBuckets(by: probe)
        let (logDay, _) = try fixtureDays(try XCTUnwrap(store.plan), buckets: buckets)
        let before = store.plan

        let abandoned = legSession(on: logDay.date)
        store.recordOutcome(for: abandoned, abandoned: true)
        XCTAssertNil(store.takeOverCoveredDay(for: abandoned, abandoned: true, memory: m, today: monday()))

        // A leg log on a day whose own plan is legs replaced that session.
        let legDays = store.plan!.days.filter {
            $0.kind == .lift && $0.generatedWorkout.map { PlanStore.coverage(of: $0, by: buckets) >= PlanStore.coveredShare } == true
        }
        let own = try XCTUnwrap(legDays.first)
        let ownLog = legSession(on: own.date)
        store.recordOutcome(for: ownLog, abandoned: false)
        XCTAssertNil(store.takeOverCoveredDay(for: ownLog, abandoned: false, memory: m, today: monday()))
        XCTAssertEqual(store.plan, before)
        XCTAssertNil(store.lastMove)
    }

    func test_noTakeover_ofADayThatHasAlreadyPassed() throws {
        // Logged later for an earlier day: the leg day it covers is already
        // behind today, so nothing moves.
        let m = try memory()
        let (store, _, _) = store()
        _ = store.generate(from: m, today: monday())
        let probe = legSession(on: monday())
        let (logDay, legDay) = try fixtureDays(try XCTUnwrap(store.plan), buckets: PlanStore.coveredBuckets(by: probe))
        let session = legSession(on: logDay.date)
        let laterToday = Calendar.current.date(byAdding: .day, value: 1, to: legDay.date)!
        let before = store.plan

        store.recordOutcome(for: session, abandoned: false)
        XCTAssertNil(store.takeOverCoveredDay(for: session, abandoned: false, memory: m, today: laterToday))
        XCTAssertEqual(store.plan, before)
    }

    // MARK: - Rotation

    func test_rotationFollowsLoggedExercises_notGeneration() throws {
        let m = try memory()
        let (store, _, picks) = store()
        _ = store.generate(from: m, today: monday())
        XCTAssertTrue(picks.lastPicked.isEmpty, "generation no longer stamps its own picks")

        // The store prunes picks older than 60 days against the wall clock.
        var session = legSession(on: Date())
        session.exercises.append(exercise("Goblet Squat", sets: 3, done: false))
        store.recordLoggedPicks(session)
        XCTAssertEqual(Set(picks.lastPicked.keys).isSuperset(of: [57, 62]), true, "\(picks.lastPicked)")
        XCTAssertNil(picks.lastPicked[60], "an exercise with no done sets was not done")
        XCTAssertEqual(picks.lastPicked[57], session.startTime)
    }
}
