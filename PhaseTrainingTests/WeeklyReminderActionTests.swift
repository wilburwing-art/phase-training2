import XCTest
@testable import PhaseTraining

/// D1 — Sunday-push day-count quick-action plumbing: action id → deep link,
/// and deep link → lift-day count. (The notification tap itself isn't
/// UI-test-drivable; these cover the pure mapping the delegate + .onOpenURL use.)
final class WeeklyReminderActionTests: XCTestCase {

    func test_dayCountAction_mapsToSetLiftDaysDeepLink() {
        XCTAssertEqual(WeeklyReminderScheduler.deepLink(forAction: "pt.lift_days.3"),
                       "phasetraining://set-lift-days?n=3")
        XCTAssertEqual(WeeklyReminderScheduler.deepLink(forAction: "pt.lift_days.2"),
                       "phasetraining://set-lift-days?n=2")
    }

    func test_openAction_mapsToPlanWeek() {
        XCTAssertEqual(WeeklyReminderScheduler.deepLink(forAction: "pt.lift_days.open"),
                       "phasetraining://plan-week")
    }

    func test_unknownAction_returnsNil() {
        XCTAssertNil(WeeklyReminderScheduler.deepLink(forAction: "something.else"))
        XCTAssertNil(WeeklyReminderScheduler.deepLink(
            forAction: "com.apple.UNNotificationDefaultActionIdentifier"))
    }

    func test_liftDays_parsesFromDeepLink() {
        XCTAssertEqual(WeeklyReminderScheduler.liftDays(
            fromDeepLink: URL(string: "phasetraining://set-lift-days?n=4")!), 4)
        XCTAssertNil(WeeklyReminderScheduler.liftDays(
            fromDeepLink: URL(string: "phasetraining://plan-week")!))
        XCTAssertNil(WeeklyReminderScheduler.liftDays(
            fromDeepLink: URL(string: "phasetraining://set-lift-days")!))
    }
}
