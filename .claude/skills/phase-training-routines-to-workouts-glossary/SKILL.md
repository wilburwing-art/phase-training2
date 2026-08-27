---
name: phase-training-routines-to-workouts-glossary
description: In phase-training-family iOS apps (phase-training, phase-training2, workout-plan) the user-facing glossary was renamed "Routines" -> "Workouts", but the rename is PARTIAL and internal code intentionally still says "routine". When the user spots a stray "routine(s)" in the UI (e.g. Library header "282 ex · 2 routines", a subtitle, an action-sheet line), fix ONLY the user-facing string literals and leave internal symbols alone — the enum case `.routines`, `CustomRoutineStore`, `pt_custom_routines` UserDefaults key, and `user_routines`/`routine_id` DB columns keep the old name on purpose to avoid a state migration. Trigger when the user says "I thought we got rid of routines as a word", "this still says routines", "the library tab says routines", or any glossary-leftover report. Skip for renaming the internal data model (that needs a UserDefaults/DB migration, not a string swap).
when-to-use: User reports a leftover "routine"/"routines" word in a phase-training app's UI and expects the glossary term "Workouts". Also when sweeping for remaining glossary leftovers.
---

# Phase-training: Routines -> Workouts glossary is partial

The UI term is **"Workouts"**; the code model is still **"routine"** on purpose. Don't conflate them.

## The intentional split (DO NOT rename these)
- `LibrarySegment.routines` enum case — comment at its declaration says the raw value is kept "to avoid a UserDefaults / state migration"; its `label` maps `.routines -> "Workouts"`.
- `CustomRoutineStore`, `CustomRoutine`, `CustomRoutineExercise` types.
- `pt_custom_routines` UserDefaults key.
- DB: `user_routines`, `user_routine_exercises`, `routine_id`, `CoachDatabase.listRoutines()`, `exercises(forRoutineId:)`.

Renaming any of these is a migration, not a glossary fix — out of scope unless the user explicitly asks.

## What you DO change: user-facing string literals only
Found in this session (LibraryScreen.swift):
- Eyebrow count `libraryEyebrowTrailing`: `"\(exCount) EX · \(routineCount) ROUTINES"` -> `WORKOUTS`. This is the "282 ex · 2 routines" the user sees.
- `TabHeader` subtitle: "Browse every exercise and routine." -> "…and workout."

Still-open user-facing leftovers on OTHER screens (surface, don't silently sweep all):
- `ExerciseActionSheet.swift` — "…The bundled routine isn't affected."
- `DemographicProfile.swift` — "Equipment-aware routine pool: only … routines."
- `Planner.swift` — generatedReason "You picked this routine for this day"

## Finding leftovers without false positives
```
grep -rn '"[^"]*[Rr]outine' PhaseTraining --include="*.swift" \
  | grep -iv 'CustomRoutine\|pt_custom_routines\|routineId\|loadTemplate\|listRoutines\|forRoutineId\|user_routine'
```
Then eyeball: `#Preview` blocks (e.g. `ExerciseTile.swift`, `TabHeader.swift` previews) are not shipped UI — skip them.

## Verify
Pure string-literal swaps inside existing valid expressions can't introduce compile errors; no need for a full sim build for these.
