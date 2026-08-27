---
name: phase-training-season-aware-generator-reuse-map
description: >
  Building or continuing the phase-training2 "season-aware generator" — the
  rearchitecture that REPLACES the goal/PrimaryFocus axis with a sport × season-phase
  primitive (demand weights → curated movement pool → phase schemes). Captures what
  ALREADY EXISTS in the repo (so you reuse, not rebuild), the exact swap seam, and the
  two traps that bite the replace. Trigger when implementing the SportSeasonGenerator,
  the sport_movements seed, the SeasonFidelityTest, the M2 focus/era rip-out, or
  adding a sport (skiing/climbing) to the season model. Skip for the strip-down DECISION
  (phase-training-generator-strip-down-scope) or adding a normal exercise
  (phase-training-coachdb-add-exercise-source-pipeline).
when-to-use: implementing/continuing the season-aware (sport × season-phase) generator rebuild in phase-training2
---

## ~Half the spec already exists — verified 2026-06-26 (grep before you build)
- **Sport taxonomy**: `Sport` slug-struct (TrainingMemory.swift). `sport_categories` already has
  `alpine-skiing`, `ski-mountaineering`, `snow-sports`, `bouldering`, `sport-climbing`, `trad-climbing`…
- **`SeasonPhase`** (5 Codable cases: off/pre/in/eventPrep/maintenance) — KEEP it. Map a 4-phase spec
  on: off/pre/in + maintenance(=transitionRecovery); `eventPrep` = conditional peak gated on
  `targetObjectiveDate` (needs its OWN demand column = "preSeason tapered" + a `.taper` ProgressionMode).
- **Phase→week shape**: `WeeklyShape.resolve(sport,season,focus)` already has `alpine-skiing×{pre,in}`
  + climbing entries. Reuse; drop the `focus` arg at replace.
- **`exercise_sport_relevance`** (1,374 rows): relevance_score + in/off_season_volume_modifier already there.
- **`MesocycleProgression`**: per-phase deload/taper/peak math already there.
- **Injury gate already built**: `CoachDatabase.contraindicatedExerciseIds(forInjurySlugs:)` +
  `exercise_injury_relevance` table tags `prehab`/`rehab` roles → the spec's prehab demand has data.
- **Eval host**: clone `GeneratorInvariantTest` mem/week fixtures (:36-65) + `GeneratorSweepReportTest`
  /tmp report-bridge + empty-catalog guard for a new `SeasonFidelityTest`.

## Genuinely NEW (what you actually build)
`Demand`/`SportVariant`/`ProgressionMode` enums; per-`(sport,variant,phase)` demand-weight `PhaseRule`
(keep in Swift static — small + tunable, no DB rebuild); a curated `sport_movements` DB seed
(movement→demands[]→allowed_phases→default_scheme_by_phase, `exercise_id` linking the 572-catalog
where present, null = gap); `SortSeasonGenerator` emitting the EXISTING `GeneratedWorkout`/
`GeneratedExercise` types; `fatigueCost` (1–5) lives in the seed+generator, NOT on the persisted type.

## The swap seam (the replace)
Two injection points: shape resolution `Planner.swift:203-207` and the focus gate
`WorkoutGenerator.swift:70-77`. `GeneratedExercise` (WeekPlan.swift:141-226) already carries
sets/reps/rpe/tempo/restSeconds/warmUps/supersetGroup → SetScheme maps on almost fully.
Selection pool: `CoachDatabase.exercises(matchingPattern:…)` (CoachDatabase.swift:669-785).
DB seed pipeline is EXPLICIT not auto: add to `_schema.sql` + the TABLES list in
`scripts/db/build_db.py` (32-57) + `db/source/*.json` + JSON_ARRAY_COLUMNS, then `python3 build_db.py`.

## Two traps that bite the replace
1. **`WorkoutFocus` ≠ `PrimaryFocus`.** `WorkoutFocus` (push/pull/legs/upper/lower/fullBody = DAY TYPE,
   used by `GeneratedWorkout.focus` + WeeklyShape + EraStyle.splitPreference) STAYS. Only `PrimaryFocus`
   (the GOAL) goes. Deleting WorkoutFocus cascades compile failures.
2. **`focuses:[PrimaryFocus]` is Codable-persisted** on TrainingMemory. Don't hard-delete — keep a
   tolerant-decode shim or existing user saves fail to load. This is the one spot "remove obsolete
   immediately" yields to persistence safety. Also re-key the hypertrophy accessory gate (WG:269/283)
   off the phase/demand profile instead of `primaryFocus`.

## Two seed traps (verified 2026-06-26 building the skiing M1)
1. **Equipment has TWO vocabularies — don't seed the wrong one.** The Swift `Equipment` enum rawValues
   (`none`, `pull_up_bar`, `cable_machine`, `resistance_band`) ≠ coach.db `equipment.slug`
   (`bodyweight`, `pull-up-bar`, `cable-machine`, `band-*`). The `sport_movements.equipment[]` seed +
   any pool filter must use the **DB slugs**; bridge live user data with
   `Equipment.allowedCoachDbSlugs(Set<Equipment>)` (what `DemographicProfile.allowedEquipmentSlugs` uses).
2. **Slug-match the SPEC movement map against `exercises.json` BEFORE budgeting backfill — the catalog
   is richer than specs assume.** Building skiing: of SPEC §3.3's ~36 movements only 8 were nominal
   gaps, and Nordic hamstring curl, reverse Nordic, eccentric step-down, Copenhagen, depth jump, lateral
   bound, rucking, skater step-down ALL already existed → real backfill ~2-4 rows, not a dozen. Run a
   token-cooccurrence search per movement first. `exercises.json` has 572 rows but **max id 1185**
   (non-contiguous) → allocate backfill ids above the max, never `count+1`.

Pairs with [[phase-training-generator-strip-down-scope]] (the decision that led here),
[[phase-training-coachdb-add-exercise-source-pipeline]] (backfilling null `exercise_id` movements).
