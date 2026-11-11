# Generator eval gap analysis

- Date: 2026-11-10
- Commit: bb17ca1 (main, build 171)
- Method: a throwaway XCTest harness drove `Planner.generate` (the full app path: shape, SessionMix, authored routines, season engine, CNS balance) for 4,958 weekly plans, wrote one JSONL record per plan, and Python scripts judged the output against `coach.db`. The harness lives in a scratch copy at `/tmp/claude-501/gap-generator/repo/PhaseTrainingTests/GapSweepTest.swift` (no tracked file in the real tree was touched). Run with `-derivedDataPath /tmp/claude-501/dd-generator`, full log grepped: `** TEST SUCCEEDED **`, `[GapSweep] plans: 4958`. Raw output: `/tmp/claude-501/gap-generator/sweep.jsonl`. Analysis scripts: `/tmp/claude-501/gap-generator/an/a*.py`.
- Harness note: `GeneratorSweepReportTest` and `GeneratorInvariantTest` were deleted in 449bd8d, as the skills say. The only existing generator eval is `SeasonFidelityTest` (2 sports x 5 phases). I built the sweep fresh rather than reuse it.
- Profiles swept:
  - 4,320 factorial plans: alpine-skiing, ski-mountaineering, climbing, bouldering x 5 seasons x 3 experience levels x 4 equipment tiers (bodyweight, dumbbells, dumbbells+bar+bands, full gym) x lift days 1 to 6 x session budgets 30/45/75 min.
  - 350 plans across all 35 catalog sports, bodyweight and full gym.
  - 120 plans with one of 15 injuries on 4 sports, 2 seasons.
  - 120 plans across the 4 training goals x 5 seasons x ages 19/45/68 (45 as female).
  - 48 plans of weeks 1 to 8 in phase.
- Scope limit: 11 sports are plannable as primary (`SportCatalog.isPlannable`, `AuthoredRoutine.swift:~150`): the ski and climbing slugs plus snowboarding, mountain-biking, mountaineering, trail-running, hiking-trekking, thru-hiking. The other 24 catalog sports are unreachable from onboarding, so their "No X session fits your equipment" empty days (8 to 16 per sport in my sweep) are not counted as findings. All counts below use the 4,678 plannable plans unless stated.
- Context was `.empty` (no logged history, no readiness, no soreness), so rotation across weeks via `recentlyPicked`, readiness scaling and recovery gating were not exercised here. The 2026-10-31 round's items (strength/size/endurance rep direction, readiness direction) hold: goal bands moved reps as designed in the goal sweep.
- Fleet (eval-rig, commit 526784e): `FleetReplay` predicts likelihood, suggestions, twin and counterfactual outputs. `grep` for `Planner`, `WorkoutGenerator`, `generateLift` in `PhaseTrainingTests/Fleet/` returns nothing. It gives population evidence on readiness and pattern engines, none on workout quality. The last fleet run (2026-09-27) predates this commit anyway. No local fleet output to read.

## Findings, ranked by impact

### 1. Time, hold, distance and per-side prescriptions are replaced by rep counts in the season engine

Evidence. `SportSeasonGenerator.prescribe` (`SportSeasonGenerator.swift:~640`) sets `reps: m.protocolReps ?? scheme.repsString` and never reads the catalog's `default_reps`. The comment on `SportMovement` (`SportSeasonModels.swift:220`) says so. The unit fix from `phase-training-prescription-precedence-and-dual-path` (b9c4527) lived in the legacy generator that 449bd8d deleted, so this class has returned.

Output observed, 51,991 season-engine exercise rows across the sweep:

| Exercise | catalog default | generated |
|---|---|---|
| Side Plank | 20-45 sec per side | 2-3 x 10-15 (2,844 rows) |
| Bird Dog | 8-6-4 x 10 sec holds per side | 2 x 10-15 (1,609) |
| Hollow Body Hold | 20-45 sec | 3 x 6-10 (622) |
| Farmer's Carry | 40-60 ft | 10-15 (174) |
| Front Plank | 30-60 sec | 10-15 (127) |
| Wall Sit (Ski Tuck) | 30-90 sec | 12-20 (76) |
| Sled Push 3-Min Round | 3 min | 12-20 (13) |

