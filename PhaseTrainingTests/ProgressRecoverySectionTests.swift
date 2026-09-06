// ProgressRecoverySectionTests.swift — SCAFFOLD (item 5 of 7).
//
// ProgressRecoverySection had no tests at all. Covers the headline
// "FRESH MUSCLE GROUPS" count (which must count only the mainSlugs the list
// below renders — it once counted all 80 muscle_groups rows and read 70+),
// days-since-last-workout, the silhouette highlight map, and side(forSlug:)
// coverage of mainSlugs.

import XCTest
@testable import PhaseTraining

final class ProgressRecoverySectionTests: XCTestCase {

    func test_freshCount_countsOnlyMainSlugs() { XCTFail("scaffold") }
    func test_freshCount_excludesFatiguedMuscles() { XCTFail("scaffold") }
    func test_sideForSlug_resolvesEveryMainSlugOrDefersDeliberately() { XCTFail("scaffold") }
    func test_daysSinceLastWorkout_nilWithNoSessions() { XCTFail("scaffold") }
    func test_daysSinceLastWorkout_floorsToCalendarDays() { XCTFail("scaffold") }
    func test_daysSinceLastWorkout_clampsFutureDatedSession() { XCTFail("scaffold") }
    func test_recoveryHighlights_excludesNoneIntensity() { XCTFail("scaffold") }
}
