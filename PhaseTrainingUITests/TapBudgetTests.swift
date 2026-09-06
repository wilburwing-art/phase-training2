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
// Each test prints two lines:
//   TAP-BUDGET | log-workout-in-workout: actual=6 reference=6 → within budget
//   TAP-BUDGET-JSON {"flow":"log-workout-in-workout","actual":6,"reference":6}
// The human line + the count are attached to the report (lifetime .keepAlways);
// the JSON line is parsed by scripts/quality/tap_budget_diff.py in CI to diff
// against PhaseTrainingUITests/tap-budget-baseline.json and surface drift.
//
// References are DERIVED from the seed shape (`Seed` below), not bare literals:
// change a seed's exercise/set count and the matching `reference` recomputes,
// and a count-invariant guard (XCTAssertEqual on what the loop actually drove)
// fails loudly so a stale `Seed` constant can't silently skew the number. The
// loops also XCTFail if their safety cap is hit — that would mean rows went
// missing from the a11y tree (e.g. a LazyVStack refactor dropping off-screen
// rows), which would otherwise make the budget silently DROP and read as a win.
//
// Flows tracked:
//   1. log-workout-in-workout   — boot straight into LogScreen (seeded 5-ex
//      session), tap the single whole-workout "Log all" button, tap Finish.
//      The tight number (2, independent of exercise count).
//   2. log-workout-full         — cold Today → Start → "Log all" the upper-1
//      fallback → Finish (auto-saves to the summary). End-to-end, no-plan.
//   3. swap-exercise            — boot into LogScreen, open a row's swap picker,
//      pick the first replacement.
//   4. log-workout-planned-full — same shape as flow 2 but for a PLANNED user:
//      a seeded WeekPlan (`--seed-plan-demo`) makes Today resolve a generated
//      workout, so the number reflects a real plan, not the fallback.
//   5. log-workout-per-set      — the REPRESENTATIVE log path: tap each set's
//      check circle one at a time (no "Log all" shortcut) + Finish. The
//      realistic ceiling that the whole-workout "Log all" (flow 1) floors.
//   6. add-exercise-mid-workout — from LogScreen, open the picker, pick the
//      first catalog exercise; it appends as a new row.
//   7. edit-then-start          — from Today (planned), open a row's action
//      sheet, move it, then Start. The edit-before-you-lift cost.
//   8. discard-workout          — Finish (auto-saves) → Discard → confirm
//      (deletes the just-logged record).
//   9. log-sport                — seeded sport day → Log session → accept the
//      default 60 min / moderate → Save. The hybrid non-lift loop.
//  10. onboarding-to-first-plan — cold launch → minimal onboarding answers →
//      accept the generated plan → land in the tabs. The activation budget.
//  11. weekly-check-in          — auto-present the check-in → walk the steps →
//      pick a rating → regenerate + accept. The weekly retention loop.
//  12. build-and-start-workout  — Library → Workouts → Build a workout → add
//      one exercise → Start. The from-scratch activation cost.
//  13. start-saved-workout      — Library → Workouts → ▶ on a saved row. The
//      repeat-use cost once a workout exists.
//  14. edit-weight-mid-workout  — tap a set's weight field, type a new value,
//      confirm. The typing cost the other log flows deliberately exclude.
//
// What these numbers do and do NOT capture:
//   - They measure the INTENDED minimal-tap path. Flows 1/2/4 take the
//     whole-workout "Log all" shortcut (1 tap for the whole session); flow 5 is
//     the per-set counterpart so the shortcut-vs-per-set gap is visible. Neither
//     includes the keystrokes to TYPE weight/reps — set 1 is pre-filled and
//     edits propagate, so a clean log needs zero typing on the happy path.
//   - swap-exercise (flow 3) is the NO-SEARCH floor: it accepts the first
//     offered replacement. A swap that needs a typed search query costs more;
//     that's deliberately out of scope (we'd be timing keyboard mechanics).
//     The typing dimension is covered on its own by edit-weight-mid-workout
//     (flow 14), so the two together bound the search-type + log-type costs.
//   - The seed pre-completes set 1 on 2 of the 5 exercises, so flow 1/5 counts
//     reflect a partially-started session (the realistic mid-workout case),
//     not a from-scratch 15-set log.