That is 5,465 rows (10.5%) where a timed or distance movement shows reps, and 81.8% of season-engine sessions carry at least one catalog movement whose default is not a plain rep band. Separately, "per side" is dropped on 14,299 rows (27.5%): Dead Bug, Single-Leg RDL, Single-Leg Calf Raise, Lateral Lunge, Cossack Squat, Lateral Bound to Stick. Authored routines keep it ("10 per side", "40-60 ft"), so the same exercise reads differently depending on which path served it. Rucking appears as "60s hold" (aerobicUphill scheme) for a walking exercise.

Effect on a user. A "Hollow Body Hold, 3 x 6-10" has no meaning on the log screen, the hold timer (shipped in build 168) never offers itself because the reps field is numeric, and a skier sees "Side Plank 10-15" with no side or seconds. Unilateral work is ambiguous about whether the count is per leg, and the minutes estimate does not double it.

Suggested fix. In `prescribe`, when the movement's catalog `default_reps` is non-numeric (reuse `isNumericRepBand`), keep it verbatim over the demand band and keep the demand's sets, RPE and rest. Carry "per side" through for unilateral movements. Add `protocol_reps` rows only for the few that need a real protocol. Add an invariant test: any exercise whose catalog reps carry a unit keeps that unit in the plan (grid over sports x phases).

Effort: 3 hours including the test.

### 2. Authored climbing serves an advanced-only routine to beginners, and serves the same routine twice a week

Evidence. `AuthoredRoutineSelector.select` (`AuthoredRoutine.swift:~97`) picks `ids[sessionIndex % ids.count]` from the (sport, phase) set and never reads `experience` or the routine's `difficulty`. coach.db tags "Climber Pre-Season Power Block" as `advanced`.

Output observed (climbing, pre-season, beginner, full gym, 3 lift days):
```
[lift] Climber Pre-Season Power Block est=24 (Authored program)
   Hangboard Repeaters (7/3 Protocol) | 3x6 hangs (7/3) rest120
   Campus Board Ladder (1-3-5) | 4x3-5 reps rest180   note: "Campus ladder 1-3-5 (advanced only)"
   Explosive Pull-Up | 3x3-5 rest120
   Dynamic Lock-Off (Campus-Lite) | 3x3-5 per side rest120
   Ab Wheel Rollout | 3x8-12 rest90
... same routine again two days later
```
Of 306 beginner climbing authored sessions, 180 (59%) include Campus Board Ladder, Explosive Pull-Up, Dynamic Lock-Off or Weighted Pull-Up. Where a climbing week holds two authored sessions, the same routine id repeats in 81 of 122 weeks (pre-season 20 of 20, event prep 20 of 40, maintenance 10 of 16, in-season 16 of 16). Authored rows also carry no RPE (blank), unlike every engine row.

Effect on a user. A new climber is handed campus-board work whose own note says "advanced only", twice a week, with no effort cue. Repeating a campus session on two days is a tendon-load problem as well as a boredom one.

Suggested fix. Filter `ids` by `difficulty <= experience` with a fallback to the easiest routine, and drop the routine from the rotation after it has been used earlier in the week (the engine path already rotates by `recentMovementIDs`). Add RPE to the authored rows or label them "RPE not set". Test: no `advanced` routine for a beginner; no repeated routine id inside one week when the phase has more than one.

Effort: 3 hours.

### 3. Experience and age do not change the prescription in the season engine

Evidence. `AthleteState.experience` is used only as a pool gate (`SportSeasonGenerator.swift:316`, `minExperienceRank`). `age` and `gender` do not appear anywhere under `SportSeason/` (grep returns no `.age`).

Output observed:
- Intermediate vs advanced: identical sets, reps, RPE, rest and exercises in 1,374 of 1,440 plan pairs.
- Beginner vs advanced: the only difference is which movements are eligible (2,657 differing rows, all exercise ids, none sets or RPE). A beginner gets the same 4 x 3-5 at RPE 7-8 on Barbell Back Squat and 4 x 2-3 Box Jump at RPE 6-7 as an advanced athlete (ski pre-season, 3 days).
- Age 19, 45 and 68: the 40 plans per age are byte-identical (alpine-skiing, off-season, age 68: Nordic Hamstring Curl 3 x 4-6, Broad Jump 4 x 2-3, Barbell Back Squat 4 x 3-5 at RPE 7-8, same as age 32).

The legacy generator clamped beginner sets and RPE; the clamp was deleted with it. `phase-training-prescription-precedence-and-dual-path` Trap 2 (beginner RPE cap) applies again.

Effect on a user. Onboarding asks experience, age and gender and the plan ignores two of the three. A 68-year-old beginner and a 25-year-old advanced athlete see the same weekly load.

