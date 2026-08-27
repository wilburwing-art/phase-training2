---
name: phase-training-generator-invariant-metamorphic-test
description: >
  Write or extend the property-based + metamorphic test harness for
  phase-training-family WorkoutGenerator (the axis-2 "is it right" / axis-3
  "does it hold up" complement to the OFAT sweep). Trigger when the user wants
  to "add invariant tests", "property test the generator", "assert the workout
  always X", "check the generator's direction/monotonicity", "test interactions
  the sweep misses", or after editing prescription/focusBias/the readiness or
  deload multiplier. Distinct from phase-training-generator-sweep-report (the
  sensitivity/wiring sweep) and the eval-rig LLM grader.
when-to-use: building deterministic correctness/interaction tests for generateLift without an LLM grader
---

Lives at `PhaseTrainingTests/GeneratorInvariantTest.swift` (built 2026-06-04, 10
tests green, full suite ~5.4s — the 486-cell grid is the only heavy one at
~4.5s). Auto-discovered via `Project.yml`'s `sources: PhaseTrainingTests` glob —
`xcodegen generate`, no pbxproj edits (see [[phase-training2-gitignored-pbxproj]]).
Run only it: `-only-testing:PhaseTrainingTests/GeneratorInvariantTest`.

## Three layers (all oracle-free, no LLM, no /tmp artifact)
- **Part A — property/invariant over a GRID.** Nested loops build a Cartesian
  product (`experience × focus × equipment × age × minutes` = 486 cells);
  fuzzing the WHOLE vector at once is the only cheap attack on OFAT's interaction
  blind spot. Assert per cell: no empty day, `sets ∈ [1,8]`, no dup exerciseId
  in a day, non-empty trimmed reps, `estMin ≥ 1`, disliked keyword never in any
  name. (No `Math.random` here — enumerate the grid; that IS the determinism.)
  PLUS the **injury-contraindication safety invariant** (needs a coach.db join,
  not output-only — see below).
- **Part B — metamorphic orderings.** Encode the sweep's "expected direction"
  rubric as automated gates: `deload ≤ normal ≤ push`, readiness `0.0≤0.5≤1.0`
  (gated on `hasReadinessData`), `beginner ≤ intermediate ≤ advanced`,
  `age70 ≤ age32`, shorter budget never adds movements/estMin. **Non-strict
  (≤/≥)** so a sparse-effect cell doesn't flake the ordering.
- **Part C — named pairwise interactions (the sweep's open #3).** OFAT moves
  knobs on separate axes and can't see them stack. `readiness×deload` (×0.6×0.7):
  floor still ≥1 AND stacking a 2nd suppressor never adds volume vs either alone.
  `soreness×focus` (sore areas == the focus's prime movers): day still generates
  (graceful degradation), doesn't collapse to empty.

## Injury contraindication — the differential-probe pattern (don't ship vacuous)
The contra set lives in coach.db, so cross-check the generated week against the
SAME oracle the generator filters on: `CoachDatabase.shared.contraindicatedExerciseIds(forInjurySlugs:)`
(injuries flow into `DemographicProfile.from` → `excludedExerciseIds`, WG:146).
A pass is meaningless if those exercises were never in the pool, so prove it
non-vacuous by DIFFERENTIAL: with the injury → zero contra'd ids appear; WITHOUT
it → at least one DOES (filter is load-bearing, not an empty pool). Use a DENSE
probe (`lumbar-disc-herniation`, ~10 contra) for the differential; sparse ones
(`rotator-cuff-injury`) get the safety assert only. `XCTSkipUnless(CoachDatabase.shared.isOpen)`.

## Gotchas that bit (ground assertions in the real code, not intuition)
- `intensityBias`'s type is **nested**: `GeneratorStrategy.IntensityBias`
  (cases `deload, normal, push`), NOT a top-level `IntensityBias`.
- The **`[1,8]` clamp (`WorkoutGenerator.swift` ~L1039) is the only hard set
  bound** — advanced *isolation* is UNCAPPED in `prescription` (the experience
  switch only clamps beginner/intermediate and bumps advanced *compounds*). So
  assert `sets ∈ [1,8]`, not the per-experience cap, as the universal invariant.
- The experience cap is **pre-multiplier**: `intensityBias=.push` (×1.15)
  applied after can push an intermediate 4 → 5. So "intermediate ≤ 4" is NOT a
  post-multiplier invariant — hold normal intensity + no readiness when asserting
  the cap, or use the looser `[1,8]`. (This leak is exactly why property > OFAT.)
- Reuse the sweep's **fixed-seed isolation** (one constant seed across every
  compared call) so a delta is the input, not the deterministic pick moving.
- All-green is itself the signal: it confirms the levers move in the RIGHT
  direction across the space, which the sweep (movement-only) can't.

## Not yet covered (next extensions)
- More pairwise corners beyond the two in Part C (e.g. `experience×focus×set-cap`
  — the interaction where `intensityBias=.push` leaks the intermediate ≤4 cap).
- Longitudinal / mesocycle sim + the eval-rig LLM grader (different loops; see
  [[phase-training-generator-eval-method-portfolio]]).

Pairs with [[phase-training-generator-eval-method-portfolio]] (why this method),
[[phase-training-generator-sweep-report]] (the sweep), [[eval-rig-close-the-loop-workflow]] (LLM grader).
