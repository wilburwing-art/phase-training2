---
name: phase-training-generator-session-structure-wiring
description: Add session-structure features (supersets, finishers, within-day rep-band curve, any per-exercise structural tag) to the phase-training WorkoutGenerator. The load-bearing fact is that GeneratedExercise is the ONLY unwired chokepoint — the superset/structure plumbing already exists on every downstream type. Trigger when asked to make generated workouts "better"/"real programs", add supersets/pairing/finishers to generated lift days, or implement PRD-adaptive-week D4 in phase-training / phase-training2.
when-to-use: Adding any structural field or pairing/ordering logic to WorkoutGenerator's output in a phase-training-family iOS repo. Skip for changes to exercise SELECTION (slots/pickForSlot) or PRESCRIPTION (focusBias/sets/reps/rest) — see the eval-rig risk note.
---

# Wiring session-structure into phase-training's WorkoutGenerator

The generator emits a **flat** exercise list, but the superset/structure
plumbing already exists end-to-end downstream. `GeneratedExercise`
(`PhaseTraining/Data/WeekPlan.swift`) is the only place that wasn't
populating it. So a "missing" structure feature is usually just wiring.

## The pipeline (already supports supersetGroup)
`WorkoutGenerator.generate` → `[GeneratedExercise]` → `GeneratedWorkout`
→ `.toWorkoutTemplate` → `ExerciseTemplate` → SessionStore → `LoggedExercise`
→ `SupersetGrouping.swift` (visual/nav). `ExerciseTemplate`, `Session`,
`CustomRoutine`, `BundledRoutineRow` ALL already carry `supersetGroup: Int?`.

## To add a structural field (pattern that shipped for supersets)
1. `GeneratedExercise`: add the `var` + `CodingKeys` case + **explicit
   `init` param (default nil)** + a line in the hand-written
   `init(from decoder:)` (`decodeIfPresent ?? nil` so old data decodes).
   It has NO synthesized memberwise init — edit the explicit one.
2. `GeneratedWorkout.toWorkoutTemplate`: pass the field into the
   `ExerciseTemplate(...)` call (the init already takes `supersetGroup:`).
3. `WorkoutGenerator.generate`: populate it after `picks` is fully
   assembled (after the hypertrophy accessory appends, before `estMin`).

## The superset rule that shipped (`assignAntagonistSupersets`)
Antagonist map: h-push↔h-pull, v-push↔v-pull, elbow-ext↔flex,
scapular-prot↔retr. Skip index 0 (heavy primary stays solo). Greedy: each
unpaired pick finds the next unpaired antagonist, shares an incrementing
group int. No-op on single-emphasis days (push/pull/legs have no
antagonist present) — that IS correct; matches G6 "≥1 superset where
appropriate". Hypertrophy accessory appends have `pattern: nil` → never pair.

## Eval-rig risk (decides what to bundle)
ADDITIVE changes (supersetGroup, ordering tags) = **zero** eval-rig risk —
sets/reps/rest unchanged, exercise count/order unchanged. Changes to
`focusBias` / prescription / rest tables DO risk eval-rig rubric
regressions — do those in a separate pass with eval-rig comparison.

## Verify
`xcodebuild test -project <main-repo>/PhaseTraining.xcodeproj -scheme
PhaseTraining -only-testing:PhaseTrainingTests/WorkoutGeneratorTests`.
Use direct xcodebuild, not `test_sim` — session defaults often point at a
worktree copy (see `xcodebuildmcp-session-defaults-cross-worktree`). No
new files added → no pbxproj edits needed.