Suggested fix. Add an experience modifier in `SetScheme.modulated` (beginner: cap RPE at 7, floor reps at 6, cap sets at 3; advanced: allow +1 set on strength demands) and an age modifier (65+: drop power and high-impact plyometrics to lower-impact substitutes or reduce sets, extend rest). Metamorphic tests: beginner total sets <= intermediate <= advanced; age 70 <= age 32.

Effort: 5 hours (rule choice is the cost; code is small).

### 4. Session minutes budget is both under-filled and exceeded

Evidence. `targetMovementCount` (`SportSeasonGenerator.swift:493`) clamps the user's budget into the phase rule's `sessionMinutesTarget` and its own comment admits the 11 min per movement heuristic "still over-estimates" (measured about 8 min). Authored routines ignore the budget entirely. `assemble` computes `estimatedMinutes` as sum of `ceil(sets * (rest + 40) / 60)`.

Output observed (estimated minutes per lift session, plannable sports):

| budget | mean est | share under 60% of budget | sessions over budget |
|---|---|---|---|
| 30 | 21.2 | 35% | 679 of 4,872 (14%), season engine alone 472 of 1,458 (32%) |
| 45 | 23.5 | 65% | 158 of 6,084 (max 64 min, ski off-season Upper body complement) |
| 75 | 28.3 | 90% | 0 |

Authored sessions are 21 minutes mean at 30, 45 and 75 minute budgets. Ski off-season with a 30-minute budget still gets the rule's floor (about 44 to 56 minutes). In-season complement days at 30 minutes are 14 minutes (3 movements, 1 to 2 sets, for example Skull Crusher 1 x 10-15, Dumbbell Single-Arm Row 2 x 6-10, Face Pull 2 x 6-10).

Effect on a user. Someone who sets 75 minutes gets a 25 to 30 minute plan; someone who sets 30 and skis gets 45 to 55. The budget control is half effective.

Suggested fix. Calibrate the movement count from the measured minutes per movement (about 8, or add a warm-up and transition allowance to `estimatedMinutes`), let the budget lower the rule's floor when the user asks for less than the floor, and pad short sessions by raising sets before adding movements. Add a metamorphic test: `estimatedMinutes <= budget + 5` and `>= 0.6 * budget` for budgets 30 to 75 across phases.

Effort: 3 hours.

### 5. Exercise order inside a session follows the order the demands were filled

Evidence. Picks are filled scarcest-demand-first (`SportSeasonGenerator.swift:137-146`) and emitted in that order; no sort by compound, power or fatigue runs afterward.

Output observed (alpine-skiing, full gym, 104 season-engine sessions): the heaviest lift (Barbell Back Squat, Eccentric-Focused Back Squat, Weighted Pull-Up) sits in the last two slots in 20 of 36 sessions that carry one, and follows a jump or bound in 17 of 36. Example, off-season Session 1: Dumbbell Single-Arm Row, Nordic Hamstring Curl, Single-Leg RDL, Bird Dog, then Barbell Back Squat 4 x 3-5 at RPE 7-8. Pre-season beginner Session 1: Row, Eccentric-Focused Back Squat, Box Jump, then Barbell Back Squat 4 x 3-5 (two squat variants in one session, power work after a heavy squat). The most common opening exercise is Lateral Lunge (19 of 104), then Calf Raise Endurance (14) and Stair Climber (12). There is no warm-up ramp row in engine sessions.

Effect on a user. Max-strength and power work happen fatigued; the session reads as arbitrary.

Suggested fix. After picking, stable-sort by a training-order key: power, then max strength compounds, then unilateral and eccentric work, then core and prehab. Cap one squat-pattern max-strength movement per session. Test: no power movement after an RPE 7+ movement; compound heavy lifts in the first two slots.

Effort: 2 hours.

### 6. Complement strength slots are filled with easy regressions at strength-day intensity

Evidence. The complement pool (`general-fitness` pool) feeds `.upperPush`, `.legStrength` and similar demands at 3 x 6-10, RPE 7-8, 120 s rest with no equipment or load awareness.

