---
name: phase-training-dayplan-focus-not-persisted
description: phase-training2 does NOT store a structured WorkoutFocus on a planned day — DayPlan.generatedWorkout carries a display title ("Push day"), and the WorkoutFocus is derived at generation time then discarded. So any feature that needs the focus of an ALREADY-GENERATED plan day (D3 consolidation apply path, focus-aware reshuffle, week-by-split analytics, "merge Tuesday into Wednesday", "what split is this day") cannot read it directly. Trigger when wiring such a feature, or when a function needs [WorkoutFocus] for the current week but only has DayPlans/GeneratedWorkouts.
when-to-use: Building anything in phase-training2 that must know the WorkoutFocus of an existing planned/generated day rather than generating a fresh one.
---

# DayPlan stores a title, not a focus

## The constraint (discovered wiring D3 consolidation)
`WorkoutFocus` (push/pull/legs/upper/lower/fullBodyA/B) is computed inside
`WorkoutGenerator.generateLift` from `(liftIndex, totalLifts)` + the era
`splitPreference`, used to pick the slot recipe, then **discarded**. The
persisted plan keeps only:
- `DayPlan.kind` (.lift/.sport/.rest/...) — no focus
- `DayPlan.generatedWorkout?.title` — a DISPLAY string ("Push day"), not a
  stable enum; merged days now read "Leg day + Push day"

`GeneratedWorkout` has `title, summary, exercises, estimatedMinutes,
provenance, refinedByLLMAt` — **no `focus` field**.

So e.g. `WeekConsolidator.consolidate(_ focuses: [WorkoutFocus], to:)` can't
be fed from a live week without first recovering each lift day's focus.

## Two ways to recover it (pick deliberately)
1. **Derive** — recompute focus from the lift day's index position, mirroring
   `generateLift`'s logic. Fragile: it must replicate the era
   `splitPreference` override (age-derived cohort hijacks liftIndex→focus for
   totalLifts ≥ 3 — see `eval-rig-nonanchor-export-force-focus`), so a derived
   focus can disagree with what the day was actually generated as.
2. **Store** `var focus: WorkoutFocus? = nil` on `GeneratedWorkout` (or
   `DayPlan`). Cleaner + reusable. Low migration risk: `GeneratedWorkout`
   uses synthesized Codable, and a `T? = nil` property decodes missing keys as
   nil for old saved plans. `WorkoutFocus` is already `Codable` (String enum).
   Cost: set it on the planner write path wherever workouts are generated.

Default recommendation: **store the field** — derivation drift (path 1)
silently mislabels days, the exact bug class that bit the eval-rig export
harness. Confirm with the user before the migration since it touches
persisted plan data.

## Where this came up
D3's decision + generation layer (`WeekConsolidator`,
`generateConsolidated`) is complete, but the PlanStore apply path stalled on
this: consolidating a *live* week needs the current lift days' focuses.
