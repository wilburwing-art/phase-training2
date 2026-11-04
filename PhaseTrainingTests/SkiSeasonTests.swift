import HealthKit
import XCTest
@testable import PhaseTraining

/// Ski days this season: Health workouts and the sport log, one count per day.
final class SkiSeasonTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func workout(_ type: HKWorkoutActivityType, _ start: Date, minutes: Double = 60,
                         descent: Double? = nil, own: Bool = false) -> HKWorkoutLike {
        HKWorkoutLike(uuid: UUID(), activityType: type, startDate: start, duration: minutes * 60,
                      totalEnergyBurnedKcal: nil,
                      sourceBundleId: own ? HealthWorkoutTag.bundlePrefix : "com.apple.health",
                      elevationDescendedMeters: descent)
    }

    private func log(_ slug: String, _ day: Date) throws -> SportLogEntry {
        SportLogEntry(date: cal.startOfDay(for: day),
                      sport: try XCTUnwrap(Sport.catalog.first { $0.slug == slug }),
                      durationMinutes: 240, intensity: .hard, note: nil, loggedAt: day)
    }

    func test_seasonStartsAugFirst() {
        XCTAssertEqual(SkiSeason.seasonStart(now: date(2026, 11, 3), calendar: cal), date(2026, 8, 1, 0))
        XCTAssertEqual(SkiSeason.seasonStart(now: date(2026, 7, 31), calendar: cal), date(2025, 8, 1, 0))
    }

    func test_runsOnOneDayAreOneDay_crossCountryAndOldWorkoutsAreOut() {
        let now = date(2027, 1, 20)
        let s = SkiSeason.summarize(workouts: [
            workout(.downhillSkiing, date(2027, 1, 10, 9), minutes: 20),
            workout(.downhillSkiing, date(2027, 1, 10, 11)),
            workout(.snowboarding, date(2027, 1, 10, 14)),
            workout(.crossCountrySkiing, date(2027, 1, 12)),
            workout(.downhillSkiing, date(2026, 7, 20)),
        ], sportLogs: [], now: now, calendar: cal)
        XCTAssertEqual(s.days, 1)
        XCTAssertEqual(s.lastDay, date(2027, 1, 10, 0))
    }

    func test_sportLogUnionsWithHealthByDay() throws {
        let now = date(2027, 1, 20)
        let s = SkiSeason.summarize(
            workouts: [workout(.downhillSkiing, date(2027, 1, 10))],
            sportLogs: [try log("alpine-skiing", date(2027, 1, 10)),
                        try log("snowboarding", date(2027, 1, 14)),
                        try log("climbing", date(2027, 1, 15))],
            now: now, calendar: cal)
        XCTAssertEqual(s.days, 2, "the logged Jan 10 is the same day as the workout; Jan 14 adds one")
        XCTAssertNil(s.verticalMeters)
        XCTAssertEqual(s.daysWithVertical, 0)
    }

    func test_verticalSumsOnlyWorkoutsThatCarryIt() {
        let now = date(2027, 1, 20)
        let s = SkiSeason.summarize(workouts: [
            workout(.downhillSkiing, date(2027, 1, 10), descent: 3000),
            workout(.downhillSkiing, date(2027, 1, 11), descent: 2500),
            workout(.downhillSkiing, date(2027, 1, 12)),
        ], sportLogs: [], now: now, calendar: cal)
        XCTAssertEqual(s.days, 3)
        XCTAssertEqual(s.verticalMeters, 5500)
        XCTAssertEqual(s.daysWithVertical, 2)
        XCTAssertEqual(SkiSeason.verticalLabel(meters: 5500, imperial: false), "5,500 m")
        XCTAssertEqual(SkiSeason.verticalLabel(meters: 5500, imperial: true), "18,045 ft")
    }

    func test_appWrittenWorkoutsDoNotCount() {
        let s = SkiSeason.summarize(workouts: [workout(.downhillSkiing, date(2027, 1, 10), own: true)],
                                    sportLogs: [], now: date(2027, 1, 20), calendar: cal)
        XCTAssertEqual(s.days, 0)
    }
}
