# Feature gap analysis

Date: 2026-11-10. Commit: bb17ca1 (build 171). Analysis: feature gap.

Method: inventoried `PhaseTraining/Screens`, `Components`, `Data`, `Health`, `Imports`, `Coach`, `PhaseTrainingWatch`, `Shared` and `Project.yml`. Ran the 11-item probe from `phase-training-feature-gap-checklist` plus the stumbled-upon list, then grepped each candidate by several names before classifying. Read-only; no code was changed. The two root-level gap docs, `docs/PLAN-gap-backlog-2026-11.md` and older audits were used as pointers only. The 20 items shipped from the 2026-10-31 backlog were not re-raised.

Classes: SHIPPED, REACHABILITY GAP (exists, hard to find), PARTIAL, MISSING.

What the app ships today (verified against `Project.yml`): three targets of substance, the iPhone app (`Project.yml:62`, `TARGETED_DEVICE_FAMILY: "1"` at :153), the watchOS app (`Project.yml:180`) and test bundles (:222, :237). There is no widget, Live Activity, App Intents or iPad target.

## Findings ranked by impact

### 1. Warm-up ramp is prescribed by the generator and never reaches Log (PARTIAL)

Evidence:
- `WorkoutGenerator.swift:233-240` builds a 3-step ramp (40%, 60%, 80% of working load) for the first compound lift when the muscle is not sore.
- `WeekPlan.swift:197-201` stores it as `warmUpSets` on `GeneratedExercise`.
- `WeekPlan.swift:270-285` (`toWorkoutTemplate`) builds `ExerciseTemplate` without `warmUpSets`. A repo-wide grep for `warmUpSets` finds no reader outside `WeekPlan.swift`, `WorkoutGenerator.swift` and the 3-line doc comment that names the eval-rig exporter.
- The only warm-up UI is the manual "Mark as warmup" toggle (`LogSetRow.swift:145`, `EditSessionSheet.swift:149`).

User-visible effect: the plan logic says "ramp up" but Log shows only working sets. The lifter adds ramp sets by hand on the heaviest lift of the day, then flips each to warmup.

