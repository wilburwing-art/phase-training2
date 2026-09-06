# Onboarding as tutorial

## The problem

Onboarding is a modal `fullScreenCover` questionnaire with its own chrome
(`OnboardingScaffold`), its own draft state machine, and its own copy of every
question. It ends on a plan the user is asked to "Accept" with no other option.

Two things are wrong with that.

**The Accept is a fake choice.** The user has never trained with the app, so
they cannot form a verdict on a week plan. Worse, the plan they accept is not
the plan they get: the preview called bare `Planner.generate(memory:routines:)`,
while `finish()` commits `planStore.generate(from:)` (overrides, context,
feedback bias, custom-routine post-processing) and then kicks off LLM refinement
that rewrites lift days seconds later.

**The questions are asked in a room that stops existing.** Nearly every
onboarding step is a duplicate implementation of a Profile editor. Same UI,
different binding target: `$draft` vs `store.memory`. `SportsEditorSheet` even
imports `OnboardingChip` and `OnboardingPickRow`, the onboarding chrome.

| Onboarding step | Permanent home |
|---|---|
| sports | Profile → Sports |
| sportSeasons | Profile → Seasons |
| availability | Profile → Session length, Lift days |
| equipment | Profile → Equipment |
| experience | Profile → Experience |
| about | Profile → About you |
| eraAffinity | **nowhere** (deleted, see below) |
| constraints | Profile → Exercises to avoid, Injuries |
| coachConsent | Profile → CoachSettingsRow |
| planPreview | Week tab |

So the app maintains two implementations of every setting, one of which each
user sees exactly once, and it teaches nothing about where anything lives.

## The reframe

Onboarding's job is not "collect ten fields." Those can be defaulted. Its job is
to build a mental model: what this does, where I change it, what happens when I
do. Make the onboarding path and the settings path the same path.

**Ask only what is irreducible. Default the rest, visibly. Send every correction
to the real home of that setting.**

## Shape

1. **Gate** (`welcome → sports → sportSeasons → coachConsent`). Sport and season
   are irreducible: `WeeklyShape.resolve(primarySport:season:)` needs them and
   the season engine is gated on plannable sports. Consent is an Apple
   5.1.2(i) gate, not a personalization question.
2. **Land on the Week tab** with a real plan already built from defaults, and
   the defaults on screen as tappable assumption chips.
3. **Chips open the real Profile editors** against the live store. Correcting an
   assumption teaches its permanent location, and the week rebuilds underneath.
4. **A permanent "Finish setup" row on Profile** lists what is still assumed.
   The checklist IS the onboarding, and it never disappears. Day-one and
   month-three users hit the same surface.

The plan preview step is deleted, not fixed. Moving the reveal after the gate
kills the fake Accept by elimination and removes the preview-vs-committed
divergence, because the plan on the Week tab is the committed plan.

## Slices

### Slice 1 — remove the era axis ✅ (commit `fe6eb31`)

An orphan: `eraAffinity` was an onboarding step with no Profile home, so it
could never be changed again. Investigation found most of it already dead
(`splitPreference`, `repRangeBias`, `aestheticTags`, `archetypalPrograms` had
zero production readers). Removed entirely. Behavior changes: coach prose loses
its vocabulary block; readiness density norm goes flat at 3.0/wk; `"er:"` leaves
`planInputsHash` (one-time regen for existing users).

### Slice 2 — cut the gate

Delete steps `availability`, `equipment`, `experience`, `about`, `constraints`,
`planPreview` and their screens. 10 steps → 4. Tap floor 12 → 7.

**Blocker to clear first: the defaults are wrong for a silent user.**
`equipment` defaults to `[.bodyweight]`, which under a questionnaire every gym
user is forced past, but under defaults would silently produce a bodyweight-only
week forever. Change to `[.fullGym]`: most-likely, not most-conservative. The
rest are already fine (`sessionMinutes 45`, `liftDaysPerWeek 3`,
`experience .beginner`, age/gender nil).

**Orphan to close first:** `startingState` is written ONLY by
`OnboardingExperienceScreen`. Deleting that screen orphans it exactly as era
was orphaned. Add it to `ExperienceEditorSheet` in this slice.

(Free-text `constraints` is fine: `InjuriesEditorSheet` reads and removes legacy
entries, `InjuryPickerSheet` writes slugs, and the weekly check-in has its own
constraints screen.)

### Slice 3 — assumption chips

Add `TrainingMemory.statedFields: Set<String>` — the profile fields the user has
explicitly set, as opposed to running on a default. A `ProfileField` enum owns
the keys.

`statedFields` MUST stay out of `planInputsHash`. It does not affect generation,
and that hash is both the auto-regen trigger and the `deterministicPick` seed,
so putting presentation state in it would reshuffle the week for nothing (the
mistake `"er:"` was making).

A `PlanAssumptionsRow` on the Week tab renders one chip per unstated field
("3 lift days · assumed") and opens that field's real Profile editor. Every
editor stamps its field into `statedFields` on write, so the chip retires
itself.

### Slice 4 — Profile setup checklist

A "Finish setup" row on Profile showing `n` remaining assumptions, opening a
sheet that lists them and routes to the same editors. Permanent, not a
first-run-only surface.

### Slice 5 — just-in-time asks (NOT IN THIS PASS)

Ask each remaining thing at the moment it first matters: equipment when a
workout list is first opened, injuries/dislikes in `PostWorkoutFeedbackSheet`
after session one. Needs an ask-ledger (fired / dismissed / cooldown) or it
becomes nagware. Deferred deliberately — the chips and checklist are the
pull-based version and should ship first to see if push is even needed.

## Things that will bite

- **Data quality drops.** A modal questionnaire gets ~100% field completion
  because there is no exit. Pull-based gets less. That is acceptable ONLY
  because the plan is good on defaults and the assumptions are visible. If the
  chips get ignored, revisit before adding more JIT pressure.
- **`TapBudgetTests` goes red while the unit suite stays green.** The UITest
  target is separate and slow. Any step-set change needs the test, its doc
  comment, `tap-budget-baseline.json`, and `OnboardingPlanDetailUITests`
  updated in the same commit.
- **Step rawValues shift.** Removing a step shifts every later
  `OnboardingStep` rawValue down, stranding a `pt_onboarding_step` saved by an
  older build. `OnboardingFlow.resumeStep(rawValue:)` clamps past-the-end
  values (added in slice 1).
- **`ProfileFieldCoverageTests` uses `Mirror`** and requires a `Probe` per
  stored property. Adding `statedFields` needs a Probe with a `skipReason`.
- **Coach consent stays an explicit blocking ask.** Moving it to first-coach-tap
  is defensible but is an App Store review question, not a refactor. Out of
  scope here.
