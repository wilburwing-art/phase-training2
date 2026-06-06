// ReadinessEventsTests — characterization coverage for the private
// `buildReadinessEvents` step inside `GeneratorContext.from(...)`.
//
// The builder unions native sessions + imported workouts + light/moderate
// sport logs into ONE ReadinessEvent per distinct calendar day within the
// 28-day readiness window. It is private, so these tests observe it
// through the public `from(...)` outputs:
//
//   - `hasReadinessData` is exactly `!readinessEvents.isEmpty`
//   - with `cohort: nil` the density norm is 3.0/wk, so
//     `readinessBreakdown.density == eventCount / 12` — inverting density
//     recovers the deduped event COUNT.
//   - recency reads the raw event startTime, so the "earliest event of
//     the day wins" rule is observable via score deltas in the 3–14 day
//     recency ramp zone.
//
// All tests inject a fixed `now` — no un-injected Date() anywhere.

import XCTest
@testable import PhaseTraining

final class ReadinessEventsTests: XCTestCase {

    // MARK: - Fixtures

    private func now() -> Date { Date(timeIntervalSince1970: 1_780_000_000) }

    /// With `cohort: nil` → norm 3.0/wk: density = (count / 4wks) / 3.0.
    private func expectedDensity(eventCount: Int) -> Double {
        Double(eventCount) / 12.0
    }

    private func session(startTime: Date) -> SavedSession {
        SavedSession(
            templateId: "t", name: "Lift", category: "",
            startTime: startTime, exercises: [], feel: nil, note: nil,
            endTime: startTime.addingTimeInterval(3600), duration: 3600
        )
    }

    private func imported(id: String, startTime: Date) -> ImportedWorkout {
        ImportedWorkout(
            id: id, source: .healthKit, kind: .strength,
            startTime: startTime, duration: 45 * 60, energyKcal: 300
        )
    }

    private func sportLog(date: Date, intensity: EventIntensity) -> SportLogEntry {
        SportLogEntry(
            date: date,
            sport: Sport(slug: "climbing", name: "Climbing"),
            durationMinutes: 90,
            intensity: intensity,
            note: nil,
            loggedAt: date
        )
    }

    private func build(
        sessions: [SavedSession] = [],
        soreness: [SorenessEntry] = [],
        feedback: [FeedbackEntry] = [],
        sportLogs: [SportLogEntry] = [],
        importedWorkouts: [ImportedWorkout] = []
    ) -> GeneratorContext {
        GeneratorContext.from(
            sessions: sessions,
            soreness: soreness,
            feedback: feedback,
            sportLogs: sportLogs,
            importedWorkouts: importedWorkouts,
            now: now()
        )
    }

    // MARK: - Empty inputs

    func test_emptyInputs_produceNoReadinessEvents() {
        let ctx = build()
        XCTAssertFalse(ctx.hasReadinessData,
                       "no sessions/imports/sportLogs → no readiness events")
        XCTAssertEqual(ctx.readinessScore, 0.5, accuracy: 0.0001,
                       "empty event set must fall back to the neutral 0.5 sentinel")
        XCTAssertEqual(ctx.readinessBreakdown, ReadinessSignal.neutral.breakdown)
        XCTAssertTrue(ctx.isEmpty)
    }

    // MARK: - Source mapping (which inputs become events)

    func test_nativeSession_inWindow_producesOneEvent() {
        let ctx = build(sessions: [session(startTime: now().addingTimeInterval(-2 * 86_400))])
        XCTAssertTrue(ctx.hasReadinessData)
        XCTAssertEqual(ctx.readinessBreakdown.density, expectedDensity(eventCount: 1),
                       accuracy: 0.0005,
                       "one in-window session → exactly one readiness event")
    }

    func test_importedWorkout_inWindow_producesOneEvent() {
        let ctx = build(importedWorkouts: [imported(id: "HK-1",
                                                    startTime: now().addingTimeInterval(-2 * 86_400))])
        XCTAssertTrue(ctx.hasReadinessData)
        XCTAssertEqual(ctx.readinessBreakdown.density, expectedDensity(eventCount: 1),
                       accuracy: 0.0005)
    }

