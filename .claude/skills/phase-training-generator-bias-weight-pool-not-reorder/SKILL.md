---
name: phase-training-generator-bias-weight-pool-not-reorder
description: Adding an exercise-selection bias to phase-training2. CURRENT (2026-09-25): the live season engine sorts candidates with a comparator in SportSeasonGenerator.generateSession, so a bias is a comparator key (see the status note; exerciseAffinities is wired this way via AthleteState). HISTORY: the deleted legacy slot picker used a uniform deterministicPick, where only pool weighting worked. Still true for both: a signal that affects generation but must not auto-rebuild the week stays OUT of planInputsHash. Trigger when adding a preference/affinity/ranking bias to exercise selection, wiring a TrainingMemory signal into the generator, or when a preferred exercise does not show up more often. Skip for prescription (sets/reps) changes, see phase-training-prescription-precedence-and-dual-path.
when-to-use: Adding any new candidate-selection bias to WorkoutGenerator.pickForSlot, or deciding whether a generation-affecting TrainingMemory field belongs in planInputsHash.
---

> **Status 2026-09-25: the mechanics below describe the DELETED legacy picker.**
> `pickForSlot`, `pickAccessoryByName` and uniform `deterministicPick` went with
> the legacy generator. The live season engine
> (`SportSeasonGenerator.generateSession`) SORTS candidates with a comparator and
> takes `prefix(count)`, so reordering IS the mechanic there. Affinity is
> consumed as: primary-demand match, then `rotationTier` (0 fresh, 1 recent,
> 2 affinity <= `AthleteState.affinitySinkThreshold`), then low fatigue, then
> affinity descending, then djb2. It reaches the engine via
> `AthleteState.exerciseAffinities` straight from `TrainingMemory`, not via
> `GeneratorContext`, so `includeParkedSignals` is irrelevant. Mechanic 2 (keep
> it out of `planInputsHash`) still holds. The old consume tests passed by
> XCTSkip on an empty "Rest" day; the replacements in `ExerciseSwapMemoryTests`
> XCTUnwrap their fixture instead.


# Biasing the phase-training2 slot picker

Built 2026-06-22 implementing swap-memory (swap A→B boosts B in future plans),
which woke the dormant write-only `TrainingMemory.exerciseAffinities` stub.

## Mechanic 1 — weight the pool, don't reorder
`deterministicPick(from:slotIdx:hashSeed:)` (WorkoutGenerator.swift) is
`arr[fold(hashSeed)+slotIdx % count]` — a UNIFORM draw. So:
- `applyStaplePreference` / `applyVariety` / `applySoreFilter` bias by FILTERING
  (shrinking the pool). That works.
- `applyEraAesthetic` returns `preferred + rest` (a reorder, same count) — under
  uniform indexing this is a near no-op. Do NOT copy it for a real bias.
- To make exercise X picked MORE often, duplicate it in the array:
  `Array(repeating: ex, count: min(max(1, 1+score), 4))`. 4× cap keeps a favorite
  frequent, not permanent. Strong-negative (≤ -2) → `continue` (drop), with a
  `weighted.isEmpty ? candidates` fallback so a sole candidate survives.
- Place the weighting OUTERMOST, right before each `deterministicPick`, AFTER
  `applyVariety` (so a just-picked exercise still rotates out).

## Mechanic 2 — generation-affecting ≠ in planInputsHash
`memory.planInputsHash` is BOTH the auto-regen trigger (RootTabView: "a change
that drifts planInputsHash silently rebuilds the week") AND the `deterministicPick`
seed (Planner.swift). A swap-derived preference must bias the NEXT generation
without rebuilding the current week, so `exerciseAffinities` is kept OUT of the
hash. Document it in its ProfileFieldCoverageTests probe (`mutateForHash: nil` +
written skipReason) — the build-78 gate forces a probe for every new field.

## Dual-path + single source
The bias must reach BOTH `pickForSlot` AND the accessory `pickAccessoryByName`
(WorkoutGenerator+Accessories) — the dual-path rule. Thread it via
`GeneratorContext.exerciseAffinities` (populated in PlanStore.buildGeneratorContext,
like recentSoreAreas) and have BOTH paths read `context.exerciseAffinities`. Bug
seen here: accessory read `memory.exerciseAffinities` while the test set it on
`context` — identical in production, but a divergent source. Make both read context.

## Test it metamorphically
Vary `hashSeed` across ~30 seeds, tally pick frequency; assert boosting a
partially-picked exercise (1 ≤ freq < seeds, so its slot has alternatives) raises
its frequency, and ≤ -2 drops it. See ExerciseSwapMemoryTests.
