# Gap round: behavior and health signals

Date: 2026-11-10. Commit: bb17ca1 (build 171). Analyst: gap-signals.

Method: loaded the three signal skills, then traced each signal by grep and by reading the writer and every reader in `PhaseTraining/`, `Shared/` and `PhaseTrainingWatch/`. Every line cited below was read in this session. Nothing was run or built, so "cannot fire" means no code path sets the input, and "no effect" means no reader changes plan, suggestion or on-screen number. Prior round (2026-10-31, `docs/PLAN-gap-backlog-2026-11.md`) items were not re-raised unless they regressed or the claim did not hold.

Classes: LIVE (captured and consumed), DEAD (captured, no consumer that changes output), BROKEN (reader exists but cannot fire or reads the wrong key), MISSING (worth capturing, not captured).

## Summary

8 findings: 3 BROKEN, 4 DEAD, 1 MISSING-group. Largest: the pre-workout check-in has a pain field nothing can set, preference signals skip every authored-routine day, and the one-tap post-workout "how did it feel" never reaches the planner.

## Findings, ranked by impact

### 1. BROKEN: `SorenessEntry.pain` can never be true, so four readers are dead code

- Evidence: the only writer of a `SorenessEntry` is `Screens/SorenessCheckInSheet.swift:207-215`, which hard-codes `pain: false` at :211. A grep for `pain: true` and `.pain =` across `PhaseTraining/` and `Shared/` finds no other writer (only the abandon-reason enum case, which is a different type). The check-in header (`SorenessCheckInSheet.swift:6-9`) lists the pre-build-107 joint areas as removed, and no pain control replaced them.
- Readers that cannot fire: `Data/MuscleRecovery.swift:83` (`|| entry.pain` blocks the named areas), `Coach/InsightGenerator.swift:94` (pain flag makes the Today insight eligible), `Coach/CoachContext.swift:429` ("pain: yes"), `Coach/CoachContext+LoadBlocks.swift:24` (`painDays` in the recovery trend).
- Effect: a lifter with a tweaked joint has no way to say so before training. The only path to a hard block is `soreness == "high"` on muscle buckets (`MuscleRecovery.swift:83-86`), which does not express pain. The coach trend line "pain days" is always zero.
- Fix: add a "Pain or tweak" toggle to the check-in (per area, or one flag plus the existing area chips) and write `pain: true`. The recovery path already blocks on it. Add a test that a saved entry with pain blocks its areas on the next regen.
- Effort: 2 h.

### 2. BROKEN: swap, favorite, dislike and "stop planning it" signals do not reach authored-routine days

- Evidence: `WorkoutGenerator.generateLift` serves an authored routine before the season engine (`Data/WorkoutGenerator.swift:98-107`). `AuthoredRoutine.shouldServeAuthored` returns true for the climbing pilot and for every sport the season engine does not support (`Data/AuthoredRoutine.swift:58-61`). `SportSeasonGenerator.supports` is true only for ski and climbing slugs (`Data/SportSeason/SportSeasonGenerator.swift:459-462`). The authored comment says this path serves seven of the ten plannable sports (`AuthoredRoutine.swift:173`). Row resolution uses only injury-excluded ids and equipment (`AuthoredRoutine.swift:210-247`, signature takes `excluded` and `allowed`). The only readers of `exerciseAffinities` are `SportSeasonGenerator.swift:193` (tie-break) and :578 (sink). `dislikes` is read only through `AthleteState.dislikedNameKeywords` (`Data/SportSeason/AthleteState.swift:155`). A grep of `memory.dislikes` and `.dislikes` in `Data/` finds no authored-path reader.
- Effect: for those sports, `MemoryStore.recordSwap` (`Data/MemoryStore.swift:113-122`), "recommend more or less", the Profile avoid-list and `PatternEngine`'s accept action `.sinkExercise` (`Data/PlanStore+Suggestions.swift:37-44`) store a value and change nothing. The weekly check-in tells the user "You keep skipping X" with an "Stop planning it" button (`Data/PatternEngine.swift:193-199`); accepting it sets affinity to -2, the rule's own filter (`PatternEngine.swift:185-188`) then stops re-asking, and the authored routine still lists X next week. The user is told it was handled.
- Fix: in `AuthoredRoutine.resolvedRows`, drop or substitute rows whose names match `dislikedNameKeywords` or whose affinity is at or below the sink threshold, reusing the existing substitute path (`AuthoredRoutine.swift:236-247`). Thread `memory` or an `AthleteState` into the two `resolvedRows` callers. Add a test: sink an exercise, regenerate an authored day, assert it is absent or swapped.
- Effort: 5 h.

