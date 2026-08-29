---
name: phase-training-planstore-mutation-seams-and-week-caps
description: Two phase-training2 PlanStore facts that bite when adding a plan-mutating feature. (1) The PlanEdit/apply() seam can only change a day's KIND — it has NO op to set a day's generatedWorkout content. To set/replace a day's workout you must use the direct-mutation pattern (mutate plan.days[idx], then self.plan = plan; savePlan()) like regenerateToday/consolidateWeek. (2) A per-week capped action (reshuffle, consolidation) needs ~6 plumbing sites, easy to half-wire. Trigger when building a feature that regenerates/replaces workouts in the WeekPlan, or adds a per-week-capped plan action, in phase-training2.
when-to-use: Adding any PlanStore feature that rewrites a day's workout (consolidation, regenerate variants, merge/swap a day's exercises) or that needs a weekly-capped, rollover-resetting counter.
---

# PlanStore: mutation seams + weekly caps

## Seam 1 — PlanEdit can't set a workout
`PlanEdit` cases: move / swapKind / protectDay / shorten / addSession /
removeSession. `apply(diff:)` re-composes `generatedWorkout` ONLY for days
whose **kind changed** (via `composeWorkout`). There is **no PlanEdit to
replace a same-kind day's workout content**. So "regenerate / merge / swap
this day's exercises" can't go through propose()/apply().

**Use the direct-mutation pattern instead** (regenerateToday:~933,
consolidateWeek):
```swift
guard var plan = plan else { return }
plan.days[idx].generatedWorkout = workout
plan.days[idx].title = workout.title
plan.days[idx].routineId = nil
plan.days[idx].generatedReason = workout.provenance
self.plan = plan
savePlan()
recentPicks?.record(exerciseIds: workout.exercises.map(\.exerciseId))
```
`DayPlan` fields are all `var`. To drop a day to rest: set `kind = .rest`,
`generatedWorkout = nil`, `title = "Rest"`, `routineId/generatedReason = nil`.

## Seam 2 — a per-week capped counter is ~6 sites
Mirror `midWeekReshuffleCount` exactly (PR 8). For `midWeek<X>Count`:
1. two key constants: `<x>CountKey`, `<x>WeekKey`
2. `@Published var midWeek<X>Count: Int` (stored, NO default)
3. **init**: load block comparing saved weekStart to `thisWeekStart` →
   `integer(forKey:)` else `0`. MUST set the stored prop in init (single
   init at ~134) or it won't compile.
4. `static let weekly<X>Cap = N`
5. `clear()`: `midWeek<X>Count = 0` + `removeObject` both keys
6. `saveX Count(now:)`: `defaults.set(count, countKey)` +
   `defaults.set(now.startOfTrainingWeek(), weekKey)`
7. at the apply site: guard `< cap`, then `midWeek<X>Count += 1; saveXCount()`
Rollover reset is implicit: step 3's weekStart-tag compare resets to 0 on a
new training week.

## Verify
PlanStore.swift is usually clean of in-flight generator work, so add it
wholesale — but a test that builds the app (any `-only-testing`) compiles
the SwiftUI screens too. UI behavior (banner button → mutation) still needs
a real run / XCUITest; compile-green is necessary not sufficient. Plan days
need `generatedWorkout.focus` set for focus-aware reads
(see `phase-training-dayplan-focus-not-persisted`).

## Seam 3 — `updateOverrides` regenerates the WHOLE week, and clearing is lossy

`PlanStore+Validation.swift:83` — `updateOverrides` runs
`block(&overrides)`, `saveOverrides()`, then **`generate(from: memory)`**,
which rebuilds every day and calls `kickOffLLMRefinementIfConsented`.

Right cost for one deliberate edit (Week day editor, OverrideTodaySheet).
Wrong cost for anything a user can operate repeatedly — a scroller, a
segmented control, an undo. Today's title wheel would have rerolled the week
and fired a refinement on every stop.

**Two independent problems, and the second is the one that surprises:**

1. Cost and blast radius: one day's change rebuilds seven.
2. **Clearing an override does not restore, it re-derives.** Nothing retains
   the day the override displaced, so removing `customRoutineByDate[key]` and
   regenerating yields a *different* workout. In a fixture whose plan was
   seeded rather than generated, today came back as a **rest day**. To a user
   it reads as the app rerolling their session for no reason.

**The pattern that works** (`PlanStore+TodayWorkoutSwitch.swift`): write the
same persisted override so the choice still survives a later regeneration,
then apply it to the one day with the Seam-1 direct mutation, and stash what
you displaced so the way back is exact.

- `WeekOverrides.displacedPlanByDate: [Date: DisplacedPlan]?` — **Optional**,
  per the `weekTone` / `prescriptionRefreshByDate` note in that file: a
  non-optional field missing from an old payload throws `keyNotFound` and the
  `try?` decode in PlanStore nukes the entire week's overrides.
- Write the stash **only if absent**, or switching between two saved workouts
  overwrites it with another saved workout and the planned stop is lost.
- Share the composer. `composeWorkout(fromCustom:)` is no longer private
  precisely so a direct switch and a regeneration cannot drift.

Verify a switch by asserting on the day's EXERCISE LIST, not its title: a
title proves a label moved, the list proves the mutation landed.
