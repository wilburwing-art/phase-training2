import XCTest
@testable import PhaseTraining

/// Build 103 follow-up — the weightKg ↔ bodyWeightLog funnel. These lock the
/// invariant that the scalar consumers read (strength ratios, generator) and
/// the trend series can't drift, and that no path nulls a legitimately-set
/// weight.
final class BodyWeightReconcileTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func test_recordBodyWeight_mirrorsScalarToNewest() {
        var mem = TrainingMemory()
        mem.recordBodyWeight(80, on: base)
        XCTAssertEqual(mem.weightKg, 80)
        XCTAssertEqual(mem.bodyWeightLog.count, 1)
    }

    func test_recordBodyWeight_backDatedDoesNotClobberNewerScalar() {
        var mem = TrainingMemory()
        mem.recordBodyWeight(78, on: base)                       // newest
        mem.recordBodyWeight(85, on: base.addingTimeInterval(-30 * 86_400)) // older
        // Scalar must still reflect the genuinely-newest entry (78), not the
        // just-appended older one.
        XCTAssertEqual(mem.weightKg, 78)
    }

    func test_remirror_doesNotNullScalarWhenLogEmpties() {
        var mem = TrainingMemory()
        mem.weightKg = 80                 // onboarded scalar, no log entry
        mem.recordBodyWeight(75, on: base) // now log=[75], scalar=75
        mem.bodyWeightLog.removeAll()      // user deletes the only entry
        mem.remirrorWeightFromLog()
        // Scalar is preserved (75), NOT nulled — the strength-ratios card
        // must not vanish on a delete.
        XCTAssertEqual(mem.weightKg, 75)
    }

    func test_backfill_seedsScalarIntoEmptyLogOnce() {
        var mem = TrainingMemory()
        mem.weightKg = 82
        mem.onboardedAt = base
        mem.backfillBodyWeightLogFromScalar()
        XCTAssertEqual(mem.bodyWeightLog.count, 1)
        XCTAssertEqual(mem.bodyWeightLog.first?.weightKg, 82)
        XCTAssertEqual(mem.bodyWeightLog.first?.date, base)
        // Idempotent — a second call doesn't add a duplicate.
        mem.backfillBodyWeightLogFromScalar()
        XCTAssertEqual(mem.bodyWeightLog.count, 1)
    }

    func test_backfill_noOpWithoutScalar() {
        var mem = TrainingMemory()
        mem.weightKg = nil
        mem.backfillBodyWeightLogFromScalar()
        XCTAssertTrue(mem.bodyWeightLog.isEmpty)
    }

    func test_reconcile_appendsOnGenuineChange() {
        var mem = TrainingMemory()
        mem.recordBodyWeight(78, on: base)   // log newest = 78
        mem.weightKg = 82                     // About You writes scalar directly
        mem.reconcileScalarIntoLog(on: base.addingTimeInterval(86_400))
        XCTAssertEqual(mem.bodyWeightLog.count, 2)
        XCTAssertEqual(mem.latestBodyWeightEntry?.weightKg, 82)
    }

    func test_reconcile_noOpWhenAlreadyConsistent() {
        var mem = TrainingMemory()
        mem.recordBodyWeight(80, on: base)
        // Scalar already equals newest — re-opening About You without a change
        // must not spam the log.
        mem.reconcileScalarIntoLog(on: base.addingTimeInterval(86_400))
        XCTAssertEqual(mem.bodyWeightLog.count, 1)
    }

    func test_reconcile_seedsWhenLogEmpty() {
        var mem = TrainingMemory()
        mem.weightKg = 90
        mem.onboardedAt = base
        mem.reconcileScalarIntoLog()
        XCTAssertEqual(mem.bodyWeightLog.count, 1)
        XCTAssertEqual(mem.bodyWeightLog.first?.weightKg, 90)
    }
}
