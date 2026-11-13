// ArcDeloadWeekTests.swift: the arc deload as a stored, labelled, declinable
// week fact (WeekOverrides.arcDeload).
//
// Store-level: a PlanStore with its own UserDefaults suite and an isolated
// SessionStore, seeded with three past build weeks so the real
// planArcSignal returns .deload. Every test here goes through the real
// signal; none writes `applied` directly.

import XCTest
@testable import PhaseTraining

final class ArcDeloadWeekTests: XCTestCase {

    // MARK: - Fixtures

    private var cal: Calendar { Calendar.current.mondayFirst }

    /// Monday 2026-05-11 00:00 local.
    private func monday(_ weekOffset: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11
        return cal.date(byAdding: .weekOfYear, value: weekOffset, to: cal.date(from: c)!)!
    }

    private func freshDefaults(_ tag: String = #function) -> UserDefaults {
        let suite = "ArcDeloadWeekTests.\(tag).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func memory(liftDays: Int = 4) -> TrainingMemory {
        var m = TrainingMemory()
        m.primarySport = Sport.resolve(slug: "climbing")
        m.seasonsBySport = [m.primarySport!: .offSeason]
        m.equipment = [.fullGym]
        m.liftDaysPerWeek = liftDays
        m.sessionMinutes = 60
        return m
    }

    private func makeSession(start: Date) -> SavedSession {
        SavedSession(
            templateId: "t", name: "Push day", category: "lift",
            startTime: start, exercises: [], feel: nil, note: nil,
            endTime: start.addingTimeInterval(3_600), duration: 3_600)
    }

    /// A past week's snapshot with 4 planned lift days and 4 logged sessions.
    private func buildWeek(_ weekStart: Date) -> (WeekPlanSnapshot, [SavedSession]) {
        let days = (0..<7).map { i -> DayPlan in
            DayPlan(date: cal.date(byAdding: .day, value: i, to: weekStart)!,
                    kind: i < 4 ? .lift : .rest,
                    title: i < 4 ? "Push day" : "Rest",
                    routineId: nil, generatedWorkout: nil)
        }
        let sessions = (0..<4).map { i in
            makeSession(start: cal.date(byAdding: .day, value: i, to: weekStart)!
                .addingTimeInterval(18 * 3_600))
        }
        let snap = WeekPlanSnapshot(
            weekStart: weekStart,
            plan: WeekPlan(days: days, generatedAt: weekStart, inputsHash: "arc"),
            actualSessionIDs: sessions.map(\.id),
            capturedAt: weekStart.addingTimeInterval(7 * 86_400))
        return (snap, sessions)
    }

    /// A store whose history is three build weeks before `monday(0)`, plus
    /// logged sessions for the weeks in `alsoLoggedWeeks` so a plan generated
    /// for them snapshots as a build week too.
    private func makeStore(alsoLoggedWeeks: [Int] = [], tag: String = #function) -> PlanStore {
        let defaults = freshDefaults(tag)
        let store = PlanStore(defaults: defaults, today: monday(0))
        let sessionStore = SessionStore(defaults: freshDefaults("session-\(tag)"),
                                        userDB: UserDatabase(path: ":memory:"))
        var snaps: [WeekPlanSnapshot] = []
        var sessions: [SavedSession] = []
        for w in [-3, -2, -1] {
            let (snap, ss) = buildWeek(monday(w))
            snaps.append(snap)
            sessions += ss
        }
        for w in alsoLoggedWeeks {
            sessions += buildWeek(monday(w)).1
        }
        sessionStore.savedSessions = sessions
        store.sessionStore = sessionStore
        store.pastPlans = snaps
        return store
    }

    private func onboarded(_ m: TrainingMemory) -> TrainingMemory {
        var m = m
        m.onboardedAt = monday(0)
        return m
    }

    private func liftSets(_ plan: WeekPlan) -> Int {
        plan.days.filter { $0.kind == .lift }
            .compactMap(\.generatedWorkout)
            .flatMap(\.exercises)
            .reduce(0) { $0 + $1.sets }
    }

    private func markerDate(_ store: PlanStore) -> Date? {
        (store.defaults.object(forKey: PlanStore.lastDeloadWeekKey) as? Double)
            .map { Date(timeIntervalSince1970: $0) }
    }

