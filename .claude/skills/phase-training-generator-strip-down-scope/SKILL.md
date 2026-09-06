---
name: phase-training-generator-strip-down-scope
description: >
  When the phase-training2 owner feels the WorkoutGenerator is "too complex /
  too many variables / too many programs" and wants to strip it down to a
  predictable generator they personally use (then expand later) — run the full
  harness set for a current-state picture FIRST, because the recurring verdict is
  "the generator CORE is correct; what's bloated is the PERSONALIZATION/PROGRAM
  SURFACE, not the logic." Trigger on "the generator is choking on all the
  variables", "I made the scope too large", "strip out programs/variables",
  "what do I keep vs cut", "give me a picture of how the generator works before I
  decide what to cut". Skip for adding a feature (feature-gap-checklist), running
  one harness (sweep-report), or classifying one knob (knob-blast-radius-tiers).
when-to-use: scoping a strip-down / simplification of the generator; producing a full current-state picture before the owner decides what to cut
---

## The one-command full picture (do this first)
Run ALL generator harnesses in ONE `xcodebuild test` (build once, all suites):
`-only-testing:` GeneratorSweepReportTest, GeneratorInvariantTest,
GeneratorStrategyTests, GeneratorContextTests, ReadinessGeneratorShipGateTests,
WorkoutGeneratorTests. Run against the CURRENT (possibly dirty) tree — that's the
"where it's at now" the owner asked for. Background it; the sweep writes
`/tmp/generator-sweep/report.{html,md}` (md is the portable artifact to hand back).
Verified 2026-06-22: 99 tests, 0 failures, ~90s incl. build.

## The verdict pattern that keeps recurring
- **Core is fine.** All ~23 swept knobs read `live`; metamorphic orderings
  (beginner≤inter≤adv, deload≤normal≤push, readiness monotone, age55 drops,
  shorter-budget-never-adds, no-dup, no-empty, dislikes/injury safety) all PASS.
  `live` is a FLOOR not a grade, but green metamorphic = direction is right.
- **The bloat is the PROGRAM SURFACE, not the code.** The combinatorial blast is
  6 primaryFocus × 5 SeasonPhase × 3 ExperienceLevel × 3 StartingState × 216
  sport_categories (+107 bundled routines) = thousands of configs the owner
  can't hold in their head. That's the "scope too large" feeling. (EraCohort
  was a 6-wide factor here until it was deleted on 2026-09-06.)
- **Half the complexity is dormant.** Phase-1 demographic generator always runs;
  Phase-2/3 adaptive (readiness/overload/stagnation/sore-filter) NO-OPs without
  logged data or HealthKit ("sophisticated, runs degraded by default"). It adds
  zero noise to a fresh user, so it's not what's making it feel heavy.

## The recommendation to give (not the owner's first instinct)
1. Strip the SURFACE, not the core — don't gut Phase 1, the harnesses prove it.
2. **HIDE in UI before DELETE in code.** Lock the app to the owner's own config
   (e.g. intermediate/hypertrophy + their equipment/days) as the default path;
   leave season/sport machinery dormant. Predictable app now, tested code kept
   for the expand phase. Deleting structural knobs (season/startingState)
   means updating the metamorphic tests that guard them — real work for code likely
   re-added.
3. KEEP the adaptive layer — it's what makes the app theirs over time, inert anyway.
4. Strip-down is CHEAP to validate here: cut/hide a knob → re-run sweep+invariant
   (~8s on top of build) → see exactly what moved and whether invariants hold.

## Where each "program" axis is actually wired (verified 2026-06-22, grep the consumers)
Half the perceived complexity is product surface that NEVER reaches `generateLift`:
- **SeasonPhase (5)** — NOT a generator knob. Only in Planner + MesocycleProgression
  (week-shape / mesocycle level) + UI. That's why the sweep doesn't sweep it. → hide
  the season concept for a predictable personal plan; Planner code stays intact.
- **StartingState (3)** — NOT in the generator path at all. Onboarding UI + CoachContext
  (LLM) + WeekPlan only. `generateLift` never reads it. → hide unless using calibration-week.
- **EraCohort (6)** — DELETED 2026-09-06. This entry read "DOES reach the generator
  (Phase-1 `splitPreference` at totalLifts≥3, WG:72)", which stopped being true when
  the legacy selection engine was removed in the season-engine pivot: by deletion time
  `splitPreference`/`repRangeBias`/`aestheticTags` had zero production readers. A
  cautionary case for this whole skill — re-verify "DOES reach the generator" claims
  with a fresh grep before repeating them. See [[phase-training-personalization-two-axes]].
- **primaryFocus (6)** — only hypertrophy + general_strength are structurally distinct;
  sport_performance = same lifts as general_strength w/ power prescription;
  endurance/weight_loss/longevity = volume/time TRIMS (~5 ex/day, shorter sessions).
- **experience (3)** — real structural clamp (set caps), metamorphic-gated. Lock to yours.
Lesson: before recommending keep/hide/delete on an axis, `grep -rln <Axis>` across
WorkoutGenerator*/Planner/GeneratorContext — an axis that's UI/Planner/LLM-only is a pure
HIDE (never touches workout output), distinct from one that genuinely reshapes the workout.

## Fold candidates the sweep surfaces
general_strength vs sport_performance = SAME movement selection, differ only on
prescription (5×5 RPE8 vs 3-5 + explosive "X" tempo). weight_loss/longevity mostly
trim volume/time — prescription presets, not distinct programs. Question whether
each earns a separate "program" slot in a stripped v1. Pairs with
[[phase-training-knob-blast-radius-tiers]] (per-knob tier),
[[phase-training-generator-eval-method-portfolio]] (trust the sweep's limits),
[[phase-training-feature-gap-checklist]] (the ADD direction — inverse of this).
