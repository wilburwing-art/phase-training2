---
name: phase-training-legacy-generator-selection-vs-prescription-split
description: When removing phase-training2's "legacy demographic WorkoutGenerator" after the ski/climb season-engine pivot, only the SELECTION engine is dead — the PRESCRIPTION machinery is still LIVE and must stay. generate()/pickForSlot/ExerciseQueryCache/WorkoutFocus.slots/recipes/stagnation-swap/antagonist-supersets are unreachable and deletable; but makePickedRow + prescription/rpeTempoHints/progressiveOverloadHint (+Prescription.swift) + represcribe (+Represcribe.swift) are consumed by the LIVE custom-routine override path (PlanStore+Generation applyCustomRoutineOverrides, reachable for ski/climb), and represcribe consumes GeneratorContext.priorBest. WorkoutFocus enum + .lift() also stay. Verified 2026-06-27. Trigger when planning/executing removal of the legacy WorkoutGenerator, or when an audit/explore agent says "delete WorkoutGenerator+Prescription / +Represcribe" (it's wrong). Skip for the season prescription (DemandScheme) or the goal-axis deletion.
when-to-use: Scoping or executing the deletion of the legacy demographic generator in phase-training2 — deciding what's dead (selection) vs live (prescription/represcribe).
---

# The legacy generator splits: SELECTION (dead) vs PRESCRIPTION (live)

`WorkoutGenerator` is two subsystems fused in one file. After the ski/climb gate only the SELECTION half
is unreachable.

**DEAD — delete (demographic selection):** `generate(...)` core loop; `pickForSlot`;
`ExerciseQueryCache`; `degradationFallbackPatterns`; `applyStagnationSwap`; `assignAntagonistSupersets`;
the WorkoutGenerator `deterministicPick<T>(from:slotIdx:hashSeed:)` (NOT Planner's same-named func);
`provenanceLine`; `WorkoutFocus.slots` + `PatternSlot`; `WorkoutGenerator+Accessories.swift`
(`highMinuteAccessoryPatterns`, used only by `generate()`'s degradation). Plus the eval-rig:
`EvalRigExporter.swift`, `scripts/generator-sweep.sh`, the ProfileScreen "Export eval-rig JSON" button.

**LIVE — keep:** `makePickedRow`; `WorkoutGenerator+Prescription.swift` (prescription / rpeTempoHints /
progressiveOverloadHint / isMuscleSoreForExercise / capRPE / lerp / nilIfEmpty); **`+Represcribe.swift`**.
Reason: `WorkoutGenerator.represcribe` re-prescribes **custom-routine day overrides** and is reachable
for ski/climb via `PlanStore+Generation.swift` `applyCustomRoutineOverrides` → it calls `makePickedRow`
and consumes `context.priorBest`. `WorkoutFocus` enum + `.lift()` (defined in WorkoutGenerator.swift)
are used by the season engine / Planner / PlanStore / LLM — keep.

After deletion, `generateLift`/`generateConsolidated` collapse to thin season dispatchers; keep their
full signatures (params parked) and return a safe empty `GeneratedWorkout` for the can't-happen
no-supported-sport branch instead of crashing.

## The trap (why this needs a skill)
Multi-agent explore/audit sweeps (even opus) classified `+Prescription.swift` and `+Represcribe.swift`
as "LEGACY-ONLY, delete" — they traced consumers from `generate()` down but missed the UPWARD live
caller (`PlanStore` custom-routine path). **Before deleting any helper of an audit-flagged "legacy"
subsystem, grep its callers in BOTH directions** and confirm no live feature (custom routines here)
consumes it. Tests mirror the split: delete selection tests, KEEP prescription/makePickedRow/represcribe
tests — so most legacy test files get TRIMMED, not whole-deleted.

Pairs with [[phase-training-season-engine-sidelines-adaptive-layer]],
[[phase-training-prescription-precedence-and-dual-path]], [[verify-audit-claim-before-implementing]].
