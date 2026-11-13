# Brief: Today widget (slot A)

## Backlog item

`docs/PLAN-gap-backlog-2026-11b.md`, Phase 6: "Today widget, in the same extension (6 h)". A Home Screen widget in the existing `PhaseTrainingWidgets` extension that shows today's planned day.

## Problem

The plan lives in the app's `UserDefaults.standard` (`pt_week_plan`), which the widget extension cannot read. There is no App Group in the repo. The widget also has to show the right day after midnight when the app has not run.

## Design (fixed, do not redesign)

1. **App Group** `group.com.phasetraining.app`, on the app target and the widget target. The watch target does not get it.
2. **Snapshot of the week.** The app writes one small Codable value covering every day of the current `WeekPlan` to the group's `UserDefaults`. The widget reads only that value. The widget never decodes `WeekPlan`, `DayPlan` or anything else from the app target.
3. **Timeline from the snapshot.** The widget builds one entry for now and one for each later midnight inside the snapshot's days, plus one entry at the midnight after the last day, which shows the empty state. Policy `.never`; the app reloads the timeline when the snapshot changes.
4. **Write on change only.** The app compares the new snapshot to the last one written and skips the write and the reload when they are equal. `generatedAt` style timestamps stay out of the snapshot so equality works.

### Shared type: `Shared/Widget/TodayWidgetSnapshot.swift` (new, plain Foundation)

```swift
struct TodayWidgetDay: Codable, Hashable {
    enum Kind: String, Codable { case lift, sport, rest, event }
    var date: Date        // start of day, local calendar
    var kind: Kind
    var title: String     // "Upper Day 1", "Skiing", "Rest day", event title
    var detail: String?   // "6 exercises · 18 sets", "About 45 min", nil
    var done: Bool
}

struct TodayWidgetSnapshot: Codable, Hashable {
    static let appGroup = "group.com.phasetraining.app"
    static let defaultsKey = "pt_today_widget_snapshot"
    static let widgetKind = "TodayWidget"
    var days: [TodayWidgetDay]

    func day(on date: Date, calendar: Calendar = .current) -> TodayWidgetDay?
    static func load(from defaults: UserDefaults?) -> TodayWidgetSnapshot?
    func save(to defaults: UserDefaults?)
}
```

Encode dates as `secondsSince1970`, as `PlanStore+Persistence.swift` does. `load` returns nil on a missing or undecodable value.

`Shared/` is compiled by the watch target as a whole, so the file must build on watchOS: Foundation only, no WidgetKit import.

### App side: `PhaseTraining/Widget/TodayWidgetPublisher.swift` (new)

Two parts, as `RestActivityCoordinator` and `ActivityKitRestHost` are split:

- A pure static function, testable with no stores:
  `static func snapshot(plan: WeekPlan?, completedDays: Set<Date>, calendar: Calendar) -> TodayWidgetSnapshot?`
  Returns nil for a nil plan. Per `DayPlan`:
  - `lift`: title is `workoutTemplate?.name ?? title`. Detail is "N exercises · M sets" from the template (same counts as `headerSubtitle`, `TodayScreen+Derived.swift:187-200`, with "exercises" spelled out). No template: detail nil.
  - `sport`: title is `sport?.name ?? "Sport day"`. Detail is "About N min" when `durationMinutes` is set, else nil.
  - `rest`: title "Rest day", detail nil.
  - `event`: title is the day's `title`, or "Event day" when empty. Detail nil.
  - `done` is true when `completedDays` contains the day's start of day. Rest days are never done.
- `final class TodayWidgetPublisher`: `init(planStore:store:defaults:reload:)`. `defaults` defaults to `UserDefaults(suiteName: TodayWidgetSnapshot.appGroup)`, `reload` to a closure calling `WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetSnapshot.widgetKind)`. It subscribes to `planStore.$plan` and `store.$savedSessions` (the seam `WatchSyncCoordinator.swift:67-73` uses), publishes once in `init`, and holds the last written snapshot for the equality check. A nil snapshot removes the key and reloads.
  - `@Published` fires in `willSet`. Read the new value from the sink argument, never from the store property inside the sink.
  - `completedDays`: start of day of each saved session in the plan's week that was completed. Find how an abandoned session is marked (`saveAbandoned`, `SessionStore.swift:586`, and `DayOutcome`) and leave abandoned sessions out. Report what you used.
- Create it in `PhaseTrainingApp.swift` next to the `WatchSyncCoordinator` creation (line 733), held the same way.

`BackupCoordinator.eraseAllData` must leave no snapshot behind. `PlanStore.clear()` sets `plan = nil`, which the publisher turns into a key removal; confirm that path runs during an erase and add the removal to `eraseAllData` only if it does not.

### Widget side: `PhaseTrainingWidgets/TodayWidget.swift` (new)

