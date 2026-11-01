# Gap backlog, November 2026

From the eight gap analyses run 2026-10-31 (feature, signals, competitive,
reach, screen critique, accessibility, generator eval, coverage). Work the
phases in order and tick items as they ship. Estimates come from reading the
code, not from measurement.

## Phase 1: quick fixes (one build, about half a day)

- [ ] Commit the midnight-UTC fixture fix in `ActivityDetectionTests.swift`, so main goes green.
- [ ] Stop scrolled content running under the status bar on Progress and Profile, where text collides with the clock.
- [ ] Remove dashes from about 38 user-facing strings.
  - Examples: `TrainingMemory.swift:557` "Stay strong — no peak in mind", `PlanValidator.swift:165`, `MissedWorkoutBanner`, `CheckInMissedScreen`.
- [ ] Raise `ink3` to at least 4.5:1 on `surface`. It measures 4.40:1 today, under the AA minimum for small text.
- [ ] Add VoiceOver labels to icon-only buttons:
  - the onboarding back chevron;
  - `WorkoutCategoryScreen`, `TodayScreen+TemplateEditor`, `DayWorkoutPreviewSheet`, `PlanDiffSheet` and `InsightCard`.

## Phase 2: reach (one build, about 2 hours)

- [ ] Show the history check without a CSV import.
  - It is gated in `CSVImportSection.swift:42`.
  - It should appear whenever the profile has flags or breaks, so native-only lifters see typo flags, breaks and the detraining rate.
- [ ] Open the plate calculator from a barbell set in Log. Today it is reachable only from Profile.

## Phase 3: safety net (tests only, no build, about half a day)

This phase comes before Phase 4 because Phase 4 changes the weights the app suggests.

- [ ] Add goal and readiness dimensions to `FilterCompositionTests`.
- [ ] Add direction (metamorphic) gates for the season engine:
  - strength goal reps <= size reps <= endurance reps;
  - readiness 0 sets <= readiness 1 sets.
- [ ] Raise `ExerciseFilters.swift` coverage from 49%. It decides equipment and injury exclusions.
- [ ] Add `CoachClient.swift` tests for error and timeout paths. Coverage is 2.8% today.

## Phase 4: lifting features (two builds)

- [ ] **Logged RPE and RIR steer the next weight (about half a day).**
  - RIR of 3 or more, or RPE of 7 or less: take a bigger step.
  - RIR 0, or RPE 9.5 or more: hold the weight.
  - Reads `LoggedSet.rpe`/`.rir` in `ProgressionSuggestion`. Imported Hevy RPE comes along for free.
- [ ] **Per-exercise notes (about half a day).**
  - Add an Optional `note` field to `LoggedExercise` (`Shared/Models/SessionModels.swift:125`), following the Codable rule for added fields.
  - Show it on the next session of that exercise.
  - Import Hevy `exercise_notes`.

## Phase 5: bigger bets (each gets its own plan first)

- [ ] **CSV export (about 1 day).** Write a CSV that Hevy or Strong can import, so portability works both ways.
- [ ] **Climbing tools (several days).**
  - A hangboard and interval timer.
  - A finger-strength test log feeding the existing finger-strength demands in `SportSeason/*`.
  - Benchmarks: Crimpd and Lattice.
- [ ] **Ski lead (scoping session first).** No adaptive season-aware ski app was found. Decide what widens the lead before building.

## Not scheduled

- Ease volume after hard days: already shipped as `Planner.applyRecentSignalBias`.
- Re-run the shadow twin replay on `workout-plan/data/fitbod-history.csv`, which runs to 2026-03-10. Do this only before any readiness work.
