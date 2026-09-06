// ProgressRecoverySectionTests.swift — the Progress tab's recovery block.
//
// ProgressRecoverySection had no tests at all. Its data source
// (MuscleFreshness) is well covered by MuscleFreshnessTests; what wasn't
// covered is the section's own presentation math sitting on top of it.
//
// The load-bearing case is freshMainMuscleCount. The headline once counted
// every row MuscleFreshness returns — all ~80 muscle_groups slugs, including
// muscles never trained, which default to freshness 1.0 — while the list
// below it rendered only the 19 mainSlugs. It read 70+ and was unrelated to
// the label next to it.

import XCTest
@testable import PhaseTraining

final class ProgressRecoverySectionTests: XCTestCase {

    private typealias Section = ProgressRecoverySection

    private func row(_ slug: String,
                     freshness: Double,
                     daysSince: Int? = nil) -> MuscleFreshness.Row {
        MuscleFreshness.Row(
            slug: slug,
            label: slug.capitalized,
            freshness: freshness,
            lastWorked: daysSince.map { Date().addingTimeInterval(-Double($0) * 86_400) },
            daysSinceLastWorked: daysSince
        )
    }

    // MARK: - Fresh headline

    func test_freshCount_countsOnlyMainSlugs() {
        // Two fresh main slugs, plus fresh rows for muscles the list never
        // renders. Only the two may reach the headline.
        let rows = [
            row("chest", freshness: 1.0),
            row("lats", freshness: 1.0),
            row("sartorius", freshness: 1.0),
            row("brachialis", freshness: 1.0),
            row("soleus", freshness: 1.0),
        ]
        XCTAssertEqual(Section.freshMainMuscleCount(rows: rows), 2)
    }

    func test_freshCount_excludesFatiguedMuscles() {
        let rows = [
            row("chest", freshness: 1.0),
            row("triceps", freshness: 0.99),   // just short of recovered
            row("quadriceps", freshness: 0.0),
            row("glutes", freshness: 0.5),
        ]
        XCTAssertEqual(Section.freshMainMuscleCount(rows: rows), 1)
    }

    func test_freshCount_neverExceedsTheListItLabels() {
        // The regression in one line: MuscleFreshness returns a row for every
        // muscle_groups slug, and an untrained muscle defaults to freshness
        // 1.0. Feed it the full catalog shape with nothing trained and the
        // headline must still be bounded by the list it labels.
        //
        // allMuscles is injected (the MuscleFreshnessTests convention) so
        // nothing here touches CoachDatabase.
        let extras = (0..<60).map { (slug: "filler-\($0)", name: "Filler \($0)") }
        let allMuscles = Section.mainSlugs.map { (slug: $0, name: $0.capitalized) } + extras
        let rows = MuscleFreshness.rows(
            from: [],
            now: Date(),
            resolve: { _ in nil },
            allMuscles: allMuscles
        )

        XCTAssertEqual(rows.count, allMuscles.count)
        XCTAssertTrue(rows.allSatisfy { $0.freshness >= 1.0 },
                      "Nothing trained, so every row defaults to fully fresh")
        XCTAssertEqual(Section.freshMainMuscleCount(rows: rows), Section.mainSlugs.count)
        XCTAssertLessThan(Section.freshMainMuscleCount(rows: rows), rows.count,
                          "The headline must not count rows the list never renders")
    }

    func test_freshCount_emptyRowsIsZero() {
        XCTAssertEqual(Section.freshMainMuscleCount(rows: []), 0)
    }

    // MARK: - Silhouette side

    func test_sideForSlug_resolvesEveryMainSlugOrDefersDeliberately() {
        // Every main slug must either name a side or be one of the few that
        // genuinely read from both. A new mainSlug added without a side
        // entry falls into the default and renders a blank silhouette beside
        // its row, which is the bug this guards.
        let bothSides: Set<String> = ["shoulders", "delt-lateral"]
        for slug in Section.mainSlugs {
            let side = Section.side(forSlug: slug)
            if bothSides.contains(slug) {
                XCTAssertNil(side, "\(slug) reads from both sides")
            } else {
                XCTAssertNotNil(side, "\(slug) has no silhouette side; its thumbnail renders blank")
            }
        }
    }

    func test_sideForSlug_anteriorAndPosteriorExamples() {
        XCTAssertEqual(Section.side(forSlug: "chest"), .front)
        XCTAssertEqual(Section.side(forSlug: "quadriceps"), .front)
        XCTAssertEqual(Section.side(forSlug: "lats"), .back)
        XCTAssertEqual(Section.side(forSlug: "hamstrings"), .back)
    }

