---
name: phase-training-legacy-generator-selection-vs-prescription-split
description: What survived the deletion of phase-training2's legacy demographic WorkoutGenerator and why. The selection engine (generate core loop, pickForSlot, ExerciseQueryCache, WorkoutFocus.slots, stagnation swap, antagonist supersets) went in 449bd8d; the legacy row prescriber went in 11d 2.2. What stays in WorkoutGenerator files is the custom-routine refresh (represcribe in +Represcribe.swift, reachable from PlanStore+Generation applyCustomRoutineOverrides), the progressive-overload target hint (+Prescription.swift), isMuscleSoreForExercise and capRPE, and the WorkoutFocus enum with .lift(). Trigger when an audit or explore agent says "delete WorkoutGenerator+Represcribe / +Prescription" or "the legacy generator is dead", or before deleting any helper in WorkoutGenerator*.swift. Skip for the season prescription itself (DemandScheme, SportSeasonGenerator.prescribe) or the goal-axis deletion.
when-to-use: Deciding whether a WorkoutGenerator helper in phase-training2 is dead or still serves the custom-routine refresh path.
---

# The legacy generator after deletion

**Deleted:** the demographic selection loop (449bd8d: `generate(...)` core, `pickForSlot`,
`ExerciseQueryCache`, degradation fallback, stagnation swap, antagonist supersets,
`WorkoutFocus.slots` + `PatternSlot`, `WorkoutGenerator+Accessories.swift`, the eval-rig exporter)
and the legacy row prescriber with its focus bias, RPE/tempo hints and beginner clamps (11d 2.2).

**Live, keep:**
- `WorkoutGenerator+Represcribe.swift`: `represcribe` refreshes a custom-routine override day.
  Caller: `PlanStore+Generation.swift` `applyCustomRoutineOverrides`. Each row goes through
  `SportSeasonGenerator.prescribeRefresh`, the season engine's own `prescribe`, so a refreshed
  custom day and a planned day agree for the same athlete.
- `WorkoutGenerator+Prescription.swift`: `progressiveOverloadHint` and the target-weight math
  (`targetLb`, `repBandMidpoint`, `steppedTargetLb`). Reads `GeneratorContext.priorBest`.
- `WorkoutGenerator.swift`: `isMuscleSoreForExercise`, `capRPE`, the `WorkoutFocus` enum and
  `.lift()` (used by the season engine, Planner, PlanStore and the LLM path), and the thin
  `generateLift` / `generateConsolidated` season dispatchers.

## The trap
Explore and audit sweeps classified `+Represcribe.swift` and `+Prescription.swift` as legacy-only.
They traced consumers down from the deleted `generate()` and missed the upward live caller in
`PlanStore`. Before deleting any helper of a subsystem an audit calls legacy, grep its callers in
both directions and confirm no live feature (custom routines here) consumes it.

Pairs with [[phase-training-season-engine-sidelines-adaptive-layer]],
[[phase-training-prescription-precedence-and-dual-path]], [[verify-audit-claim-before-implementing]].
