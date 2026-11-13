# Brief: UI test for the arc deload notice (slot A)

Third brief for the Phase 7 item (`docs/briefs/arc-deload-label.md`, `docs/briefs/arc-deload-label-followup.md`). The logic is reviewed and accepted. The lead's simulator walk confirmed the Today eyebrow reads "MAINTENANCE · DELOAD" with `arcDeload = applied` in `pt_week_overrides`. The Week notice could not be reached by hand: the Simulator has no window on this machine right now, so nothing can tap. A UI test reaches it and stays as the regression test.

## Change

1. `PhaseTraining/App/PhaseTrainingApp.swift`, in the DEBUG seed block beside `--seed-plan-demo`: a new flag `--seed-arc-deload` that writes `pt_week_overrides` for the current training week with `arcDeload = .applied` (build a `WeekOverrides(weekStart: Date().startOfTrainingWeek())`, set the field, encode with the same date strategy `PlanStore` uses). It must run after the `--ui-test-reset` wipe and before `PlanStore` is created, as the other seeds do. Add its line to the comment list of seeds. It pairs with `--ui-test-onboarded --ui-test-reset --seed-plan-demo`.

2. `PhaseTrainingUITests/ArcDeloadNoticeUITests.swift` (new), modelled on `MoveBannerUITests.swift` (same launch helper style and waits). Load the `phase-training-xcuitest-recipe` skill first. One test, `test_weekNotice_showsAndDeclineRemovesIt`:
   - launch with `--ui-test-onboarded --ui-test-reset --seed-plan-demo --seed-arc-deload`;
   - on Today, a static text whose label ends in "DELOAD" exists;
   - open the Week tab; `arc-deload-notice` exists with the label "Three hard weeks in a row, so this week is lighter", and `arc-deload-decline` exists and is hittable; all seven `week-day-row-N` rows exist and are hittable (the notice must not push a row off screen);
   - attach a screenshot named `week-arc-deload` with `lifetime = .keepAlways` for this run;
   - tap `arc-deload-decline`; `arc-deload-notice` no longer exists within 5 seconds; attach `week-after-decline`;
   - back on Today, no static text ends in "DELOAD".

   If the plan that `declineArcDeload` regenerates from the un-onboarded seed memory makes any of these assertions impossible, do not weaken the assertion: report what the screen showed.

3. Run with `-resultBundlePath <scratchpad>/arc-ui.xcresult` (delete any earlier bundle at that path first), then `xcrun xcresulttool export attachments --path ... --output-path <scratchpad>/arc-ui-shots` and give the two PNG paths in the report. After the run, set the two attachments' lifetime back to the default (remove the `.keepAlways` lines) so the committed test is quiet; no second run is needed for that edit, a build of the UI test target is enough.

## Build and test

Slot A only: UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`, `-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A`, both on every `xcodebuild` call. `xcodegen generate` after adding the file. One class only: `-only-testing:PhaseTrainingUITests/ArcDeloadNoticeUITests`. Never the whole UI target. Full log to a file, grepped as before.

The simulator currently holds the lead's hand seed. `--ui-test-reset` wipes it.

Do not commit. Do not touch `docs/`.

## Report

One final report: files changed, the test result, the two screenshot paths, the measured height of a day row with the notice showing if the test can read it (`frame.height` of `week-day-row-0`), and anything that did not match this brief.
