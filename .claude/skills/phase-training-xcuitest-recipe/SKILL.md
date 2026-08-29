---
name: phase-training-xcuitest-recipe
description: Boot a phase-training-family iOS app (phase-training, phase-training2, workout-plan) directly into LogScreen with a deterministic session for XCUITests. The recipe combines four existing launch args — `--ui-test-onboarded` (skip welcome gate), `--ui-test-reset` (wipe defaults), `--seed-supersets-demo` (write a 5-exercise active session to UserDefaults), and `--ui-test-rest-seconds=N` (clamp every exercise's rest interval so timer-expiry tests fire in ~2s instead of 60-90s). Trigger when writing or extending XCUITests against LogScreen, RestTimer, or any in-workout flow in these repos. Also covers the picker-row identifier pattern and the known squat-hit-test flake. Skip for unit tests against SessionStore (use PhaseTrainingTests instead) and for non-fitness apps.
when-to-use: writing XCUITests against LogScreen / RestTimer / mid-workout flow in phase-training / phase-training2 / workout-plan
---

# XCUITest recipe for phase-training-family LogScreen

## Boot directly into LogScreen

`TodayTab.onAppear` routes to `.log` when `store.active != nil`. So:

```swift
let app = XCUIApplication()
app.launchArguments += [
    "--ui-test-onboarded",       // skip OnboardingFlow
    "--ui-test-reset",           // wipe pt_active_session, pt_sessions, ...
    "--seed-supersets-demo",     // write a deterministic 5-exercise session
]
app.launchArguments.append("--ui-test-rest-seconds=2")  // optional, see below
app.launch()
XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8))
```

`--ui-test-reset` is processed BEFORE `--seed-supersets-demo` in `PhaseTrainingApp.init` (reset clears UserDefaults, then seed writes the demo session). The seed's shape: bench/row are superset 1 with set 1 done; squat is solo; curl/pushdown are superset 2.

## Fast-rest hook

`--ui-test-rest-seconds=N` (added in commit `77c6e0e`) clamps every exercise's `rest: Int` at session-load time so timer-expiry tests don't wait 60-90s. Lives in `LogScreen.loadIfNeeded()`:

```swift
if let s = Self.uiTestRestOverride {
    for i in session.exercises.indices { session.exercises[i].rest = s }
}
```

Use ≥10s if the test needs the active card alive during interaction (preset menu, +15 chip). Use 2s if the test wants expiry within waitForExistence(timeout: 4).

## Identifiers you can rely on

- `log-finish`, `log-cancel` (header), `log-add-exercise` (bottom)
- `log-exercise-name-{exIdx}` (header tap → detail sheet)
- `log-swap-{exIdx}` (per-exercise swap button)
- `log-set-num-{ex}-{set}` (set number Text — tap propagates to row's onTapGesture)
- `log-set-check-{ex}-{set}` (check dot Button)
- `log-set-weight-{ex}-{set}`, `log-set-reps-{ex}-{set}` (TextFields when un-done, Text when done)
- `log-rest-add15`, `log-rest-skip` (RestTimer chips — use these as rest-card-presence proxies; the card's own identifier doesn't propagate reliably)
- `log-rest-time` (Menu button), `log-rest-preset-{seconds}` (preset items)
- `picker-row-name-{exerciseName}` (ExercisePickerSheet rows — match by predicate `BEGINSWITH 'picker-row-name-'`)

## Known flake

Taps on `log-set-check-2-*` (squat, the solo exercise between two supersets in the seed) do NOT route to `toggleSet`. Bench/row/pushdown taps work. Diagnostic dumps show the set never flips to done. Root cause unknown — possibly a SwiftUI hit-test interaction with the solo-row position. Workaround: design tests against bench (idx 0) or pushdown (idx 4) instead of squat.

## Don't

- Don't `git add` pbxproj edits — `*.xcodeproj` is in phase-training2's `.gitignore` (see `[[phase-training2-gitignored-pbxproj]]`).
- Don't use `app.otherElements["log-rest-card"]` to check for rest visibility — the HStack identifier doesn't surface. Use `app.buttons["log-rest-add15"].exists` instead.
- Don't use `app.staticTexts["DONE"]` race: the flash lasts only 1.2s; sample with `waitForExistence(timeout: 4)` from a fastRest=2 start.

## An SF Symbol brings its own identifier and it beats the Button's

`.accessibilityIdentifier("x")` on a `Button` whose label is a bare
`Image(systemName:)` does not stick: the symbol name becomes the identifier.
The weekly check-in's close button reported `xmark`, not `checkin-close`, and
the test read as "the button is missing" rather than "the button is named
something else".

Put the identifier on the **Image**, and keep the label on the Button:

```swift
Button(action: onClose) {
    Image(systemName: "xmark")
        .frame(width: 32, height: 32)
        .accessibilityIdentifier("checkin-close")   // on the Image
}
.buttonStyle(.plain)
.accessibilityLabel("Close")                        // on the Button
```

Same family as the `log-rest-card` note above: an identifier set on the
wrapper does not always reach the element XCUITest matches.

**Diagnose it in one run** rather than guessing, by putting the element dump
in the failure message:

```swift
XCTAssertTrue(el.waitForExistence(timeout: 5),
  "not found; visible: " + app.buttons.allElementsBoundByIndex
      .map { "\($0.identifier)|\($0.label)" }.joined(separator: ", "))
```

That printed `xmark|Close` and ended the guessing immediately.

## Known-failing UI tests (baseline, 2026-08-29)

Five fail on clean `main`, so baseline before blaming a change:
`BuildAndStartWorkoutUITests`, `KettleCompleteUITests`, and three
`TapBudgetTests` (buildAndStart, discardWorkout, startSavedWorkout). To
baseline, `git stash` is not enough — new untracked `.swift` files still break
the build. Move them aside too, then `xcodegen generate`.

## Two more element-surfacing facts

**An accessibility element with actions is a `button`.** A view carrying
`.accessibilityElement(children: .ignore)` plus `.accessibilityAdjustableAction`
and `.accessibilityAction` surfaces as `app.buttons[...]`, NOT
`app.otherElements[...]`. Today's workout wheel cost a run to that. When a
custom element is not found, dump both collections before changing the code.

**"Timed out waiting for AX loaded notification" is not a test failure.** It is
the runner failing to initialize, usually after many consecutive UI runs
against one simulator, and every test in the invocation reports as failed with
no assertion output. Fix with `xcrun simctl shutdown <udid>` then `boot`, and
re-run before believing any result from that invocation.