    private func hasRecoveryRestDay(_ plan: WeekPlan) -> Bool {
        plan.days.contains { $0.kind == .rest && $0.title == "Recovery" }
    }

    // MARK: - Tests

    func test_arcFires_marksWeekAppliedAndShowsDeload() throws {
        let store = makeStore()
        let m = memory()
        let plan = store.generate(from: m, today: monday(0))

        XCTAssertEqual(store.overrides.arcDeload, .applied)
        XCTAssertTrue(store.isArcDeloadWeek)
        XCTAssertTrue(hasRecoveryRestDay(plan), "4 lift days: the arc demotes one to Recovery")
        let marker = try XCTUnwrap(markerDate(store))
        XCTAssertTrue(cal.isDate(marker, inSameDayAs: monday(0)))

        let eyebrow = TodayScreen.eyebrow(
            seasonLabel: m.seasonForPlanner.compactLabel,
            sportShortName: m.primarySport?.shortName,
            showsDeload: store.overrides.weekTone == .recovery || store.isArcDeloadWeek)
        XCTAssertTrue(eyebrow.hasSuffix("DELOAD"), eyebrow)
    }

    func test_deloadSurvivesSecondGenerateInSameWeek() {
        let m = memory()
        let store = makeStore()
        let first = store.generate(from: m, today: monday(0))
        let second = store.generate(from: m, today: monday(0))

        let declinedStore = makeStore()
        declinedStore.overrides.arcDeload = .declined
        let normal = declinedStore.generate(from: m, today: monday(0))

        XCTAssertEqual(liftSets(second), liftSets(first))
        XCTAssertLessThan(liftSets(second), liftSets(normal))
        XCTAssertTrue(store.isArcDeloadWeek)
    }

    func test_twoLiftDays_cooldownStarts() throws {
        let m = memory(liftDays: 2)
        let store = makeStore(alsoLoggedWeeks: [0])
        _ = store.generate(from: m, today: monday(0))

        XCTAssertEqual(store.overrides.arcDeload, .applied)
        let marker = try XCTUnwrap(markerDate(store))
        XCTAssertTrue(cal.isDate(marker, inSameDayAs: monday(0)))

        XCTAssertEqual(store.planArcSignal(today: monday(1)), .none)
        store.refreshForCurrentWeek(memory: onboarded(m), today: monday(1))
        XCTAssertNil(store.overrides.arcDeload)
        XCTAssertFalse(store.isArcDeloadWeek)
    }

    func test_decline_regeneratesWithoutDeload() {
        let m = memory()
        let store = makeStore()
        let deload = store.generate(from: m, today: monday(0))
        store.declineArcDeload(memory: m, today: monday(0))
        let declined = store.plan!

        XCTAssertEqual(store.overrides.arcDeload, .declined)
        XCTAssertFalse(store.isArcDeloadWeek)
        XCTAssertTrue(hasRecoveryRestDay(deload))
        XCTAssertFalse(hasRecoveryRestDay(declined))
        XCTAssertGreaterThan(liftSets(declined), liftSets(deload))
    }

    func test_decline_survivesLaterRegens() {
        let m = memory()
        let store = makeStore()
        _ = store.generate(from: m, today: monday(0))
        store.declineArcDeload(memory: m, today: monday(0))
        store.updateOverrides(memory: m, today: monday(0)) { $0.weekTone = .busy }
        store.updateOverrides(memory: m, today: monday(0)) { $0.weekTone = nil }
        let plan = store.generate(from: m, today: monday(0))

        XCTAssertEqual(store.overrides.arcDeload, .declined)
        XCTAssertFalse(store.isArcDeloadWeek)
        XCTAssertFalse(hasRecoveryRestDay(plan))
    }

    func test_decline_doesNotStartCooldown() {
        let m = memory()
        let store = makeStore(alsoLoggedWeeks: [0])
        _ = store.generate(from: m, today: monday(0))
        store.declineArcDeload(memory: m, today: monday(0))

        XCTAssertNil(store.defaults.object(forKey: PlanStore.lastDeloadWeekKey))
        XCTAssertEqual(store.planArcSignal(today: monday(1)), .deload)
    }