### 3. DEAD: the one-tap post-workout feel rating never reaches the planner

- Evidence: `Screens/CompleteScreen.swift:75` defines five options ("Too easy" to "Too much"), shown unconditionally at :153 via `feelSection` (:354). The choice is written to `SavedSession.feel` (:505). A grep of `.feel` in `Data/` and `Coach/` finds one reader, `Coach/CoachContext.swift:276` (text for the chat). The planner reads difficulty only from `FeedbackEntry.difficulty` (`Data/Planner.swift:246-247`, thresholds at :258), which is written only by the opt-in `PostWorkoutFeedbackSheet` (`Screens/PostWorkoutFeedbackSheet.swift:173-180`) behind the "Add details" button (`CompleteScreen.swift:536-542`).
- Effect: two difficulty inputs exist and the cheap, always-shown one is ignored. The planner's "two or more too_hard in 7 days drops a lift day" rule (`Planner.swift:258-263`) only fires for users who open the secondary sheet. Most sessions will contribute zero.
- Fix: derive a `FeedbackEntry`-equivalent from `feel` at save (Too easy to too_easy, Too much to too_hard, leave Easy/Right/Hard neutral, or count Hard at half weight; product call), or have `applyRecentSignalBias` read `SavedSession.feel` directly. Keep the sheet for hurt areas and notes.
- Effort: 3 h.

### 4. DEAD: the required check-in field (energy), plus time budget and equipment-changed, have no effect on the plan

- Evidence: `SorenessCheckInSheet.swift:198` makes energy the only required field (`canSave: energy != nil`). Energy is read only in `Coach/CoachContext.swift:427` and the histogram in `CoachContext+LoadBlocks.swift:28`. `timeBudget` (chips 30/45/60/90, `SorenessCheckInSheet.swift:160-175`) and `equipmentChanged` are read only at `CoachContext.swift:432-433`. `MuscleRecovery.status` takes soreness severity and areas only (`Data/MuscleRecovery.swift:64-92`). A grep for `.energy`, `.timeBudget` and `equipmentChanged` across `Data/` and `Screens/` finds no other reader.
- Effect: the user is forced to answer a question whose answer does nothing, and "TIME TODAY 30m" does not shorten today's workout. `GeneratorStrategy.durationMinutes` already exists (`Data/Planner.swift` applyWeekTone path) and could carry it.
- Fix: (a) energy "low" feeds `AthleteState.readinessScore` as a one-day override or eases the day (cap RPE 7, one fewer set); (b) `timeBudget` regenerates today with `strategy.durationMinutes`; (c) if neither ships, make energy optional. Pair with finding 1 in one check-in pass.
- Effort: 5 h.

### 5. DEAD, scheduled: nightly HRV, resting HR and sleep (commit 8700760) have no reader