import XCTest

final class TapBudgetTests: XCTestCase {

    /// Known shapes of the deterministic UI-test seeds. Kept here so the
    /// per-flow `reference` and the count-invariant guards reference ONE place:
    /// changing a seed forces updating these (the guard fails otherwise), and
    /// the reference recomputes automatically.
    private enum Seed {
        /// `--seed-supersets-demo`: 5 exercises (PhaseTrainingApp.seedSupersetsDemo).
        static let supersetsExercises = 5
        /// Same seed: 13 of 15 sets undone (set 1 pre-done on 2 of the 5).
        static let supersetsUndoneSets = 13
        /// `--seed-plan-demo`: 5-exercise generatedWorkout (seedPlanDemo).
        static let plannedExercises = 5
        /// No-plan fallback: WorkoutTemplate.upper1 has 6 exercises.
        static let fallbackExercises = 6
        /// Start + Finish = 2 fixed taps around the single whole-workout "Log
        /// all" tap in the two end-to-end "from Today" flows (each is overhead
        /// + 1, independent of exercise count). Finish AUTO-SAVES and lands on
        /// the summary — no separate Save tap, no feedback Skip.
        static let fullFlowOverhead = 2
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 1. Log a workout (in-workout slice)

    /// From inside LogScreen with the seeded session: log the WHOLE workout with
    /// the single header "Log all" button, then Finish. Reference: 1 Log-all +
    /// 1 Finish = 2 (independent of exercise count — that's the point of the
    /// whole-workout button vs the per-exercise shortcut).
    func testTapBudget_logWorkout_inWorkout() throws {
        let app = launchInLog()
        var counter = TapCounter(app: app, flow: "log-workout-in-workout")

        logAllWorkout(&counter, expectedExercises: Seed.supersetsExercises)
        counter.tap("log-finish")

        recordTapBudget(counter, reference: 2)
    }

    // MARK: - 2. Log a workout (full, Today → saved, no plan)

    /// Cold start with no plan and no active session → Today shows the upper-1
    /// fallback as a startable lift day. Start → Log all → Finish (auto-saves
    /// to the summary). Reference: Start + Log all + Finish = 3.
    func testTapBudget_logWorkout_full() throws {
        let app = launchOnToday()
        var counter = TapCounter(app: app, flow: "log-workout-full")

        runFullFlowFromToday(&counter, expectedExercises: Seed.fallbackExercises)

        recordTapBudget(counter, reference: Seed.fullFlowOverhead + 1)
    }

    // MARK: - 3. Swap an exercise

    /// From LogScreen, open the swap picker on exercise idx 2 (Back Squat) and
    /// pick the first offered replacement. Reference: 1 open + 1 pick = 2.
    /// This is the no-search floor — accepting the first row. A swap that needs
    /// a typed query costs more and is intentionally not tracked here.
    func testTapBudget_swapExercise() throws {
        let app = launchInLog()
        var counter = TapCounter(app: app, flow: "swap-exercise")

        counter.tap("log-swap-2")
        tapFirstPickerRow(&counter)

        recordTapBudget(counter, reference: 2)
    }

    // MARK: - 4. Log a workout (full, PLANNED user)

    /// Same end-to-end shape as flow 2, but Today resolves a seeded 5-exercise
    /// generatedWorkout (`--seed-plan-demo`) instead of the upper-1 fallback.
    func testTapBudget_logWorkout_plannedFull() throws {
        let app = launchOnToday(extraArgs: ["--seed-plan-demo"])
        var counter = TapCounter(app: app, flow: "log-workout-planned-full")

        runFullFlowFromToday(&counter, expectedExercises: Seed.plannedExercises)

        recordTapBudget(counter, reference: Seed.fullFlowOverhead + 1)
    }

    // MARK: - 5. Log a workout per-set (representative, non-bulk)