    func test_sideForSlug_unknownSlugDefersToCallerToggle() {
        XCTAssertNil(Section.side(forSlug: "not-a-muscle"))
    }

    // MARK: - Days since last workout

    func test_daysSinceLastWorkout_nilWithNoSessions() {
        XCTAssertNil(Section.daysSinceLastWorkout(sessions: [], now: Date()))
    }

    func test_daysSinceLastWorkout_floorsToCalendarDays() {
        let cal = Calendar.current
        let now = Date()
        // Started late yesterday, read today: 1 calendar day, even though
        // fewer than 24 hours have elapsed.
        let yesterdayLate = cal.date(byAdding: .hour, value: -4, to: cal.startOfDay(for: now))!
        XCTAssertEqual(
            Section.daysSinceLastWorkout(sessions: [session(at: yesterdayLate)], now: now),
            1
        )
    }

    func test_daysSinceLastWorkout_sameDayIsZero() {
        let now = Date()
        let earlier = Calendar.current.startOfDay(for: now)
        XCTAssertEqual(
            Section.daysSinceLastWorkout(sessions: [session(at: earlier)], now: now),
            0
        )
    }

    func test_daysSinceLastWorkout_usesMostRecentSession() {
        let now = Date()
        let cal = Calendar.current
        let old = cal.date(byAdding: .day, value: -30, to: now)!
        let recent = cal.date(byAdding: .day, value: -2, to: now)!
        XCTAssertEqual(
            Section.daysSinceLastWorkout(
                sessions: [session(at: old), session(at: recent)],
                now: now
            ),
            2
        )
    }

    func test_daysSinceLastWorkout_clampsFutureDatedSession() {
        // An import or a clock change can land a session ahead of now. The
        // headline must read 0 days, never a negative.
        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: 3, to: now)!
        XCTAssertEqual(
            Section.daysSinceLastWorkout(sessions: [session(at: future)], now: now),
            0
        )
    }

    // MARK: - Highlights

    func test_recoveryHighlights_excludesNoneIntensity() {
        let rows = [
            row("chest", freshness: 1.0),    // .none — fully recovered
            row("lats", freshness: 0.2),     // .primary
            row("glutes", freshness: 0.5),   // .secondary
            row("biceps", freshness: 0.8),   // .tertiary
        ]
        let highlights = Section.highlights(from: rows)

        XCTAssertNil(highlights["chest"], "A fresh muscle must not paint the silhouette")
        XCTAssertEqual(highlights.count, 3)
        XCTAssertEqual(highlights["lats"], .primary)
        XCTAssertEqual(highlights["glutes"], .secondary)
        XCTAssertEqual(highlights["biceps"], .tertiary)
    }

    func test_recoveryHighlights_emptyWhenEverythingIsFresh() {
        let rows = [row("chest", freshness: 1.0), row("lats", freshness: 1.0)]
        XCTAssertTrue(Section.highlights(from: rows).isEmpty)
    }

    // MARK: - Row subtitle

    func test_subtitle_neverTrainedTodayAndPlural() {
        XCTAssertEqual(Section.subtitle(for: row("chest", freshness: 1.0)),
                       "No recent exercises")
        XCTAssertEqual(Section.subtitle(for: row("chest", freshness: 0.0, daysSince: 0)),
                       "Trained today")
        XCTAssertEqual(Section.subtitle(for: row("chest", freshness: 0.2, daysSince: 1)),
                       "1 day ago")
        XCTAssertEqual(Section.subtitle(for: row("chest", freshness: 0.6, daysSince: 3)),
                       "3 days ago")
    }

    // MARK: - Fixtures

    private func session(at start: Date) -> SavedSession {
        SavedSession(
            templateId: "t", name: "Workout", category: "",
            startTime: start,
            exercises: [
                LoggedExercise(
                    id: "bench", name: "Barbell Bench Press", type: nil, unit: "lbs",
                    targetSets: 1, targetReps: 5, rest: 90,
                    sets: [LoggedSet(num: 1, weight: "135", reps: "5",
                                     rpe: "", done: true, isWarmup: false)],
                    prevSets: []
                )
            ],
            feel: nil, note: nil,
            endTime: start.addingTimeInterval(3600), duration: 3600
        )
    }
}
