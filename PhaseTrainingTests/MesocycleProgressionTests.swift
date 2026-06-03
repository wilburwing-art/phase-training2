import XCTest
@testable import PhaseTraining

/// Build 103 — MesocycleProgression decides whether the user's badge
/// should warn about an upcoming deload, render a deload pill, or stay
/// quiet. The rules here are also the source of truth for the badge
/// copy on Today / Progress / Week, so the boundaries matter.
final class MesocycleProgressionTests: XCTestCase {

    func test_cycleLengths_perPhase() {
        XCTAssertEqual(MesocycleProgression.cycleLength(for: .offSeason), 4)
        XCTAssertEqual(MesocycleProgression.cycleLength(for: .preSeason), 4)
        XCTAssertEqual(MesocycleProgression.cycleLength(for: .inSeason), 6)
        XCTAssertEqual(MesocycleProgression.cycleLength(for: .eventPrep), 4)
        // Maintenance is intentionally 0 — no programmed deload cycle.
        XCTAssertEqual(MesocycleProgression.cycleLength(for: .maintenance), 0)
    }

    func test_buildWeeksReturnBuildState() {
        let week1 = MesocycleProgression.status(phase: .preSeason, weeksInPhase: 1, daysUntilPeak: nil)
        XCTAssertEqual(week1.state, .build)
        XCTAssertEqual(week1.weekOfCycle, 1)
        XCTAssertEqual(week1.badge, "BUILD W1")

        let week2 = MesocycleProgression.status(phase: .preSeason, weeksInPhase: 2, daysUntilPeak: nil)
        XCTAssertEqual(week2.state, .build)
        XCTAssertEqual(week2.weekOfCycle, 2)
    }

    func test_secondToLastWeekWarnsDeloadNext() {
        // 4-week cycle: week 3 = "deload next week"
        let s = MesocycleProgression.status(phase: .preSeason, weeksInPhase: 3, daysUntilPeak: nil)
        XCTAssertEqual(s.state, .deloadNextWeek)
        XCTAssertEqual(s.weekOfCycle, 3)
        XCTAssertEqual(s.badge, "DELOAD NEXT")
    }

    func test_lastWeekIsDeload() {
        let s = MesocycleProgression.status(phase: .preSeason, weeksInPhase: 4, daysUntilPeak: nil)
        XCTAssertEqual(s.state, .deload)
        XCTAssertEqual(s.weekOfCycle, 4)
        XCTAssertEqual(s.badge, "DELOAD WK")
    }

    func test_cycleWrapsAtWeek5() {
        // Week 5 of a 4-week cycle → week 1 of next cycle (build).
        let s = MesocycleProgression.status(phase: .preSeason, weeksInPhase: 5, daysUntilPeak: nil)
        XCTAssertEqual(s.state, .build)
        XCTAssertEqual(s.weekOfCycle, 1)
    }

    func test_inSeasonHasLongerCycle_deloadsAtWeek6() {
        // 6-week in-season cycle. Week 5 = deload-next, week 6 = deload, week 7 = build w1.
        XCTAssertEqual(MesocycleProgression.status(phase: .inSeason, weeksInPhase: 5, daysUntilPeak: nil).state, .deloadNextWeek)
        XCTAssertEqual(MesocycleProgression.status(phase: .inSeason, weeksInPhase: 6, daysUntilPeak: nil).state, .deload)
        XCTAssertEqual(MesocycleProgression.status(phase: .inSeason, weeksInPhase: 7, daysUntilPeak: nil).state, .build)
        XCTAssertEqual(MesocycleProgression.status(phase: .inSeason, weeksInPhase: 7, daysUntilPeak: nil).weekOfCycle, 1)
    }

    func test_maintenance_isOffCycle() {
        let s = MesocycleProgression.status(phase: .maintenance, weeksInPhase: 3, daysUntilPeak: nil)
        XCTAssertEqual(s.state, .offCycle)
        XCTAssertNil(s.weekOfCycle)
        XCTAssertEqual(s.badge, "")
    }

    func test_nilWeeksReturnsOffCycle() {
        let s = MesocycleProgression.status(phase: .preSeason, weeksInPhase: nil, daysUntilPeak: nil)
        XCTAssertEqual(s.state, .offCycle)
    }

    // MARK: - Event prep

    func test_eventPrepWithinSevenDaysOfPeak_isTaper() {
        let s = MesocycleProgression.status(phase: .eventPrep, weeksInPhase: 2, daysUntilPeak: 5)
        XCTAssertEqual(s.state, .taper)
        XCTAssertEqual(s.badge, "TAPER")
    }

    func test_eventPrepBetweenSevenAndFourteenDays_warnsTaperNext() {
        let s = MesocycleProgression.status(phase: .eventPrep, weeksInPhase: 2, daysUntilPeak: 10)
        XCTAssertEqual(s.state, .deloadNextWeek)
        XCTAssertEqual(s.badge, "TAPER NEXT")
    }

    func test_eventPrepOnPeakDay_isPeak() {
        let s = MesocycleProgression.status(phase: .eventPrep, weeksInPhase: 4, daysUntilPeak: 0)
        XCTAssertEqual(s.state, .peak)
        XCTAssertEqual(s.badge, "PEAK")
    }

    func test_eventPrepAfterPeak_stillFlagsPeak() {
        let s = MesocycleProgression.status(phase: .eventPrep, weeksInPhase: 5, daysUntilPeak: -2)
        XCTAssertEqual(s.state, .peak)
    }

    func test_eventPrepFarFromPeak_fallsThroughToCycle() {
        // 21 days out → outside taper window → normal cycle math (4-week cycle).
        let s = MesocycleProgression.status(phase: .eventPrep, weeksInPhase: 2, daysUntilPeak: 21)
        XCTAssertEqual(s.state, .build)
        XCTAssertEqual(s.weekOfCycle, 2)
    }

    func test_eventPrepWithoutPeakDate_fallsThroughToCycleMath() {
        let s = MesocycleProgression.status(phase: .eventPrep, weeksInPhase: 4, daysUntilPeak: nil)
        XCTAssertEqual(s.state, .deload)
        XCTAssertEqual(s.weekOfCycle, 4)
    }
}
