// ProgressBodyCardTests.swift — body-weight / body-composition card math.
//
// Covers the derivations behind ProgressScreen+BodyCards.swift, extracted to
// ProgressStats so they're reachable from a test.
//
// The rule worth the most here is latest-per-metric. Composition entries are
// sparse by source: a DEXA scan reports both body fat and lean mass, a
// consumer scale reports only body fat, and a caliper log may report neither
// consistently. Reading `log.last?.bodyFatPercent` would blank the BF stat
// the moment a lean-only reading landed on top, while the BF sparkline below
// it kept rendering from the full series — a trend line above a missing
// number.

import XCTest
@testable import PhaseTraining

final class ProgressBodyCardTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private lazy var t0 = Date(timeIntervalSince1970: 1_770_000_000)

    private func composition(daysIn: Int,
                             bf: Double? = nil,
                             lean: Double? = nil) -> BodyCompositionEntry {
        BodyCompositionEntry(
            date: t0.addingTimeInterval(Double(daysIn) * day),
            bodyFatPercent: bf,
            leanMassKg: lean
        )
    }

    private func bodyWeight(daysIn: Int, kg: Double) -> BodyWeightEntry {
        BodyWeightEntry(date: t0.addingTimeInterval(Double(daysIn) * day), weightKg: kg)
    }

    // MARK: - Latest per metric

    func test_latestBF_ignoresNewerLeanOnlyEntry() {
        let log = [
            composition(daysIn: 0, bf: 22.0, lean: 60.0),
            composition(daysIn: 10, bf: 20.5, lean: 61.0),
            composition(daysIn: 20, lean: 62.0),   // lean-only, newest
        ]
        XCTAssertEqual(ProgressStats.latestBodyFatPercent(in: log), 20.5)
        XCTAssertEqual(ProgressStats.latestLeanMassKg(in: log), 62.0)
    }

    func test_latestLean_ignoresNewerBFOnlyEntry() {
        let log = [
            composition(daysIn: 0, bf: 22.0, lean: 60.0),
            composition(daysIn: 10, bf: 21.0),     // scale reading, BF only
            composition(daysIn: 20, bf: 20.0),     // scale reading, newest
        ]
        XCTAssertEqual(ProgressStats.latestLeanMassKg(in: log), 60.0)
        XCTAssertEqual(ProgressStats.latestBodyFatPercent(in: log), 20.0)
    }

    func test_latestPerMetric_nilWhenMetricNeverLogged() {
        let log = [composition(daysIn: 0, bf: 18.0), composition(daysIn: 5, bf: 17.5)]
        XCTAssertNil(ProgressStats.latestLeanMassKg(in: log))
        XCTAssertEqual(ProgressStats.latestBodyFatPercent(in: log), 17.5)
    }

    func test_latestPerMetric_readsChronologicallyNotByArrayOrder() {
        // The card sorts before rendering; the helpers sort too, so an
        // unsorted log can't yield a "latest" from the middle of the log.
        let log = [
            composition(daysIn: 20, bf: 20.0),
            composition(daysIn: 0, bf: 22.0),
            composition(daysIn: 10, bf: 21.0),
        ]
        XCTAssertEqual(ProgressStats.latestBodyFatPercent(in: log), 20.0)
    }

    func test_latestPerMetric_emptyLogIsNil() {
        XCTAssertNil(ProgressStats.latestBodyFatPercent(in: []))
        XCTAssertNil(ProgressStats.latestLeanMassKg(in: []))
    }

    // MARK: - Series

    func test_compositionSeries_skipNilReadingsPerMetric() {
        let log = [
            composition(daysIn: 0, bf: 22.0, lean: 60.0),
            composition(daysIn: 10, bf: 21.0),      // no lean
            composition(daysIn: 20, lean: 62.0),    // no BF
        ]
        XCTAssertEqual(ProgressStats.bodyFatSeries(in: log), [22.0, 21.0])
        XCTAssertEqual(
            ProgressStats.leanMassSeries(in: log, imperial: false),
            [60.0, 62.0]
        )
    }

    func test_leanMassSeries_convertsToPoundsWhenImperial() {
        let log = [composition(daysIn: 0, lean: 60.0), composition(daysIn: 10, lean: 62.0)]
        let lb = ProgressStats.leanMassSeries(in: log, imperial: true)
        XCTAssertEqual(lb.count, 2)
        XCTAssertEqual(lb[0], BodyMetrics.kgToLb(60.0), accuracy: 0.0001)
        XCTAssertEqual(lb[1], BodyMetrics.kgToLb(62.0), accuracy: 0.0001)
    }

    func test_compositionSeries_orderedOldestFirst() {
        let log = [
            composition(daysIn: 20, bf: 20.0),
            composition(daysIn: 0, bf: 22.0),
            composition(daysIn: 10, bf: 21.0),
        ]
        XCTAssertEqual(ProgressStats.bodyFatSeries(in: log), [22.0, 21.0, 20.0])
    }

    // MARK: - trendDelta

    func test_trendDelta_nilUnderTwoPoints() {
        XCTAssertNil(ProgressStats.trendDelta([]))
        XCTAssertNil(ProgressStats.trendDelta([18.5]))
    }

    func test_trendDelta_signedFirstToLast() {
        // Body fat down is a negative delta (the card tints that .ok).
        XCTAssertEqual(ProgressStats.trendDelta([22.0, 21.0, 20.0])!, -2.0, accuracy: 0.0001)
        // Lean mass up is a positive delta (also .ok, opposite sign).
        XCTAssertEqual(ProgressStats.trendDelta([60.0, 62.0])!, 2.0, accuracy: 0.0001)
        // Flat series has a delta of zero, not nil — the chip renders "+0.0".
        XCTAssertEqual(ProgressStats.trendDelta([60.0, 60.0])!, 0.0, accuracy: 0.0001)
    }

    func test_trendDelta_usesEndpointsNotExtremes() {
        // A dip and recovery nets out; the card reports net change, not range.
        XCTAssertEqual(
            ProgressStats.trendDelta([80.0, 74.0, 80.0])!, 0.0, accuracy: 0.0001
        )
    }

    // MARK: - Body weight

    func test_bodyWeightDelta_signedAgainstFirstEntry() {
        let log = [
            bodyWeight(daysIn: 0, kg: 80.0),
            bodyWeight(daysIn: 7, kg: 79.0),
            bodyWeight(daysIn: 14, kg: 78.5),
        ]
        XCTAssertEqual(ProgressStats.bodyWeightDeltaKg(in: log)!, -1.5, accuracy: 0.0001)
        XCTAssertEqual(ProgressStats.latestBodyWeightKg(in: log)!, 78.5, accuracy: 0.0001)
    }

    func test_bodyWeightDelta_nilForSingleEntry() {
        // One weigh-in is a value, not a trend. The card renders no delta
        // chip, so deltaColor's .ink3 branch is unreachable in practice.
        let log = [bodyWeight(daysIn: 0, kg: 80.0)]
        XCTAssertNil(ProgressStats.bodyWeightDeltaKg(in: log))
        XCTAssertEqual(ProgressStats.latestBodyWeightKg(in: log)!, 80.0, accuracy: 0.0001)
    }

    func test_bodyWeightDelta_emptyLogIsNil() {
        XCTAssertNil(ProgressStats.bodyWeightDeltaKg(in: []))
        XCTAssertNil(ProgressStats.latestBodyWeightKg(in: []))
    }

    func test_bodyWeight_readsChronologicallyNotByArrayOrder() {
        let log = [
            bodyWeight(daysIn: 14, kg: 78.5),
            bodyWeight(daysIn: 0, kg: 80.0),
            bodyWeight(daysIn: 7, kg: 79.0),
        ]
        XCTAssertEqual(ProgressStats.latestBodyWeightKg(in: log)!, 78.5, accuracy: 0.0001)
        XCTAssertEqual(ProgressStats.bodyWeightDeltaKg(in: log)!, -1.5, accuracy: 0.0001)
    }
}
