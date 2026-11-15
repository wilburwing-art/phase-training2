# Brief: screen polish, the Profile row list and the Library muscle tiles

Backlog item: `docs/PLAN-gap-backlog-2026-11b.md`, "Later, not scheduled": "Screen polish from `screens.md`: Week header stack, Library muscle icons, Profile 23-row list, Log tab bar under the music card." This brief covers the Profile and Library parts. Audit findings: `audits/2026-11-10-gap-round/screens.md`, Profile 2 and Library 1 and 2. Screenshots: `audits/2026-11-10-gap-round/screens/08-profile.png` and `03-library.png`.

Agent: builder. Skills to load first: `phase-training2-gitignored-pbxproj`, `phase-training-xcodebuild-test-failed-grep-full-log`, `phase-training-xcuitest-recipe`.

Slot B. Every `xcodebuild` call passes both:

```
-destination 'platform=iOS Simulator,id=0929A7A4-66C6-454B-873E-F8349E2FD397'
-derivedDataPath ~/Library/Developer/Xcode/DerivedData-B
```

A second builder is working in this same checkout on slot A. Its files are `WeekScreen.swift`, `PlanAssumptionsRow.swift`, `PlanValidationBanner.swift`, `LogScreen.swift`, `NowPlayingCard.swift` and the Week and Now Playing UI tests. Do not edit those. If your build fails with an error in one of them, the other builder is mid-edit: run the build again, up to five times, before reporting it.

## Files to touch

- `PhaseTraining/Screens/ProfileScreen.swift`
- `PhaseTraining/Screens/ProfileScreen+RowSummaries.swift`
- `PhaseTraining/Screens/LibraryScreen.swift`
- `PhaseTraining/Data/ExerciseFilters.swift` (`LibraryTile` only)
- `PhaseTraining/Components/MuscleChipBadge.swift`
- `PhaseTrainingTests/LibraryTileInvariantTests.swift`
- `PhaseTrainingUITests/ProfileGoalUITests.swift`, and any other UI test that taps a Profile row this brief removes

## Part 1: Profile row list

### Problem

Profile is one scroll of 20 always-on rows (25 with every conditional row). Five of them, "Session length", "Lift days", "Equipment", "Experience" and "Training focus", edit the same fields as the "Plan setup" row directly above them, which opens `SetupChecklistSheet` with Schedule, Equipment, Experience, Goal and Past workouts. "TOOLS" is a group of one row.

### Design

Four groups plus the danger zone, in this order. Row labels, icons, values, sheets and conditions are as they are today unless stated.

**PLAN**
1. Plan setup (new value, below)
2. Sports
3. Discipline (only if `store.memory.skisPrimary`, as now)
4. Seasons
5. Support sport (same condition and paywall routing as now)
6. Performance goals

**BODY**
7. About you
8. Body weight
9. Body composition
10. Injuries

**EXERCISES**
11. Favorite exercises
12. Exercises to avoid
13. Plate calculator

**APP**
14. Reminders
15. AI Coach (`CoachSettingsRow`, same condition)
16. Health & Imports
17. Subscription (same condition)
18. Data
19. Privacy Policy
20. the two `#if DEBUG` rows

**DANGER ZONE**: unchanged.

Removed from Profile: the "Session length", "Lift days", "Equipment", "Experience" and "Training focus" rows. Their fields are edited from Plan setup. The header, the "Recommended for you" block and `dangerZoneSection` do not change.

**Plan setup row value.** `setupChecklistSummary` returns "N assumed" when any field is assumed (as now). When none is, it returns `store.memory.assumptionSummary(for: .availability)` ("3 lift days · 45 min") in place of "All set", so the row shows the two numbers the removed rows used to show.

**Dead code to delete in the same pass.** Everything the five removed rows were the only user of: the inline number alert for session length and lift days with its state, `beginEditing`, the commit function and `clampNotice` and its text; the `presenting...` state and `.sheet` for the Equipment, Experience and Goal editors on `ProfileScreen`; `liftDaysSummary`, `equipmentSummary`, `experienceSummary` and any other summary no row reads. Grep each symbol before deleting it and keep anything another file uses (`EquipmentEditorSheet`, `ExperienceEditorSheet` and `GoalEditorSheet` themselves stay: `ProfileFieldEditorHost` presents them). If `TrainingConstraints.sessionMinutesUIRange` or `liftDaysRange` lose their last caller, say so in the report and leave them; they sit beside planner constants.

