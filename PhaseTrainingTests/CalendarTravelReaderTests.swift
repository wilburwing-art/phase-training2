import EventKit
import XCTest
@testable import PhaseTraining

final class CalendarTravelReaderTests: XCTestCase {

    private var denver: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        denver.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func test_unreadableStatusesReturnDenied() async {
        for status in [EKAuthorizationStatus.denied, .restricted, .writeOnly] {
            let result = await CalendarTravelReader.findTravel(
                weekStart: Date(), calendar: denver, store: EKEventStore(), status: status)
            XCTAssertEqual(result, .denied, "status \(status.rawValue)")
        }
    }

    func test_readWindowIsTwoDaysEachSideOfTheWeek() throws {
        let w = try XCTUnwrap(CalendarTravelReader.readWindow(weekStart: date(2026, 5, 11, 15), calendar: denver))
        XCTAssertEqual(w.start, date(2026, 5, 11, 0))
        XCTAssertEqual(w.from, date(2026, 5, 9, 0))
        XCTAssertEqual(w.to, date(2026, 5, 20, 0))
    }

    func test_readWindowAcrossDSTChangeStillLandsOnMidnights() throws {
        let w = try XCTUnwrap(CalendarTravelReader.readWindow(weekStart: date(2026, 3, 6, 15), calendar: denver))
        XCTAssertEqual(w.start, date(2026, 3, 6, 0))
        XCTAssertEqual(w.from, date(2026, 3, 4, 0))
        XCTAssertEqual(w.to, date(2026, 3, 15, 0))
        for d in [w.start, w.from, w.to] {
            XCTAssertEqual(denver.startOfDay(for: d), d)
        }
    }
}