Suggested fix: when a session starts from a generated template, insert the ramp rows (`isWarmup = true`, weights from the first working set's suggestion times `loadPctOfWorking`) ahead of the working sets, and carry `warmUpSets` through `ExerciseTemplate`. Gate with the existing PR/volume filters, which already skip warmups. Needs a Codable-optional field per the existing rule.

Effort: 5 to 7 hours including a test that the ramp is excluded from PR and volume math.

### 2. No automatic backup or sync; backup is a manual file export (MISSING)

Evidence:
- `BackupManager.swift:1-9` states it is "Not a sync mechanism" and that a CloudKit approach was left out.
- Entry point is Profile, Data row (`ProfileScreen.swift:253`), then share sheet (`BackupCoordinator.swift:21-40`). Grep for `autoBackup|scheduledBackup|lastBackupDate|iCloudBackup|CloudKit|ubiquity` finds only the comment above.
- Data lives in `Documents/user.db` (`UserDatabase.swift:30`), which the OS includes in an iCloud device backup unless the user turned that off. The app does nothing to reduce the exposure if they have.

User-visible effect: a lifter with years of history who never opened Profile > Data has one copy. There is no prompt, no "last backed up" date, and no second-device sync.

Suggested fix, cheapest first: (a) show "Last exported" on the Data row and a nudge after N new sessions (2 to 3 hours); (b) write the existing envelope to the app's iCloud Drive container on a weekly schedule via `BGAppRefreshTask` (about 1 day); (c) full CloudKit sync is a multi-week project and is not recommended before (a) and (b).

Effort: 3 hours for (a), 8 hours for (b).

### 3. Rest timer ends at a notification; nothing on the Lock Screen or Dynamic Island (MISSING)

Evidence:
- Rest expiry is a `UNTimeIntervalNotificationTrigger` (`RestTimerState.swift:104-112`, `.timeSensitive`).
- `Project.yml` has no widget extension. Grep for `ActivityKit|LiveActivity|WidgetKit|AppIntent` across all three source roots returns nothing. `Info.plist` has no `NSSupportsLiveActivities`.

User-visible effect: while the phone is locked between sets, the lifter sees no countdown and no current-exercise context. They get one banner at expiry. Strong, Hevy and Fitbod all show a Lock Screen rest countdown, and it is the most visible gap during an actual workout.

Suggested fix: a widget extension target with a Live Activity (exercise name, set n of m, rest countdown, "Done set" via App Intent). The rest state already lives in `RestTimerState`; the work is the new target, a shared attributes struct and `pbxproj` plumbing (see `phase-training2-gitignored-pbxproj`). The same target gives a home-screen "Today's workout" widget at low extra cost.

Effort: 14 to 20 hours for the Live Activity, 6 more for a Today widget.

### 4. No "repeat this workout" or "save as routine" from a finished session (MISSING)

Evidence:
- `CompleteScreen.swift` actions are Done, feedback and Discard only (`:513`, `:539`, `:554`).
- History rows offer only "Edit session" (`HistoryScreen.swift:257`).
- "Save to library" exists only on the Today template editor (`TodayScreen+TemplateEditor.swift:290`), the day preview (`DayWorkoutPreviewSheet.swift:490`) and the coach request screen (`CoachRequestScreen.swift:533`). Each builds a `CustomRoutine` from a template, never from a `SavedSession`.
- Grep for "save as routine|repeat workout|startFromSession" finds nothing.

User-visible effect: a lifter who improvised a good session, or who wants to run last Tuesday's workout again, has to rebuild it exercise by exercise.

Suggested fix: a "Repeat" and "Save as routine" action on the expanded History row and on the Complete screen. `CustomRoutine(...)` construction already exists three times and takes exercise name, sets, reps, rest and superset group. Native sessions only; imported sessions can sit behind the same action once names are matched.

Effort: 4 to 5 hours.

### 5. Cannot create a custom exercise (MISSING)

Evidence:
- The only exercise source is the bundled catalog (`ExercisePickerSheet.swift:1`, "searchable picker over coach.db exercises"). `Resources/coach.db` is read-only (`UserDatabase.swift:5`). Grep for custom or new exercise creation finds no creation UI. `ExerciseEditorSheet` edits the sets, reps and rest of an exercise already in a template (`TodayScreen.swift:209`).
- `UnmatchedNamesSheet` lets an imported name be mapped to a catalog exercise or ignored, but cannot add one.

User-visible effect: a lift outside the 582-row catalog (a gym machine with a brand name, a rehab drill) cannot be logged on its own terms. Import "ignore" drops it from the strength view entirely.

Suggested fix: a `user_exercises` table in `user.db` (name, equipment, primary muscle, unit type) merged into `CoachDatabase.exercises()` results, with an "Add custom exercise" row at the bottom of the picker's empty state and on `UnmatchedNamesSheet`. Needs care so the generator never picks a user row without taxonomy data (see `phase-training-coachdb-add-exercise-source-pipeline`).

Effort: 10 to 14 hours.

### 6. Superset creation exists only inside the custom routine editor (REACHABILITY GAP)

Evidence:
- Log renders supersets (`LogExerciseBlock.swift:23`, `:255`) and the round logic (`LogScreenHelpers.swift:171`).
- Users can create or break a group only in `CustomRoutineEditSheet.swift:274-340`. The generator assigns antagonist pairs (`WeekPlan.swift:203-208` comment). No control in Log or in `DayWorkoutPreviewSheet`.

User-visible effect: mid-workout, when a gym is crowded and the lifter wants to pair two exercises, there is no way to do it.

Suggested fix: "Superset with next" in the exercise context menu in Log (`LogExerciseBlock.swift:87-107` already holds that menu) and in the preview sheet.

Effort: 3 hours.

### 7. Only one set type: warmup. No drop set, failure or AMRAP flag (PARTIAL)

Evidence: the only per-set classification is `isWarmup` (`LogSetRow.swift:41`, `:145`). "AMRAP" appears only as a free-text reps label (`WeekPlan.swift:185`, `CoachTools.swift:66`). The CSV exporter writes `W` or a running number only (`WorkoutCSVExporter.swift:35`).

User-visible effect: failure sets and drop sets are indistinguishable from normal working sets in History, PR logic and volume. Imported Hevy and Strong set types are flattened on the way in.

Suggested fix: replace the Bool with a small `setType` enum (normal, warmup, drop, failure) using the existing Codable-optional rule, a long-press menu on the set row, and "ignore for PR" on drop sets. Warmup stays the only type excluded from volume; failure counts.

Effort: 8 to 10 hours including the user.db migration and export mapping.

### 8. History has no search and no filter except by exercise from a drill-in (THIN UI)

Evidence: `HistoryScreen.swift` has no `.searchable` and no date or tag filter. The only filter is `initialExerciseFilter` (`:11-31`), reached from an exercise's action sheet (`TodayScreen.swift:264`, `DayWorkoutPreviewSheet.swift:131`, `CoachRequestScreen.swift:141`). The session tag field written on the Complete screen (`CompleteScreen.swift:405`) is not a filter.

User-visible effect: finding "that heavy squat day in March" means scrolling the accordion list.

Suggested fix: `.searchable` over session name, exercise names and note text, plus a tag chip row. All fields are already in memory in `displaySessions`.

Effort: 3 to 4 hours.

### 9. No progress photos (MISSING)

Evidence: body weight and body composition are logged (`BodyWeightLogSheet.swift`, `BodyCompositionLogSheet.swift`; `BodyCompositionEntry.swift:19-25` holds body fat, lean mass, method, note). Grep for `PhotosPicker|UIImagePickerController|progressPhoto` finds nothing. No girth or tape measurements either.

User-visible effect: body-composition goals (the entries above feed them) have numbers but no visual record.

Suggested fix: store photos in the app container (not the Photos library, to match the privacy stance), a dated grid under the body-composition card, a side-by-side compare. Exclude the folder from the JSON backup or include it as a separate archive.

Effort: 10 to 12 hours. Lower priority than 1 to 8 for a lifting app; included because every comparable tracker has it.

### 10. No automatic deload or mesocycle structure (PARTIAL, known)

Evidence: `TodayScreen+Derived.swift:153-157` says DELOAD appears only when the user picks the Recovery week tone and that "there's no auto-scheduled mesocycle deload to read". `WeekScreen.swift:801` describes Recovery as "~30% fewer sets". The planner does have `MesocycleProgression.swift`, `PlanArc.swift` and `CNSBudgetEngine.swift`, and `phase-training-periodization-model-no-auto-deload` records the decision.

User-visible effect: the app named for phases leaves deload timing to the lifter. A suggestion card ("fourth hard week in a row, take a recovery week?") would use signals that already exist (`SkipStreakDetector`, readiness, `WeeklyCheckInFlow` intents at `:43`).

Suggested fix: surface a one-tap suggestion in the weekly check-in after 3 consecutive build weeks with falling readiness or RPE creep. Do not schedule automatically.

Effort: 6 to 8 hours. Only worth doing after the owner confirms the earlier no-auto-deload decision still stands.

### 11. Apple Health is read-mostly: no body weight or body fat write-back (PARTIAL)

Evidence: body mass, physiology and workout reads request `toShare: []` (`HealthKitImporter.swift:152`, `:206`; `PhysiologyReader.swift:45`). Only workouts are shared (`HealthWorkoutWriter.swift:100`).

User-visible effect: weights logged in-app do not appear in Health, so other apps and the Health summary stay stale.

Suggested fix: write `bodyMass` and `bodyFatPercentage` on save, with a Health & Imports toggle (default off) and a sync identifier to avoid duplicates, mirroring what `HealthWorkoutWriter` already does for workouts.

Effort: 4 hours.

### 12. English only; iPhone only (MISSING, scope decision)

Evidence: `Localizable.xcstrings` holds 451 keys with `en` as the only localization; `TARGETED_DEVICE_FAMILY: "1"` (`Project.yml:153`). Plate sets support both lb and kg (`PlateCalculatorSheet.swift:321`) and the unit toggle is in About You (`AboutYouEditorSheet.swift:69`).

User-visible effect: no non-English store listing; no iPad layout. Only matters if the growth plan targets those.

Effort: iPad compatibility pass 8 to 16 hours; translation depends on languages chosen. Not recommended before items 1 to 8.

### 13. Smaller items

- Workout summary share card (Complete screen). `ShareSheet` is used only for backup and CSV export (`ProfileScreen.swift:387`). Effort 4 hours.
- No Siri, Shortcuts or App Intents ("Start today's workout"). Grep for `AppShortcut|INIntent|AppIntent` is empty. Pairs with item 3. Effort 5 hours.
- No Apple Watch complication; the watch app is otherwise full (`PhaseTrainingWatchApp.swift:165-172` weight and rep steppers, `WatchRestTimer.swift`, HK workout session). Effort 5 hours after item 3.

## Checked and fine

Do not re-raise these without evidence of a regression.

- 1RM projection (Epley): `StrengthStandards.swift`, shown per lift in `ExerciseStrengthSection.swift:45` (struct `ExerciseStrengthView`, presented from the exercise detail sheet) and on `ProgressScreen+GoalCards.swift`.
- PR detection and PR badge: `store.allPersonalRecords` (`ProgressScreen.swift:106`), `PRPill` on the Complete summary (`CompleteScreen.swift:346`, `ExerciseTile.swift:244`).
- Per-muscle volume: `MuscleVolume` rows rendered as bars (`ProgressScreen+BodyCards.swift:319`); weekly volume chart (`ProgressAggregates.swift:57`).
- Muscle recovery and anatomical view: `MuscleFreshness.swift`, `BodyAnatomyView.swift`, `TodayRecoveryCard.swift`, `ProgressRecoverySection.swift`.
- Progressive overload suggestion pill using RPE and RIR: `ProgressionSuggestion.swift`, shown at `LogExerciseBlock.swift:311`.
- RPE and RIR logging at set level (`LogSetRow.swift:286`), warmup flag (manual), per-exercise notes with last note carry-over (`LogExerciseBlock.swift:140-145`).
- Rest timer in app with +15 and skip plus expiry notification (`RestTimerState.swift`, `Components/RestTimer.swift`). Only the Lock Screen surface is missing (item 3).
- Plate calculator reachable from Log's barbell context menu (`LogExerciseBlock.swift:99-103`) and Profile (`ProfileScreen.swift:218`).
- Hold and interval timer, max-hang test, ski readiness test, ski discipline picker: `HoldTimerSheet.swift`, `MaxHangTestSheet.swift`, `SkiReadinessTestSheet.swift`, `SkiDisciplineSheet.swift`.
- Exercise substitution mid-workout (`LogExerciseBlock.swift:67`, `:87`), mid-workout Add exercise (`LogScreen.swift:304-315`), per-set add and delete (`LogExerciseBlock.swift:208-219`).
- Exercise video and attribution: `ExerciseDetailSheet.swift:302` renders `videoURL`.
- In-progress session survives a kill: persisted under `pt_active_session` (`BackupManager.swift:235`).
- Import from Fitbod, Hevy and Strong, unmatched-name mapping, CSV export in Strong format: `Imports/`, `UnmatchedNamesSheet.swift`, `WorkoutCSVExporter.swift`.
- Body weight and body composition logs with trend charts, goals and milestone notifications, reminders, inactivity nudges: `BodyWeightLogSheet.swift`, `GoalMilestoneNotifier.swift`, `NotificationSettingsScreen.swift`.
- Watch app: companion with Start, set logging, rest timer and HK workout session; sync reducer in `Shared/WatchSync`. The 2026-09-10 gap docs claiming there is no Watch app are out of date.
- Debug-only surfaces confirmed as such: "Regenerate muscle chips" and "Signals & shadow twin" sit under `#if DEBUG` (`ProfileScreen.swift:261`, `:372`). `SetupChecklistSheet` is outside the `#if DEBUG` block (`ProfileScreen.swift:370`).

## Summary table

| # | Finding | Class | Hours |
|---|---|---|---|
| 1 | Generated warm-up ramp never reaches Log | PARTIAL | 5 to 7 |
| 2 | No automatic backup or sync | MISSING | 3 to 8 |
| 3 | No Lock Screen rest timer or widgets | MISSING | 14 to 26 |
| 4 | No repeat or save-as-routine from a session | MISSING | 4 to 5 |
| 5 | No custom exercise creation | MISSING | 10 to 14 |
| 6 | Superset creation only in routine editor | REACHABILITY GAP | 3 |
| 7 | Only warmup set type | PARTIAL | 8 to 10 |
| 8 | History search and filters | THIN UI | 3 to 4 |
| 9 | Progress photos | MISSING | 10 to 12 |
| 10 | Auto deload suggestion | PARTIAL | 6 to 8 |
| 11 | Health write-back for body metrics | PARTIAL | 4 |
| 12 | Localization and iPad | MISSING | 8 to 16+ |
| 13 | Share card, Shortcuts, complication | MISSING | 14 |
