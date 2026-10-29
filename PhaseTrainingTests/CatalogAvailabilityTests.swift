import XCTest
@testable import PhaseTraining

/// One clear failure for the one infrastructure fault that fails dozens of
/// catalog tests at once.
///
/// The test host reads `coach.db` straight from the installed app bundle.
/// If anything reinstalls the app on this simulator while the suite runs
/// (another `xcodebuild`, a `simctl install`, a second session on the same
/// device), SQLite logs "vnode unlinked while in use" and every catalog
/// query returns empty from then on. Reproduced 2026-10-29 by running
/// `simctl install` mid-suite.
final class CatalogAvailabilityTests: XCTestCase {

    func test_bundledCatalogIsReadable() {
        XCTAssertGreaterThan(
            CoachDatabase.shared.exerciseCount(), 100,
            """
            coach.db returned no exercises. If the log shows "vnode unlinked while in use", \
            the app was reinstalled on this simulator during the run: re-run on an idle \
            simulator, and treat the other catalog failures in this run as noise.
            """)
    }
}
