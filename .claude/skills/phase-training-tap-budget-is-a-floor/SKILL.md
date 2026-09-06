---
name: phase-training-tap-budget-is-a-floor
description: >
  Interpret or extend phase-training's TapBudgetTests, and the reusable
  UI-test mechanisms it relies on: seeding a planned-user WeekPlan via
  --seed-plan-demo (survives launch only because auto-regen is gated on
  memory.onboardedAt), and detecting undone-vs-done sets via the weight cell
  being a TextField. Tap counts measure the OPTIMAL minimal-tap floor, not
  typical usage. Trigger for "is the tap budget accurate", "add/extend tap
  budget flows", "seed a planned user in a phase-training UI test", or
  reasoning about per-flow tap cost in phase-training / phase-training2.
when-to-use: >
  Questions about TapBudgetTests.swift, adding flows/variants, or seeding a
  planned WeekPlan / detecting set state in any phase-training UI test. Skip
  for unrelated XCUITest work (see phase-training-xcuitest-recipe).
---

# phase-training tap budget is a floor, not typical usage

`PhaseTrainingUITests/TapBudgetTests.swift` tracks (does NOT gate — decision
2026-05-31) tap counts for 3 flows. A broken flow fails the build; going over
budget only prints `TAP-BUDGET | <flow>: actual=N reference=M` + a keepAlways
attachment. The references are arithmetically correct — verified against source:

11 flows (2026-06-01, all verified passing on sim, actual==reference):
in-workout 6 · full 10 · swap 2 · planned-full 9 · per-set 14 · add-exercise 2 ·
edit-then-start 3 · discard 3 · log-sport 2 · onboarding 12 · weekly-check-in 6.
(onboarding: 13→12 on 2026-06-27 with the goal/focus step deleted, back UP to 13
when the consent pick was added, then 13→12 on 2026-09-06 with the era-affinity
step deleted. It has been wrong in this file twice — read the test, not this line.)
References derive from a `Seed` enum (not literals) + a count-invariant guard
(`XCTAssertEqual` on what the loop drove) so a seed change fails loud. CI:
`TAP-BUDGET-JSON` markers → `scripts/quality/tap_budget_diff.py` vs
`tap-budget-baseline.json`, wired non-gating into `test.yml` (tee + diff step).

Key facts that make the numbers what they are:
- `--seed-supersets-demo` plants **5** exercises (`PhaseTrainingApp.swift:68`);
  2 have set 1 pre-`done` but all expose `log-all` since it shows when `!allDone`
  (`LogScreen.swift:455`). `logAllSets` (`:966`) marks all sets done in one tap.
- `WorkoutTemplate.upper1` has exactly **6** exercises (`WorkoutTemplate.swift:53`).
- `complete-save` auto-presents the feedback sheet; `feedback-skip` dismisses.
- `log-finish` is an unconditional closure — never a confirm dialog.

## Floor-vs-real framing (still true after flows 4/5)

Flows 1/2/4 use the "Log all sets" bulk shortcut (1 tap/ex) — a FLOOR. Flow 5
is the per-set ceiling so the gap (6 → 14 for the same session) is visible.
None count weight/reps KEYSTROKES — set 1 is pre-filled and edits propagate, so
the happy path needs zero typing. swap (flow 3) is the no-search floor. Flow 2
rides the upper-1 no-plan fallback; flow 4 is the real planned-user counterpart.

## Two reusable UI-test mechanisms this produced

1. **Seed a planned-user WeekPlan** — `--seed-plan-demo` (`PhaseTrainingApp.swift`,
   `seedPlanDemo()`) writes a 7-day `WeekPlan` to `pt_week_plan` (encode with
   `.secondsSince1970` to match `PlanStore.decoder()`) whose day-0 = `.lift`
   with a `generatedWorkout`. Today then resolves the real-plan branch
   (`TodayScreen.swift:94`). **It survives launch ONLY because PlanStore's
   auto-regen subscription is gated on `memory.onboardedAt != nil`** — nil under
   `--ui-test-reset` — so it isn't clobbered. `--ui-test-reset` clears
   `pt_week_plan` in `init()` before the seed runs, so the seed lands last.
   `@StateObject` stores construct lazily on first body render, after `App.init`,
   so the UserDefaults write is in place before PlanStore reads it (same pattern
   as `seedSupersetsDemo`).
