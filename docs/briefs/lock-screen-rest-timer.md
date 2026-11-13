# Brief: Lock Screen rest timer, integration pass (slot A)

## Backlog item

`docs/PLAN-gap-backlog-2026-11b.md`, Phase 6: "Lock Screen rest timer (Live Activity)". The Today widget in the same line is a later step and is out of scope here.

## State you start from

The feature was written on 2026-11-11 on branch `worktree-agent-a10b49ac2d7a20bc7` and never merged. Its three commits are now applied to the working tree on `main`, staged and uncommitted. Do not rewrite or restructure it. Orientation:

- `PhaseTrainingWidgets/` is a new widget extension target (`com.phasetraining.app.widgets`) declared in `Project.yml` and embedded in the app. `RestTimerLiveActivity.swift` draws the Lock Screen and Dynamic Island views.
- `Shared/LiveActivity/RestActivityAttributes.swift` holds `RestActivityState` (plain Foundation) and `RestActivityAttributes` (behind `#if os(iOS) && canImport(ActivityKit)` because the watch target compiles `Shared/`).
- `PhaseTraining/LiveActivity/RestActivityCoordinator.swift` decides start, update and end. It has no ActivityKit import. `ActivityKitRestHost.swift` is the real host and `RestActivityCenter.shared` the app-wide instance.
- `LogScreen.swift` reports through one `.onChange(of: rest)` that calls `RestActivityCenter.shared.sync(liveActivitySnapshot())`. `RestTimerState` became `Equatable` for that.
- `maybeFireRestExpiry` in `RestTimerState.swift` calls `RestActivityCenter.shared.restExpired()`.
- `PhaseTrainingApp.swift` ends the activity when `session.$active` becomes nil and on launch.

## Skills to load

`phase-training2-gitignored-pbxproj` and `phase-training-xcodebuild-test-failed-grep-full-log`.

## Files to touch

- `PhaseTraining/LiveActivity/RestActivityCoordinator.swift`
- `PhaseTrainingTests/RestActivityCoordinatorTests.swift`
- `PhaseTraining/Screens/RestTimerState.swift` only if change 2 needs the call site to pass `now` (it should not: the default argument covers it)

Nothing else. `Project.yml`, `release.yml`, the widget views, the docs and the backlog belong to the lead.

## Change 1: an expired rest loses its `finished` flag

Sequence today, with the app in the foreground at expiry:

1. `maybeFireRestExpiry` sets `rest.alertFiredFor` and `rest.expiredFlashUntil`, then calls `restExpired()`. The coordinator sends an update with `finished = true`.
2. The two mutations in step 1 change `rest`, so `.onChange(of: rest)` fires and calls `sync` with the same snapshot.
3. `sync` builds a state with `finished = false`, finds it unequal to `current` (which has `finished = true`), and sends an update that sets `finished` back to false. About 1.2 seconds later `expiredFlashUntil` is cleared and it happens again.

The widget still reads "Rest done" only because the activity is stale by then.

Fix in `sync`: when an activity exists for the same workout and the incoming state equals `current` in every field except `finished`, return without a host call and leave `current` as it is. Add the comparison as a small method on `RestActivityState` or a private helper in the coordinator, your choice. A snapshot that differs in any other field (new end date, new set number, new exercise) still sends an update with `finished = false`, which `test_expiryThenNextRest_clearsFinished` already covers.

New test: `test_expiryThenSameSnapshot_keepsFinished`. `sync(snap())`, `restExpired()`, `sync(snap())` twice. Expect exactly two host calls (start, update) and `c.current?.finished == true`.

## Change 2: never start an activity for a rest that has already run out

A start can fail while the phone app is in the background (a watch-marked set). `current` stays nil, so the next `sync` for that same rest tries to start again. If that next `sync` arrives after the rest ended (the user reopens the app, `maybeFireRestExpiry` mutates `rest`), a new activity appears already reading "Rest done".

Fix: give `sync` a clock, `func sync(_ rest: RestSnapshot?, now: Date = Date())`. In the branch that starts a new activity, skip the `host.start` call when `rest.endDate <= now`. Order inside that branch:

1. If `current != nil` (a leftover from another workout), `host.endAll()` and clear `current` and `currentWorkout`, as today.
2. If `rest.endDate <= now`, return.
3. Otherwise start, as today.

The update branch does not take the clock check. An existing activity always receives its update.

Test changes:

- Existing tests use `t0 = Date(timeIntervalSince1970: 1_000_000)`, which is in the past, so every `sync` call that expects a start must pass `now: t0`. Add a helper or pass it at each call site.
- New test `test_restAlreadyOver_doesNotStart`: `c.sync(snap(end: 90), now: t0.addingTimeInterval(91))` issues no host call and leaves `c.current` nil.
- New test `test_restEndingExactlyNow_doesNotStart`: same with `now: t0.addingTimeInterval(90)`.
- New test `test_failedStartThenExpiredRetry_doesNotStart`: `startSucceeds = false`, `sync(snap(end: 90), now: t0)`, then `startSucceeds = true`, `sync(snap(end: 90), now: t0.addingTimeInterval(120))`. Expect one `start` call in total.
- New test `test_updateStillSentForPastEndDate`: start at `now: t0`, then `sync(snap(end: 30), now: t0.addingTimeInterval(60))`. Expect start then update.

## Build and test

Slot A only. Never use another simulator or DerivedData path.

- Simulator: iPhone 17 Pro, UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`
- `-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A`
- Every `xcodebuild` call passes `-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'` and that `-derivedDataPath`.

Steps:

1. `xcodegen generate` (the new target and five new Swift files are not in the generated project yet).
2. Make the two changes.
3. Run these test classes, one `xcodebuild test` invocation, full log to a file in your scratchpad, then grep it as the skill says:
   - `-only-testing:PhaseTrainingTests/RestActivityCoordinatorTests`
   - `-only-testing:PhaseTrainingTests/RestTimerStateTests`
4. From the build products under DerivedData-A, confirm and report:
   - `PhaseTraining.app/PlugIns/PhaseTrainingWidgets.appex` exists;
   - `plutil -p PhaseTraining.app/Info.plist` shows `NSSupportsLiveActivities` true;
   - the appex `Info.plist` has `CFBundleVersion` equal to the app's and `NSExtensionPointIdentifier` `com.apple.widgetkit-extension`;
   - the watch app still built (`PhaseTraining.app/Watch/` is populated).

Do not run the UI test target or the full unit suite. Do not commit.

## Done looks like

- `RestActivityCoordinatorTests` passes with the 15 existing tests plus the 5 new ones (20).
- `RestTimerStateTests` passes (6).
- The four build-product checks in step 4 hold.
- No compiler warnings introduced in the files you touched.

## Report

One final report, no interim messages: files changed, each test class with pass and fail counts, the step 4 results, decisions made on anything this brief left open, and anything you noticed outside its scope (list it, do not fix it). If something here conflicts with the code you find, take the conservative option, record it, and keep going.
