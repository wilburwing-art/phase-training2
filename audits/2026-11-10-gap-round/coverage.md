# Test coverage gap analysis

- Date: 2026-11-10
- Commit: bb17ca1 (main, build 171), working tree has untracked docs and scripts/llm only
- Method: `xcodebuild test -scheme PhaseTraining -only-testing:PhaseTrainingTests -enableCodeCoverage YES` on a cloned iPhone 17 Pro simulator (deleted afterwards), own derivedDataPath /tmp/claude-501/dd-coverage, result bundle /tmp/claude-501/gap-coverage/run.xcresult. Per-file and per-function numbers from `xccov view --report --json`. UI test target not run.
- Result: ** TEST SUCCEEDED **. 1739 tests, 0 failures, 2 skipped (FleetLikelihoodSweepTests.testSweepLikelihood, FleetReplayTests.testReplayRunDirectory; both fleet dev tools that need local input).
- Line coverage by target: PhaseTraining.app 28.37% (22,886 / 80,667), PhaseTrainingWatch.app 22.13% (243 / 1,098, of which the 243 is Shared code), unit test code 94.99%.
- The 28% headline is dominated by SwiftUI views (`Screens` 3.4% of 47,722 lines). Logic code is far higher: Data 85.8%.

## Coverage by module (lines covered / executable)

| Module | Covered | Executable | % |
|---|---|---|---|
| Data (generator, planner, stores, DB, twin) | 16,408 | 19,131 | 85.8% |
| Imports | 659 | 701 | 94.0% |
| Shared/Models, Motion, WatchSync, Health | 486 | 496 | 98.0% |
| Health | 618 | 1,060 | 58.3% |
| App | 837 | 1,547 | 54.1% |
| Music | 69 | 145 | 47.6% |
| Coach | 1,541 | 4,509 | 34.2% |
| Components | 856 | 5,255 | 16.3% |
| Theme | 49 | 349 | 14.0% |
| Screens | 1,606 | 47,722 | 3.4% |
| PhaseTrainingWatch (app target files) | 0 | 929 | 0.0% |

Core logic files, all at or above 96% unless noted: AutoregulationEngine 100, MesocycleProgression 100, ProgressionSuggestion 100, SessionMix 100, WorkoutGenerator+Represcribe 100, SupportScheduler 99, SportSeasonGenerator 97, PatternEngine 97, GeneratorContext 96, TrainingLoadModel 99, TwinPrediction 99, TwinDiagnosis 99. WorkoutGenerator 89, WorkoutGenerator+Prescription 87, Planner 81, CoachDatabase 91, UserDatabase+Sessions 94, UserDatabase+Imports 91, BackupManager 90, SessionStore 90, PlanStore 84.

## Findings ranked by risk

### 1. Goal progress inputs have no test: SessionStore+GoalMetrics.swift (0 / 51)
- Evidence: `bestE1RMByExercise()` (L24, 0/19) and `fastestFiveKSeconds(sportLogs:)` (L48, 0/11) are at 0%. They are the only producers of the numbers GoalTemplate.progress consumes (CompleteScreen.swift:492-495, ProgressScreen+GoalCards.swift:43). GoalTemplateTests covers `progress` with hand-passed values, so the arithmetic is tested and the data feeding it is not.
- Risk: highest. Both change the goal progress bar the user sees. `bestE1RMByExercise` keys by `name.lowercased()` while `GoalTemplate.progress` looks up `exName.lowercased()`; a catalog rename or alias breaks the match and the bar goes to "unknown" with no failing test. The 5k matcher is a tolerant string match on sport slug and note text (L48+), exactly the sort of code that regresses on a new sport slug.
- Suggested test: SessionStore fixture with warmups, undone sets, zero weights, two sessions of one exercise with different casing; assert the max e1RM. For 5k: logs with "5k", "5K", "10k", non-run sport, no note.
- Effort: 2 h.

### 2. Planner.pickRoutine and applyFeedbackBias have 0% and no production caller
- Evidence: `Planner.pickRoutine(routines:kind:memory:profile:slotOffset:)` Planner.swift:1196, 0/79 lines. Its only caller is the overload at L1188, which itself has no caller outside the file (git grep). `Planner.applyFeedbackBias` L308, 0/8, no caller anywhere. Planner.swift is the 232-line uncovered chunk of an otherwise 81% file.
- Risk: either dead code that should be deleted (project rule is delete on sight) or a routine-selection path that was unwired during the generator rework and would pick the wrong routine if re-wired. Both change what the user sees. Confirm with the owner before deleting.
- Suggested test: if live, a table test over kinds and slotOffset; if dead, delete both and re-run Planner tests.
- Effort: 1 h to decide and delete, 3 h to test if kept.

