# Gap backlog, November 2026

From the eight gap analyses run 2026-10-31 (feature, signals, competitive,
reach, screen critique, accessibility, generator eval, coverage). Work the
phases in order and tick items as they ship. Estimates come from reading the
code, not from measurement.

## Phase 1: quick fixes (one build, about half a day)

- [x] Commit the midnight-UTC fixture fix in `ActivityDetectionTests.swift`, so main goes green.
- [x] Stop scrolled content running under the status bar on Progress and Profile, where text collides with the clock.
- [x] Remove dashes from about 38 user-facing strings.
  - Examples: `TrainingMemory.swift:557` "Stay strong — no peak in mind", `PlanValidator.swift:165`, `MissedWorkoutBanner`, `CheckInMissedScreen`.
- [x] Raise `ink3` to at least 4.5:1 on `surface`. It measures 4.40:1 today, under the AA minimum for small text.
- [x] Add VoiceOver labels to icon-only buttons:
  - the onboarding back chevron;
  - `WorkoutCategoryScreen`, `TodayScreen+TemplateEditor`, `DayWorkoutPreviewSheet`, `PlanDiffSheet` and `InsightCard`.

## Phase 2: reach (one build, about 2 hours)

- [x] Show the history check without a CSV import.
  - It is gated in `CSVImportSection.swift:42`.
  - It should appear whenever the profile has flags or breaks, so native-only lifters see typo flags, breaks and the detraining rate.
- [x] Open the plate calculator from a barbell set in Log. Today it is reachable only from Profile.

## Phase 3: safety net (tests only, no build, about half a day)

This phase comes before Phase 4 because Phase 4 changes the weights the app suggests.

- [x] Add goal and readiness dimensions to `FilterCompositionTests`.
- [x] Add direction (metamorphic) gates for the season engine:
  - strength goal reps <= size reps <= endurance reps;
  - readiness 0 sets <= readiness 1 sets.
- [x] Raise `ExerciseFilters.swift` coverage from 49%. (Correction: it is the Library browse model, not the safety filter. The safety filter is covered by the composition grid. Added three tile invariants.)
- [x] Add `CoachClient.swift` tests for error and timeout paths. Coverage is 2.8% today.

## Phase 4: lifting features (two builds)

Found while planning: logged RIR was never saved (`session_sets` had no column). Migration v5 fixes it from this build on; earlier RIR is gone.

- [x] **Logged RPE and RIR steer the next weight (about half a day).**
  - RIR of 3 or more, or RPE of 7 or less: take a bigger step.
  - RIR 0, or RPE 9.5 or more: hold the weight.
  - Reads `LoggedSet.rpe`/`.rir` in `ProgressionSuggestion`. Imported Hevy RPE comes along for free.
- [x] **Per-exercise notes (about half a day).**
  - Add an Optional `note` field to `LoggedExercise` (`Shared/Models/SessionModels.swift:125`), following the Codable rule for added fields.
  - Show it on the next session of that exercise.
  - Import Hevy `exercise_notes`.

## Phase 5: bigger bets (each gets its own plan first)

- [x] **CSV export (about 1 day).** Write a CSV that Hevy or Strong can import, so portability works both ways.
- [x] **Climbing tools (several days).** Shipped as a hold/interval timer on any timed set plus a max-hang test log (Progress card). Not yet: the test driving hangboard loads.
  - A hangboard and interval timer.
  - A finger-strength test log feeding the existing finger-strength demands in `SportSeason/*`.
  - Benchmarks: Crimpd and Lattice.
- [x] **Ski lead (scoping session first).** Scoped 2026-11-01. Finding: the season engine already carries four ski disciplines (inbounds, backcountry adds uphill aerobic, skimo caps heavy strength, park adds power and knee stability; `PhaseRule.applyingVariantOverride`), but `SportSeasonGenerator.defaultVariant` returns `.inbounds` for every skier and the "M4 variant UI" (`AthleteState.swift:130`) never shipped, so a ski-mountaineering primary trains like a resort skier. Competitors found: static dryland plans only. Picked for Phase 6.

## Phase 6: ski lead (one build each, in order)

- [x] **Ski discipline picker (about half a day).** Inbounds / backcountry / skimo / park in the onboarding season step and Profile; ski-mountaineering defaults to skimo. UI over an engine that already exists.
- [x] **Pre-season ski test (about 1 day).** A benchmark battery (wall-sit time, single-leg balance, lateral bounds, broad jump) with a Progress "SKI READINESS" card, mirroring the max-hang test.
- [x] **Ski days from Apple Watch (about 1 day).** This season's ski days from detected ski workouts, plus vertical if Health stores it (unverified), as a Progress card.

Phase 6 shipped in build 167 (2026-11-04). Vertical reads `HKMetadataKeyElevationDescended`; unconfirmed until a real watch ski day.

Not picked: snowpack-aware season start from snow-almanac. It needs a server, and the app has none by its privacy stance.

## Not scheduled

- Ease volume after hard days: already shipped as `Planner.applyRecentSignalBias`.
- Re-run the shadow twin replay on `workout-plan/data/fitbod-history.csv`, which runs to 2026-03-10. Do this only before any readiness work.
- `LoggedExercise.rpe`, `tempo` and `supersetGroup` are not saved to SQLite (same class as the RIR bug). Low priority: nothing reads them from a saved session today (Log reads the active session, the coach reads the generated week). Fix with a migration if History or a repeat-workout flow ever needs them.