Output observed (full gym, complement sessions): 41% contain Push-Up, Push Up (Knees), Chest Press (Band), Glute Bridge, Lunge (Bodyweight) or Squat (Bodyweight). 512 of 1,818 heavy-slot rows (3+ sets at RPE 7-8) for intermediate and advanced athletes are one of those: Push-Up 114, Chest Press (Band) 102, Push Up (Knees) 98, Glute Bridge 82, Lunge (Bodyweight) 78, Squat (Bodyweight) 32. Experience level does not change the rate (identical 248 of 600 sessions for beginner, intermediate and advanced). Example week 2 of off-season climbing, gym: Barbell Back Squat and Goblet Squat in week 1, then Glute Bridge and Lunge (Bodyweight) at 3 x 6-10 RPE 7-8 in week 2. Strength goal: Push-Up 4 x 3-6 at 180 s rest.

Effect on a user. A gym lifter gets knee push-ups at "RPE 7-8" and bodyweight lunges as the leg strength movement, then barbell work the next week, so loads cannot progress.

Suggested fix. Rank candidates for strength demands by loadability when the user owns the equipment (prefer barbell, dumbbell, machine over bodyweight when equipment allows), keep bodyweight movements for bodyweight tiers, and exclude "(Knees)" and band regressions above beginner. The same lesson as `phase-training-generator-bias-weight-pool-not-reorder`.

Effort: 3 hours.

### 7. Catalog equipment mis-tags put apparatus exercises in bodyweight plans

Evidence. coach.db `exercise_equipment`: `Ab Wheel Rollout` (id 7) requires only `bodyweight`, while a separate `Ab Wheel` (id 980) carries `ab-wheel`. `Sled Push (Heavy)` (533) and `Sled Push (Hill Simulation)` (682) require `bodyweight`; `Sled Push 3-Min Round` (325) lists `plyo-box` as optional.

Output observed: Ab Wheel Rollout appears in 743 rows of the 1,872 bodyweight-only plans and 558 rows of the dumbbell-only plans; Sled Push 3-Min Round in 13 bodyweight rows. A no-equipment user is prescribed an ab wheel (Caution note: "low back").

Effect on a user. Prescriptions that need purchased equipment the user said they do not have.

Suggested fix. Edit the source rows in `db/source/exercise_equipment.json` (id 7 to `ab-wheel`, sleds to `sled`), run `python3 scripts/db/build_db.py`, commit JSON and both coach.db copies per `phase-training-coachdb-add-exercise-source-pipeline`. Add a test that every exercise whose name contains an apparatus word (wheel, sled, bench, bar) has a matching equipment row.

Effort: 1 hour.

### 8. Five and six lift-day requests produce seven-day training weeks

Evidence. `Planner.generateUnbiased` fills the shape queue and `CNSBudgetEngine.balance` only demotes planner lifts to avoid three consecutive high-CNS days.

Output observed: with 5 lift days requested, 504 of 720 plans have zero rest days; with 6, 648 of 720. Day patterns (L lift, S sport, . rest): ski off-season, 6 days `LLLLLSL`; in-season, 5 or 6 days `SLLSLLL`; 4 days in-season `S.LSLLL`. The longest unbroken run is 7 days in every 5 and 6 day plan that has no rest. A 6-lift request in-season returns 5 lifts and 2 sport days, with no explanation shown in the plan data.

Effect on a user. A seven-day week with no recovery, the lift days stacking on sport days, for the athletes most likely to over-reach.

Suggested fix. Reserve one rest day as a hard constraint (lifts plus sport sessions at most 6), demote the weakest complement day, and write the reason into `generatedReason`. Test: every generated week has at least one `.rest` day.

Effort: 2 hours.

### 9. No progression inside a block, and the weekly press and pull swap exercises

Evidence. `MesocycleProgression` produces a deload week but the prescription is flat on weeks 1 to 3.

Output observed (p5, ski and climbing off-season, intermediate, gym, 4 lift days): total sets per week for weeks 1 to 8 are `57 57 57 31 57 57 57 35` (ski) and `62 62 62 54 62 62 62 54` (climbing). Sets, reps and RPE are the same in weeks 1, 2 and 3 for the same slot, yet the exercise changes each week (week 1 Chest Press (Band), week 2 Dumbbell Bench Press, week 3 Dumbbell Floor Press, week 4 Barbell Bench Press), so a user cannot add load to a lift from week to week. The deload cut is 46% of sets for ski but 13% for climbing and week 8 for ski differs from week 4 (35 vs 31).

Effect on a user. The "progressiveOverload" label has no overload in it, and a deload week is a different size depending on the sport.

Suggested fix. Add a per-week ramp (RPE +0.5 and reps or load targets per week) in `SetScheme.modulated(by:weekNumber:)`, keep anchor lifts (the first maxStrength and upperStrength picks) fixed across the block and rotate only accessories, and set one deload factor.

