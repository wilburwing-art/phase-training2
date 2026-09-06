// ReadinessSignalTests — pure-function coverage for the Phase 2
// readiness scorer. All tests inject `now` so they stay deterministic
// across calendar boundaries.

import XCTest
@testable import PhaseTraining

final class ReadinessSignalTests: XCTestCase {

    // MARK: - Fixtures

    private func now() -> Date { Date(timeIntervalSince1970: 1_780_000_000) }

    /// Helper: spread N evenly-spaced events across the last `days` days.
    private func evenlySpaced(count: Int, overDays days: Double, anchor: Date) -> [ReadinessEvent] {
        guard count > 0 else { return [] }
        // The MOST RECENT event lands at (anchor - 1 day) so recency stays
        // sharp; spread the rest back over `days`.
        let stride = (days - 1) / Double(max(count - 1, 1))
        return (0..<count).map { i in
            ReadinessEvent(startTime: anchor.addingTimeInterval(-(1 + Double(i) * stride) * 86_400))
        }
    }

    // MARK: - Empty / neutral case

    func testEmptyEventsReturnsNeutral() {
        let s = ReadinessSignal.compute(events: [], now: now())
        XCTAssertEqual(s.score, 0.5, accuracy: 0.0001)
        XCTAssertEqual(s, .neutral)
    }

    // MARK: - High-density case (brief: 4 sessions/wk for 4 wks → ≥ 0.85)

    func testFourPerWeekFourWeeksScoresHigh() {
        // 4/wk × 4 wks = 16 events evenly spread over 28 days.
        let events = evenlySpaced(count: 16, overDays: 28, anchor: now())
        let s = ReadinessSignal.compute(events: events, now: now())
        XCTAssertGreaterThanOrEqual(s.score, 0.85,
            "Expected ≥ 0.85 for 4/wk × 4wk, got \(s.score) (density=\(s.breakdown.density), recency=\(s.breakdown.recency), trend=\(s.breakdown.trend))")
    }

    // MARK: - Zero-activity case (brief: 0 sessions/4 wks → ≤ 0.10)

    func testZeroSessionsScoresLow() {
        let s = ReadinessSignal.compute(events: [], now: now())
        // Empty case returns the neutral 0.5 sentinel — covered above.
        XCTAssertEqual(s, .neutral)

        // But if we have ONE old event from 30+ days ago and nothing recent,
        // density+recency should both pull hard.
        let stale = ReadinessEvent(startTime: now().addingTimeInterval(-32 * 86_400))
        let s2 = ReadinessSignal.compute(events: [stale], now: now())
        XCTAssertLessThanOrEqual(s2.score, 0.10,
            "Expected ≤ 0.10 for one stale event, got \(s2.score) (density=\(s2.breakdown.density), recency=\(s2.breakdown.recency), trend=\(s2.breakdown.trend))")
    }

    // MARK: - Trend: ramping (1→2→3/wk) vs flat (2/wk)

    func testRampingTrendBeatsFlatTrend() {
        // Ramping: 1 event in [-28..-21), 2 in [-21..-14), 3 in [-14..-7), 3 in [-7..0)
        // → recent14 = 6, prior14 = 3 → ratio 2.0 → clamped 1.5 → mapped 1.0
        let ramp: [ReadinessEvent] = [
            ReadinessEvent(startTime: now().addingTimeInterval(-25 * 86_400)),
            ReadinessEvent(startTime: now().addingTimeInterval(-18 * 86_400)),
            ReadinessEvent(startTime: now().addingTimeInterval(-17 * 86_400)),
            ReadinessEvent(startTime: now().addingTimeInterval(-12 * 86_400)),
            ReadinessEvent(startTime: now().addingTimeInterval(-9 * 86_400)),
            ReadinessEvent(startTime: now().addingTimeInterval(-5 * 86_400)),
            ReadinessEvent(startTime: now().addingTimeInterval(-3 * 86_400)),
            ReadinessEvent(startTime: now().addingTimeInterval(-1 * 86_400)),
        ]
        // Flat: 2/wk for 4 wks = 8 evenly spread.
        let flat = evenlySpaced(count: 8, overDays: 28, anchor: now())

        let sRamp = ReadinessSignal.compute(events: ramp, now: now())
        let sFlat = ReadinessSignal.compute(events: flat, now: now())

        XCTAssertGreaterThan(sRamp.breakdown.trend, sFlat.breakdown.trend,
            "Ramping trend should score higher than flat. ramp=\(sRamp.breakdown.trend) flat=\(sFlat.breakdown.trend)")
    }

    // MARK: - Density component — flat 3.0/wk norm
    //
    // The norm used to ladder by the user's age-derived era cohort. That axis
    // was removed, so every user normalizes against the same 3.0/wk.

    func testDensityUsesFlatNorm() {
        // 12 events in 4 weeks = 3/wk = exactly the norm → density 1.0.
        let events = evenlySpaced(count: 12, overDays: 28, anchor: now())
        let s = ReadinessSignal.compute(events: events, now: now())
        XCTAssertEqual(s.breakdown.density, 1.0, accuracy: 0.0001)
    }

    func testDensityScalesWithFrequency() {
        // Half the norm (6 events / 4wk = 1.5/wk) reads half as dense.
        let sparse = ReadinessSignal.compute(
            events: evenlySpaced(count: 6, overDays: 28, anchor: now()), now: now())
        let dense = ReadinessSignal.compute(
            events: evenlySpaced(count: 12, overDays: 28, anchor: now()), now: now())
        XCTAssertEqual(sparse.breakdown.density, 0.5, accuracy: 0.0001)
        XCTAssertLessThan(sparse.breakdown.density, dense.breakdown.density)
    }

    // MARK: - Recency component

    func testRecencyOneDayAgoIsMax() {
        let r = ReadinessSignal.recencyComponent(
            events: [ReadinessEvent(startTime: now().addingTimeInterval(-86_400))],
            now: now()
        )
        XCTAssertEqual(r, 1.0, accuracy: 0.001)
    }

    func testRecencyFourteenDaysIsLow() {
        let r = ReadinessSignal.recencyComponent(
            events: [ReadinessEvent(startTime: now().addingTimeInterval(-14 * 86_400))],
            now: now()
        )
        XCTAssertEqual(r, 0.1, accuracy: 0.001)
    }

    func testRecencyTwentyEightDaysIsFloor() {
        let r = ReadinessSignal.recencyComponent(
            events: [ReadinessEvent(startTime: now().addingTimeInterval(-30 * 86_400))],
            now: now()
        )
        XCTAssertEqual(r, 0.05, accuracy: 0.001)
    }

    // MARK: - Combine: any near-zero component drags the whole score

    func testZeroRecencyDragsHighDensityDown() {
        // density 1.0, trend 1.0, recency 0.05 → geometric mean << 1.0
        let combined = ReadinessSignal.combine(density: 1.0, recency: 0.05, trend: 1.0)
        XCTAssertLessThan(combined, 0.4,
            "Near-zero recency should drag the combined score below 0.4, got \(combined)")
    }

    func testAllOnesGivesOne() {
        let combined = ReadinessSignal.combine(density: 1.0, recency: 1.0, trend: 1.0)
        XCTAssertEqual(combined, 1.0, accuracy: 0.001)
    }

    func testScoreIsClampedToZeroOne() {
        // Force impossibly high density via direct combine call.
        let combined = ReadinessSignal.combine(density: 1.5, recency: 1.0, trend: 1.0)
        XCTAssertLessThanOrEqual(combined, 1.0)
        XCTAssertGreaterThanOrEqual(combined, 0.0)
    }
}