    /// From inside LogScreen with the seeded session: instead of the "Log all
    /// sets" shortcut, tap each undone set's check circle one at a time, then
    /// Finish. The per-set ceiling that bulk-log (flow 1) floors. Auto-rest is
    /// suppressed (`--ui-test-suppress-auto-rest`): otherwise the inline rest
    /// card started by a set toggle overlays the next row and hides its controls
    /// from the a11y tree before we can query them, undercounting by a tap. Rest
    /// behavior itself is covered by LogFlowTests, not here.
    func testTapBudget_logWorkout_perSet() throws {
        let app = launchInLog(suppressAutoRest: true)
        var counter = TapCounter(app: app, flow: "log-workout-per-set")

        let tapped = perSetLogAllExercises(&counter)
        XCTAssertEqual(tapped, Seed.supersetsUndoneSets,
                       "superset demo undone-set count changed — update Seed.supersetsUndoneSets")
        counter.tap("log-finish")

        recordTapBudget(counter, reference: Seed.supersetsUndoneSets + 1)
    }

    // MARK: - 6. Add an exercise mid-workout

    /// From inside LogScreen, open the add-exercise picker and pick the first
    /// offered exercise (full catalog, no search). Reference: 1 open + 1 pick = 2.
    func testTapBudget_addExerciseMidWorkout() throws {
        let app = launchInLog()
        var counter = TapCounter(app: app, flow: "add-exercise-mid-workout")

        counter.tap("log-add-exercise")
        tapFirstPickerRow(&counter)

        // The picked exercise is appended — a 6th row (index == prior count)
        // should now exist.
        XCTAssertTrue(
            app.staticTexts["log-exercise-name-\(Seed.supersetsExercises)"].waitForExistence(timeout: 5),
            "picked exercise should be appended as a new row")

        recordTapBudget(counter, reference: 2)
    }

    // MARK: - 7. Edit the workout on Today, then start

    /// From Today with a planned workout, open the first exercise's action
    /// sheet, move it down (sheet dismisses), then Start. Measures the
    /// edit-then-start cost, not the full log. Reference: 1 open + 1 move + 1
    /// start = 3.
    func testTapBudget_editThenStart() throws {
        let app = launchOnToday(extraArgs: ["--seed-plan-demo"])
        var counter = TapCounter(app: app, flow: "edit-then-start")

        counter.tap("today-edit-1")               // open action sheet, exercise 1
        counter.tap("exercise-action-move-down")  // reorder (sheet dismisses)
        counter.tap("today-start-workout")        // start the edited workout

        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8),
                      "edit-then-start should land in LogScreen")

