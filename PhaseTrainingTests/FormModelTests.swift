// FormModelTests.swift — fitness-fatigue form (1b split) and its load events.

import XCTest
@testable import PhaseTraining

final class FormModelTests: XCTestCase {

    private let monday = Date(timeIntervalSince1970: 1_759_104_000) // 2025-09-29, a Monday UTC
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(_ day: Int, hour: Double = 0) -> Date {
        monday.addingTimeInterval(Double(day) * 86_400 + hour * 3600)
    }

    private func hours(_ h: Double, on days: [Int]) -> [ReadinessEvent] {
        days.map { ReadinessEvent(startTime: at($0, hour: 17), duration: h * 3600) }
    }

    private func form(_ events: [ReadinessEvent], day: Int = 0) -> Double? {
        FormModel.form(events: events, at: at(day), calendar: utc)
    }

    func test_noLoadInTheWindow_isNoData() {
        XCTAssertNil(form([]))
        XCTAssertNil(form(hours(1, on: [-(FormModel.windowDays + 1)])), "older than the window")
        XCTAssertNil(form(hours(1, on: [0, 1])), "on or after the target day")
    }

    func test_loadEqualToTheStartingState_isNeutral() throws {
        // Half an hour every day matches the initial fitness and fatigue exactly.
        let steady = hours(FormModel.initialLoad, on: Array(-FormModel.windowDays ..< 0))
        XCTAssertEqual(try XCTUnwrap(form(steady)), 0.5, accuracy: 1e-9)
    }

    func test_aHardBlockLowersForm_andATaperRestoresIt() throws {
        let base = hours(1, on: stride(from: -60, to: -14, by: 2).map { $0 })
        let block = hours(2, on: Array(-14 ..< 0))
        let tired = try XCTUnwrap(form(base + block))
        XCTAssertLessThan(tired, 0.5)
        let rested = try XCTUnwrap(form(base + block, day: 7))
        XCTAssertGreaterThan(rested, tired)
        XCTAssertGreaterThan(rested, 0.5, "a week off after a block: fatigue gone, fitness kept")
    }

    func test_sameDayEventsAdd_andOrderDoesNotMatter() throws {
        let split = hours(0.5, on: [-3, -3, -5])
        let whole = hours(1, on: [-3]) + hours(0.5, on: [-5])
        XCTAssertEqual(try XCTUnwrap(form(split)), try XCTUnwrap(form(whole)), accuracy: 1e-12)
        XCTAssertEqual(form(split), form(split.reversed()))
    }

    // MARK: - buildLoadEvents

    private func session(_ day: Int, minutes: Int) -> SavedSession {
        SavedSession(templateId: "t", name: "Lift", category: "", startTime: at(day, hour: 17), exercises: [],
                     feel: nil, note: nil, endTime: at(day, hour: 17).addingTimeInterval(Double(minutes) * 60),
                     duration: minutes * 60)
    }

    private func imported(_ day: Int, minutes: Int) -> ImportedWorkout {
        ImportedWorkout(id: "hk-\(day)", source: .healthKit, kind: .strength, startTime: at(day, hour: 17),
                        duration: Double(minutes) * 60, energyKcal: nil)
    }

    func test_loadEvents_carryMinutes_andTakeTheLargestSourcePerDay() throws {
        let hard = SportLogEntry(date: at(-2, hour: 9), sport: Sport(slug: "climbing", name: "Climbing"),
                                 durationMinutes: 120, intensity: .hard, note: nil, loggedAt: at(-2, hour: 9))
        let events = GeneratorContext.buildLoadEvents(
            sessions: [session(-1, minutes: 60), session(-1, minutes: 30)],
            importedWorkouts: [imported(-1, minutes: 70)],
            sportLogs: [hard],
            now: at(0, hour: 8), calendar: utc)
        let byDay = Dictionary(uniqueKeysWithValues: events.map { ($0.startTime, $0.duration / 60) })
        XCTAssertEqual(byDay[at(-1)], 90, "two in-app sessions add; the watch copy of one does not stack")
        XCTAssertEqual(byDay[at(-2)], 120, "hard sport is load")
        XCTAssertEqual(events.count, 2)
    }

    func test_loadEvents_skipTodayOnwardAndOutsideTheWindow() {
        let events = GeneratorContext.buildLoadEvents(
            sessions: [session(0, minutes: 60), session(-(FormModel.windowDays + 1), minutes: 60)],
            importedWorkouts: [], sportLogs: [], now: at(0, hour: 8), calendar: utc)
        XCTAssertTrue(events.isEmpty)
    }
}
