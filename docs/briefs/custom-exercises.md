# Brief: custom exercises, finishing pass (slot A)

## Backlog item

`docs/PLAN-gap-backlog-2026-11b.md`, Phase 6: "Custom exercises in `user.db`, never picked by the generator". Done when a custom exercise can be added from the picker's empty state, logged, shown in History and exported, and a generator sweep never picks one.

## State you start from

The feature is already written in the working tree and is uncommitted. Do not rewrite or restructure it. Design, for orientation only:

- `user.db` v11 adds `user_exercises` (`UserDatabase.swift`, `UserDatabase+UserExercises.swift`).
- A custom exercise surfaces as an `Exercise` with a negative id (`-rowId`). `CoachDatabase` stays catalog-only, which keeps the generator, season engine and authored routines from picking one.
- Only `ExerciseSearch.run` (picker) and `ExerciseLookupCache` (display) read the table.
- Backup envelope v3 carries the rows with their ids; restore, rollback and erase clear the table.
- `LoggedExercise.equipmentCategories(forExerciseIds:)` gives a custom exercise a weight field.
- `CoachDatabase` read sites log SQLite errors under `[coach-db]`, and an import index that builds empty is left uncached.

An earlier pass ran these on the current data code, all passing: `ExerciseSearchCustomTests` 11, `ExerciseShorthandLookupTests` 8, `WorkoutDiffBuilderTests` 9, `EraseAllDataTests` 4, `UserDatabaseMigrationTests` 7. You rerun them below because your build is fresh.

## Skill to load

`phase-training-xcodebuild-test-failed-grep-full-log`, and `phase-training-xcuitest-recipe` before the UI test.

## The one code change

File: `PhaseTraining/Screens/LogScreen.swift`, `appendExerciseFromPicker` (about line 705).

Problem: an exercise with no modality (every custom exercise) gets `type: picked.modalityLabel`, which is "-", and `LogExerciseBlock.swift:52` renders it as "Zorblax Cable Twist (-)".

Change: pass `nil` for `type` when `picked.modality` is nil or empty, and `picked.modalityLabel` otherwise. The swap path at `LogScreen.swift:268-272` already guards the same way; match it. Touch nothing else in the file.

If `CustomExerciseUITests` can assert the header without new accessibility identifiers, add an assertion that no static text containing "(-)" exists on Log after the custom exercise is added. If it needs a new identifier, skip the assertion and say so in the report.

## Simulator and DerivedData (slot A, yours alone)

- Simulator: iPhone 17 Pro, UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`
- Every `xcodebuild` call passes `-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'` and `-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A`.
- Project `PhaseTraining.xcodeproj`, scheme `PhaseTraining`. `xcodegen generate` was run at 01:10 on 2026-11-13; do not run it again unless you add a Swift file.
- Another agent is running tests on a different simulator (slot B) with its own DerivedData. Do not touch UDID `0929A7A4-66C6-454B-873E-F8349E2FD397` or `DerivedData-B`. It makes no code edits.
- Logs go to `/private/tmp/claude-501/-Users-wilburpyn-repos-phase-training2/70a1458d-7c05-430d-a289-1a60eacca44c/scratchpad/slot-a/` (create it), one file per run.

## What done looks like

1. The change above is made.
2. `xcodebuild build-for-testing` succeeds once.
3. Each class below is run on its own with `test-without-building -only-testing:PhaseTrainingTests/<Class>`, one at a time, and passes:
   - `ExerciseSearchCustomTests`
   - `ExerciseShorthandLookupTests`
   - `WorkoutDiffBuilderTests`
   - `EraseAllDataTests`
   - `UserDatabaseMigrationTests`
   - `BackupCoordinatorTests`
   - `BackupManagerTests`
   - `UserExerciseStoreTests`
   - `GeneratorWeekInvariantTests`
   - `PickedExerciseCategoryTests`
   - `CustomExerciseOfferTests`
4. `-only-testing:PhaseTrainingUITests/CustomExerciseUITests` passes (one test, about 2 minutes).
5. For every log, run `grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" <log>` and `grep -n "\[coach-db\]" <log>`.

On a failure: copy the failing lines and any `[coach-db]` line verbatim into the report, rerun that one class once, record the second result, and carry on with the rest. Do not change code to make a failing test pass. A failure whose assertion is a catalog read coming back empty (no exercise found, alias not resolved) is a known intermittent under measurement on slot B; report it the same way.

## Out of scope

Everything outside `appendExerciseFromPicker` and the optional UI test assertion. No commit, no push, no build number change, no backlog edits.

## Report

One final report, no interim messages: files changed, a table of class, tests, failures, any `[coach-db]` lines verbatim, decisions made on anything this brief left open, and anything noticed outside scope.
