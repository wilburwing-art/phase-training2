// TapBudgetTests.swift — interaction-cost ("tap budget") tracking for the
// core flows.
//
// These tests drive each flow's INTENDED minimal-tap path and record how many
// taps it actually took. Per the product decision (2026-05-31), the budget is
// *tracked + printed*, not enforced: a flow going over budget does NOT fail the
// build. What still fails the build is the flow breaking — if any step in the
// minimal path can't be reached, the run is red. So these double as happy-path
// smoke tests for "can a workout still be logged / swapped at all".
//
// Each test prints a line like:
//   TAP-BUDGET | log-workout-in-workout: actual=6 reference=6 → within budget
// and attaches the same string to the test report (lifetime .keepAlways) so the
// number is visible in CI artifacts and trendable over time. Tighten the
// `reference` constants by hand when you deliberately make a flow cheaper.
//
// Flows tracked:
//   1. log-workout-in-workout  — boot straight into LogScreen (seeded 5-ex
//      session), bulk-log every exercise, tap Finish. The tight number.
//   2. log-workout-full        — cold Today → Start workout → bulk-log the
//      upper-1 fallback (6 ex) → Finish → Save → skip feedback. The fuller
//      "taps to log a workout end to end" number.
//   3. swap-exercise           — boot into LogScreen, open a row's swap picker,
//      pick the first replacement.

import XCTest

final class TapBudgetTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 1. Log a workout (in-workout slice)

    /// From inside LogScreen with a seeded 5-exercise session: bulk-log every
    /// exercise via its "Log all sets" button, then Finish. Reference: 5 bulk
    /// taps + 1 Finish = 6.
    func testTapBudget_logWorkout_inWorkout() throws {
        let app = launchInLog()
        var counter = TapCounter(app: app, flow: "log-workout-in-workout")

        bulkLogAllExercises(&counter)
        counter.tap("log-finish")

        recordTapBudget(counter, reference: 6)
    }

    // MARK: - 2. Log a workout (full, Today → saved)

    /// Cold start with no plan and no active session → Today shows the upper-1
    /// fallback as a startable lift day. Start → bulk-log → Finish → Save →
    /// skip the post-workout feedback sheet. Reference: 1 Start + 6 bulk + 1
    /// Finish + 1 Save + 1 Skip = 10.
    func testTapBudget_logWorkout_full() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset"]
        app.launch()
        var counter = TapCounter(app: app, flow: "log-workout-full")

        // Today: start the (upper-1 fallback) workout.
        counter.tap("today-start-workout")

        // Now in LogScreen — wait for it, then bulk-log + finish.
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8),
                      "Start workout should land in LogScreen")
        bulkLogAllExercises(&counter)
        counter.tap("log-finish")

        // CompleteScreen: Save, then skip the feedback sheet to return to Today.
        counter.tap("complete-save")
        counter.tap("feedback-skip")

        recordTapBudget(counter, reference: 10)
    }

    // MARK: - 3. Swap an exercise

    /// From LogScreen, open the swap picker on exercise idx 2 (Back Squat) and
    /// pick the first offered replacement. Reference: 1 open + 1 pick = 2.
    func testTapBudget_swapExercise() throws {
        let app = launchInLog()
        var counter = TapCounter(app: app, flow: "swap-exercise")

        counter.tap("log-swap-2")

        // ExercisePickerSheet (titled "Replace …") exposes rows as
        // picker-row-name-<name>. Pick the first one.
        let firstRow = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'picker-row-name-'")
        ).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5),
                      "swap picker should expose at least one replacement row")
        counter.scrollIntoView(firstRow)
        firstRow.tap()
        counter.bump()

        recordTapBudget(counter, reference: 2)
    }

    // MARK: - Shared flow helpers

    /// Launch straight into LogScreen with the deterministic 5-exercise
    /// superset demo session. Mirrors LogFlowTests.launchInLog.
    private func launchInLog() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-test-onboarded",
            "--ui-test-reset",
            "--seed-supersets-demo",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8),
                      "should land in LogScreen with seeded session")
        return app
    }

    /// Tap each exercise's "Log all sets" button (log-all-<i>) once, top to
    /// bottom, for as many exercises as the session has. Exercises are never
    /// removed mid-flow, so indices are stable; an exercise whose sets are all
    /// already done simply has no log-all button and is skipped.
    private func bulkLogAllExercises(_ counter: inout TapCounter) {
        let app = counter.app
        var idx = 0
        // Cap to a sane maximum so a layout bug can't spin forever.
        while idx < 30, app.staticTexts["log-exercise-name-\(idx)"].exists {
            let logAll = app.buttons["log-all-\(idx)"]
            if logAll.exists {
                counter.tap("log-all-\(idx)")
            }
            idx += 1
        }
        XCTAssertGreaterThan(idx, 0, "expected at least one exercise to log")
    }

    // MARK: - Recording

    /// Print + attach the tap count. Per the "track, don't gate" decision this
    /// never fails on budget — it only annotates the report.
    private func recordTapBudget(_ counter: TapCounter, reference: Int) {
        let verdict = counter.count <= reference ? "within budget" : "OVER budget"
        let line = "TAP-BUDGET | \(counter.flow): actual=\(counter.count) reference=\(reference) → \(verdict)"
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "tap-budget-\(counter.flow)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Counts taps along a flow. Every `tap(id:)` waits for the element, scrolls it
/// into view, taps it, and increments the count. A missing element FAILS the
/// test (the flow is broken) — that's the one hard assertion; the budget itself
/// is recorded, not enforced.
struct TapCounter {
    let app: XCUIApplication
    let flow: String
    private(set) var count = 0

    /// Tap a button by accessibility id, counting it.
    mutating func tap(_ id: String, timeout: TimeInterval = 6,
                      file: StaticString = #file, line: UInt = #line) {
        let el = app.buttons[id]
        guard el.waitForExistence(timeout: timeout) else {
            XCTFail("[\(flow)] button '\(id)' never appeared (would-be tap #\(count + 1))",
                    file: file, line: line)
            return
        }
        scrollIntoView(el)
        el.tap()
        count += 1
    }

    /// Count a tap performed manually by the caller (e.g. a predicate-matched
    /// row that isn't addressable by a single id).
    mutating func bump() { count += 1 }

    /// Swipe up until the element is hittable (or we give up). Used for the
    /// per-exercise "Log all sets" buttons that sit below the fold.
    func scrollIntoView(_ el: XCUIElement, maxSwipes: Int = 6) {
        var tries = 0
        while !el.isHittable, tries < maxSwipes {
            app.swipeUp()
            tries += 1
        }
    }
}
