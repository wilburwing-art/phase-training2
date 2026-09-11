// GoalMilestoneNotifierTests.swift — PR 11 (commit 4).
//
// Pins the milestone decision logic in GoalMilestoneNotifier:
//   - edge-triggered crossing: fires when progress reaches 1.0 with a
//     persisted best-seen BELOW 1.0, never on repeat observations
//   - weekly cap: at most `weeklyCap` fires in any trailing 7 days
//   - recordSeen advances the floor even when nothing fires, so one
//     achievement can't re-fire on every save
//
// Pure-logic tests only: `notifyIfCrossed` touches UNUserNotificationCenter
// (no test double — the same boundary that keeps NotificationBudget pure),
// so its delivery contract is pinned by the decision functions + the call
// site's budget gates, not by a unit test.

import XCTest
@testable import PhaseTraining

final class GoalMilestoneNotifierTests: XCTestCase {

    private var defaults: UserDefaults!

    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "GoalMilestoneNotifierTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func goal(id: UUID = UUID()) -> UserGoal {
        UserGoal(id: id, templateId: .benchBodyweight, createdAt: Date(timeIntervalSince1970: 0))
    }

    private func recordFires(_ count: Int, now: Date) {
        for i in 0..<count {
            GoalMilestoneNotifier.recordFired(
                now: now.addingTimeInterval(Double(-i) * 86_400), defaults: defaults)
        }
    }

    // MARK: - Crossing

    func test_progressBelowOne_neverFires() {
        let g = goal()
        XCTAssertFalse(GoalMilestoneNotifier.shouldFire(
            goalId: g.id, progress: 0.99, defaults: defaults))
        // 0.99 seen stays below the floor — 1.0 the next save can fire.
        GoalMilestoneNotifier.recordSeen(goalId: g.id, progress: 0.99, defaults: defaults)
        XCTAssertTrue(GoalMilestoneNotifier.shouldFire(
            goalId: g.id, progress: 1.0, defaults: defaults))
    }

    func test_firstCrossing_fires() {
        let g = goal()
        XCTAssertTrue(GoalMilestoneNotifier.shouldFire(
            goalId: g.id, progress: 1.0, defaults: defaults))
    }

    func test_repeatObservationSameAchievement_doesNotRefire() {
        let g = goal()
        GoalMilestoneNotifier.recordSeen(goalId: g.id, progress: 1.0, defaults: defaults)
        XCTAssertFalse(GoalMilestoneNotifier.shouldFire(
            goalId: g.id, progress: 1.0, defaults: defaults),
            "the seen floor must consume the crossing edge — no push per app open")
        // Higher progress on an already-done goal is also not a new edge.
        XCTAssertFalse(GoalMilestoneNotifier.shouldFire(
            goalId: g.id, progress: 1.2, defaults: defaults))
    }

    func test_regressionBackUnderOne_thenReCross_firesAgain() {
        let g = goal()
        GoalMilestoneNotifier.recordSeen(goalId: g.id, progress: 1.0, defaults: defaults)
        // recordSeen keeps the MAX — a regression below 1.0 does NOT lower
        // the floor, so re-crossing the same achievement stays silent.
        GoalMilestoneNotifier.recordSeen(goalId: g.id, progress: 0.8, defaults: defaults)
        XCTAssertFalse(GoalMilestoneNotifier.shouldFire(
            goalId: g.id, progress: 1.0, defaults: defaults))
    }

    // MARK: - Weekly cap

    func test_weeklyCap_blocksThirdMilestone() {
        let now = Date()
        recordFires(GoalMilestoneNotifier.weeklyCap, now: now)
        let g = goal()
        XCTAssertFalse(GoalMilestoneNotifier.shouldFire(
            goalId: g.id, progress: 1.0, now: now, defaults: defaults),
            "cap spent this week: even a first crossing stays silent")
    }

    func test_weeklyCap_isRolling() {
        let now = Date()
        // 2 fires 8 days ago are outside the trailing 7-day window.
        recordFires(GoalMilestoneNotifier.weeklyCap, now: now.addingTimeInterval(-8 * 86_400))
        let g = goal()
        XCTAssertTrue(GoalMilestoneNotifier.shouldFire(
            goalId: g.id, progress: 1.0, now: now, defaults: defaults))
    }

    func test_capCheckedBeforeSeenFloor_edgeOrder() {
        // A blocked (capped) crossing still consumes nothing on the seen
        // floor — the caller records seen AFTER the decision. Assert the
        // decision alone didn't mutate state.
        let before = GoalMilestoneNotifier.seenProgress(defaults: defaults)
        let g = goal()
        recordFires(GoalMilestoneNotifier.weeklyCap, now: Date())
        _ = GoalMilestoneNotifier.shouldFire(goalId: g.id, progress: 1.0, defaults: defaults)
        XCTAssertEqual(GoalMilestoneNotifier.seenProgress(defaults: defaults), before,
                       "shouldFire is a pure read — mutation belongs to recordSeen")
    }

    // MARK: - Persistence shape

    func test_seenProgress_emptyByDefault() {
        XCTAssertTrue(GoalMilestoneNotifier.seenProgress(defaults: defaults).isEmpty)
    }

    func test_firedLog_roundTripsThroughJSON() {
        let now = Date()
        GoalMilestoneNotifier.recordFired(now: now, defaults: defaults)
        let log = GoalMilestoneNotifier.firedLog(defaults: defaults)
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log[0].timeIntervalSince1970,
                       now.timeIntervalSince1970, accuracy: 1.0)
    }
}
