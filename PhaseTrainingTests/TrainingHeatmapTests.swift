// TrainingHeatmapTests.swift — month grid behind the Progress heatmap.
//
// Covers TrainingHeatmap (Data/TrainingHeatmap.swift). Every case pins a UTC
// gregorian calendar and a fixed month; nothing reads the real clock.

import XCTest
@testable import PhaseTraining

final class TrainingHeatmapTests: XCTestCase {

    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = firstWeekday
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar().date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func session(_ start: Date, minutes: Int, name: String = "Upper") -> SavedSession {
        SavedSession(templateId: "t", name: name, category: "Strength",
                     startTime: start, exercises: [], feel: nil, note: nil,
                     endTime: start.addingTimeInterval(TimeInterval(minutes * 60)),
                     duration: minutes * 60)
    }

    // MARK: - Grid shape

    /// October 2026 starts on a Thursday and has 31 days: four blanks before
    /// the 1st on a Sunday-first grid, five rows, blanks after the 31st.
    func test_weeks_sundayFirst_padsToWholeWeeks() {
        let weeks = TrainingHeatmap.weeks(month: date(2026, 10, 15), sessions: [],
                                          calendar: calendar(firstWeekday: 1))
        XCTAssertEqual(weeks.count, 5)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(weeks[0].prefix(4).filter { $0 == nil }.count, 4)
        XCTAssertEqual(weeks[0][4]?.date, date(2026, 10, 1, 0))
        XCTAssertEqual(weeks.flatMap { $0 }.compactMap { $0 }.count, 31)
    }

    func test_weeks_mondayFirst_shiftsLeadingBlanks() {
        let weeks = TrainingHeatmap.weeks(month: date(2026, 10, 15), sessions: [],
                                          calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(weeks[0].prefix(3).filter { $0 == nil }.count, 3)
        XCTAssertEqual(weeks[0][3]?.date, date(2026, 10, 1, 0))
    }

    /// February 2026 starts on a Sunday and has exactly 28 days: no padding.
    func test_weeks_monthFillingExactRows_hasNoBlanks() {
        let weeks = TrainingHeatmap.weeks(month: date(2026, 2, 10), sessions: [],
                                          calendar: calendar(firstWeekday: 1))
        XCTAssertEqual(weeks.count, 4)
        XCTAssertFalse(weeks.flatMap { $0 }.contains { $0 == nil })
    }

    // MARK: - Session bucketing

    func test_sessionsBucketByStartDay_andIgnoreOtherMonths() {
        let sessions = [
            session(date(2026, 10, 3, 7), minutes: 40, name: "AM"),
            session(date(2026, 10, 3, 18), minutes: 30, name: "PM"),
            session(date(2026, 9, 30), minutes: 60),
            session(date(2026, 11, 1), minutes: 60),
        ]
        let days = TrainingHeatmap.weeks(month: date(2026, 10, 1), sessions: sessions,
                                         calendar: calendar())
            .flatMap { $0 }.compactMap { $0 }
        let third = days.first { $0.date == date(2026, 10, 3, 0) }!
        XCTAssertEqual(third.sessions.map(\.name), ["AM", "PM"])
        XCTAssertEqual(third.minutes, 70)
        XCTAssertEqual(days.reduce(0) { $0 + $1.sessions.count }, 2)
    }

    // MARK: - Levels

    func test_level_thresholds() {
        XCTAssertEqual(TrainingHeatmap.level(minutes: 0, sessionCount: 0), 0)
        XCTAssertEqual(TrainingHeatmap.level(minutes: 0, sessionCount: 1), 1,
                       "a zero-duration session still marks the day")
        XCTAssertEqual(TrainingHeatmap.level(minutes: 29, sessionCount: 1), 1)
        XCTAssertEqual(TrainingHeatmap.level(minutes: 30, sessionCount: 1), 2)
        XCTAssertEqual(TrainingHeatmap.level(minutes: 60, sessionCount: 1), 3)
        XCTAssertEqual(TrainingHeatmap.level(minutes: 90, sessionCount: 2), 4)
        XCTAssertEqual(TrainingHeatmap.level(minutes: 240, sessionCount: 3), 4)
    }

    // MARK: - Paging and headers

    func test_monthStart_offsetsAcrossYearBoundary() {
        let start = TrainingHeatmap.monthStart(offset: -10, now: date(2026, 10, 12),
                                               calendar: calendar())
        XCTAssertEqual(start, date(2025, 12, 1, 0))
    }

    func test_weekdaySymbols_rotateToFirstWeekday() {
        var cal = calendar(firstWeekday: 2)
        cal.locale = Locale(identifier: "en_US")
        XCTAssertEqual(TrainingHeatmap.weekdaySymbols(calendar: cal),
                       ["M", "T", "W", "T", "F", "S", "S"])
    }
}
