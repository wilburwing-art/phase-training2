---
name: phase-training-authored-routine-serving
description: How coach.db ROUTINES get served on a lift day in phase-training2 (the "authored program spine" path, built 2026-07-17), and the non-obvious contract that decides whether a routine you added actually appears. Trigger when distilling a program into servable routines, adding/expanding authored routines for a sport, wiring a new sport to authored content, or debugging "I added a routine to coach.db but it's not being served / the day still shows generated/empty output." Distinct from phase-training-coachdb-add-exercise-source-pipeline (that's adding EXERCISES + the shared source-JSON/build_db/CHECK/tags gotchas — reuse it for those); this is the routine SELECTION + serving layer on top.
---

# Authored routine serving (phase-training2)

The single content chokepoint is `WorkoutGenerator.generateLift` — BEFORE the
`SportSeasonGenerator.supports` gate it calls `AuthoredRoutineSelector.select`;
a hit returns `AuthoredRoutine.workout(forRoutineId:…)` (verbatim authored
sets/reps + per-user "target: X lb" recs via `progressiveOverloadHint`, which the
season path omits). Miss → falls through to the season engine. Files:
`Data/AuthoredRoutine.swift`, `Data/CoachDatabase.swift`
(`authoredRoutineIds`/`authoredRoutineMeta`).

## Three gates a routine must clear to be SERVED (each is a silent "no-show")
1. **Sport is authored-served** — `shouldServeAuthored` = sport in `pilotSports`
   (= `PhaseRule.climbingSlugs`) OR `!SportSeasonGenerator.supports(sport)`. So:
   climbing (pilot) ✓; MTB/cycling/running/snowboarding (engine can't handle) ✓;
   **ski/ski-mtn/snow-sports (season-engine flagship) NOT served** on purpose.
   Adding routines for a supported-but-non-pilot sport does nothing.
2. **Full-session filter** (`CoachDatabase.authoredRoutineIds` SQL):
   `goal NOT IN (prehab,mobility,warm_up,pt_rehab,recovery)` AND
   `duration_minutes >= 25`. A 10-min prehab routine will NEVER serve as a day.
3. **Phase match** — `phaseLabels(for:)` maps SeasonPhase→coach.db `routines.phase`:
   offSeason→[off_season,base], preSeason→[build], inSeason→[maintenance],
   eventPrep→[build,maintenance], maintenance→[maintenance,base]. Routine must be
   tagged to the sport via `routine_sports`→`sport_categories.id` AND carry a
   matching `phase`. Multiple matches rotate by `sessionIndex % count`, id ASC.

Kill-switch: UserDefaults `authored_routines_enabled` (default true).

## Fallback tiers + the generic base (Easy Strength, added 2026-07-18)
`select` tries, in order: (1) sport + mapped phase; (2) if empty AND unsupported,
sport + ANY phase; (3) if still empty AND the slug is in `outdoorAuthoredSlugs`,
the **generic base** pool `general-fitness` (any phase). Tier 3 is gated on the
allowlist so a nonsense slug still returns nil (regression: it briefly served
Easy Strength for "nonexistent-sport-xyz" until gated). Easy Strength (#298) is
the generic base — tagged to `general-fitness` AND every outdoor sport (phase
`base`), so it also rotates into their off-season directly (tier 1).
**TRAP:** `general-fitness` is a SYNTHETIC slug with NO `sport_categories` row
(TrainingMemory says so). Tagging a routine to it silently serves nothing until
you ADD the row (`distill_easy_strength.py` adds id 755). Same class as the
three-vocab trap below.

## Distilling a program → servable routines
`scripts/db/distill_snowboard.py` is the template (shralpinism → 3 splitboard
routines #295-297 + 5 signature movements). Appends to `routines.json`,
`routine_exercises.json` (autoincrement id), `routine_sports.json`
(`sport_id`), and new movements to `exercises.json`, then `build_db.py`. For the
source-not-artifact / keep-all-keys / `tags` = JSON *string* / `source_type` &
other CHECK constraints, follow [[phase-training-coachdb-add-exercise-source-pipeline]].
Grounding: only distil STARTABLE strength/dryland sessions into routines;
endurance/ride days are read-and-log sport sessions (day.notes), not routines.

## REACHABILITY — the gate is OPEN (built 2026-07-17), but THREE slug vocabs must align
A sport is selectable-as-primary when `SportCatalog.isPlannable(slug)` = season
supported OR in `SportCatalog.outdoorAuthoredSlugs` WITH ≥1 authored routine. It
gates `OnboardingSportsScreen`, `SportsEditorSheet`, and `migrateToSupportedSportGate`
(no longer strips a plannable outdoor primary). Partial coverage is safe:
`select` nearest-phase-falls-back to ANY full-session routine for an unsupported
sport (never an empty day; supported sports fall through to the engine instead).

**THE TRAP that cost a UITest cycle:** `isPlannable("snowboarding")` was true but
the onboarding chip never rendered — because `Sport.catalog` (TrainingMemory.swift,
the onboarding list) had NO "snowboarding" entry; it bundled it as "snow-sports".
To make an authored sport reachable, THREE slug vocabularies must match:
1. `routine_sports` → `sport_categories.slug` — how the distilled routine is TAGGED.
2. `SportCatalog.outdoorAuthoredSlugs` — the isPlannable allowlist.
3. **`Sport.catalog`** — the onboarding/editor list iterated by the filter. If the
   slug isn't a catalog entry, `.filter { isPlannable }` never sees it → no chip.
   (snow-sports/cycling bundle their variants; distinct authored sports like
   snowboarding/mountain-biking needed NEW catalog rows.) Also: `snow-sports`
   is ski-engine-supported, so a snowboarder must pick the distinct "Snowboarding".

Verify with `AuthoredRoutineTests` (routine ids per sport/phase + a
snowboarding-primary `Planner.generate` → authored non-empty lift days) AND
`OnboardingSportGateUITests` (chip shows) — SQL/isPlannable alone hides the vocab gap.