- Wiring verified, capture works end to end: grant only from the Profile button (`Health/PhysiologyReader.swift:36-43`, `Screens/HealthImports/PhysiologyCaptureSection.swift:79`), hourly foreground refresh gated on `isEnabled` and `isOnboarded` (`App/PhaseTrainingApp.swift:818-821`, `PhysiologyReader.swift:196-215`), summariser and merge (`Health/PhysiologyNight.swift:132`, :237), stored under `pt_physiology_nights`, included in backup (`Data/BackupManager.swift:84`, :250, :397).
- Readers: a grep for `PhysiologyNight`, `loadNights` and `physiolog` outside the Health folder finds only the DEBUG Signals sheet (`Screens/TwinScorecardSheet.swift:46-52`), the capture section's counts, and backup. `ReadinessSignal` is built from session density, recency and trend only (`Data/ReadinessSignal.swift:1-45`), and `FormModel` from training hours (`Data/FormModel.swift:1-25`). No input to the planner, check-in or coach is physiological.
- Status: intentional ("Capture and store only", commit body). `PLAN-next-gen.md:507` gates the reader on 6+ weeks of nights for the owner. Capture shipped in build 145 (commit dated 2026-09-26), so about 6.5 weeks have elapsed if capture was switched on that day; the code cannot show whether it was. The twin review that gates 1b and 1c was calendared for 2026-10-24 (`PLAN-predictive-recommendations.md:212`) and `git log` since 2026-10-20 shows no commit or doc recording it.
- Suggested next step, smaller than the full 1c reader: a DEBUG row that joins each stored night to the next-day check-in (energy, soreness) and to that day's `DayOutcome`, and prints counts and a rank correlation. That tells the owner whether the data separates anything before any generator wiring. Also record the 2026-10-24 review outcome, or set a new date.
- Effort: 3 h for the join readout; the full 1c reader is about 16 h per the plan.

### 6. DEAD effect: completion-pattern autoregulation only writes a note no screen shows

- Evidence: `GeneratorContext.buildAttemptHistory` (`Data/GeneratorContext.swift:405`) walks sessions every regen. `AutoregulationEngine.classify` consumes it in `WorkoutGenerator+Prescription.swift:45` and folds soften (-5%) or amplify (+5 lb) into the "target: X lb" string. That string lands in `GeneratedExercise.notes`, and `toWorkoutTemplate` builds `ExerciseTemplate` without it (`Data/WeekPlan.swift:264-287`); `ExerciseTemplate` has no notes field (`Data/WorkoutTemplate.swift:6-24`). Weights users see come from `ProgressionSuggestion`, which reads only the last session's top set and `HistoryProfile` (`Screens/LogScreenHelpers.swift:39-56`, `Data/ProgressionSuggestion.swift:87-103`) and never consults completion rate.
- Effect: two sessions in a row at under 80% completion do not soften the on-screen suggestion. The engine's output reaches only the coach text.
- Fix: either feed the soften/amplify classification into `ProgressionSuggestion` (through `HistoryProfile`, which already has per-exercise points) or delete `AutoregulationEngine`, `attemptHistory` and its builder per the repo's obsolete-code rule.
- Effort: 3 h.

### 7. BROKEN key plus DEAD: post-workout "anything hurt" uses a joint vocabulary the recovery path cannot read

- Evidence: areas offered are "lower back, knee, shoulder, elbow, wrist, neck, hip, ankle" (`Screens/PostWorkoutFeedbackSheet.swift:41-44`). Recovery and the sore filters use `MuscleBucket` slugs (chest, back, shoulders, quads, ...; `Data/ExerciseFilters.swift:85-91`). `MuscleRecovery.status` takes check-in soreness only (`MuscleRecovery.swift:64-92`). `hurtAreas` is read in `GeneratorContext.buildRecentSoreAreas` (`Data/GeneratorContext.swift:494-509`), which is parked (`includeParkedSignals` false, :271-273), and in coach text (`CoachContext.swift:416`). If unparked, "knee", "hip" and "ankle" would still match no bucket; "shoulder" matches "shoulders" only by substring.
- Related: `FeedbackEntry.ranLong` is hard-coded false (`PostWorkoutFeedbackSheet.swift:178`) and read at `CoachContext.swift:415`, so it never prints. `sessionId` is the template id, not a per-session id (`CompleteScreen.swift:199`), so a feedback row cannot be joined to one session.
- Effect: reporting a hurt knee after a session changes nothing about the next leg day. Joint hurt areas map to the injury contraindication sets (`DemographicProfile.excludedByInjury`), not to muscle buckets, so a mapping is needed.
- Fix: map hurt joints to bucket sets (knee to quads and hamstrings, shoulder to shoulders, lower back to back and glutes, etc.) and feed feedback from the last 36 h into `MuscleRecovery.status` as eased areas. Delete `ranLong`. Store the session start time as the id.
- Effort: 3 h.

### 8. MISSING and DEAD minor group