2. **Detect undone vs done sets** — an undone set renders its weight cell as a
   `TextField`; `numCell` switches to static `Text` once done. So
   `app.textFields["log-set-weight-<e>-<s>"].exists` is the reliable "still
   undone" probe (used by `perSetLogAllExercises` to never re-toggle a done set).

**Landmine:** the bulk/per-set loops walk `idx` until `log-exercise-name-<idx>`
stops existing — correct ONLY because LogScreen is an eager
`ScrollView { VStack { ForEach } }` (`LogScreen.swift:182-192`), so every row is
in the a11y tree. A `LazyVStack` refactor would drop off-screen rows, the loop
would stop early, and the budget would silently DROP (reads as "cheaper!" when
the test went blind). Harden by asserting the iterated count == the seed's known
shape, and by `XCTFail`/`log()` if the `idx<30`/`setIdx<12` caps are ever hit.

## Extending to onboarding + weekly check-in (2026-06-01)

Both reuse `OnboardingPrimaryButton` (check-in via `CheckInScaffold`), so adding
an optional `a11yId` param to it + `OnboardingChip`/`OnboardingPickRow` ids most
controls in 5 files, not 13. Seeds/triggers: onboarding presents on cold launch
with `--ui-test-reset` and NO `--ui-test-onboarded`; weekly check-in needs a new
`--ui-test-open-weekly-checkin` arg → a `.task` sets `tabSelection.showWeeklyCheckIn`.
Two traps that cost two debug rounds (both manifest as
[[xcuitest-tap-no-op-misleading-downstream-failure]] — a no-op tap, blamed
downstream):
- **Shared-id race.** One id ("onboarding-continue") on every step's button
  races the `.id(step)` transition (leaving + entering button both briefly
  exist) → tap lands on a non-advancing instance. Fix: step-specific id
  `onboarding-continue-\(step)` so each tap waits for the actual step.
- **Default-selection deselect.** Tapping the "first option" of a gated step
  that ships PRE-SELECTED toggles it OFF → Continue disabled → no-op → stuck.
  Check `TrainingMemory` defaults first: `sports=[]` (must pick), but
  `equipment=[.bodyweight]` is pre-set — the minimal path advances on the
  default. That's why onboarding is 12 taps (11 advances + 1 sport selection),
  not the ~22 a naive walk assumes.

## Step add/remove desyncs the walk — invisible under unit-green (2026-06-27)

The onboarding flow is `welcome → sports → sportSeasons → availability →
equipment → experience → about → constraints → coachConsent → planPreview`. `testTapBudget_onboardingToFirstPlan` taps `onboarding-continue-\(step)`
for each. Deleting/reordering an `OnboardingStep` (e.g. the goal/focus step,
removed M2b) **silently leaves this UI test red** — the UITest target is separate
and slow, so the whole unit suite stays green and CI/local "tests pass" hides it.
Fix when you change the step set: (1) remove/rename the matching `counter.tap`,
(2) decrement the `recordTapBudget(..., reference: N)` count, (3) re-run JUST that
test (`-only-testing:PhaseTrainingUITests/TapBudgetTests/testTapBudget_onboardingToFirstPlan`,
~25s). Run the UITest target after ANY onboarding-flow change.

Three more places carry the same count and are easy to miss: the doc comment
above the test, `PhaseTrainingUITests/tap-budget-baseline.json`
(`"onboarding-to-first-plan"`), and `OnboardingPlanDetailUITests`, which walks
the same step ids. Removing a step ALSO shifts every later `OnboardingStep`
rawValue down by one, which strands a `pt_onboarding_step` saved by an older
build — `OnboardingFlow.resumeStep(rawValue:)` clamps past-the-end values to the
last step so a nearly-finished draft isn't dropped.

Build/verify: session defaults may point at a `.claude/worktrees/...` project —
build the MAIN repo explicitly (`xcodebuild build-for-testing -project
PhaseTraining.xcodeproj ...`), then `test-without-building -only-testing:...`.
