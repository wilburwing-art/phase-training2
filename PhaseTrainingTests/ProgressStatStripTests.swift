// ProgressStatStripTests.swift — SCAFFOLD (item 1 of 7).
//
// Covers the stat-strip helpers that ProgressScreen+StatCards.swift computes
// at render time: the weekly-target streak (incl. its grace week and the
// bounded-cursor guard that replaced a main-thread infinite loop), the
// this-week session count, and the PRs·30d filter.
//
// Requires the ProgressStats extraction (Data/ProgressStats.swift) so `now`
// is injectable — the originals call Date() inline, which would make every
// assertion flake across a Monday-midnight boundary.

import XCTest
@testable import PhaseTraining

final class ProgressStatStripTests: XCTestCase {

    func test_streak_countsConsecutiveWeeksMeetingTarget() { XCTFail("scaffold") }
    func test_streak_graceWeek_startsFromLastWeekWhenThisWeekShort() { XCTFail("scaffold") }
    func test_streak_gapWeekBreaksTheRun() { XCTFail("scaffold") }
    func test_streak_weekUnderTargetIsNotCounted() { XCTFail("scaffold") }
    func test_streak_emptyHistory_isZero() { XCTFail("scaffold") }
    func test_streak_terminatesWhenEveryKnownWeekMeetsTarget() { XCTFail("scaffold") }
    func test_thisWeekCount_sumsWeeksAtOrAfterThisWeekStart() { XCTFail("scaffold") }
    func test_prsInLastDays_filtersOnCutoff() { XCTFail("scaffold") }
}