- Imported RPE does not reach progression. The prior-round backlog says "Imported Hevy RPE comes along for free" (`docs/PLAN-gap-backlog-2026-11.md:44`). It does not: imported sets never enter `savedSessions` (`Data/ImportedHistorySessions.swift:9-12`), `prevSets` come from native sessions (`Data/SessionStore.swift:304-308`), and `HistoryProfile.SetRecord` and `ProvenStrength` carry weight and reps only (`HistoryProfile.swift:81-86`). Imported rows keep `rir` and `rpe` in `imported_sets` (`Data/UserDatabase.swift:203`). Effort 3 h to carry effort into `SetRecord` and `fromHistory`.
- Rest actually taken is not recorded: the rest timer is view-local and not persisted (`Screens/LogScreen.swift:11-13`), and `session_sets` has no timestamp or rest column (`Data/UserDatabase+Sessions.swift:335`). A per-set completion time would give true session density and rest adherence. Effort 3 h (migration plus the Codable rule for added fields).
- Watch live heart rate is displayed (`PhaseTrainingWatch/PhaseTrainingWatchApp.swift:36`) and published by the controller (`WatchWorkoutController.swift:20`) but not sent in `WatchSyncEvent` or stored on the phone. Low value until physiology has a reader.
- Session-start places (3c) are captured and clustered but read only by the DEBUG sheet (`Screens/TwinScorecardSheet.swift:38-44`); a reader is gated on repeat visits by `PLAN-next-gen.md:508`. `MotionStore` labeled motion is likewise read only by the DEBUG sheet (`TwinScorecardSheet.swift:101`). Both intentional, listed so the dead-by-design inventory is complete.
- `GeneratorContext.recentHardSportDays` is computed each regen (`GeneratorContext.swift:277`) but its only reader is the `isEmpty` check (:105); the planner recomputes the same count locally (`Planner.swift:250-259`). Delete the field. Effort 0.5 h.
- `FormModel` and `Counterfactual` (2a) are read only by the DEBUG sheet (`TwinScorecardSheet.swift:80-91`). Intentional per `PLAN-next-gen.md:108-113`.

## Signal table