### 3. PlanStore week refresh and regenerate-today paths are thin
- Evidence: `PlanStore.regenerateToday(memory:today:salt:)` PlanStore.swift:790, 9/42 (21%); `refreshForCurrentWeek` L765, 2/8; `currentValidationIssues` PlanStore+Validation.swift:22, 3/22; `acknowledgedRulePatterns` L48, 0/8. PlanStore overall is 84%, so these are the gaps in the mutation surface. PlanStoreValidationOverrideTests exists but exercises overrides, not the issue listing.
- Risk: regenerateToday replaces the day's workout directly (mutate plan.days[idx], then savePlan), the direct-mutation pattern noted in the planstore-mutation-seams skill. A regression changes today's workout and per-week caps.
- Suggested test: seed a plan, call regenerateToday with two salts, assert a changed workout, the week cap increments, completed or logged days are untouched, and the plan persists across reload.
- Effort: 3 h.

### 4. LLM plan refinement is untested: PlanStore+LLMRefinement.swift (43 / 277, 16%)
- Evidence: `refineCurrentPlanWithLLM` 0/64, `refineSingleDay` 0/84, `existingFocus` 0/12, `applyRefinedWorkout` 0/11. Skill phase-training-llm-refinement-clobbers-edits records that this path overwrote user edits once.
- Risk: it rewrites the weights and exercises the user sees. A user-edit clobber regression would not be caught.
- Suggested test: inject a stub client; assert edited days and logged days are skipped, an invalid response leaves the plan unchanged, and the focus is preserved.
- Effort: 4 h (needs a client seam; check whether one exists first).

### 5. Coach tool-call proposals: CoachTools.swift 150 / 357 (42%)
- Evidence: the four proposal closures are 0%: proposePlan L17 (0/38), proposeWorkout L56 (0/42), proposeMemory L99 (0/32), buildWorkout L132 (0/73). Also CoachConsent 0/33, MiniPlanDiffCard 0/183, MiniWorkoutDiffCard 0/181, MiniMemoryDiffCard 0/145, MiniDiffCardChrome 0/160.
- Risk: these turn model output into plan, workout and memory diffs the user accepts. Coach apply-by-id logic is covered elsewhere (skill phase-training-coach-diff-apply-by-id-not-name); the schema-to-diff builders are not.
- Suggested test: feed canned tool-call JSON to each closure; assert diff contents, unknown exercise ids rejected, malformed args return an error.
- Effort: 4 h.

### 6. Subscription purchase and restore: SubscriptionStore.swift 92 / 148 (62%)
- Evidence: `purchase(_:)` L86 0/19, `restore()` L108 0/8, `terms(for:)` L169 0/8, `refreshEntitlement()` L210 9/19. SubscriptionStoreTests, CoachEntitlementTests, SupportEntitlementTests and CoachSurfaceGatingTests cover gating state. `PhaseTraining.storekit` exists in the repo.
- Risk: purchase and restore failing leaves a paying user without Pro. Gating itself is covered, so the risk is in transaction handling. The skill ios-pro-gate-held-open is relevant.
- Suggested test: StoreKitTest session with PhaseTraining.storekit: purchase, restore after expiry, refund revoke, pending state.
- Effort: 4 h.

### 7. Watch sync coordinator on the phone side: WatchSyncCoordinator.swift 47 / 198 (24%)
- Evidence: `apply(_:)` L129 0/32, `activeChanged` L82 0/16, `session(_:didReceive:)` L196 0/15, `didReceiveUserInfo` L218 0/9, `pushContext` 7/18. Shared/WatchSync reducer is 96.5% and WatchSyncReducerTests exists, so the pure reducer is fine. All five PhaseTrainingWatch app files are 0% (WatchSessionModel 0/204, WatchWorkoutController 0/106, MotionRecorder 0/77, WatchRestTimer 0/49, PhaseTrainingWatchApp 0/414); the Watch target has no unit test host.
- Risk: a set logged on the watch that fails to apply to the phone session loses data. Sits under the reducer, so a reducer test passes while apply drops the result.
- Suggested test: drive `apply` with reducer output against an in-memory SessionStore; replay duplicate and out-of-order messages.
- Effort: 4 h for phone side; Watch target needs a test target, 6+ h.

