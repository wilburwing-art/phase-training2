# Follow-up brief: arc deload label, review rulings (slot A)

Follows `docs/briefs/arc-deload-label.md`. Every decision in your report stands. One code change, found at review.

## The gap

The first brief said `WeekOverrides` is replaced at the week rollover. That holds only on a relaunch (`PlanStore.init`, `reloadFromDefaults`). When the app stays alive across Monday, `refreshForCurrentWeek(memory:today:)` (`PlanStore.swift`, about line 770) calls `generate` with last week's in-memory `overrides`. With the new field, last week's `applied` is carried into the new week: a second deload week in a row, labelled, with the marker moved forward. Last week's `declined` would suppress a deload the new week is due. The same path already carries last week's `weekTone`.

## Change

In `refreshForCurrentWeek`, after `promotePendingIfDue(today:)` and before the `planCoversCurrentWeek` guard:

```swift
// A store that lived through the rollover still holds last week's
// overrides. Start the new week clean, as init does on a relaunch.
let thisWeek = today.startOfTrainingWeek()
if !Calendar.current.isDate(overrides.weekStart, inSameDayAs: thisWeek) {
    overrides = WeekOverrides(weekStart: thisWeek)
    saveOverrides()
}
```

Nothing else changes. Do not add a reset inside `generate` or `updateOverrides`.

## Tests

`ArcDeloadWeekTests` (add):
- `test_rollover_doesNotCarryAppliedIntoNextWeek`: generate at `monday(0)` (applied, with week 0 logged so it is a build week), then `refreshForCurrentWeek(memory:today: monday(1))` on a memory with `onboardedAt` set. Assert `overrides.weekStart` is `monday(1)`, `overrides.arcDeload == nil`, `isArcDeloadWeek` false, and the plan's first day is in the week of `monday(1)`.
- `test_rollover_doesNotCarryDeclinedIntoNextWeek`: generate at `monday(0)`, decline, then `refreshForCurrentWeek` at `monday(1)` with week 0 logged. The cooldown never started, so the new week is `applied`.
- `test_rollover_dropsLastWeeksTone`: tone Build set in week 0, `refreshForCurrentWeek` at `monday(1)`, `overrides.weekTone == nil`.

In `test_twoLiftDays_cooldownStarts`, replace the hand-written `store.overrides = WeekOverrides(weekStart: monday(1))` plus `generate` with `refreshForCurrentWeek`, so the test goes through the real rollover.

## Build and test

Slot A only, as before: UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`, `-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A`, both on every `xcodebuild` call. One `xcodebuild test` call, full log to a file, with the seven classes from the first brief plus:

- `-only-testing:PhaseTrainingTests/PlanHistoryTests` if a class of that name exists; otherwise grep `PhaseTrainingTests` for `refreshForCurrentWeek` and `promotePendingIfDue` and add every class that calls either.

If the run shows the empty-catalog failures again ("coach.db must have ...", `vnode unlinked while in use`), re-run once and report both runs. In the report, name every failing test of the first run that is in a file you touched.

Do not commit. Do not touch `docs/`.

## Report

One final report: files changed, each class with pass and fail counts, the classes you added for `refreshForCurrentWeek`, and any existing test that depended on overrides surviving the rollover (list it with what it asserted; do not edit it to pass without saying so).
