// PlanHistoryTests.swift — coverage for PR 4 of the weekly-coach roadmap.
//
// Pins the snapshot infrastructure that every later PR builds on:
//   - WeekPlanSnapshot.capture/trim
//   - PlanStore.snapshotCurrentPlan idempotency by weekStart
//   - PlanStore.shape(forWeek:) join of snapshot + sessions
//   - 12-week rolling cap
//   - persistence round-trip
//   - CoachContext.snapshot emits a PAST WEEKS block

import XCTest
@testable import PhaseTraining

final class PlanHistoryTests: XCTestCase {

    // MARK: - Helpers

    private func makePlan(weekStart: Date,
                         liftDays: Int = 3,
                         sportDays: Int = 0) -> WeekPlan {
        let cal = Calendar.current
        let mondayStart = weekStart.startOfTrainingWeek(calendar: cal)
        let kinds: [DayKind] = {
            var k: [DayKind] = []
            for i in 0..<7 {
                if i < liftDays               { k.append(.lift) }
                else if i < liftDays + sportDays { k.append(.sport) }
                else                          { k.append(.rest) }
            }
            return k
        }()
        let days = (0..<7).map { i -> DayPlan in
            DayPlan(
                date: cal.date(byAdding: .day, value: i, to: mondayStart) ?? mondayStart,
                kind: kinds[i],
                title: kinds[i] == .lift ? "Push" : kinds[i] == .sport ? "Climbing" : "Rest",
                routineId: nil,
                generatedWorkout: nil,
                generatedReason: "test"
            )
        }
        return WeekPlan(days: days, generatedAt: Date(), inputsHash: "test")
    }

    private func makeSession(on date: Date, name: String = "Workout") -> SavedSession {
        SavedSession(
            templateId: "t",
            name: name,
            category: "",
            startTime: date,
            exercises: [],
            feel: nil,
            note: nil,
            endTime: date.addingTimeInterval(3600),
            duration: 3600
        )
    }

    private func freshStore() -> PlanStore {
        let suite = "plan-history-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PlanStore(defaults: defaults)
    }

    // MARK: - WeekPlanSnapshot.capture

    func test_capture_pickWeekStartFromFirstDay() {
        let cal = Calendar.current
        let monday = Date(timeIntervalSince1970: 1_700_092_800)  // 2023-11-16 (Thu), normalize to Monday
        let mondayOfThatWeek = monday.startOfTrainingWeek(calendar: cal)
        let plan = makePlan(weekStart: mondayOfThatWeek, liftDays: 3)
        let snap = WeekPlanSnapshot.capture(plan, sessions: [], now: Date(timeIntervalSince1970: 1_700_300_000))
        XCTAssertTrue(cal.isDate(snap.weekStart, inSameDayAs: mondayOfThatWeek))
    }

    func test_capture_filtersSessionsToWeekWindow() {
        let cal = Calendar.current
        let now = Date(timeIntervalSince1970: 1_700_092_800)
        let monday = now.startOfTrainingWeek(calendar: cal)
        let plan = makePlan(weekStart: monday, liftDays: 3)
        // Three sessions: two inside the week, one before, one after
        let beforeWeek = cal.date(byAdding: .day, value: -2, to: monday)!
        let inWeek1 = cal.date(byAdding: .day, value: 1, to: monday)!
        let inWeek2 = cal.date(byAdding: .day, value: 4, to: monday)!
        let afterWeek = cal.date(byAdding: .day, value: 9, to: monday)!
        let sessions = [
            makeSession(on: beforeWeek),
            makeSession(on: inWeek1),
            makeSession(on: inWeek2),
            makeSession(on: afterWeek),
        ]
        let snap = WeekPlanSnapshot.capture(plan, sessions: sessions, now: now)
        XCTAssertEqual(snap.actualSessionIDs.count, 2)
        XCTAssertTrue(snap.actualSessionIDs.contains(inWeek1.timeIntervalSince1970))
        XCTAssertTrue(snap.actualSessionIDs.contains(inWeek2.timeIntervalSince1970))
    }

    // MARK: - WeekPlanSnapshot.trim

