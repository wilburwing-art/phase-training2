---
name: phase-training-season-engine-wire-into-app
description: >
  Wiring phase-training2's SportSeasonGenerator into the LIVE app (the M2
  "replace"): making it the generator for ski/climb, gating onboarding, and
  migrating existing users — plus the traps that bite. Trigger when injecting the
  season engine into Planner/PlanStore/generateLift, narrowing the app to
  supported sports, finishing the M2c/M2d goal-axis deletion, or debugging "some
  screens still produce legacy (non-season) workouts." Fourth sibling to
  season-aware-generator-reuse-map (what exists), season-generator-engine-pitfalls
  (the §5 math), and season-engine-add-a-sport (extend to sport N+1).
when-to-use: wiring SportSeasonGenerator into the live app / the M2 replace
---

Done M2a–c1 (2026-06-26), 4 green commits on `feat/season-aware-generator`.

## The injection seam is NOT just the Planner (reuse-map said Planner:203 — incomplete)
`WorkoutGenerator.generateLift` has **7+ direct callers**: Planner.makeSlot +
makeOverrideSlot, PlanStore single-day regen (~:588) + generateConsolidated (~:683),
PlanStore+Generation (~:233), PlanStore+LLMRefinement (~:233), ProfileScreen (~:538),
CoachRequestScreen (~:472). Injecting ONLY at the Planner shape-fill leaves the rest on
the legacy path (ski/climb users get legacy workouts from regen/refine/previews).
**Fix: put the dispatch INSIDE `generateLift`** (single point, +`adjacentSportDay: Bool`
param): `if SportSeasonGenerator.supports(memory.primarySport?.slug) { return
generateSession(AthleteState.from(memory, variant: defaultVariant(slug),
weekNumber: memory.weeksInCurrentPhase ?? 1, recentMovementIDs: recentlyPicked),
sessionIndex: liftIndex, adjacentSportDay: …) }`. Add `supports`/`defaultVariant`
helpers (ski→inbounds, climb→sportRoute). ALSO route `generateConsolidated` — its
merged path calls the private `generate()` directly, bypassing generateLift.

## Traps
- **`GeneratedWorkout.focus` must be a real value, not nil.** Set `.fullBodyA` in
  assemble — D3 consolidation, split analytics, and LLM-refinement `existingFocus`
  anchor on it; nil silently degrades them.
- **Onboarding migration infinite-loop.** Gating: filter the sports chip cloud to
  `SportSeasonGenerator.supports($0.slug)`; migrate by nil-ing `memory.onboardedAt`
  (the fullScreenCover gate, PhaseTrainingApp ~:295) for unsupported users. BUT you
  MUST also strip the unsupported sport from `sports`/`primarySport` in the same
  update — else the filtered picker can't deselect it, primarySport stays
  unsupported, and the gate re-triggers every launch forever. Test it.
- **Removing an `OnboardingStep` (Int enum) case** auto-renumbers the contiguous
  rawValues (safe), but the step's screen file then references the deleted `.case`
  → delete that screen file too (XcodeGen: `rm` + `xcodegen generate`).

## M2c/M2d deletion coupling (the goal-axis rip-out)
Removing the `focuses` CodingKey = old saves ignore that JSON key (no shim needed).
BUT the legacy generator (`focusBias`, `rpeTempoHints` switch, hypertrophy gate) depends
on `PrimaryFocus`, so deleting the enum is COUPLED with deleting the legacy
`WorkoutGenerator.generate` core + the old eval harnesses (GeneratorSweepReportTest /
GeneratorInvariantTest test the focus generator) + a ~13-file test sweep. After M2c1 the
legacy path is dormant-but-reachable-for-unsupported (which don't exist post-gate), so the
app is shippable BEFORE the deletion — stage the mass-delete separately + build-gate it.