| Signal | Written | Read by | Class |
|---|---|---|---|
| Logged weight, reps, done | `UserDatabase+Sessions.swift:335` | `ProgressionSuggestion`, `HistoryProfile`, `priorBest`, `MuscleFreshness` | LIVE |
| Logged RIR and RPE (native) | `LogScreen.swift:566`, `LogSetRow.swift:93` | `LoggedSet.effortRIR` to `ProgressionSuggestion.swift:93,243-262` | LIVE (native only; see 8) |
| Imported RPE and RIR | `UserDatabase+Imports.swift:182-183` | nothing | DEAD |
| Exercise swap | `MemoryStore.recordSwap`, `LogScreen.swift:268`, `TodayScreen+TemplateEditor.swift:263` | season engine only (`SportSeasonGenerator.swift:193,578`) | LIVE for ski and snowboard, BROKEN for authored days (2) |
| Favorite, "recommend less", dislikes | `ExerciseActionSheet.swift:96-103`, Profile | same as swap | same as swap (2) |
| Planned vs actual (`DayOutcome`) | `PlanStore+DayOutcomes.swift` | `PatternEngine` (session length, dropped), `SessionLikelihood`, coach | LIVE |
| Dropped exercise to "Stop planning it" | `PatternEngine.swift:175-205` | `exerciseAffinities` | BROKEN on authored days (2) |
| Abandoned workout and reason | `LogScreen.swift:529`, `pt_abandoned_workouts` | `PatternEngine.swift:137` (timeOut only), coach | LIVE |
| Missed workout, skip streak | `PlanStore+MissedWorkoutAutopilot.swift` | `PlanStore+Generation.swift:51`, `SessionLikelihood.swift:137`, coach | LIVE |
| Check-in soreness severity and areas | `SorenessCheckInSheet.swift:207` | `MuscleRecovery.swift:83-99` to generator and authored gate | LIVE |
| Check-in pain | `SorenessCheckInSheet.swift:211` (always false) | four readers | BROKEN (1) |
| Check-in energy, time budget, equipment changed | `SorenessCheckInSheet.swift:207` | coach text only | DEAD (4) |
| Post-workout feel (one tap) | `CompleteScreen.swift:505` | coach text only | DEAD (3) |
| Post-workout difficulty (opt-in sheet) | `PostWorkoutFeedbackSheet.swift:173` | `Planner.swift:246-263`, coach | LIVE, low reach |
| Post-workout hurt areas | `PostWorkoutFeedbackSheet.swift:176` | parked context field, coach text | BROKEN key (7) |
| Session mood after | `CompleteScreen.swift:506` | `ProgressStats.moodAfterSummary`, coach | LIVE (display) |
| Weekly check-in rating and intent chips | `WeeklyCheckInFlow.swift:62-77,281` | `derivedWeekTone` to `WeekOverrides.weekTone` to `Planner.swift:333` | LIVE |
| Stored `WeeklyCheckIn` rows (notes, intent text) | `WeeklyCheckInFlow.swift:274-283` | nothing | DEAD (display-free history) |
| Hard sport logs | `SportLogStore` | `Planner.swift:250-263`, readiness exclusion | LIVE |
| HealthKit workouts | `HealthKitImporter` | readiness events, `FormModel` | LIVE |
| HealthKit activity detection | `ActivityDetectionStore` | Today banner to sport log and week event | LIVE |
| Calendar travel | `CalendarTravelReader` | check-in events to planner | LIVE |
| Session start time | `SessionStore` | `SessionLikelihood` usual hour | LIVE |
| Body weight log | `BodyWeightLogSheet.swift:323` | `StrengthStandards`, `GoalTemplate`, `MaxHangTest`, coach | LIVE (display and goals) |
| Body composition log | `BodyCompositionLogSheet.swift:368` | Profile and Progress only | DEAD, intentional |
| Nightly HRV, resting HR, sleep | `PhysiologyReader.swift:196` | DEBUG sheet, backup | DEAD, scheduled (5) |
| Explore sessions | `ExploreRecorder`, `UserDatabase+Explore.swift` | `PatternEngine.swift:206` (viewed routine), DEBUG zero-result list | LIVE (narrow) |
| Session places, motion, twin prediction | capture only | DEBUG sheet | DEAD, intentional |
| Rest taken, per-set time, watch HR | not stored | | MISSING (8) |

## Checked and fine

- Readiness threading: both `Planner.generate` call sites pass context (`PlanStore+Generation.swift:54`, `WeeklyCheckInFlow.swift:253` via `makeGeneratorContext`). The old dropped-context bug has not regressed.
- Readiness into the season engine and authored gate: `WorkoutGenerator.swift:66-71` passes score and `MuscleRecovery` status; blocked buckets drop authored rows (`AuthoredRoutine.swift:265-274`).
- Skip streak and missed autopilot reach `Planner.generate` through `deEmphasizedWeekdays`.
- Post-workout difficulty does change the plan (`Planner.swift:246-263`); the skill's note that it is coach-only stays corrected. The reach problem is finding 3.
- RIR and RPE now steer the weight pill (`Shared/Models/SessionModels.swift:109-113`, `ProgressionSuggestion.swift:243-262`), with the 5+ RIR option parsing as 5.
- Stagnation: `HistoryProfile.plateau` drives the "add a rep" rule (`ProgressionSuggestion.swift:206`), so the parked `stagnantExercises` field is not a lost signal.
- `SessionLikelihood` reaches the weekly-check-in preview (`CheckInPreviewScreen.swift:111-115`) and the chat drawer (`CoachDrawer.swift:391`); the claim in its header holds. The chat drawer does not pass `readinessScore` (`CoachDrawer.swift:365-391`; only `PlanStore+LLMRefinement.swift:147` does), which matches the "silent signal" rule in `CoachContext.swift:56-64`.
- PatternEngine rule ids are stable across accept (`PatternEngine.swift:162` comment and id), and the dropped rule filters out already-sunk names.
- Physiology capture privacy posture: not in the coach snapshot, in backup, swept by erase (`BackupManager.swift:250,397`, `PhysiologyReader.swift:155-162`).
- Twin diagnosis numbers in the skill (811 pairs, 58.1% direction) were not re-measured; only the wiring was checked.