    func test_recoveryTone_doesNotStackAndStartsCooldown() throws {
        let m = memory()
        let store = makeStore()
        store.overrides.weekTone = .recovery
        let plan = store.generate(from: m, today: monday(0))

        let reference = makeStore()
        reference.overrides.weekTone = .recovery
        reference.overrides.arcDeload = .declined
        let recoveryOnly = reference.generate(from: m, today: monday(0))

        XCTAssertEqual(store.overrides.arcDeload, .applied)
        XCTAssertEqual(liftSets(plan), liftSets(recoveryOnly))
        XCTAssertFalse(store.isArcDeloadWeek)
        let marker = try XCTUnwrap(markerDate(store))
        XCTAssertTrue(cal.isDate(marker, inSameDayAs: monday(0)))
    }

    func test_buildTone_suspendsArc_andTypicalBringsItBack() throws {
        let m = memory()
        let store = makeStore()
        _ = store.generate(from: m, today: monday(0))
        XCTAssertNotNil(markerDate(store))

        store.updateOverrides(memory: m, today: monday(0)) { $0.weekTone = .build }
        XCTAssertFalse(store.isArcDeloadWeek)
        XCTAssertFalse(hasRecoveryRestDay(store.plan!))
        XCTAssertNil(markerDate(store))

        store.updateOverrides(memory: m, today: monday(0)) { $0.weekTone = nil }
        XCTAssertTrue(store.isArcDeloadWeek)
        XCTAssertTrue(hasRecoveryRestDay(store.plan!))
        let marker = try XCTUnwrap(markerDate(store))
        XCTAssertTrue(cal.isDate(marker, inSameDayAs: monday(0)))
    }

    func test_rollover_doesNotCarryAppliedIntoNextWeek() {
        let m = onboarded(memory())
        let store = makeStore(alsoLoggedWeeks: [0])
        _ = store.generate(from: m, today: monday(0))
        XCTAssertEqual(store.overrides.arcDeload, .applied)

        store.refreshForCurrentWeek(memory: m, today: monday(1))

        XCTAssertTrue(cal.isDate(store.overrides.weekStart, inSameDayAs: monday(1)))
        XCTAssertNil(store.overrides.arcDeload)
        XCTAssertFalse(store.isArcDeloadWeek)
        let first = store.plan!.days.first!.date
        XCTAssertTrue(cal.isDate(first.startOfTrainingWeek(), inSameDayAs: monday(1)))
    }

    func test_rollover_doesNotCarryDeclinedIntoNextWeek() {
        let m = onboarded(memory())
        let store = makeStore(alsoLoggedWeeks: [0])
        _ = store.generate(from: m, today: monday(0))
        store.declineArcDeload(memory: m, today: monday(0))
        XCTAssertEqual(store.overrides.arcDeload, .declined)

        store.refreshForCurrentWeek(memory: m, today: monday(1))

        XCTAssertTrue(cal.isDate(store.overrides.weekStart, inSameDayAs: monday(1)))
        XCTAssertEqual(store.overrides.arcDeload, .applied)
        XCTAssertTrue(store.isArcDeloadWeek)
    }

    func test_rollover_dropsLastWeeksTone() {
        let m = onboarded(memory())
        let store = makeStore(alsoLoggedWeeks: [0])
        store.updateOverrides(memory: m, today: monday(0)) { $0.weekTone = .build }
        XCTAssertEqual(store.overrides.weekTone, .build)

        store.refreshForCurrentWeek(memory: m, today: monday(1))

        XCTAssertNil(store.overrides.weekTone)
    }

    func test_eyebrow_deloadForRecoveryToneAndForArc() {
        func eyebrow(tone: WeekTone?, arc: Bool) -> String {
            TodayScreen.eyebrow(seasonLabel: "Pre-season", sportShortName: "Skiing",
                                showsDeload: tone == .recovery || arc)
        }
        XCTAssertEqual(eyebrow(tone: nil, arc: false), "SKIING · PRE-SEASON")
        XCTAssertEqual(eyebrow(tone: .recovery, arc: false), "SKIING · PRE-SEASON · DELOAD")
        XCTAssertEqual(eyebrow(tone: nil, arc: true), "SKIING · PRE-SEASON · DELOAD")
    }
}