### 8. HealthKit: HealthKitImporter.swift 166 / 409 (41%), PhysiologyReader.swift 25 / 188 (13%)
- Evidence: every `HKHealthStoreWrapper` query (recentWorkouts L161, recentBodyMetrics L210, fetchSamples L249) is 0%. PhysiologyReader.samples L51, quantities L75, sleepSamples L93 and PhysiologyCapture.connect L182, refreshIfEnabled L196 are 0%. HealthKitImporterTests covers the mapping on the protocol side. The readiness inputs (sleep, HRV, resting HR) flow through PhysiologyReader, which feeds ReadinessSignal (96% covered, but only with injected values).
- Risk: unit conversion or predicate mistakes change the readiness number and therefore the suggested weights. The wrapper is thin but untested.
- Suggested test: protocol fake at the wrapper seam for PhysiologyReader (it takes a `store:` parameter already); assert unit conversion, sleep stage bucketing, date windowing. Real HK queries need a device and stay out of scope.
- Effort: 3 h.

### 9. BackupCoordinator 0 / 73 (restore and erase)
- Evidence: `handleImport` L55 0/20, `performRestore` L84 0/13, `eraseAllData` L121 0/11, `exportBackup` L44 0/10, `exportWorkoutsCSV` L34 0/9. BackupManager (the engine) is 90% covered, and BackupPlanStateTests exists.
- Risk: erase must span UserDefaults and SQLite (skill phase-training-wipe-spans-userdefaults-and-sqlite). The coordinator is the one place that calls all stores, so an added store that is forgotten here is not caught. Data loss on restore is the worst user outcome in this list, though the code is low churn.
- Suggested test: populate each store, `eraseAllData`, assert every store and the UserDefaults keys are empty; round trip export then restore.
- Effort: 3 h.

### 10. UserDatabase routines and migration edges
- Evidence: `UserDatabase.routine(id:)` L49 0/16, `delete(routineId:)` L152 0/15 (UserDatabase+Routines 75%); UserDatabase.swift 98 / 120 (82%); CustomRoutineStore 17 / 37; BundledRoutineRow 11 / 80. UserDatabaseMigrationTests exists and the Data layer is otherwise 91-100%.
- Risk: moderate. Deleting a routine that a plan day references is the untested case.
- Suggested test: delete a routine referenced by a plan day and by a session; reload.
- Effort: 2 h.

### 11. Remaining thin logic outside views
- TrainingMemory.swift 403 / 530 (76%): uncovered are display getters (Equipment.icon 0/18, TrainingGoal.subtitle, SportVariant.disciplineSubtitle). Low risk.
- ExerciseFilters.swift 166 / 276 (60%): uncovered are tile label and symbol getters (LibraryTile, WorkoutGoalTile, WorkoutSportTile.symbol 0/54). Filter composition itself is covered (FilterCompositionTests). Low risk; a test that every enum case has a non-empty label and a valid SF symbol name costs 1 h.
- InsightGenerator 34 / 139, WeeklyReminderScheduler 31 / 112, SessionLocationCapture 8 / 90, GeneratorStrategy 7 / 20, ProfileField 22 / 61, CoachContext+MovementBlocks 48 / 122 (39%). The last one builds prompt text from movement data; a wrong block misleads the coach, so it is the pick of this group (2 h).
- Effort for the group: 6 h.

### 12. SwiftUI screens at 3.4%
- Evidence: 47,722 executable lines, 1,606 covered. Largest: LibraryScreen 1,771 uncovered, ProfileScreen 1,715, ExerciseDetailSheet 1,376, LogScreen 1,357, WeekScreen 1,293, CompleteScreen 1,231, CoachDrawer 1,217, TodayScreen 510 of 1,146.
- Risk: expected for views; UI test target covers them but was not run (about 60 min). Logic embedded in views (LogSetRow 589 lines, RestTimerState 65 / 303, HoldTimerSheet 6 / 325, RestTimer 0 / 200, PlateCalculatorSheet 0 / 655) is untestable without extraction. PlateCalculatorSheet and RestTimerState hold arithmetic and timer state worth moving into tested types.
- Suggested test: extract plate math and rest timer state into pure types; test those. Do not chase view coverage.
- Effort: 5 h for plate calculator and rest timer.

## Checked and fine
- Generator, prescription, autoregulation, progression, mesocycle, season engine, support scheduler, PatternEngine and Twin (load model, prediction, diagnosis): all 87-100%.
- Previous round items (goal and readiness dimensions in FilterCompositionTests) have not regressed; suite is green.
- UserDatabase sessions, imports and import-name matching: 91-100%.
- Persistence migration has a dedicated test file (UserDatabaseMigrationTests); BackupManager 90%.
- Shared watch reducer, models and motion code: 96-99%.
- Subscription gating (Coach, Support, surface gating) has test files; only purchase and restore transactions are thin (finding 6).
- No hardcoded dev-path failures: the two skips are fleet tools, no mktemp errors in the log.
- Count caveat: 1739 executed tests, the log's final summary; no flake signature (IOSurface) seen on this run.
