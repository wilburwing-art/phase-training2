import XCTest
@testable import PhaseTraining

/// Build 103 — BodyMetricsMerger turns a batch of HK samples into appends
/// to TrainingMemory.bodyWeightLog + bodyCompositionLog, de-duplicating
/// against entries that are already there (so a re-sync doesn't spam the
/// log). Composition samples taken within the same minute collapse onto
/// one entry — most smart scales emit BF% and lean within the same
/// second, but the underlying HK timestamps differ slightly.
final class BodyMetricsMergerTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func bm(_ kind: HKBodyMetricSample.Kind, daysAgo: Int, value: Double) -> HKBodyMetricSample {
        HKBodyMetricSample(
            uuid: UUID(),
            kind: kind,
            date: base.addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            value: value
        )
    }

    func test_emptySamples_returnsLogsUnchanged() {
        let result = BodyMetricsMerger.merge(weightLog: [], compositionLog: [], samples: [])
        XCTAssertTrue(result.weight.isEmpty)
        XCTAssertTrue(result.composition.isEmpty)
        XCTAssertEqual(result.summary.addedWeightEntries, 0)
        XCTAssertEqual(result.summary.addedCompositionEntries, 0)
        XCTAssertNil(result.summary.newestSampleAt)
    }

    func test_weightSamples_appendToWeightLog() {
        let samples = [
            bm(.bodyMass, daysAgo: 10, value: 80.0),
            bm(.bodyMass, daysAgo: 5,  value: 79.5),
        ]
        let result = BodyMetricsMerger.merge(weightLog: [], compositionLog: [], samples: samples)
        XCTAssertEqual(result.weight.count, 2)
        // Sorted newest-first
        XCTAssertGreaterThan(result.weight[0].date, result.weight[1].date)
        XCTAssertEqual(result.summary.addedWeightEntries, 2)
    }

    func test_pairedBFAndLean_collapseOntoOneEntry() {
        // Both samples within the same minute → one BodyCompositionEntry.
        let lean = bm(.leanBodyMass, daysAgo: 5, value: 65.0)
        let bf = HKBodyMetricSample(
            uuid: UUID(),
            kind: .bodyFatPercent,
            date: lean.date.addingTimeInterval(2),  // 2 seconds later
            value: 18.5
        )
        let result = BodyMetricsMerger.merge(weightLog: [], compositionLog: [], samples: [lean, bf])
        XCTAssertEqual(result.composition.count, 1)
        XCTAssertEqual(result.composition[0].bodyFatPercent, 18.5)
        XCTAssertEqual(result.composition[0].leanMassKg, 65.0)
        XCTAssertEqual(result.summary.addedCompositionEntries, 1)
    }

    func test_distinctMinutes_remainDistinctEntries() {
        // Two readings 5 minutes apart → two entries.
        let bf1 = bm(.bodyFatPercent, daysAgo: 10, value: 19.0)
        let bf2 = HKBodyMetricSample(
            uuid: UUID(),
            kind: .bodyFatPercent,
            date: bf1.date.addingTimeInterval(60 * 5),
            value: 18.8
        )
        let result = BodyMetricsMerger.merge(weightLog: [], compositionLog: [], samples: [bf1, bf2])
        XCTAssertEqual(result.composition.count, 2)
    }

    func test_duplicateWeightSample_skipped() {
        // Existing entry at T; HK sample within a minute of T should not
        // re-write the row.
        let existing = BodyWeightEntry(date: base, weightKg: 80.0)
        let sample = HKBodyMetricSample(
            uuid: UUID(),
            kind: .bodyMass,
            date: base.addingTimeInterval(15),  // 15s later
            value: 80.05
        )
        let result = BodyMetricsMerger.merge(
            weightLog: [existing],
            compositionLog: [],
            samples: [sample]
        )
        XCTAssertEqual(result.weight.count, 1)
        XCTAssertEqual(result.summary.addedWeightEntries, 0)
        XCTAssertEqual(result.summary.skippedDuplicateSamples, 1)
    }

    func test_duplicateCompositionSample_skipped() {
        let existing = BodyCompositionEntry(date: base, bodyFatPercent: 19.0)
        let sample = HKBodyMetricSample(
            uuid: UUID(),
            kind: .bodyFatPercent,
            date: base.addingTimeInterval(30),
            value: 19.1
        )
        let result = BodyMetricsMerger.merge(
            weightLog: [],
            compositionLog: [existing],
            samples: [sample]
        )
        XCTAssertEqual(result.composition.count, 1)
        XCTAssertEqual(result.summary.addedCompositionEntries, 0)
        XCTAssertEqual(result.summary.skippedDuplicateSamples, 1)
    }

    func test_summaryTracksNewestSampleTimestamp() {
        let samples = [
            bm(.bodyMass, daysAgo: 30, value: 78.0),
            bm(.bodyMass, daysAgo: 1,  value: 77.5),
            bm(.bodyMass, daysAgo: 15, value: 77.8),
        ]
        let result = BodyMetricsMerger.merge(weightLog: [], compositionLog: [], samples: samples)
        XCTAssertEqual(result.summary.newestSampleAt, base.addingTimeInterval(-1 * 86_400))
    }

    func test_pairedReading_straddlingMinuteBoundary_stillCollapses() {
        // BF% at 10:00:58 and lean at 10:01:02 — 4s apart but across a
        // wall-clock minute. The old minute-floor split these into two rows;
        // proximity clustering must keep them as one reading.
        let bfDate = Date(timeIntervalSince1970: 1_700_000_058)  // …:58
        let leanDate = Date(timeIntervalSince1970: 1_700_000_062) // …:02 next min
        let bf = HKBodyMetricSample(uuid: UUID(), kind: .bodyFatPercent, date: bfDate, value: 18.0)
        let lean = HKBodyMetricSample(uuid: UUID(), kind: .leanBodyMass, date: leanDate, value: 64.0)
        let result = BodyMetricsMerger.merge(weightLog: [], compositionLog: [], samples: [bf, lean])
        XCTAssertEqual(result.composition.count, 1, "paired reading across a minute boundary must collapse to one row")
        XCTAssertEqual(result.composition[0].bodyFatPercent, 18.0)
        XCTAssertEqual(result.composition[0].leanMassKg, 64.0)
    }

    func test_compositionEntry_keepsRealTimestamp_notMinuteFloor() {
        // Entry date must be the real sample time, not floored to the minute.
        let d = Date(timeIntervalSince1970: 1_700_000_037)  // …:37
        let bf = HKBodyMetricSample(uuid: UUID(), kind: .bodyFatPercent, date: d, value: 20.0)
        let result = BodyMetricsMerger.merge(weightLog: [], compositionLog: [], samples: [bf])
        XCTAssertEqual(result.composition[0].date, d, "entry should keep the real timestamp, not a minute floor")
    }

    func test_dedup_usesRealTimestamps_noFalseSkipFromFlooring() {
        // Existing entry at 10:01:05; a genuinely new reading at 10:02:50
        // (105s later). Under the old floored-bucket comparison the buckets
        // (10:01:00 vs 10:02:00) were 55s apart and wrongly deduped. Real
        // timestamps are 105s apart → must be kept.
        let existing = BodyCompositionEntry(
            date: Date(timeIntervalSince1970: 1_700_000_065),  // 10:01:05
            bodyFatPercent: 19.0
        )
        let newSample = HKBodyMetricSample(
            uuid: UUID(),
            kind: .bodyFatPercent,
            date: Date(timeIntervalSince1970: 1_700_000_170),  // 10:02:50, +105s
            value: 18.5
        )
        let result = BodyMetricsMerger.merge(
            weightLog: [],
            compositionLog: [existing],
            samples: [newSample]
        )
        XCTAssertEqual(result.composition.count, 2, "a reading 105s away must not be deduped")
        XCTAssertEqual(result.summary.addedCompositionEntries, 1)
    }

    func test_existingLog_preserved_newSamplesAppended() {
        // User has an old DEXA entry; HK samples include 2 new fresher
        // readings + a re-read of the same day. The old entry should
        // survive, the 2 new should land, the duplicate gets skipped.
        let old = BodyCompositionEntry(
            date: base.addingTimeInterval(-90 * 86_400),
            bodyFatPercent: 22.0,
            leanMassKg: 60.0,
            method: "DEXA"
        )
        let newBF1 = bm(.bodyFatPercent, daysAgo: 30, value: 20.5)
        let newBF2 = bm(.bodyFatPercent, daysAgo: 5,  value: 19.5)
        let dup = HKBodyMetricSample(
            uuid: UUID(),
            kind: .bodyFatPercent,
            date: old.date.addingTimeInterval(20),
            value: 22.1
        )
        let result = BodyMetricsMerger.merge(
            weightLog: [],
            compositionLog: [old],
            samples: [newBF1, newBF2, dup]
        )
        XCTAssertEqual(result.composition.count, 3) // old + 2 new
        XCTAssertEqual(result.summary.addedCompositionEntries, 2)
        XCTAssertEqual(result.summary.skippedDuplicateSamples, 1)
    }
}
