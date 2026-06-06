// MuscleFreshnessTests.swift — characterization tests for the per-muscle
// recovery freshness model (MuscleFreshness.rows / .highlights / Row.intensity).
//
// Every test injects a fixed `now` (epoch-anchored Date) and a stub resolver
// so nothing touches CoachDatabase or the wall clock. The anchor was chosen
// so that "N days ago" fixtures straddle the 2026 US spring-forward DST
// transition — the model intentionally counts 86,400-second days, not
// calendar days, and the DST test pins that down.

import XCTest
@testable import PhaseTraining

final class MuscleFreshnessTests: XCTestCase {

    /// 2026-03-09 12:00:00 UTC. Sessions placed 2-3 "days" earlier span the
    /// US spring-forward DST change (2026-03-08 02:00 local / 09:00 UTC in
    /// America/Denver).
    private let now = Date(timeIntervalSince1970: 1_773_057_600)

    // MARK: - rows: empty / never-trained

    func test_emptySessions_allMusclesFullyFresh() {
        let rows = MuscleFreshness.rows(
            from: [],
            now: now,
            resolve: resolver([:]),
            allMuscles: [("chest", "Chest"), ("quadriceps", "Quads")]
        )
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            XCTAssertEqual(row.freshness, 1.0)
            XCTAssertNil(row.lastWorked)
            XCTAssertNil(row.daysSinceLastWorked)
            XCTAssertEqual(row.intensity, BodyAnatomyView.HighlightIntensity.none)
        }
    }

    func test_neverTrainedMuscle_isFullyFresh() {
        let session = savedSession(name: "Bench Press", daysAgo: 1)
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now,
            resolve: resolver(["Bench Press": [chest]]),
            allMuscles: [("chest", "Chest"), ("biceps", "Biceps")]
        )
        let biceps = rows.first { $0.slug == "biceps" }
        XCTAssertEqual(biceps?.freshness, 1.0)
        XCTAssertNil(biceps?.lastWorked)
        XCTAssertNil(biceps?.daysSinceLastWorked)
    }

    func test_allMusclesSuperset_everySlugGetsARow_inOrder() {
        let session = savedSession(name: "Bench Press", daysAgo: 1)
        let all: [(slug: String, name: String)] = [
            ("quadriceps", "Quads"), ("chest", "Chest"),
            ("biceps", "Biceps"), ("calves", "Calves"),
        ]
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now,
            resolve: resolver(["Bench Press": [chest]]),
            allMuscles: all
        )
        XCTAssertEqual(rows.map(\.slug), ["quadriceps", "chest", "biceps", "calves"],
                       "Row order should follow allMuscles, not training recency")
        XCTAssertEqual(rows.map(\.label), ["Quads", "Chest", "Biceps", "Calves"])
    }

    // MARK: - rows: recovery decay

    func test_decay_halfwayThroughWindow() {
        // Chest window = 5 days; trained 2.5 days ago → freshness 0.5.
        let session = savedSession(name: "Bench Press", daysAgo: 2.5)
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now,
            resolve: resolver(["Bench Press": [chest]]),
            allMuscles: [("chest", "Chest")]
        )
        XCTAssertEqual(rows[0].freshness, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rows[0].lastWorked, session.startTime)
        XCTAssertEqual(rows[0].daysSinceLastWorked, 2)
    }

    func test_decay_usesPerMuscleWindow() {
        // Same 3-days-ago session: calves (3-day window) fully recover,
        // quadriceps (6-day window) sit at exactly half.
        let session = savedSession(name: "Leg Day", daysAgo: 3)
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now,
            resolve: resolver(["Leg Day": [
                (slug: "calves", role: "primary", label: "Calves"),
                (slug: "quadriceps", role: "primary", label: "Quads"),
            ]]),
            allMuscles: [("calves", "Calves"), ("quadriceps", "Quads")]
        )
        XCTAssertEqual(rows[0].freshness, 1.0, accuracy: 1e-9)
        XCTAssertEqual(rows[1].freshness, 0.5, accuracy: 1e-9)
    }

    func test_decay_unknownSlugFallsBackToDefaultWindow() {
        // "mystery-muscle" isn't in recoveryWindow → 5-day default.
        let session = savedSession(name: "Mystery Move", daysAgo: 2.5)
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now,
            resolve: resolver(["Mystery Move": [
                (slug: "mystery-muscle", role: "primary", label: "Mystery"),
            ]]),
            allMuscles: [("mystery-muscle", "Mystery")]
        )
        XCTAssertEqual(rows[0].freshness, 0.5, accuracy: 1e-9)
    }

    func test_decay_capsAtFullyRecovered() {
        // Way past the window: freshness clamps to 1.0 but lastWorked /
        // daysSinceLastWorked still report the stale session.
        let session = savedSession(name: "Bench Press", daysAgo: 30)
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now,
            resolve: resolver(["Bench Press": [chest]]),
            allMuscles: [("chest", "Chest")]
        )
        XCTAssertEqual(rows[0].freshness, 1.0)
        XCTAssertEqual(rows[0].lastWorked, session.startTime)
        XCTAssertEqual(rows[0].daysSinceLastWorked, 30)
        XCTAssertEqual(rows[0].intensity, BodyAnatomyView.HighlightIntensity.none)
    }

    func test_justTrained_freshnessZero() {
        let session = savedSession(name: "Bench Press", daysAgo: 0)
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now,
            resolve: resolver(["Bench Press": [chest]]),
            allMuscles: [("chest", "Chest")]
        )
        XCTAssertEqual(rows[0].freshness, 0.0)
        XCTAssertEqual(rows[0].daysSinceLastWorked, 0)
        XCTAssertEqual(rows[0].intensity, .primary)
    }

    func test_futureDatedSession_clampsToZeroDays() {
        // A session timestamped after `now` (clock skew, edited date) must
        // clamp to zero elapsed days, not produce negative freshness.
        let session = savedSession(name: "Bench Press", daysAgo: -1)
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now,
            resolve: resolver(["Bench Press": [chest]]),
            allMuscles: [("chest", "Chest")]
        )
        XCTAssertEqual(rows[0].freshness, 0.0)
        XCTAssertEqual(rows[0].daysSinceLastWorked, 0)
    }

    func test_daysSinceLastWorked_floorsPartialDays() {
        let session = savedSession(name: "Bench Press", daysAgo: 1.9)
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now,
            resolve: resolver(["Bench Press": [chest]]),
            allMuscles: [("chest", "Chest")]
        )
        XCTAssertEqual(rows[0].daysSinceLastWorked, 1)
    }

    // MARK: - rows: multiple sessions + done-set gating

    func test_multipleSessions_mostRecentWins_anyOrder() {
        let old = savedSession(name: "Bench Press", daysAgo: 4)
        let recent = savedSession(name: "Bench Press", daysAgo: 1)
        let resolve = resolver(["Bench Press": [chest]])

        for sessions in [[old, recent], [recent, old]] {
            let rows = MuscleFreshness.rows(
                from: sessions,
                now: now,
                resolve: resolve,
                allMuscles: [("chest", "Chest")]
            )
            // 1 day / 5-day window = 0.2 regardless of input order.
            XCTAssertEqual(rows[0].freshness, 0.2, accuracy: 1e-9)
            XCTAssertEqual(rows[0].lastWorked, recent.startTime)
            XCTAssertEqual(rows[0].daysSinceLastWorked, 1)
        }
    }

    func test_sessionWithNoDoneSets_doesNotFatigue() {
        // The recent session has zero done sets — only the old one counts.
        let old = savedSession(name: "Bench Press", daysAgo: 4)
        let recentUndone = savedSession(name: "Bench Press", daysAgo: 1, done: false)
        let rows = MuscleFreshness.rows(
            from: [old, recentUndone],
            now: now,
            resolve: resolver(["Bench Press": [chest]]),
            allMuscles: [("chest", "Chest")]
        )
        XCTAssertEqual(rows[0].freshness, 0.8, accuracy: 1e-9)
        XCTAssertEqual(rows[0].lastWorked, old.startTime)
    }

    func test_exerciseWithNoDoneSets_skippedWithinSession() {
        // One session, two exercises: bench all-undone, curl done. Only the
        // curl's muscle decays even though the session itself has done sets.
        let bench = loggedExercise(name: "Bench Press", done: false)
        let curl = loggedExercise(name: "Curl", done: true)
        let session = savedSession(exercises: [bench, curl], daysAgo: 1)
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now,
            resolve: resolver([
                "Bench Press": [chest],
                "Curl": [(slug: "biceps", role: "primary", label: "Biceps")],
            ]),
            allMuscles: [("chest", "Chest"), ("biceps", "Biceps")]
        )
        XCTAssertEqual(rows[0].freshness, 1.0, "Undone bench should not fatigue chest")
        XCTAssertNil(rows[0].lastWorked)
        // Biceps window = 4 days → 1/4 = 0.25.
        XCTAssertEqual(rows[1].freshness, 0.25, accuracy: 1e-9)
    }

    func test_onlyPrimaryRole_fatigues() {
        let session = savedSession(name: "Bench Press", daysAgo: 1)
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now,
            resolve: resolver(["Bench Press": [
                chest,
                (slug: "triceps", role: "secondary", label: "Triceps"),
                (slug: "delt-anterior", role: "stabilizer", label: "Front Delt"),
            ]]),
            allMuscles: [("chest", "Chest"), ("triceps", "Triceps"), ("delt-anterior", "Front Delt")]
        )
        XCTAssertEqual(rows[0].freshness, 0.2, accuracy: 1e-9)
        XCTAssertEqual(rows[1].freshness, 1.0, "Secondary role must not fatigue")
        XCTAssertEqual(rows[2].freshness, 1.0, "Stabilizer role must not fatigue")
    }

    // MARK: - rows: resolver mapping

    func test_unknownExercise_resolverNil_noFatigue() {
        let session = savedSession(name: "Mystery Move", daysAgo: 1)
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now,
            resolve: resolver([:]),
            allMuscles: [("chest", "Chest")]
        )
        XCTAssertEqual(rows[0].freshness, 1.0)
        XCTAssertNil(rows[0].lastWorked)
    }

    func test_resolverMapsByExerciseName() {
        let bench = loggedExercise(name: "Bench Press", done: true)
        let squat = loggedExercise(name: "Squat", done: true)
        let session = savedSession(exercises: [bench, squat], daysAgo: 1)
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now,
            resolve: resolver([
                "Bench Press": [chest],
                "Squat": [(slug: "quadriceps", role: "primary", label: "Quads")],
            ]),
            allMuscles: [("chest", "Chest"), ("quadriceps", "Quads")]
        )
        XCTAssertEqual(rows[0].freshness, 0.2, accuracy: 1e-9)   // 1/5
        XCTAssertEqual(rows[1].freshness, 1.0 / 6.0, accuracy: 1e-9) // 1/6
    }

    func test_resolverMemoized_oncePerUniqueName() {
        // Same exercise name across 3 sessions → resolve fires once.
        var calls: [String: Int] = [:]
        let counting: MuscleVolume.NameResolver = { name in
            calls[name, default: 0] += 1
            return MuscleVolume.ResolvedExercise(muscles: [self.chest])
        }
        let sessions = [
            savedSession(name: "Bench Press", daysAgo: 1),
            savedSession(name: "Bench Press", daysAgo: 3),
            savedSession(name: "Bench Press", daysAgo: 5),
        ]
        _ = MuscleFreshness.rows(
            from: sessions,
            now: now,
            resolve: counting,
            allMuscles: [("chest", "Chest")]
        )
        XCTAssertEqual(calls["Bench Press"], 1)
    }

    // MARK: - DST-adjacent dates

    func test_dstSpanningInterval_countsPureSecondsNotWallClockDays() {
        // last = 2026-03-07 00:00:00 UTC; now = last + 2.5 × 86,400 s. That
        // interval spans the US spring-forward transition (2026-03-08 02:00
        // local). The model counts 86,400-second days via timeIntervalSince,
        // so the answer is exactly 0.5 freshness / 2 floor-days in every
        // timezone — DST never shifts it.
        let last = Date(timeIntervalSince1970: 1_772_841_600)
        let session = savedSession(name: "Bench Press", startTime: last)
        let rows = MuscleFreshness.rows(
            from: [session],
            now: now, // 1_773_057_600 = last + 216,000 s
            resolve: resolver(["Bench Press": [chest]]),
            allMuscles: [("chest", "Chest")]
        )
        XCTAssertEqual(rows[0].freshness, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rows[0].daysSinceLastWorked, 2)
    }

    // MARK: - rows: freshness bounds

    func test_freshness_alwaysWithinUnitInterval() {
        // Future-dated, fresh, mid-window, and ancient sessions — every row
        // must stay inside 0...1 so Row.intensity's bands are total.
        for offset in [-2.0, 0.0, 0.1, 2.5, 4.99, 5.0, 365.0] {
            let session = savedSession(name: "Bench Press", daysAgo: offset)
            let rows = MuscleFreshness.rows(
                from: [session],
                now: now,
                resolve: resolver(["Bench Press": [chest]]),
                allMuscles: [("chest", "Chest")]
            )
            XCTAssertGreaterThanOrEqual(rows[0].freshness, 0.0, "offset \(offset)")
            XCTAssertLessThanOrEqual(rows[0].freshness, 1.0, "offset \(offset)")
        }
    }

    // MARK: - Row.intensity

    func test_intensity_thresholdBands() {
        XCTAssertEqual(row(freshness: 0.0).intensity, .primary)
        XCTAssertEqual(row(freshness: 0.32).intensity, .primary)
        XCTAssertEqual(row(freshness: 0.33).intensity, .secondary)
        XCTAssertEqual(row(freshness: 0.65).intensity, .secondary)
        XCTAssertEqual(row(freshness: 0.66).intensity, .tertiary)
        XCTAssertEqual(row(freshness: 0.99).intensity, .tertiary)
        XCTAssertEqual(row(freshness: 1.0).intensity, BodyAnatomyView.HighlightIntensity.none)
    }

    func test_intensity_monotoneWithRecency() {
        // More recent training (lower freshness) → equal-or-more-severe
        // highlight. Sweep the unit interval and assert severity never
        // increases as freshness rises.
        func severity(_ i: BodyAnatomyView.HighlightIntensity) -> Int {
            switch i {
            case .primary:   return 3
            case .secondary: return 2
            case .tertiary:  return 1
            case .none:      return 0
            }
        }
        var previous = Int.max
        for step in 0...20 {
            let freshness = Double(step) / 20.0
            let s = severity(row(freshness: freshness).intensity)
            XCTAssertLessThanOrEqual(s, previous, "freshness \(freshness)")
            previous = s
        }
    }

    // MARK: - highlights

    func test_highlights_emptySessions_emptyDict() {
        let out = MuscleFreshness.highlights(
            from: [],
            now: now,
            resolve: resolver([:]),
            allMuscles: [("chest", "Chest"), ("biceps", "Biceps")]
        )
        XCTAssertTrue(out.isEmpty)
    }

    func test_highlights_excludesFreshMuscles() {
        // Chest just trained; biceps never trained → only chest appears, so
        // the silhouette stays gray for recovered muscles.
        let session = savedSession(name: "Bench Press", daysAgo: 0)
        let out = MuscleFreshness.highlights(
            from: [session],
            now: now,
            resolve: resolver(["Bench Press": [chest]]),
            allMuscles: [("chest", "Chest"), ("biceps", "Biceps")]
        )
        XCTAssertEqual(out, ["chest": .primary])
    }

    func test_highlights_thresholdBandsPerMuscle() {
        // chest:      1 day / 5 → 0.20 → .primary
        // quadriceps: 3 days / 6 → 0.50 → .secondary
        // biceps:     3 days / 4 → 0.75 → .tertiary
        // calves:     3 days / 3 → 1.00 → excluded
        let sessions = [
            savedSession(name: "Bench Press", daysAgo: 1),
            savedSession(name: "Squat", daysAgo: 3),
            savedSession(name: "Curl", daysAgo: 3),
            savedSession(name: "Calf Raise", daysAgo: 3),
        ]
        let out = MuscleFreshness.highlights(
            from: sessions,
            now: now,
            resolve: resolver([
                "Bench Press": [chest],
                "Squat": [(slug: "quadriceps", role: "primary", label: "Quads")],
                "Curl": [(slug: "biceps", role: "primary", label: "Biceps")],
                "Calf Raise": [(slug: "calves", role: "primary", label: "Calves")],
            ]),
            allMuscles: [
                ("chest", "Chest"), ("quadriceps", "Quads"),
                ("biceps", "Biceps"), ("calves", "Calves"),
            ]
        )
        XCTAssertEqual(out, [
            "chest": .primary,
            "quadriceps": .secondary,
            "biceps": .tertiary,
        ])
    }

    // MARK: - Helpers

    private let chest: (slug: String, role: String, label: String) =
        (slug: "chest", role: "primary", label: "Chest")

    /// Test resolver — bypasses CoachDatabase so tests don't depend on the
    /// bundled SQLite. Maps exercise names → muscle role tuples.
    private func resolver(_ map: [String: [(slug: String, role: String, label: String)]]) -> MuscleVolume.NameResolver {
        return { name in
            guard let muscles = map[name] else { return nil }
            return MuscleVolume.ResolvedExercise(muscles: muscles)
        }
    }

    private func row(freshness: Double) -> MuscleFreshness.Row {
        MuscleFreshness.Row(
            slug: "chest", label: "Chest", freshness: freshness,
            lastWorked: nil, daysSinceLastWorked: nil
        )
    }

    private func loggedExercise(name: String, done: Bool) -> LoggedExercise {
        LoggedExercise(
            id: name, name: name, type: nil, unit: "lbs",
            targetSets: 1, targetReps: 5, rest: 90,
            sets: [LoggedSet(num: 1, weight: "135", reps: "5", rpe: "", done: done)],
            prevSets: []
        )
    }

    private func savedSession(name: String, daysAgo: Double, done: Bool = true) -> SavedSession {
        savedSession(name: name, startTime: now.addingTimeInterval(-daysAgo * 86_400), done: done)
    }

    private func savedSession(name: String, startTime: Date, done: Bool = true) -> SavedSession {
        savedSession(exercises: [loggedExercise(name: name, done: done)], startTime: startTime)
    }

    private func savedSession(exercises: [LoggedExercise], daysAgo: Double) -> SavedSession {
        savedSession(exercises: exercises, startTime: now.addingTimeInterval(-daysAgo * 86_400))
    }

    private func savedSession(exercises: [LoggedExercise], startTime: Date) -> SavedSession {
        SavedSession(
            templateId: "t", name: "Workout", category: "",
            startTime: startTime,
            exercises: exercises, feel: nil, note: nil,
            endTime: startTime.addingTimeInterval(3600), duration: 3600
        )
    }
}