    func test_trim_dedupesByWeekStartLatestWins() {
        let week = Date(timeIntervalSince1970: 1_700_092_800).startOfTrainingWeek()
        let plan = makePlan(weekStart: week)
        let early = WeekPlanSnapshot(weekStart: week, plan: plan,
                                     actualSessionIDs: [],
                                     capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let late = WeekPlanSnapshot(weekStart: week, plan: plan,
                                    actualSessionIDs: [1, 2, 3],
                                    capturedAt: Date(timeIntervalSince1970: 1_700_500_000))
        let result = WeekPlanSnapshot.trim([early, late])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].actualSessionIDs.count, 3,
                       "later capture should replace earlier one for same weekStart")
    }

    func test_trim_capsToLimit() {
        let cal = Calendar.current
        let base = Date(timeIntervalSince1970: 1_700_092_800).startOfTrainingWeek()
        // 15 weeks of snapshots
        let snaps: [WeekPlanSnapshot] = (0..<15).map { i in
            let ws = cal.date(byAdding: .day, value: -7 * i, to: base)!.startOfTrainingWeek()
            return WeekPlanSnapshot(weekStart: ws, plan: makePlan(weekStart: ws),
                                    actualSessionIDs: [],
                                    capturedAt: Date())
        }
        let trimmed = WeekPlanSnapshot.trim(snaps, limit: 12)
        XCTAssertEqual(trimmed.count, 12)
        // Newest first
        for i in 0..<(trimmed.count - 1) {
            XCTAssertGreaterThan(trimmed[i].weekStart, trimmed[i + 1].weekStart)
        }
    }

    // MARK: - WeekPlanSnapshot.completionRatio

    func test_completionRatio_zeroWhenNoPlannedWorkouts() {
        let monday = Date(timeIntervalSince1970: 1_700_092_800).startOfTrainingWeek()
        let plan = makePlan(weekStart: monday, liftDays: 0, sportDays: 0)
        let snap = WeekPlanSnapshot.capture(plan, sessions: [], now: monday)
        XCTAssertEqual(snap.completionRatio(in: []), 0)
    }

    func test_completionRatio_collapsesMultiSessionDays() {
        let cal = Calendar.current
        let monday = Date(timeIntervalSince1970: 1_700_092_800).startOfTrainingWeek()
        let plan = makePlan(weekStart: monday, liftDays: 3)
        let day1 = cal.date(byAdding: .day, value: 0, to: monday)!
        // Two sessions on day 1, none elsewhere → 1/3 days completed
        let sessions = [
            makeSession(on: day1),
            makeSession(on: day1.addingTimeInterval(7200)),
        ]
        let snap = WeekPlanSnapshot.capture(plan, sessions: sessions, now: monday)
        XCTAssertEqual(snap.completedSessionCount(in: sessions), 1)
        XCTAssertEqual(snap.completionRatio(in: sessions), 1.0 / 3.0, accuracy: 0.01)
    }

    // MARK: - PlanStore snapshot triggers

    func test_setPlan_capturesSnapshot() {
        let store = freshStore()
        let monday = Date().startOfTrainingWeek()
        let plan = makePlan(weekStart: monday)
        store.setPlan(plan)
        XCTAssertEqual(store.pastPlans.count, 1)
        XCTAssertTrue(Calendar.current.isDate(store.pastPlans[0].weekStart,
                                              inSameDayAs: monday))
    }

    func test_setPlan_idempotentByWeekStart() {
        let store = freshStore()
        let monday = Date().startOfTrainingWeek()
        let v1 = makePlan(weekStart: monday, liftDays: 3)
        let v2 = makePlan(weekStart: monday, liftDays: 5)
        store.setPlan(v1)
        store.setPlan(v2)
        XCTAssertEqual(store.pastPlans.count, 1,
                       "two setPlan calls for the same week should produce one snapshot")
        XCTAssertEqual(store.pastPlans[0].plannedLiftDays, 5,
                       "latest setPlan content wins")
    }

    func test_setPlan_separateWeeksAccumulate() {
        let store = freshStore()
        let cal = Calendar.current
        let monday = Date().startOfTrainingWeek()
        let priorMonday = cal.date(byAdding: .day, value: -7, to: monday)!.startOfTrainingWeek()
        store.setPlan(makePlan(weekStart: priorMonday))
        store.setPlan(makePlan(weekStart: monday))
        XCTAssertEqual(store.pastPlans.count, 2)
        XCTAssertGreaterThan(store.pastPlans[0].weekStart, store.pastPlans[1].weekStart,
                             "newest snapshot listed first")
    }

    // MARK: - PlanStore.shape(forWeek:)

    func test_shape_returnsNilWhenNoSnapshot() {
        let store = freshStore()
        XCTAssertNil(store.shape(forWeek: Date()))
    }

    func test_shape_joinsSnapshotWithSessions() {
        let store = freshStore()
        let cal = Calendar.current
        let monday = Date().startOfTrainingWeek()
        let plan = makePlan(weekStart: monday, liftDays: 3)

        // Stub a SessionStore manually — PlanStore reads sessionStore?.savedSessions
        let sessionStore = SessionStore(defaults: UserDefaults(suiteName: "stub-\(UUID())")!)
        let day1 = cal.date(byAdding: .day, value: 0, to: monday)!
        let day2 = cal.date(byAdding: .day, value: 1, to: monday)!
        sessionStore.savedSessions = [
            makeSession(on: day1),
            makeSession(on: day2),
        ]
        store.sessionStore = sessionStore
        store.setPlan(plan)

        let shape = store.shape(forWeek: monday)
        XCTAssertNotNil(shape)
        XCTAssertEqual(shape?.plannedLiftDays, 3)
        XCTAssertEqual(shape?.completedLiftDays, 2)
        XCTAssertEqual(shape?.completionRatio ?? 0, 2.0 / 3.0, accuracy: 0.01)
    }

    // MARK: - Persistence

    func test_persistsAcrossInstances() {
        let suite = "plan-history-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let monday = Date().startOfTrainingWeek()
        do {
            let store = PlanStore(defaults: defaults)
            store.setPlan(makePlan(weekStart: monday, liftDays: 4))
            XCTAssertEqual(store.pastPlans.count, 1)
        }
        let reopened = PlanStore(defaults: defaults)
        XCTAssertEqual(reopened.pastPlans.count, 1,
                       "snapshots should survive a fresh PlanStore init from the same defaults")
        XCTAssertEqual(reopened.pastPlans[0].plannedLiftDays, 4)
    }

    func test_clearWipesHistory() {
        let store = freshStore()
        store.setPlan(makePlan(weekStart: Date().startOfTrainingWeek()))
        XCTAssertEqual(store.pastPlans.count, 1)
        store.clear()
        XCTAssertEqual(store.pastPlans.count, 0)
    }

    // MARK: - 12-week cap

    func test_rollingCapDropsOldest() {
        let store = freshStore()
        let cal = Calendar.current
        let monday = Date().startOfTrainingWeek()
        // Set 15 weeks of plans, each older than the last
        for i in 0..<15 {
            let week = cal.date(byAdding: .day, value: -7 * i, to: monday)!.startOfTrainingWeek()
            store.setPlan(makePlan(weekStart: week))
        }
        XCTAssertEqual(store.pastPlans.count, PlanStore.pastPlansLimit)
        // Verify the OLDEST week was dropped (14 weeks ago)
        let oldestKept = store.pastPlans.last!.weekStart
        let expectedOldest = cal.date(byAdding: .day, value: -7 * (PlanStore.pastPlansLimit - 1),
                                      to: monday)!.startOfTrainingWeek()
        XCTAssertTrue(cal.isDate(oldestKept, inSameDayAs: expectedOldest))
    }

    // MARK: - CoachContext block

    func test_coachContext_emitsPastWeeksBlock() {
        let cal = Calendar.current
        let now = Date()
        let monday = now.startOfTrainingWeek()
        let priorMonday = cal.date(byAdding: .day, value: -7, to: monday)!.startOfTrainingWeek()
        let plan = makePlan(weekStart: priorMonday, liftDays: 3)
        let snap = WeekPlanSnapshot.capture(plan, sessions: [], now: now)

        let blob = CoachContext.snapshot(
            now: now,
            activeTab: .today,
            memory: TrainingMemory(),
            plan: nil,
            recentSessions: [],
            recentFeedback: [],
            recentSoreness: [],
            pastPlans: [snap]
        )
        XCTAssertTrue(blob.contains("PAST WEEKS"),
                      "Coach context should include the PAST WEEKS block when history exists")
        XCTAssertTrue(blob.contains("planned 3"),
                      "Block should report planned workout count")
    }

    func test_coachContext_excludesCurrentWeekFromBlock() {
        // The current (in-flight) week shouldn't show in PAST WEEKS because
        // its completion ratio is meaningless on a Monday-morning snapshot.
        let now = Date()
        let monday = now.startOfTrainingWeek()
        let plan = makePlan(weekStart: monday, liftDays: 3)
        let snap = WeekPlanSnapshot.capture(plan, sessions: [], now: now)

        let blob = CoachContext.snapshot(
            now: now,
            activeTab: .today,
            memory: TrainingMemory(),
            plan: nil,
            recentSessions: [],
            recentFeedback: [],
            recentSoreness: [],
            pastPlans: [snap]
        )
        XCTAssertFalse(blob.contains("PAST WEEKS"),
                       "Snapshot of the current week should not appear in PAST WEEKS")
    }
}