    func test_lightAndModerateSportLogs_produceEvents() {
        let logs = [
            sportLog(date: now().addingTimeInterval(-2 * 86_400), intensity: .light),
            sportLog(date: now().addingTimeInterval(-5 * 86_400), intensity: .moderate),
        ]
        let ctx = build(sportLogs: logs)
        XCTAssertTrue(ctx.hasReadinessData,
                      "light/moderate sport counts as general activity")
        XCTAssertEqual(ctx.readinessBreakdown.density, expectedDensity(eventCount: 2),
                       accuracy: 0.0005)
    }

    func test_hardSportLog_doesNotProduceEvent() {
        // Sport = fatigue: a hard sport day must NOT raise the readiness
        // signal (it already trims a lift day via recentHardSportDays —
        // counting it here too would double-dip).
        let ctx = build(sportLogs: [sportLog(date: now().addingTimeInterval(-2 * 86_400),
                                             intensity: .hard)])
        XCTAssertFalse(ctx.hasReadinessData)
        XCTAssertEqual(ctx.readinessScore, 0.5, accuracy: 0.0001)
        XCTAssertEqual(ctx.readinessBreakdown, ReadinessSignal.neutral.breakdown)
        // Contrast: the same log DOES feed the hard-sport fatigue counter.
        XCTAssertEqual(ctx.recentHardSportDays, 1)
    }

    func test_mixedIntensitySportLogs_onlyNonHardCount() {
        let logs = [
            sportLog(date: now().addingTimeInterval(-2 * 86_400), intensity: .hard),
            sportLog(date: now().addingTimeInterval(-5 * 86_400), intensity: .light),
        ]
        let ctx = build(sportLogs: logs)
        XCTAssertTrue(ctx.hasReadinessData)
        XCTAssertEqual(ctx.readinessBreakdown.density, expectedDensity(eventCount: 1),
                       accuracy: 0.0005,
                       "only the light log becomes a readiness event")
    }

    func test_sorenessAndFeedback_doNotProduceEvents() {
        // Soreness check-ins + feedback feed recentSoreAreas — they are
        // NOT readiness inputs (readiness = sessions + imports + sport).
        var sore = SorenessEntry(date: now().addingTimeInterval(-1 * 86_400))
        sore.areas = ["quads"]
        let fb = FeedbackEntry(
            date: now().addingTimeInterval(-1 * 86_400),
            sessionId: "x", difficulty: "right",
            hurtAreas: ["shoulder"], ranLong: false, notes: nil
        )
        let ctx = build(soreness: [sore], feedback: [fb])
        XCTAssertFalse(ctx.hasReadinessData,
                       "in-window soreness/feedback alone must not create readiness events")
        XCTAssertEqual(ctx.readinessScore, 0.5, accuracy: 0.0001)
        // Proof the entries WERE in-window and consumed — by the soreness
        // signal, not the readiness one.
        XCTAssertTrue(ctx.recentSoreAreas.contains("quads"))
        XCTAssertTrue(ctx.recentSoreAreas.contains("shoulder"))
    }

    func test_distinctDaysAcrossSources_eachCountOnce() {
        let ctx = build(
            sessions: [session(startTime: now().addingTimeInterval(-2 * 86_400))],
            sportLogs: [sportLog(date: now().addingTimeInterval(-16 * 86_400),
                                 intensity: .moderate)],
            importedWorkouts: [imported(id: "HK-1",
                                        startTime: now().addingTimeInterval(-9 * 86_400))]
        )
        XCTAssertTrue(ctx.hasReadinessData)
        XCTAssertEqual(ctx.readinessBreakdown.density, expectedDensity(eventCount: 3),
                       accuracy: 0.0005,
                       "three sources on three distinct days → three events")
    }

    // MARK: - Same-day dedup

    func test_sameDaySessionAndImport_dedupeToOneEvent() {
        // The user logged in-app AND HK detected it from the watch — the
        // same calendar day must count once, not twice.
        let dayStart = Calendar.current.startOfDay(
            for: now().addingTimeInterval(-5 * 86_400))
        let ctx = build(
            sessions: [session(startTime: dayStart.addingTimeInterval(6 * 3600))],
            importedWorkouts: [imported(id: "HK-1",
                                        startTime: dayStart.addingTimeInterval(18 * 3600))]
        )
        XCTAssertTrue(ctx.hasReadinessData)
        XCTAssertEqual(ctx.readinessBreakdown.density, expectedDensity(eventCount: 1),
                       accuracy: 0.0005,
                       "session + import on the same day must dedupe to one event")
    }