        recordTapBudget(counter, reference: 3)
    }

    // MARK: - 8. Discard a workout

    /// From LogScreen, Finish (auto-saves) → Discard → confirm the alert. Since
    /// Finish now saves, Discard deletes the just-logged record. Reference:
    /// 1 Finish + 1 Discard + 1 confirm = 3. The destructive confirm stays.
    func testTapBudget_discardWorkout() throws {
        let app = launchInLog()
        var counter = TapCounter(app: app, flow: "discard-workout")

        counter.tap("log-finish")
        // T1-3 made Finish confirm when sets are still open, and the seed
        // leaves 13 of 15 undone, so this flow always sees the alert. Same
        // label-keyed tap as the discard confirm below (an explicit id on an
        // alert button produced duplicate matches on iOS 26).
        // Scope to the alert: LogScreen's own Finish button is still in the
        // hierarchy behind it, so an app-wide query matches two.
        let finishConfirm = app.alerts.buttons["Finish"]
        XCTAssertTrue(finishConfirm.waitForExistence(timeout: 5),
                      "open sets should raise the finish confirm")
        finishConfirm.tap()
        counter.bump()
        XCTAssertTrue(app.buttons["complete-discard"].waitForExistence(timeout: 8),
                      "Finish should auto-save and show the summary")
        counter.tap("complete-discard")

        // Destructive confirm is a SwiftUI `.alert`; its buttons can't carry a
        // reliable accessibilityIdentifier (an explicit id produced duplicate
        // matches on iOS 26), so tap the destructive button by its label. This
        // keys on the English string — fine for the en-US CI sim, would need a
        // localized lookup if the CI locale ever changes.
        let confirm = app.buttons["Discard"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5),
                      "discard confirm alert should appear")
        confirm.tap()
        counter.bump()

        recordTapBudget(counter, reference: 4)
    }

    // MARK: - 9. Log a sport session

    /// Today is a seeded sport day (`--seed-sport-demo`) → tap Log session,
    /// accept the default 60 min / moderate, Save. Reference: 1 open + 1 save = 2.
    func testTapBudget_logSport() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-sport-demo"]
        app.launch()
        var counter = TapCounter(app: app, flow: "log-sport")

        XCTAssertTrue(app.buttons["today-log-sport"].waitForExistence(timeout: 8),
                      "a sport day should show the Log session CTA")
        counter.tap("today-log-sport")
        counter.tap("sport-log-save")

        recordTapBudget(counter, reference: 2)
    }

    // MARK: - 10. Onboarding → first plan (cold launch)

    /// The activation budget: cold launch (no --ui-test-onboarded) → walk the
    /// minimal valid onboarding path → accept the generated plan → land in the
    /// main tabs. Sports is the only step with no default (must pick one);
    /// equipment ships pre-selected, so the minimal path advances on its
    /// default. The Accept button is gated on async plan generation, so it's
    /// tapped once enabled. Reference: 10 advances + 1 sport selection +
    /// 1 consent pick = 12. (Was 13 before the era-affinity step was removed.)
    func testTapBudget_onboardingToFirstPlan() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-reset"]   // NO --ui-test-onboarded
        app.launch()
        var counter = TapCounter(app: app, flow: "onboarding-to-first-plan")

        XCTAssertTrue(app.buttons["onboarding-continue-welcome"].waitForExistence(timeout: 8),
                      "cold launch should present onboarding")

        // Each Continue is ided by its step, so every tap waits for the actual
        // step to be on screen (no shared-id race across the transition). Only
        // SPORTS needs a selection — equipment (defaults to bodyweight) is
        // pre-selected, so tapping an option there would DESELECT the default;
        // the minimal path just advances on the default.
        counter.tap("onboarding-continue-welcome")
        tapFirstMatching(&counter, prefix: "onboarding-sport-")     // sports (no default)
        counter.tap("onboarding-continue-sports")
        counter.tap("onboarding-continue-sportSeasons")
        counter.tap("onboarding-continue-availability")
        counter.tap("onboarding-continue-equipment")
        counter.tap("onboarding-continue-experience")
        counter.tap("onboarding-continue-about")
        counter.tap("onboarding-continue-constraints")
        // Consent is the second gated step (T0-5): neither option is
        // pre-selected, so Continue stays disabled until the user picks one.
        // Declining keeps the walk offline and costs the same single tap.
        counter.tap("onboarding-consent-off")
        counter.tap("onboarding-continue-coachConsent")
        counter.tapWhenEnabled("onboarding-continue-planPreview", timeout: 15)  // Accept

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10),
                      "accepting the plan should dismiss onboarding into the main tabs")

        recordTapBudget(counter, reference: 12)
    }

    // MARK: - 11. Weekly check-in → regenerated plan

    /// `--ui-test-open-weekly-checkin` presents the flow on launch. Walk
    /// intent → constraints → events (all advance on defaults) → feedback
    /// (pick a rating, the one gated step) → Generate plan → Accept. The plan
    /// is generated synchronously before the preview, so Accept is enabled on
    /// arrival. Reference: 5 advances + 1 rating = 6.
    func testTapBudget_weeklyCheckIn() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--ui-test-open-weekly-checkin"]
        app.launch()
        var counter = TapCounter(app: app, flow: "weekly-check-in")

        XCTAssertTrue(app.buttons["checkin-continue-intent"].waitForExistence(timeout: 10),
                      "weekly check-in should auto-present on launch")
        counter.tap("checkin-continue-intent")
        counter.tap("checkin-continue-constraints")
        counter.tap("checkin-continue-events")
        tapFirstMatching(&counter, prefix: "checkin-rating-")        // feedback (gated)
        counter.tap("checkin-continue-feedback")                     // "Generate plan"
        counter.tapWhenEnabled("checkin-continue-preview", timeout: 12)  // Accept

        // Record the count first — it's complete once Accept is tapped, so the
        // CI marker emits even if the dismissal smoke-check below is slow.
        recordTapBudget(counter, reference: 6)

        // Smoke-check that Accept dismissed the sheet back to the app. Generous
        // timeout: sheet-dismiss animation + a11y teardown can lag on a cold sim.
        let gone = expectation(for: NSPredicate(format: "exists == false"),
                               evaluatedWith: app.buttons["checkin-continue-preview"])
        wait(for: [gone], timeout: 12)
    }

    // MARK: - 12. Build a workout from scratch and start it

    /// The "build my day" path: Library → Workouts → Build a workout → add one
    /// exercise → Start. The from-scratch activation cost when the user wants to
    /// train something their plan didn't give them. Before this path existed the
    /// only route was scheduling a custom routine onto a day and waiting for a
    /// regen, so this flow's budget is the whole point of the feature.
    func testTapBudget_buildAndStartWorkout() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 10),
                      "should land in the tabs")

        var counter = TapCounter(app: app, flow: "build-and-start-workout")
        app.tabBars.buttons["Library"].tap()          // 1 — Library tab
        counter.bump()
        counter.tap("Workouts")                       // 2 — Workouts segment
        counter.tap("library-create-custom")          // 3 — Build a workout
        counter.tap("Add exercise")                   // 4 — open the picker
        tapFirstPickerRow(&counter)                   // 5 — pick an exercise
        counter.tap("custom-routine-start")           // 6 — Start workout

        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 10),
                      "build-and-start should land in the live log")
        recordTapBudget(counter, reference: 6)
    }

    // MARK: - 13. Start a SAVED workout (the Library play button)

    /// One-tap-per-step start of an existing saved workout: Library → Workouts →
    /// ▶ on the row. The saved-workout counterpart to flow 12 — this is the
    /// repeat-use cost once a workout exists.
    func testTapBudget_startSavedWorkout() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 10))

        // Arrange: build + save one workout (not counted — this is setup).
        app.tabBars.buttons["Library"].tap()
        app.buttons["Workouts"].tap()
        app.buttons["library-create-custom"].tap()
        app.buttons["Add exercise"].tap()
        let firstRow = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'picker-row-name-'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()
        // Save is gated on a non-empty name (Start is not — see
        // CustomRoutineEditSheet.canStart). Setup, so not counted.
        let nameField = app.textFields["custom-routine-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "routine name field should exist")
        nameField.tap()
        nameField.typeText("Budget Flow")
        app.buttons["Save"].tap()

        // Act: the measured flow — the saved row's play button.
        var counter = TapCounter(app: app, flow: "start-saved-workout")
        let play = app.buttons.matching(
            NSPredicate(format: "label == 'Start workout'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 6), "saved workout should expose a play button")
        play.tap()
        counter.bump()                                // 1 — ▶ on the saved row

        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 10),
                      "play button should land in the live log")
        recordTapBudget(counter, reference: 1)
    }

    // MARK: - 14. Edit a set's weight mid-workout (the typing cost)

    /// From LogScreen with the seeded session: tap the first UNDONE set's
    /// weight field, clear it, type a new value, confirm. The typing cost that
    /// flows 1/2/4/5 deliberately exclude (their happy path needs zero
    /// typing). The seed leaves sets 2+ undone on every exercise, so
    /// `log-set-weight-0-1` exists and is editable.
    ///
    /// Counted taps only — keystrokes are NOT taps and are not counted (same
    /// policy as the swap flow's search exclusion); the flow measures how many
    /// navigation taps editing requires around the typing. Reference:
    /// 1 tap field + 1 confirm = 2.
    func testTapBudget_editWeightMidWorkout() throws {
        let app = launchInLog(suppressAutoRest: true)
        var counter = TapCounter(app: app, flow: "edit-weight-mid-workout")

        let field = app.textFields["log-set-weight-0-1"]
        XCTAssertTrue(field.waitForExistence(timeout: 6),
                      "an undone set's weight field should be editable")
        field.tap()
        counter.bump()                                // 1 — tap the weight field
        // Clear the pre-filled value, then type. Keystrokes are not taps; only
        // the field-tap and the keyboard-dismiss are counted. The decimal pad
        // has no select-all that reaches this field reliably, so clear via
        // cut from the double-tap selection: double-tap selects, Cut removes.
        field.doubleTap()                             // selects the word
        let cut = app.menuItems["Cut"]
        if cut.waitForExistence(timeout: 2.5) {
            cut.tap()
        }
        field.typeText("60")
        // Dismiss the keyboard: decimal pad has no Done, so tap the same field
        // then swipe down (the dismiss is a tap-equivalent interaction and
        // counts).
        app.swipeDown()
        counter.bump()

        // The edit landed: the field now shows the typed value.
        XCTAssertEqual(field.value as? String, "60",
                       "typed weight should stick in the field")

        recordTapBudget(counter, reference: 2)
    }

    // MARK: - Launch helpers

    /// Launch straight into LogScreen with the deterministic superset demo
    /// session. `fastRest` clamps every exercise's rest interval (seconds).
    private func launchInLog(fastRest: Int? = nil,
                             suppressAutoRest: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-test-onboarded",
            "--ui-test-reset",
            "--seed-supersets-demo",
        ]
        if let s = fastRest { app.launchArguments.append("--ui-test-rest-seconds=\(s)") }
        if suppressAutoRest { app.launchArguments.append("--ui-test-suppress-auto-rest") }
        app.launch()
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8),
                      "should land in LogScreen with seeded session")
        return app
    }

    /// Launch onto Today (onboarded, clean state). `extraArgs` adds seeds such
    /// as `--seed-plan-demo`. Waits for the start-workout CTA so the flow has a
    /// startable day before the first tap.
    private func launchOnToday(extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset"] + extraArgs
        app.launch()
        XCTAssertTrue(app.buttons["today-start-workout"].waitForExistence(timeout: 8),
                      "Today should show a startable workout")
        return app
    }

    // MARK: - Shared flow bodies

    /// Tap the first row in an ExercisePickerSheet (rows are static texts ided
    /// `picker-row-name-<name>`). Counts one tap. Shared by the swap + add-
    /// exercise flows; the sheet auto-dismisses on pick.
    private func tapFirstPickerRow(_ counter: inout TapCounter) {
        let app = counter.app
        let firstRow = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'picker-row-name-'")
        ).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5),
                      "picker should expose at least one row")
        counter.scrollIntoView(firstRow)
        firstRow.tap()
        counter.bump()
    }

    /// Tap the first button whose accessibility id begins with `prefix` (the
    /// onboarding option components are ided by-slug, so the test taps a valid
    /// selection without hard-coding which one is first). Counts one tap.
    private func tapFirstMatching(_ counter: inout TapCounter, prefix: String) {
        let app = counter.app
        let el = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        ).firstMatch
        XCTAssertTrue(el.waitForExistence(timeout: 6), "expected a control ided '\(prefix)*'")
        counter.scrollIntoView(el)
        el.tap()
        counter.bump()
    }


    /// Spine shared by the two end-to-end "log a workout from Today" flows:
    /// Start → Log all → Finish → Save → skip feedback. Asserts the LogScreen +
    /// CompleteScreen waypoints and that the workout had `expectedExercises`
    /// exercises, so a broken seam is diagnosed precisely.
    private func runFullFlowFromToday(_ counter: inout TapCounter, expectedExercises: Int) {
        let app = counter.app

        counter.tap("today-start-workout")
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8),
                      "[\(counter.flow)] Start should land in LogScreen")

        logAllWorkout(&counter, expectedExercises: expectedExercises)

        counter.tap("log-finish")
        // Finish AUTO-SAVES and lands on the summary — no Save/Skip taps. The
        // workout is logged at this point; returning to Today via "Done" is
        // post-logging navigation and isn't part of the budget (the summary
        // shows with the tab bar visible).
        XCTAssertTrue(app.buttons["complete-done"].waitForExistence(timeout: 8),
                      "[\(counter.flow)] Finish should auto-save and show the summary")
    }

    /// Log the WHOLE workout with the single header "Log all" button (one tap),
    /// after asserting the session has `expectedExercises` exercise rows — the
    /// seed-shape guard that catches a seed silently changing. Counting the rows
    /// also catches a LazyVStack refactor dropping off-screen rows from the
    /// a11y tree (the row probe would under-count and the guard would fail).
    private func logAllWorkout(_ counter: inout TapCounter, expectedExercises: Int) {
        let app = counter.app
        let cap = 30
        var seen = 0
        while seen < cap, app.staticTexts["log-exercise-name-\(seen)"].exists { seen += 1 }
        XCTAssertLessThan(seen, cap,
                          "hit the \(cap)-exercise cap — rows likely missing from the a11y tree")
        XCTAssertEqual(seen, expectedExercises,
                       "[\(counter.flow)] workout exercise count changed (expected \(expectedExercises))")
        counter.tap("log-all-workout")
    }

    /// Tap each UNDONE set's check circle, exercise by exercise. Returns the
    /// number of checks tapped. An undone set renders its weight cell as an
    /// editable TextField (`numCell` switches to static Text once done), so the
    /// presence of `log-set-weight-<e>-<s>` in `textFields` is the reliable
    /// "still undone" signal — we never re-toggle a done set. XCTFails if either
    /// safety cap is hit (rows/sets missing from the a11y tree → unreliable).
    @discardableResult
    private func perSetLogAllExercises(_ counter: inout TapCounter) -> Int {
        let app = counter.app
        let exCap = 30, setCap = 12
        var exIdx = 0
        var tapped = 0
        while exIdx < exCap, app.staticTexts["log-exercise-name-\(exIdx)"].exists {
            var setIdx = 0
            while setIdx < setCap {
                // No check button at this index → past the end of this exercise.
                guard app.buttons["log-set-check-\(exIdx)-\(setIdx)"].exists else { break }
                if app.textFields["log-set-weight-\(exIdx)-\(setIdx)"].exists {
                    counter.tap("log-set-check-\(exIdx)-\(setIdx)")
                    tapped += 1
                }
                setIdx += 1
            }
            XCTAssertLessThan(setIdx, setCap,
                              "hit the \(setCap)-set cap on exercise \(exIdx) — sets likely missing "
                              + "from the a11y tree; tap count is unreliable")
            exIdx += 1
        }
        XCTAssertGreaterThan(exIdx, 0, "expected at least one exercise")
        XCTAssertLessThan(exIdx, exCap,
                          "hit the \(exCap)-exercise cap — rows likely missing from the a11y tree")
        return tapped
    }

    // MARK: - Recording

    /// Print (human + JSON marker) + attach the tap count. Per the "track,
    /// don't gate" decision this never fails on budget — it only annotates the
    /// report and feeds the CI baseline diff. `seconds` is wall-clock from the
    /// counter's creation to the final bump: a flow can hold its tap count
    /// while its real interaction cost (rest-card waits, picker latency) grows.
    private func recordTapBudget(_ counter: TapCounter, reference: Int) {
        let verdict = counter.count <= reference ? "within budget" : "OVER budget"
        let line = "TAP-BUDGET | \(counter.flow): actual=\(counter.count) "
            + "reference=\(reference) → \(verdict)"
        print(line)
        // Machine-readable marker parsed by scripts/quality/tap_budget_diff.py.
        // seconds/swipes/max-gap are optional extras the report renders when
        // present. max_gap_s is the longest single inter-tap wait; date feeds
        // the history trend file.
        let seconds = String(format: "%.1f", counter.elapsedSeconds)
        let maxGap = String(format: "%.1f", counter.maxGap)
        let p95 = String(format: "%.1f", counter.p95Gap)
        let iso = ISO8601DateFormatter().string(from: Date())
        print("TAP-BUDGET-JSON {\"flow\":\"\(counter.flow)\",\"actual\":\(counter.count),"
            + "\"reference\":\(reference),\"seconds\":\(seconds),"
            + "\"swipes\":\(counter.swipes),\"max_gap_s\":\(maxGap),"
            + "\"p95_gap_s\":\(p95),\"date\":\"\(iso)\"}")
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
    private(set) var swipes = 0
    /// Longest single inter-tap wait, seconds. A flow can hold its tap count
    /// while one step stalls (rest-card overlay, picker latency); max-gap
    /// isolates that from uniformly slow taps.
    private(set) var maxGap: TimeInterval = 0
    /// All inter-tap gaps (for the p95 column). Empty for 1-tap flows.
    private var gaps: [TimeInterval] = []
    private var lastTapAt: Date?
    /// Wall-clock from counter creation (first read in `elapsedSeconds`, so a
    /// flow that constructs the counter late — e.g. flow 13, whose setup isn't
    /// counted — measures only the tapped portion).
    private let start = Date()

    init(app: XCUIApplication, flow: String) {
        self.app = app
        self.flow = flow
    }

    var elapsedSeconds: TimeInterval { Date().timeIntervalSince(start) }

    private mutating func noteTap() {
        let now = Date()
        if let last = lastTapAt {
            let gap = now.timeIntervalSince(last)
            maxGap = max(maxGap, gap)
            gaps.append(gap)
        }
        lastTapAt = now
        count += 1
    }

    /// 95th-percentile inter-tap gap, seconds. 0 for 1-tap flows (no gaps).
    /// Unlike whole-flow wall-clock, this ignores deliberate dwell time and
    /// isolates per-step stalls — the product-relevant time signal.
    var p95Gap: TimeInterval {
        guard !gaps.isEmpty else { return 0 }
        let sorted = gaps.sorted()
        let idx = min(Int((Double(sorted.count) * 0.95).rounded(.up)) - 1,
                      sorted.count - 1)
        return sorted[max(0, idx)]
    }

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
        // A button that exists but is disabled/obscured taps as a SILENT no-op;
        // counting it would let a broken flow look fine here and fail
        // misleadingly a step later. Require it to actually be hittable.
        // isHittable alone is not enough: a DISABLED SwiftUI button still
        // reports hittable, so the tap no-ops and the flow dies several
        // assertions later against a screen that never advanced. Three of
        // main's seven red UI tests failed exactly that way.
        guard el.isHittable, el.isEnabled else {
            XCTFail("[\(flow)] button '\(id)' exists but isn't tappable — disabled "
                    + "(\(el.isEnabled ? "enabled" : "DISABLED")) or obscured "
                    + "(would-be tap #\(count + 1))", file: file, line: line)
            return
        }
        el.tap()
        noteTap()
    }

    /// Tap a button once it exists AND becomes enabled. Used for a control that
    /// is briefly disabled while an on-appear step settles — e.g. the
    /// plan-preview Accept button, enabled once OnboardingPlanPreviewScreen's
    /// `.onAppear` plan generation returns (synchronous, but not instant on a
    /// cold sim). Polls within a SINGLE `timeout` budget (existence + enabled
    /// together), so worst-case wait is `timeout`, not 2×.
    mutating func tapWhenEnabled(_ id: String, timeout: TimeInterval = 10,
                                 file: StaticString = #file, line: UInt = #line) {
        let el = app.buttons[id]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !(el.exists && el.isEnabled) {
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard el.exists, el.isEnabled else {
            XCTFail("[\(flow)] button '\(id)' never became enabled within \(Int(timeout))s",
                    file: file, line: line)
            return
        }
        scrollIntoView(el)
        el.tap()
        noteTap()
    }

    /// Count a tap performed manually by the caller (e.g. a predicate-matched
    /// row that isn't addressable by a single id).
    mutating func bump() { noteTap() }

    /// Swipe up until the element is hittable (or we give up). Used for the
    /// per-exercise "Log all sets" buttons that sit below the fold. Swipe
    /// count feeds the report's scroll-distance column.
    mutating func scrollIntoView(_ el: XCUIElement, maxSwipes: Int = 6) {
        var tries = 0
        while !el.isHittable, tries < maxSwipes {
            app.swipeUp()
            tries += 1
            swipes += 1
        }
    }
}
