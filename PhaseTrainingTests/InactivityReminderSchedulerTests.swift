import XCTest
@testable import PhaseTraining

/// T1-55 landed a generation token so a schedule that is mid-await when the
/// user taps Finish drops its write instead of firing "Still training?" thirty
/// minutes after the workout is already in history. Nothing pinned it. The
/// notification center itself is not unit-testable; the token is, and the
/// token IS the fix.
@MainActor
final class InactivityReminderSchedulerTests: XCTestCase {

    func test_bumpInvalidatesTheOutstandingGeneration() {
        let g1 = InactivityReminderScheduler.bumpGeneration()
        XCTAssertTrue(InactivityReminderScheduler.isCurrent(g1))
        _ = InactivityReminderScheduler.bumpGeneration()
        XCTAssertFalse(InactivityReminderScheduler.isCurrent(g1),
                       "an older schedule must see itself as stale after any newer bump")
    }

    func test_cancelInvalidatesAnInFlightSchedule() {
        // The race: schedule (bump A, suspend on notificationSettings), then
        // Finish -> cancel (bump B). When A resumes it must not write.
        let inFlight = InactivityReminderScheduler.bumpGeneration()
        InactivityReminderScheduler.cancel()
        XCTAssertFalse(InactivityReminderScheduler.isCurrent(inFlight),
                       "cancel must bump so the awaiting schedule drops its add")
    }

    func test_generationIsMonotonic() {
        let a = InactivityReminderScheduler.bumpGeneration()
        let b = InactivityReminderScheduler.bumpGeneration()
        let c = InactivityReminderScheduler.bumpGeneration()
        XCTAssertLessThan(a, b); XCTAssertLessThan(b, c)
        XCTAssertTrue(InactivityReminderScheduler.isCurrent(c))
        XCTAssertFalse(InactivityReminderScheduler.isCurrent(b))
    }
}