One thing to check before deleting the alert: its commit marks `.availability` as stated. Confirm `AvailabilityEditorSheet` does the same when the lifter changes a stepper. If it does not, stop and report; do not edit `PlanAssumptionsRow.swift`.

### Tests

- `ProfileGoalUITests.test_pickStrengthGoal` taps a row beginning "Training focus". Re-route it: Profile, the row beginning "Plan setup", `setup-checklist-row-goal`, `goal-strength`, Done, then assert the checklist row shows "Strength". Keep what the test proves (picking Strength changes the stored goal and the UI shows it).
- Grep `PhaseTrainingUITests` for the five removed row titles ("Session length", "Lift days", "Equipment", "Experience", "Training focus") used as Profile rows and re-route each the same way. `OnboardingLandingUITests` reaches the equipment editor from the Week chip and needs no change.
- Run, one class at a time: `ProfileGoalUITests`, `SetupGoalHistoryUITests`, `SkiDisciplineUITests`, `SupportSportUITests`, `SportsEditorLastSportUITests`, `WorkoutCSVExportUITests`, `MotivationBatchUITests`, and the unit class `SetupChecklistGoalHistoryTests`.

### Out of scope

The "Recommended for you" block (audit Profile 3), the contents of `SetupChecklistSheet`, any editor sheet, the danger zone.

## Part 2: Library muscle tiles

### Problem

The seven muscle tiles use SF Symbols that show something else: Chest is a side-bend figure (`figure.cooldown`), Back a lunge, Quads a runner (`LibraryTile.symbol`, `ExerciseFilters.swift` around line 185). The symbols have different intrinsic heights, so tiles in one grid row start a few points apart.

The app already ships the right artwork: `Assets.xcassets/MuscleChips/<bucket>-<front|back>`, 22 template images rendered at 252pt (1x to 3x), a body with one muscle group drawn opaque. `MuscleChipBadge` draws them at 28pt on Today rows.

### Design

- In `MuscleChipBadge.swift`, pull the artwork (the asset lookup with its `BodyAnatomyView` fallback, template rendering, accent tint) out into a small internal view, `MuscleFigure(group: MuscleBucket, side: BodyAnatomyView.AnatomySide)`, that fills whatever frame it is given. `MuscleChipBadge` uses it and looks exactly as before. The file comment gains one line saying the Library tiles use the same artwork.
- In `LibraryTile`, delete `symbol` and add `var figureBucket: MuscleBucket`: chest → `.chest`, back → `.back`, shoulders → `.shoulders`, arms → `.biceps`, quads → `.quads`, hamsGlutes → `.glutes`, core → `.core`. The side is `figureBucket.naturalSide`.
- In `LibraryScreen.tileFace`, replace the `Image(systemName:)` with `MuscleFigure(group: tile.figureBucket, side: tile.figureBucket.naturalSide)` in a fixed `.frame(width: 56, height: 56)`, `.accessibilityHidden(true)`. Everything else on the tile stays. The fixed frame is what makes the two tiles of a row the same height; confirm in the simulator that they are.
- `workoutTileFace` (sport and goal tiles on the Workouts segment) keeps its SF Symbols. Give its symbol a fixed-height frame only if its rows show the same misalignment; say what you saw.

### Tests

- `LibraryTileInvariantTests`: add `test_everyTileFigureIsOneOfItsMembers` (each tile's `figureBucket` is in `tile.members`) and `test_everyTileFigureHasABundledImage` (`UIImage(named: "MuscleChips/<bucket>-<side>")` is non-nil for each tile; if the unit test bundle cannot see the app's asset catalog through the host app, say so and drop this one).
- Run `LibraryTileInvariantTests` and the UI class `ImageSlotScalingUITests` (it taps `library-tile-core`).

### Out of scope

New artwork, the Workouts tiles' symbols, `LibraryMuscleScreen`.

## Done

- App target builds on slot B.
- Every class listed under the two Tests headings passes.
- One screenshot each of Profile (top of the list, and scrolled to the APP group) and of the Library tab, taken on slot B after your change and saved under the scratchpad directory; give their full paths in the report.
- The report states the count of always-on Profile rows after the change.

Do not commit, push or bump the build. Return one final report: files changed, test classes run with pass and fail counts, decisions made on anything this brief left open, and anything you noticed outside its scope.
