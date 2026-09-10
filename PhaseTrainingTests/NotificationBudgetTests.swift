// NotificationBudgetTests.swift — PR 12 of the weekly-coach roadmap.
//
// Coverage:
//   - Daily cap: 3 delivered → 4th blocked; counters are per-day.
//   - Operational class bypasses the cap (rest timers must always fire).
//   - Suppression: 3 dismissals of a class in the window → blocked;
//     older dismissals fall out of the window.
//   - Per-class kill switch: disabled → blocked regardless of budget.
//   - Record helpers: delivered counts, dismissal log round-trip.

import XCTest
@testable import PhaseTraining

final class NotificationBudgetTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suite = "notif-budget-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private let day = Date(timeIntervalSince1970: 1_770_000_000)

    // MARK: - Daily cap

    func test_authorize_allowsFirstThreeDeliveries() {
        for _ in 0..<3 {
            XCTAssertTrue(NotificationBudget.authorize(cls: .weeklyPlan, now: day, defaults: defaults))
            NotificationBudget.recordDelivered(cls: .weeklyPlan, now: day, defaults: defaults)
        }
        // 4th push of the day is over the cap.
        XCTAssertFalse(NotificationBudget.authorize(cls: .weeklyPlan, now: day, defaults: defaults))
    }

    func test_deliveredCount_resetsNextDay() {
        for _ in 0..<3 {
            NotificationBudget.recordDelivered(cls: .weeklyPlan, now: day, defaults: defaults)
        }
        let nextDay = day.addingTimeInterval(2 * 86_400)
        XCTAssertEqual(NotificationBudget.deliveredCount(now: nextDay, defaults: defaults), 0)
        XCTAssertTrue(NotificationBudget.authorize(cls: .weeklyPlan, now: nextDay, defaults: defaults))
    }

    func test_operationalClass_bypassesDailyCap() {
        for _ in 0..<5 {
            XCTAssertTrue(NotificationBudget.authorize(cls: .operational, now: day, defaults: defaults))
            NotificationBudget.recordDelivered(cls: .operational, now: day, defaults: defaults)
        }
        // Also doesn't consume the shared budget.
        XCTAssertEqual(NotificationBudget.deliveredCount(now: day, defaults: defaults), 0)
    }

    // MARK: - Suppression

    func test_threeDismissalsSuppressClass() {
        for _ in 0..<3 {
            NotificationBudget.recordDismissal(cls: .coachMilestone, now: day, defaults: defaults)
        }
        XCTAssertFalse(NotificationBudget.authorize(cls: .coachMilestone, now: day, defaults: defaults))
        // Other classes unaffected.
        XCTAssertTrue(NotificationBudget.authorize(cls: .weeklyPlan, now: day, defaults: defaults))
    }

    func test_dismissalsFallOutOfWindow() {
        let old = day.addingTimeInterval(-Double(NotificationBudget.suppressionWindowDays + 2) * 86_400)
        for _ in 0..<3 {
            NotificationBudget.recordDismissal(cls: .coachMilestone, now: old, defaults: defaults)
        }
        XCTAssertTrue(NotificationBudget.authorize(cls: .coachMilestone, now: day, defaults: defaults))
    }

    // MARK: - Kill switch

    func test_disabledClass_isBlocked_evenUnderBudget() {
        NotificationBudget.setEnabled(false, for: .missedWorkout, defaults: defaults)
        XCTAssertFalse(NotificationBudget.authorize(cls: .missedWorkout, now: day, defaults: defaults))
        XCTAssertFalse(NotificationBudget.isEnabled(.missedWorkout, defaults: defaults))
        // Re-enable.
        NotificationBudget.setEnabled(true, for: .missedWorkout, defaults: defaults)
        XCTAssertTrue(NotificationBudget.authorize(cls: .missedWorkout, now: day, defaults: defaults))
    }

    // MARK: - Priority order

    func test_priorityOrder_missedBeforeWeeklyBeforeMilestone() {
        XCTAssertLessThan(NotificationBudget.Class.missedWorkout.priority,
                          NotificationBudget.Class.weeklyPlan.priority)
        XCTAssertLessThan(NotificationBudget.Class.weeklyPlan.priority,
                          NotificationBudget.Class.coachMilestone.priority)
    }

    // MARK: - Log round-trip

    func test_dismissalLog_persistsAcrossInstances() {
        NotificationBudget.recordDismissal(cls: .weeklyPlan, now: day, defaults: defaults)
        NotificationBudget.recordDismissal(cls: .weeklyPlan, now: day.addingTimeInterval(60), defaults: defaults)
        XCTAssertEqual(NotificationBudget.recentDismissals(of: .weeklyPlan, now: day.addingTimeInterval(120), defaults: defaults), 2)
    }

    func test_deliveryCounter_prunesOldDays() {
        NotificationBudget.recordDelivered(cls: .weeklyPlan, now: day, defaults: defaults)
        let muchLater = day.addingTimeInterval(30 * 86_400)
        NotificationBudget.recordDelivered(cls: .weeklyPlan, now: muchLater, defaults: defaults)
        // The 30-day-old counter was swept.
        XCTAssertEqual(NotificationBudget.deliveredCount(now: day, defaults: defaults), 0)
        XCTAssertEqual(NotificationBudget.deliveredCount(now: muchLater, defaults: defaults), 1)
    }
}
