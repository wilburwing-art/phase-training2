import XCTest
@testable import PhaseTraining

final class TodayWidgetSnapshotTests: XCTestCase {
    private let cal = Calendar.current
    private lazy var monday: Date = cal.startOfDay(for: Date().startOfTrainingWeek())

    private func date(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: monday)!
    }

    private func week(_ overrides: [Int: DayPlan] = [:]) -> WeekPlan {
        let days = (0..<7).map { i in
            overrides[i] ?? DayPlan(date: date(i), kind: .rest, title: "Rest")
        }
        return WeekPlan(days: days, generatedAt: Date(), inputsHash: "test")
    }

    private func liftDay(_ i: Int) -> DayPlan {
        let ex = [
            GeneratedExercise(id: "a", exerciseId: 1, name: "Bench", isCompound: true,
                              sets: 4, reps: "5", restSeconds: 120),
            GeneratedExercise(id: "b", exerciseId: 2, name: "Row", isCompound: true,
                              sets: 3, reps: "8", restSeconds: 90),
        ]
        let workout = GeneratedWorkout(title: "Upper Day 1", summary: "", exercises: ex,
                                       estimatedMinutes: 45, provenance: "test")
        return DayPlan(date: date(i), kind: .lift, title: "Lift", generatedWorkout: workout)
    }

    private func suite() -> (UserDefaults, String) {
        let name = "today-widget-tests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    func test_nilPlan_givesNilSnapshot() {
        XCTAssertNil(TodayWidgetPublisher.snapshot(plan: nil, completedDays: [], calendar: cal))
    }

    func test_liftDay_titleAndCounts() throws {
        let snap = try XCTUnwrap(TodayWidgetPublisher.snapshot(plan: week([0: liftDay(0)]),
                                                               completedDays: [], calendar: cal))
        XCTAssertEqual(snap.days[0].kind, .lift)
        XCTAssertEqual(snap.days[0].title, "Upper Day 1")
        XCTAssertEqual(snap.days[0].detail, "2 exercises · 7 sets")
        XCTAssertFalse(snap.days[0].done)
    }

    func test_sportDay_usesSportNameAndMinutes() throws {
        let sport = DayPlan(date: date(1), kind: .sport, title: "Sport",
                            sport: Sport(slug: "skiing", name: "Skiing"), durationMinutes: 45)
        let bare = DayPlan(date: date(2), kind: .sport, title: "Sport")
        let snap = try XCTUnwrap(TodayWidgetPublisher.snapshot(plan: week([1: sport, 2: bare]),
                                                               completedDays: [], calendar: cal))
        XCTAssertEqual(snap.days[1].title, "Skiing")
        XCTAssertEqual(snap.days[1].detail, "About 45 min")
        XCTAssertEqual(snap.days[2].title, "Sport day")
        XCTAssertNil(snap.days[2].detail)
    }

    func test_restDay_neverDone() throws {
        let snap = try XCTUnwrap(TodayWidgetPublisher.snapshot(plan: week(),
                                                               completedDays: [date(0)], calendar: cal))
        XCTAssertEqual(snap.days[0].title, "Rest day")
        XCTAssertFalse(snap.days[0].done)
    }

    func test_completedDay_isDone() throws {
        let snap = try XCTUnwrap(TodayWidgetPublisher.snapshot(plan: week([0: liftDay(0), 1: liftDay(1)]),
                                                               completedDays: [date(0)], calendar: cal))
        XCTAssertTrue(snap.days[0].done)
        XCTAssertFalse(snap.days[1].done)
    }

    func test_dayLookup_acrossMidnight() throws {
        let snap = try XCTUnwrap(TodayWidgetPublisher.snapshot(plan: week(), completedDays: [], calendar: cal))
        let trimmed = TodayWidgetSnapshot(days: Array(snap.days.prefix(2)))
        let mondayLate = cal.date(bySettingHour: 23, minute: 59, second: 0, of: date(0))!
        XCTAssertEqual(trimmed.day(on: mondayLate, calendar: cal)?.date, date(0))
        XCTAssertEqual(trimmed.day(on: date(1), calendar: cal)?.date, date(1))
        XCTAssertNil(trimmed.day(on: date(2), calendar: cal))
    }

    func test_roundTrip_throughDefaults() throws {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let snap = try XCTUnwrap(TodayWidgetPublisher.snapshot(plan: week([0: liftDay(0)]),
                                                               completedDays: [date(0)], calendar: cal))
        XCTAssertNil(TodayWidgetSnapshot.load(from: defaults))
        snap.save(to: defaults)
        XCTAssertEqual(TodayWidgetSnapshot.load(from: defaults), snap)
    }

    // Expected: 1 reload for the initial publish, then none for the second
    // assignment of an equal plan, then 1 more for a changed plan.
    func test_publisher_writesOnceForEqualSnapshots() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let planStore = PlanStore(defaults: suite().0)
        let sessions = SessionStore(defaults: suite().0)
        var reloads = 0
        let publisher = TodayWidgetPublisher(planStore: planStore, store: sessions, defaults: defaults,
                                             calendar: cal, reload: { reloads += 1 })
        withExtendedLifetime(publisher) {
            XCTAssertEqual(reloads, 1)
            planStore.plan = week([0: liftDay(0)])
            XCTAssertEqual(reloads, 2)
            planStore.plan = week([0: liftDay(0)])
            XCTAssertEqual(reloads, 2)
            planStore.plan = week([0: DayPlan(date: date(0), kind: .event, title: "Race")])
            XCTAssertEqual(reloads, 3)
            XCTAssertNotNil(TodayWidgetSnapshot.load(from: defaults))
        }
    }

    func test_publisher_nilPlan_removesKey() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let planStore = PlanStore(defaults: suite().0)
        let sessions = SessionStore(defaults: suite().0)
        planStore.plan = week()
        var reloads = 0
        let publisher = TodayWidgetPublisher(planStore: planStore, store: sessions, defaults: defaults,
                                             calendar: cal, reload: { reloads += 1 })
        withExtendedLifetime(publisher) {
            XCTAssertNotNil(defaults.data(forKey: TodayWidgetSnapshot.defaultsKey))
            planStore.plan = nil
            XCTAssertNil(defaults.data(forKey: TodayWidgetSnapshot.defaultsKey))
            XCTAssertEqual(reloads, 2)
        }
    }

    // MARK: Widget day pick and timeline (Shared/Widget/TodayWidgetTimeline.swift)

    private func widgetDay(_ offset: Int, done: Bool = false, detail: String? = "6 exercises · 18 sets") -> TodayWidgetDay {
        TodayWidgetDay(date: date(offset), kind: .lift, title: "Upper Day \(offset)", detail: detail, done: done)
    }

    func test_text_noSnapshot_readsNoPlanYet() {
        let day = TodayWidgetTimeline.day(at: date(0), in: nil, calendar: cal)
        XCTAssertNil(day)
        XCTAssertEqual(TodayWidgetText(day: day),
                       TodayWidgetText(title: "No plan yet", detail: "Open Phase Training", done: false))
    }

    func test_text_dateOutsideSnapshot_readsNoPlanYet() {
        let snap = TodayWidgetSnapshot(days: [widgetDay(0)])
        let day = TodayWidgetTimeline.day(at: date(3), in: snap, calendar: cal)
        XCTAssertEqual(TodayWidgetText(day: day).title, "No plan yet")
    }

    func test_text_doneDay_replacesDetailWithDone() {
        let snap = TodayWidgetSnapshot(days: [widgetDay(0, done: true), widgetDay(1)])
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: date(0))!
        XCTAssertEqual(TodayWidgetText(day: TodayWidgetTimeline.day(at: noon, in: snap, calendar: cal)),
                       TodayWidgetText(title: "Upper Day 0", detail: "Done", done: true))
        XCTAssertEqual(TodayWidgetText(day: TodayWidgetTimeline.day(at: date(1), in: snap, calendar: cal)),
                       TodayWidgetText(title: "Upper Day 1", detail: "6 exercises · 18 sets", done: false))
    }

    func test_text_openDayWithoutDetail_hasNoSecondLine() {
        let text = TodayWidgetText(day: widgetDay(0, detail: nil))
        XCTAssertNil(text.detail)
        XCTAssertFalse(text.done)
    }

    func test_timeline_noSnapshot_isNowOnly() {
        let now = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date(0))!
        XCTAssertEqual(TodayWidgetTimeline.entryDates(now: now, snapshot: nil, calendar: cal), [now])
    }

    // Expected at Monday 09:00 with Mon to Wed: now, Tue 00:00, Wed 00:00, and
    // Thu 00:00 (the empty state after the last day). Monday's own midnight is past.
    func test_timeline_turnsOverAtEachMidnightThenEmpty() {
        let snap = TodayWidgetSnapshot(days: [widgetDay(0), widgetDay(1), widgetDay(2)])
        let now = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date(0))!
        let dates = TodayWidgetTimeline.entryDates(now: now, snapshot: snap, calendar: cal)
        XCTAssertEqual(dates, [now, date(1), date(2), date(3)])
        let titles = dates.map { TodayWidgetText(day: TodayWidgetTimeline.day(at: $0, in: snap, calendar: cal)).title }
        XCTAssertEqual(titles, ["Upper Day 0", "Upper Day 1", "Upper Day 2", "No plan yet"])
    }

    func test_timeline_nowAtMidnight_isNotDuplicated() {
        let snap = TodayWidgetSnapshot(days: [widgetDay(0), widgetDay(1)])
        let dates = TodayWidgetTimeline.entryDates(now: date(1), snapshot: snap, calendar: cal)
        XCTAssertEqual(dates, [date(1), date(2)])
    }

    func test_timeline_snapshotAllInPast_isNowOnly() {
        let snap = TodayWidgetSnapshot(days: [widgetDay(0), widgetDay(1)])
        let now = cal.date(bySettingHour: 8, minute: 0, second: 0, of: date(4))!
        XCTAssertEqual(TodayWidgetTimeline.entryDates(now: now, snapshot: snap, calendar: cal), [now])
        XCTAssertNil(TodayWidgetTimeline.day(at: now, in: snap, calendar: cal))
    }

    func test_timeline_unsortedDays_comeOutAscending() {
        let snap = TodayWidgetSnapshot(days: [widgetDay(2), widgetDay(0), widgetDay(1)])
        let now = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date(0))!
        XCTAssertEqual(TodayWidgetTimeline.entryDates(now: now, snapshot: snap, calendar: cal),
                       [now, date(1), date(2), date(3)])
    }
}