- `StaticConfiguration(kind: TodayWidgetSnapshot.widgetKind, provider:)`, display name "Today", description "Today's planned session.", families `.systemSmall` and `.accessoryRectangular`.
- `.widgetURL(URL(string: "phasetraining://today"))`. The app already routes it (`PhaseTrainingApp.swift:836`).
- `systemSmall` layout, top to bottom: weekday and date eyebrow ("FRI, NOV 13", ink2, caption), title (ink, up to 2 lines, `minimumScaleFactor(0.8)`), detail (ink2, 1 line). A done day shows "Done" with a `checkmark.circle.fill` in accent in place of the detail. Background `Palette.bg` through `containerBackground(for: .widget)`.
- `accessoryRectangular`: title, then detail or "Done". System colours only, since the Lock Screen tints it.
- Empty state (no snapshot, or no day for the entry's date): title "No plan yet", detail "Open Phase Training". No invented workout.
- Placeholder and the gallery preview (`context.isPreview`) use the real snapshot when there is one and the empty state when there is not.
- The palette is `private` inside `RestTimerLiveActivity.swift`. Move it to `PhaseTrainingWidgets/WidgetPalette.swift` and use it from both files. One copy.
- System fonts only (`scripts/quality/verify_font_tokens.sh` does not scan this folder). No em or en dashes in any string.
- Add `TodayWidget()` to `PhaseTrainingWidgetsBundle`.

### Project and entitlements

- `PhaseTraining/PhaseTraining.entitlements`: add `com.apple.security.application-groups` with `group.com.phasetraining.app`.
- New `PhaseTrainingWidgets/PhaseTrainingWidgets.entitlements` with only that key.
- `Project.yml`, widget target: add `Shared/Widget` to `sources`, add `CODE_SIGN_ENTITLEMENTS: PhaseTrainingWidgets/PhaseTrainingWidgets.entitlements` to base settings.
- Do not touch `release.yml`, the build number, `docs/` or the backlog. Those belong to the lead.

## Skills to load

`phase-training2-gitignored-pbxproj` and `phase-training-xcodebuild-test-failed-grep-full-log`.

## Files to touch

New: `Shared/Widget/TodayWidgetSnapshot.swift`, `PhaseTraining/Widget/TodayWidgetPublisher.swift`, `PhaseTrainingWidgets/TodayWidget.swift`, `PhaseTrainingWidgets/WidgetPalette.swift`, `PhaseTrainingWidgets/PhaseTrainingWidgets.entitlements`, `PhaseTrainingTests/TodayWidgetSnapshotTests.swift`.

Edited: `PhaseTrainingWidgets/PhaseTrainingWidgetsBundle.swift`, `PhaseTrainingWidgets/RestTimerLiveActivity.swift` (palette move only), `PhaseTraining/App/PhaseTrainingApp.swift`, `PhaseTraining/PhaseTraining.entitlements`, `Project.yml`. `BackupCoordinator.swift` only under the erase condition above.

## Tests: `PhaseTrainingTests/TodayWidgetSnapshotTests.swift`

Build plans by hand from `DayPlan` values; these are unit fixtures.

- `test_nilPlan_givesNilSnapshot`
- `test_liftDay_titleAndCounts`: template name as title, "N exercises · M sets" as detail.
- `test_sportDay_usesSportNameAndMinutes`
- `test_restDay_neverDone`: its date in `completedDays`, `done` stays false.
- `test_completedDay_isDone`
- `test_dayLookup_acrossMidnight`: `day(on:)` returns Monday's day at 23:59 and Tuesday's at 00:00, nil the day after the last one.
- `test_roundTrip_throughDefaults`: save to a `UserDefaults(suiteName:)` made for the test, load equals, remove the suite after.
- `test_publisher_writesOnceForEqualSnapshots`: a publisher with an injected defaults and a counting `reload`; two plan assignments that produce the same snapshot give one reload after the initial one, or zero if the first equals the initial. Assert the exact count you expect and say which.
- `test_publisher_nilPlan_removesKey`

## Build and test

Slot A only. Never use another simulator or DerivedData path.

- Simulator: iPhone 17 Pro, UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`
- `-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A`
- Every `xcodebuild` call passes `-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'` and that `-derivedDataPath`.

Steps:

1. `xcodegen generate` after adding the files and editing `Project.yml`.
2. One `xcodebuild test` call, full log to a file in your scratchpad, grepped as the skill says:
   - `-only-testing:PhaseTrainingTests/TodayWidgetSnapshotTests`
   - `-only-testing:PhaseTrainingTests/RestActivityCoordinatorTests`
3. From the build products under DerivedData-A, confirm and report:
   - `codesign -d --entitlements - ` on `PhaseTraining.app` and on `PlugIns/PhaseTrainingWidgets.appex` both list `group.com.phasetraining.app`;
   - the watch app still built (`PhaseTraining.app/Watch/` is populated), which proves `Shared/Widget` compiles on watchOS.

Do not run the UI test target or the full unit suite. Do not walk the simulator; the lead does that. Do not commit.

## Done looks like

- `TodayWidgetSnapshotTests` passes (9 tests) and `RestActivityCoordinatorTests` still passes (20).
- Both build-product checks hold.
- No new compiler warnings in the files you touched.
- The widget target compiles nothing from the app target, and the app target has exactly one `WidgetCenter` call site.

## Out of scope

Medium and large families, interactive buttons, a "start workout" intent, the watch complication, showing the exercise list, `release.yml` and provisioning.

## Report

One final report, no interim messages: files changed, each test class with pass and fail counts, the step 3 results, decisions made on anything this brief left open, and anything you noticed outside its scope (list it, do not fix it). If something here conflicts with the code you find, take the conservative option, record it, and keep going.
