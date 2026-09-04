---
name: phase-training-xcuitest-recipe
description: Boot a phase-training-family iOS app (phase-training, phase-training2, workout-plan) directly into LogScreen with a deterministic session for XCUITests. The recipe combines four existing launch args — `--ui-test-onboarded` (skip welcome gate), `--ui-test-reset` (wipe defaults), `--seed-supersets-demo` (write a 5-exercise active session to UserDefaults), and `--ui-test-rest-seconds=N` (clamp every exercise's rest interval so timer-expiry tests fire in ~2s instead of 60-90s). Trigger when writing or extending XCUITests against LogScreen, RestTimer, or any in-workout flow in these repos. Also covers the picker-row identifier pattern, the known squat-hit-test flake, and the disabled-control failure mode: a tap on a button a product fix has gated no-ops and fails several assertions LATER, which left CI red for 13+ runs across three separate instances. ALSO trigger when a UI test times out waiting on a screen that never appeared, or after adding any .disabled()/nextEnabled: gate to a control a test walks. Skip for unit tests against SessionStore (use PhaseTrainingTests instead) and for non-fitness apps.
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

## A tap on a DISABLED control fails several assertions later (bit us 3x)

`isHittable` is true for a disabled SwiftUI button. The synthesized tap no-ops,
the flow never advances, and the test dies on a later `waitForExistence` against
a screen it never reached. The error names the wrong screen, so the search
starts in the wrong place.

**Three separate instances shipped to main and left CI red for 13+ runs**
(2026-08-24 to 2026-09-04), each one a correct product fix whose test walk was
never updated:

| gate added | control | test symptom |
|---|---|---|
| T0-5 consent must be an affirmative pick | `onboarding-continue-coachConsent` | "planPreview never became enabled" |
| T1-3 Finish confirms while sets are open | `log-finish` | "finishing should present the complete screen" |
| `canSave` needs a NAME | `custom-routine-start`, `Save` | "should route into the live log" |

**Diagnostic order** when a UI test times out waiting on a screen: walk BACKWARD
from the failing assertion to the last control tapped, and check whether
anything recently added a `.disabled(...)` or a gated `nextEnabled:`. The
failure is almost never where it is reported.

`TapCounter.tap` now guards `el.isHittable, el.isEnabled` and prints which one
failed. Copy that into any new helper; `isHittable` alone is not a tap check.

Two mechanics worth keeping:

- **Alert buttons need `app.alerts.buttons["X"]`.** `app.buttons["Finish"]`
  matched both the alert and LogScreen's own Finish behind it, and XCUITest
  fails the tap with "Multiple matching elements found". An explicit
  `accessibilityIdentifier` on an alert button also produced duplicates on
  iOS 26, so scope the query rather than id the button.
- **`app.textFields.firstMatch` inside a sheet can resolve to the screen
  behind it.** Naming the routine in `CustomRoutineEditSheet` grabbed Library's
  "Search workouts" box and failed with "Neither element nor any descendant has
  keyboard focus". Give the field its own id (`custom-routine-name`).

Note the gate that hid all three: the 2026-08-23 cycle's build gate was
`xcodebuild test` on **the unit suite**, which cannot observe the UI target, so
every status note read green. Gate on the whole scheme.
