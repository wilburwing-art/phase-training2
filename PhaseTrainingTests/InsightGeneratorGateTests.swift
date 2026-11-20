import XCTest
@testable import PhaseTraining

@MainActor
final class InsightGeneratorGateTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: now)!
    }

    private func session(daysAgo n: Int) -> SavedSession {
        SavedSession(templateId: "t", name: "Lift", category: "", startTime: daysAgo(n), exercises: [],
                     feel: nil, note: nil, endTime: daysAgo(n), duration: 0)
    }

    private func gate(
        memory: TrainingMemory = TrainingMemory(),
        sessions: [SavedSession] = [],
        consent: Bool = true,
        available: Bool = true,
        pro: Bool = true,
        inFlight: Bool = false
    ) -> InsightGenerator.Gate {
        InsightGenerator.gate(memory: memory, sessions: sessions, consentGranted: consent, now: now,
                              available: available, pro: pro, inFlight: inFlight)
    }

    private func memoryWithFeedback(daysAgo n: Int) -> TrainingMemory {
        var m = TrainingMemory()
        m.feedback = [FeedbackEntry(date: daysAgo(n))]
        return m
    }

    func test_unavailableWinsOverEverything() {
        XCTAssertEqual(gate(memory: memoryWithFeedback(daysAgo: 1), sessions: [session(daysAgo: 1)],
                            available: false), .coachUnavailable)
    }

    func test_noConsent() {
        XCTAssertEqual(gate(memory: memoryWithFeedback(daysAgo: 1), consent: false), .noConsent)
    }

    func test_notPro() {
        XCTAssertEqual(gate(memory: memoryWithFeedback(daysAgo: 1), pro: false), .notPro)
    }

    func test_inFlight() {
        XCTAssertEqual(gate(memory: memoryWithFeedback(daysAgo: 1), inFlight: true), .inFlight)
    }

    func test_insightToday_blocks() {
        var m = memoryWithFeedback(daysAgo: 1)
        m.coachInsights = [CoachInsight(date: now, body: "x")]
        XCTAssertEqual(gate(memory: m), .alreadyToday)
    }

    func test_insightYesterday_doesNotBlock() {
        var m = memoryWithFeedback(daysAgo: 1)
        m.coachInsights = [CoachInsight(date: daysAgo(1), body: "x")]
        XCTAssertEqual(gate(memory: m), .due)
    }

    func test_noSignal() {
        XCTAssertEqual(gate(), .noSignal)
    }

    func test_sorenessWithoutPain_isNotASignal() {
        var m = TrainingMemory()
        m.soreness = [SorenessEntry(date: daysAgo(1), pain: false)]
        XCTAssertEqual(gate(memory: m), .noSignal)
    }

    func test_sessionFourDaysAgo_isNotASignal() {
        XCTAssertEqual(gate(sessions: [session(daysAgo: 4)]), .noSignal)
    }

    func test_feedbackAlone_isDue() {
        XCTAssertEqual(gate(memory: memoryWithFeedback(daysAgo: 6)), .due)
    }

    func test_painSorenessAlone_isDue() {
        var m = TrainingMemory()
        m.soreness = [SorenessEntry(date: daysAgo(6), pain: true)]
        XCTAssertEqual(gate(memory: m), .due)
    }

    func test_recentSessionAlone_isDue() {
        XCTAssertEqual(gate(sessions: [session(daysAgo: 2)]), .due)
    }
}
