# Follow-up brief: 44pt tap targets, a test that can fail (slot A)

Outcome 2026-11-13: the red run passed (the Library play button started the workout from 4pt above its circle with the modifier removed). The modifier and this test were discarded.

Parent brief: `docs/briefs/tap-targets.md`. Its design, rules, simulator slot and DerivedData path all still apply. The app-source diff is accepted as it stands; change no app source except for the temporary red-run edit below.

## Ruling on the first report

`testDiscardHitAreaExtendsPastDrawnCircle` passed on unmodified code, because a plain Button with empty space around it already takes taps about 28pt past its frame. The test proves nothing about `tapTarget`. Where a small button sits inside a tappable row, the row takes a direct hit on every point outside the button's drawn frame, and that is the case the modifier should change.

## Changes

1. Delete `testDiscardHitAreaExtendsPastDrawnCircle` from `PhaseTrainingUITests/LogFlowTests.swift`.

2. Add one UI test for a small button inside a tappable row whose row tap does something different from the button. (The first version of this brief named the Today info button; no such tile exists. `.controls` is used only in `CustomRoutineEditSheet`, on a row with no tap.)

   Site: the Library "Start workout" play button, `LibraryScreen.swift:419` (YOUR WORKOUTS strip). The tile has `trailing: .iconButton(systemName: "play.fill", accessibilityLabel: "Start workout", onTap: { requestStart(c) })` and a row `onTap` that opens the saved workout. Default `.catalog` density, so the row pads 14 around the 32 x 32 circle. Parent-brief site 4.

   Name: `testStartWorkoutHitAreaExtendsPastDrawnCircleInsideTappableRow`, in whichever UI test file already reaches the Library workouts list with a saved custom workout. If no existing launch argument seeds one, create it through the UI in the test, as an existing test does if one does. Add no seed code to the app.

   Steps:
   - Take the first `app.buttons["Start workout"]`.
   - Tap the point 20pt above its centre (`withOffset(CGVector(dx: 0, dy: -20))`): 4pt above the 32pt circle, inside the 44pt box, inside the row.
   - Assert that the start path ran (whatever `requestStart` presents: the start confirm or the Log screen; assert on an element only that path shows).
   - Assert that the row's own destination (the saved-workout sheet) is absent.

   If the row is too short for that point to fall inside it, tap 20pt left of centre instead and record it.

3. Red run, required. Temporarily remove the `.tapTarget(width: 32, height: 32)` line from the `.iconButton` case in `ExerciseTile.swift` (the label with `.background(Color.accentWash)` and `.clipShape(Circle())`), run the new test, and record the result. Then restore the line exactly and run it again.
   - Red fails and green passes: done.
   - Red passes: the modifier has no effect a UI test can see at this site. Restore the line, keep the test, and say so plainly in the report with the tap offsets you probed. Do not look for another site.
   - Green fails: stop and report what the tap did instead.
   - No saved custom workout can be put in the Library without new app code or more than about ten UI steps: write no test, and report that.

4. Confirm with `git diff` at the end that `ExerciseTile.swift` holds the same four `tapTarget` lines as before your red run.

## Test runs required

1. The new test, red run (modifier line removed at the play button).
2. The new test, green run.
3. `-only-testing:PhaseTrainingUITests/LogFlowTests/testDiscardWorkoutPromptsConfirmation` (the file changed).

`TapTargetTests` does not need a re-run: no file it covers changes.

## Final report (one message, no interim messages)

- Files changed in this follow-up.
- Each run with pass and fail counts, red run included, and the tap point used.
- The part of your first report that was cut off in delivery, repeated in full: everything after the site 20 line under "Caps used" (site 21, the clip-shortfall list, decisions on anything left open, and anything flagged outside scope).
