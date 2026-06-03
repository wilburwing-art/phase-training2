import XCTest
@testable import PhaseTraining

/// Build 103 — TrainingMemory.weeksInCurrentPhase + daysUntilPeak power the
/// SeasonPhaseBadge subtext on Today / Progress / Week. These guards lock
/// the math so the badge can't silently drift to "Week 0" or skip weeks
/// because of rounding.
final class SeasonPhaseTimelineTests: XCTestCase {

    func test_weeksInCurrentPhase_nilWhenNeitherTimestampSet() {
        // Pre-onboarding: no phaseStartedAt and no onboardedAt. Counter
        // hides until the user actually completes onboarding.
        var mem = TrainingMemory()
        mem.phaseStartedAt = nil
        mem.onboardedAt = nil
        XCTAssertNil(mem.weeksInCurrentPhase)
    }

    func test_weeksInCurrentPhase_fallsBackToOnboardedAt() {
        // Build-103 fallback — existing installs that haven't re-picked a
        // phase since updating still get a counter, anchored to onboarding.
        var mem = TrainingMemory()
        mem.phaseStartedAt = nil
        mem.onboardedAt = Calendar.current.date(byAdding: .day, value: -14, to: Date())
        XCTAssertEqual(mem.weeksInCurrentPhase, 3)
    }

    func test_weeksInCurrentPhase_prefersPhaseStartedAtOverOnboardedAt() {
        // When both are set, phaseStartedAt wins — the user has re-picked
        // their phase after onboarding, and the counter should reflect the
        // current block, not their lifetime in the app.
        var mem = TrainingMemory()
        let cal = Calendar.current
        mem.onboardedAt = cal.date(byAdding: .day, value: -90, to: Date())
        mem.phaseStartedAt = cal.date(byAdding: .day, value: -7, to: Date())
        XCTAssertEqual(mem.weeksInCurrentPhase, 2)
    }

    func test_weeksInCurrentPhase_firstSevenDaysIsWeekOne() {
        var mem = TrainingMemory()
        let cal = Calendar.current
        // Stamp today → week 1. Stamp 6 days ago → still week 1.
        mem.phaseStartedAt = Date()
        XCTAssertEqual(mem.weeksInCurrentPhase, 1)
        mem.phaseStartedAt = cal.date(byAdding: .day, value: -6, to: Date())
        XCTAssertEqual(mem.weeksInCurrentPhase, 1)
    }

    func test_weeksInCurrentPhase_advancesOnDaySeven() {
        var mem = TrainingMemory()
        let cal = Calendar.current
        mem.phaseStartedAt = cal.date(byAdding: .day, value: -7, to: Date())
        XCTAssertEqual(mem.weeksInCurrentPhase, 2)
        mem.phaseStartedAt = cal.date(byAdding: .day, value: -21, to: Date())
        XCTAssertEqual(mem.weeksInCurrentPhase, 4)
    }

    func test_daysUntilPeak_nilWhenNoPeak() {
        var mem = TrainingMemory()
        mem.peakDate = nil
        XCTAssertNil(mem.daysUntilPeak)
    }

    func test_daysUntilPeak_countsForward() {
        var mem = TrainingMemory()
        let cal = Calendar.current
        mem.peakDate = cal.date(byAdding: .day, value: 14, to: Date())
        // Allow a 1-day fudge — the relative diff can land 13 or 14 depending
        // on time-of-day rounding around the boundary.
        let d = mem.daysUntilPeak ?? 0
        XCTAssertTrue(d == 13 || d == 14, "expected 13-14, got \(d)")
    }

    func test_daysUntilPeak_negativeAfterPeak() {
        var mem = TrainingMemory()
        let cal = Calendar.current
        mem.peakDate = cal.date(byAdding: .day, value: -3, to: Date())
        let d = mem.daysUntilPeak ?? 0
        XCTAssertTrue(d == -3 || d == -2, "expected -3 to -2, got \(d)")
    }

    func test_bodyWeightLog_codableRoundTrip() throws {
        var mem = TrainingMemory()
        let now = Date()
        mem.bodyWeightLog = [
            BodyWeightEntry(date: now.addingTimeInterval(-86400 * 14), weightKg: 80.0),
            BodyWeightEntry(date: now.addingTimeInterval(-86400 * 7),  weightKg: 79.5, note: "post-cut"),
            BodyWeightEntry(date: now, weightKg: 79.1),
        ]
        mem.weightKg = 79.1
        mem.phaseStartedAt = now.addingTimeInterval(-86400 * 21)
        mem.defaultSeason = .preSeason

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(mem)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(TrainingMemory.self, from: data)

        XCTAssertEqual(decoded.bodyWeightLog.count, 3)
        XCTAssertEqual(decoded.bodyWeightLog[1].note, "post-cut")
        XCTAssertEqual(decoded.weightKg, 79.1)
        XCTAssertEqual(decoded.defaultSeason, .preSeason)
        XCTAssertEqual(decoded.weeksInCurrentPhase, 4)
    }

    func test_schemaVersion_bumpedTo7() {
        let mem = TrainingMemory()
        XCTAssertEqual(mem.schemaVersion, 7)
    }
}
