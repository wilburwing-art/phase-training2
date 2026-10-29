---
name: phase-training-season-engine-sidelines-adaptive-layer
description: In phase-training2 after the ski/climb onboarding gate, SportSeasonGenerator is the LIVE generator and it consumes NEITHER GeneratorContext (readiness/soreness/progressive-overload/stagnation) NOR GeneratorStrategy (the LLM build_workout tool) — both are built/decoded and threaded through generateLift but silently dropped, because generateSession takes only (AthleteState, sessionIndex, adjacentSportDay). So the entire adaptive + LLM-coaching layer is INERT for every real user; it's consumed only by the now-unreachable legacy WorkoutGenerator. Verified 2026-06-27 (3 explore agents + grep). Trigger when removing/rewiring the WorkoutGenerator, asking "does readiness/soreness/LLM build_workout affect ski/climb workouts" (it doesn't), or scoping what's safe to delete vs what's a feature loss. Skip for signal-level GeneratorContext defects (see phase-training-generator-context-dead-and-broken-signals).
when-to-use: Reasoning about whether the legacy generator / GeneratorContext / GeneratorStrategy can be deleted, or why readiness/LLM-built workouts have no effect for ski/climb users.
---

# The season engine sidelines the whole adaptive + LLM layer

`WorkoutGenerator.generateLift` dispatches: `if SportSeasonGenerator.supports(memory.primarySport?.slug)`
→ season engine, else legacy. After M2b the onboarding gate (`OnboardingSportsScreen` filter +
`MemoryStore.migrateToSupportedSportGate`, run from `PhaseTrainingApp` on launch) forces every user to
ski/climb, so **the legacy branch is unreachable in production** and the season engine is the only live
generator.

`SportSeasonGenerator.generateSession(_ athlete, sessionIndex, adjacentSportDay)` takes **no
`context:` and no `strategy:`**. `generateLift` still has `context: GeneratorContext` /
`strategy: GeneratorStrategy` params and ~12 call sites still thread them (Planner, PlanStore,
PlanStore+LLMRefinement/+Generation, CoachRequestScreen build_workout preview, WeeklyCheckInFlow), but
for ski/climb they're **silently dropped**. Consequence to state plainly when asked: readiness/soreness/
progressive-overload adaptation and the LLM "build me a workout" tool currently do **nothing** for any
real user. (This is broader than the legacy `phase-training-generator-context-dead-and-broken-signals`
"degraded-by-default" note — that was empty context for fresh users; this is the live generator
ignoring the layer structurally.) **One exception:** `WorkoutGenerator.represcribe` (custom-routine
override path, reachable for ski/climb) DOES consume `context.priorBest` for its progressive-overload
note — so context is not 100% inert. **Superseded in part (re-checked 2026-10-28):** readiness now reaches the
engine through `AthleteState.readinessScore` and scales SETS by lerp(0.6, 1.0)
(`SportSeasonGenerator.swift:200`), and swap/recommend affinities reach it
through `AthleteState.exerciseAffinities`. Soreness reaches it too, since
build 150: `Planner.soreness(for:memory:)` (check-in day plus the next day,
mild/high/pain) feeds `AthleteState.soreBuckets`. The slot comparator then
ranks sore prime movers below the rest of their demand, and the ones that
stay are capped at RPE 7, with a third fewer sets when soreness is high.
`generateLift(date:)` is the switch, so a caller that passes no date gets
no soreness. `GeneratedWorkout.soreAreas` stamps what was applied, and
`PlanStore.applySoreness` (on check-in save and on launch) rebuilds only
the days whose stamp is stale. The parked `GeneratorContext.recentSoreAreas`
is still unused. See [[phase-training-legacy-generator-selection-vs-prescription-split]].

## Consumer map (who actually reads context/strategy)
LEGACY-ONLY (consume at generation): `WorkoutGenerator.generate()` core loop +
`WorkoutGenerator+Prescription.swift` + `+Accessories.swift` + `+Represcribe.swift`. Eval-only:
`EvalRigExporter.swift`, `GeneratorSweepReportTest`, `scripts/generator-sweep.sh`, the ProfileScreen
"Export eval-rig JSON" button. PRODUCERS that stay even if generation is gutted: `GeneratorContext`
builders (history/PRs/soreness), the `build_workout` LLM tool (`CoachTools.swift` + `CoachToolDecoder`).

## Traps
1. **Grep `GeneratorContext` over-matches comments.** Hits in `HealthKitImporter`, `Session`,
   `ProgressionSuggestion`, `UserDatabase`, `ImportedSet` are **doc comments only**, not code — don't
   count them as consumers. Verify each hit is a real read.
2. **Deleting GeneratorContext/GeneratorStrategy is NOT "remove the generator" — it's removing two
   features.** They're built from real user data + the LLM coach surface; ripping them out kills
   readiness adaptation + build_workout until rebuilt on the season engine. Scope the removal as
   (a) surgical = legacy generation engine + eval-rig + their tests, park the adaptive/LLM types; vs
   (b) full teardown = also delete the adaptive/LLM layer + its Planner/PlanStore/Coach threading. This
   is a product call — confirm with the owner, don't infer.
3. `WorkoutFocus` (day type), `GeneratedWorkout/Exercise`, `DemographicProfile`, `WeeklyShape`,
   `WeekConsolidator` are SHARED with the season engine — keep them.

Pairs with [[phase-training-delete-primaryfocus-goal-axis]] and
[[phase-training-season-prescription-demand-scheme]].

## Recovery gate (build 152, 2026-10-29)

Logged volume now reaches the engine. `MuscleFreshness` is volume-based (sets × role,
sqrt-scaled recovery hours, sessions stack) and `MuscleRecovery.status(on:)` turns it plus the
soreness check-in into `blocked` (<0.5, dropped from the pool) and `eased` (0.5 to 0.8, sore tier,
RPE 7) buckets. `GeneratorContext.muscleExposures` carries the loads; `PlanStore.applyRecovery`
rebuilds changed days after a save, on open and after a check-in. Traps found building it:
- **Report what the gate cost against an ungated pick, never against the pool.** Counting blocked
  movements in the pool said a ski complement day "skipped quads"; that day never picks legs.
  `generateSession` reruns itself with `blockedBuckets = []` and diffs.
- **A gate on a sport session will drop accessories the previous complement day trained** (a
  climbing push accessory after an upper push day). That is rule one working. Probe sport days
  for SIGNATURE muscles only (`RecoveryWeekProbeTests`), or the probe fails on correct behavior.
- **UI tests asserting a Today caption depend on the weekday's SessionMix role.** A "high"
  quads check-in on a complement upper day skips nothing and shows no caption. Use a mild
  check-in (eased is stamped on any day) for a deterministic assertion.
- Build 153 (`PlanStore+LoggedSession.swift`): `recentPicks` is stamped only from LOGGED
  exercises at the session's time; generation stamps nothing. An off-plan (`switched` /
  `unplanned`) session that covers 50%+ of a later lift day's sets swaps with it via `swap`.
  `RecentPicksStore.prune` uses the wall clock, so a test with 2026-05 fixture dates sees its
  picks pruned on write; date rotation tests from `Date()`. Pass `today:` into anything that
  calls `swap`/`updateOverrides` from a test, or the regen builds the real current week.