    func test_sameDayDedup_keepsEarliestEventOfDay() {
        // Recency reads the raw event timestamp, so in the 3–14 day ramp
        // zone the within-day winner is observable: keeping the EARLIEST
        // event means the deduped context scores exactly like the
        // morning-only one, and strictly below the evening-only one.
        let dayStart = Calendar.current.startOfDay(
            for: now().addingTimeInterval(-10 * 86_400))
        let morning = dayStart.addingTimeInterval(6 * 3600)
        let evening = dayStart.addingTimeInterval(18 * 3600)

        let both = build(
            sessions: [session(startTime: morning)],
            importedWorkouts: [imported(id: "HK-1", startTime: evening)]
        )
        let morningOnly = build(sessions: [session(startTime: morning)])
        let eveningOnly = build(importedWorkouts: [imported(id: "HK-1", startTime: evening)])

        XCTAssertEqual(both.readinessBreakdown, morningOnly.readinessBreakdown,
                       "deduped day must carry the earliest event's timestamp")
        XCTAssertEqual(both.readinessScore, morningOnly.readinessScore,
                       accuracy: 0.000001)
        XCTAssertGreaterThan(eveningOnly.readinessScore, both.readinessScore,
                             "if the later event had won, recency (and score) would be higher")
    }

    // MARK: - 28-day window cutoff

    func test_windowBoundary_exactly28DaysOld_isIncluded() {
        // cutoff = now - 28d, filter is `>= cutoff` — the boundary is in.
        let ctx = build(sessions: [session(startTime: now().addingTimeInterval(-28 * 86_400))])
        XCTAssertTrue(ctx.hasReadinessData,
                      "event exactly at the 28-day cutoff is still inside the window")
        XCTAssertEqual(ctx.readinessBreakdown.density, expectedDensity(eventCount: 1),
                       accuracy: 0.0005)
    }

    func test_windowBoundary_olderThan28Days_isExcluded() {
        let ctx = build(sessions: [session(startTime: now().addingTimeInterval(-28 * 86_400 - 1))])
        XCTAssertFalse(ctx.hasReadinessData,
                       "one second past the cutoff → no readiness events")
        XCTAssertEqual(ctx.readinessScore, 0.5, accuracy: 0.0001)
        XCTAssertEqual(ctx.readinessBreakdown, ReadinessSignal.neutral.breakdown)
    }

    func test_windowCutoff_appliesToImportsAndSportLogsToo() {
        let ctx = build(
            sessions: [session(startTime: now().addingTimeInterval(-2 * 86_400))],
            sportLogs: [sportLog(date: now().addingTimeInterval(-29 * 86_400),
                                 intensity: .light)],
            importedWorkouts: [imported(id: "HK-OLD",
                                        startTime: now().addingTimeInterval(-29 * 86_400))]
        )
        XCTAssertTrue(ctx.hasReadinessData)
        XCTAssertEqual(ctx.readinessBreakdown.density, expectedDensity(eventCount: 1),
                       accuracy: 0.0005,
                       "stale import + stale sport log must not add events alongside the fresh session")
    }

    // MARK: - Determinism

    func test_sameInputsAndNow_produceIdenticalContext() {
        var sore = SorenessEntry(date: now().addingTimeInterval(-1 * 86_400))
        sore.areas = ["quads"]
        let sessions = [
            session(startTime: now().addingTimeInterval(-2 * 86_400)),
            session(startTime: now().addingTimeInterval(-9 * 86_400)),
        ]
        let logs = [
            sportLog(date: now().addingTimeInterval(-5 * 86_400), intensity: .moderate),
            sportLog(date: now().addingTimeInterval(-12 * 86_400), intensity: .hard),
        ]
        let imports = [imported(id: "HK-1", startTime: now().addingTimeInterval(-16 * 86_400))]

        let a = build(sessions: sessions, soreness: [sore],
                      sportLogs: logs, importedWorkouts: imports)
        let b = build(sessions: sessions, soreness: [sore],
                      sportLogs: logs, importedWorkouts: imports)
        XCTAssertEqual(a, b,
                       "from(...) with an injected now must be a pure function of its inputs")
    }
}
