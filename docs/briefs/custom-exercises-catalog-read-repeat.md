# Brief: catalog empty-read repeat measurement (slot B, tests only)

## Backlog item

`docs/PLAN-gap-backlog-2026-11b.md`, Phase 6: "Custom exercises in `user.db`". This brief covers one check that gates its commit. You make no code edits.

## Why

On 2026-11-13 two unit classes failed intermittently because reads of the bundled `coach.db` came back empty inside the test host: `ExerciseSearchCustomTests` (4 of 11 on the first run after a fresh install, then 55 of 55 over five iterations) and `WorkoutDiffBuilderTests` (1 of 9, in a test older than this work). `CoachDatabase.swift` now logs any SQLite error at its read sites with the prefix `[coach-db]` through `NSLog`. This run measures how often the failure happens and captures what the log line says.

## Skill to load

`phase-training-xcodebuild-test-failed-grep-full-log`.

## Files to touch

None in the repo. If the build fails to compile, report the error verbatim and stop.

## Simulator and DerivedData (slot B, yours alone)

- Simulator: iPhone 17 Pro B, UDID `0929A7A4-66C6-454B-873E-F8349E2FD397`
- Every `xcodebuild` call passes `-destination 'platform=iOS Simulator,id=0929A7A4-66C6-454B-873E-F8349E2FD397'` and `-derivedDataPath ~/Library/Developer/Xcode/DerivedData-B`.
- Project `PhaseTraining.xcodeproj`, scheme `PhaseTraining`. Do not run `xcodegen generate`.
- Another agent is building and testing on a different simulator (slot A) and will edit one line in `PhaseTraining/Screens/LogScreen.swift`. Do not touch UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2` or `DerivedData-A`.
- Logs go to `/private/tmp/claude-501/-Users-wilburpyn-repos-phase-training2/70a1458d-7c05-430d-a289-1a60eacca44c/scratchpad/slot-b/` (create it), one file per invocation, named `<Class>-<n>.log`.

## Steps

1. `xcodebuild build-for-testing` once.
2. Erase nothing and boot nothing by hand; let `xcodebuild` manage the simulator.
3. Run `xcodebuild test-without-building -only-testing:PhaseTrainingTests/ExerciseSearchCustomTests` as ten separate invocations, one after another. Separate invocations matter: each reinstalls the app, and `-test-iterations` did not reproduce the failure.
4. The same for `-only-testing:PhaseTrainingTests/WorkoutDiffBuilderTests`, ten separate invocations.
5. After each invocation, grep its log:
   - `grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" <log>`
   - `grep -n "\[coach-db\]" <log>`
   - `grep -E "Executed [0-9]+ tests" <log> | tail -1`

A shell loop is fine. Never run two invocations at once.

If the `[coach-db]` line does not show in the xcodebuild log for a failing invocation, also pull it from the simulator log for that time window:
`xcrun simctl spawn 0929A7A4-66C6-454B-873E-F8349E2FD397 log show --last 3m --predicate 'eventMessage CONTAINS "coach-db"'`

## What done looks like

All 20 invocations have run and each has a log. Failures do not stop the run and are not retried.

## Report

One final report, no interim messages:
- a table: class, invocation number, tests executed, failures;
- totals: invocations with at least one failure, out of 10, per class;
- every failing assertion line verbatim;
- every `[coach-db]` line verbatim, with the invocation it came from, or the statement that none appeared;
- anything else you noticed. No fixes, no commits.