Effort: 4 hours.

### 10. Injury exclusions pass the safety invariant but cover few exercises for elbow, finger and hip injuries

Evidence. Zero generated exercises appear in `profile.excludedExerciseIds` across all 120 injury plans and the 4,320 factorial plans (the safety path is wired). Coverage depends on tagged rows: `exercise_injury_relevance` has contraindicated rows for tennis-elbow 4, stinger-burner 5, finger-pulley 6, hip-flexor-strain 10, hip-labral-tear 14, wrist-sprain 17, golfers-elbow 18, against 60 to 149 for most others.

Output observed: the tennis-elbow plans (alpine-skiing) still contain Skull Crusher (Lying Triceps Extension), Barbell Curl, Reverse Wrist Curl and Dumbbell Single-Arm Row; golfers-elbow plans contain Skull Crusher and Barbell Curl; lumbar-disc-herniation plans contain Ab Wheel Rollout and Barbell Bent-Over Row despite 79 exclusions. A clinician should rule on which of these belong, so treat this as a coverage question rather than a confirmed bug.

Effect on a user. The in-app promise "we'll filter out exercises that aren't safe for the injuries you pick" is only as good as the tags, and the sparse ones are the common overuse injuries of the two sports served.

Suggested fix. A tagging pass for the seven thin injuries (flexion-extension loaded elbow work for the elbow tendinopathies, loaded spinal flexion for disc), with a test that any injury with fewer than 20 contraindications fails a listed review gate.

Effort: 3 hours engineering plus clinical review time.

### 11. Upper-push volume is thin or absent in short ski weeks

Evidence. Weekly sets by pattern group (alpine-skiing, intermediate, full gym, 45 min, off and pre-season, means): 2 lift days: push 0, pull 4, knee 12.5, hinge 7. 3 days: push 4.5, pull 8.5. 4 days: push 9, pull 13. Climbing 3 days: push 6.5 against pull 16.5 (ratio 1:2.5), 2 days 3.5 against 16.5.

Effect on a user. A two-day skier gets no pressing at all for the season; a climber's push to pull ratio is lopsided.

Suggested fix. Add a weekly pattern floor in `SessionMix` or the complement rotation (at least 6 push sets and a push:pull ratio between 1:2 and 1:1 per week where the complement slots exist). Test the weekly ratio.

Effort: 2 hours.

## Checked and fine

- Injury safety: 0 of 4,678 plannable plans contain an excluded exercise, season engine and authored path both (`profile.excludedExerciseIds`).
- Equipment filter for restricted tiers: 0 violations of `is_required` equipment for bodyweight, dumbbell and home-bar users (the Ab Wheel result in finding 7 comes from a wrong catalog tag, and the filter did what the tags said). Full gym returns an empty allow list by convention and is unrestricted.
- Empty days: no empty session on plannable sports. Authored-served outdoor sports (snowboarding, mountain-biking, mountaineering, trail-running, hiking, thru-hiking) give sessions at bodyweight and full gym alike (0 "authored-no-fit" days in my sweep for them).
- Set bounds: every engine row has sets in 1 to 6; no row with 0 sets or empty reps.
- Goal axis: strength 3-6 reps at 180 s, size 8-12 at 90 s, endurance 15-20 at 45 s, applied to rebandable demands only; power, finger and eccentric demands keep their own band (`DemandScheme.swift:rebandable`).
- Seasons: weekly sets fall off-season 57, pre 48, event prep 40, in-season 31, maintenance 23 (ski, 4 days, 45 min), matching phase intent. Hangboard capped at two sessions a week (test exists, output agrees).
- Deload week exists and reduces volume (finding 9 is about magnitude and the lack of in-block ramp).
- Cross-day repetition: moderate. Unique-exercise share by tier at 3 lift days: bodyweight 0.75, dumbbell 0.80, gym 0.87, home bar 0.85. It reaches 0.55 for bodyweight at 6 days (Push-Up on 4 of 6 days) but 5 to 6 lift days are the case finding 8 already flags.
- Fleet/eval-rig: covered above, no generator evidence available locally.

## Not reachable but noted

- 24 non-plannable catalog sports return empty "No X session fits your equipment and injuries yet" sport days for bodyweight users (and bodybuilding, olympic-weightlifting, obstacle-course-racing even at full gym). If a secondary sport or an import path can set one of these as primary, `AuthoredRoutine.swift:~190` becomes a user-facing empty day. I did not find such a path in this sweep.
