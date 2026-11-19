# Brief: voice 2.5 Workout App Intents

Backlog item: `docs/PLAN-backlog-2026-11-voice.md` 2.5. Spec: `docs/PLAN-voice.md`.
Agent: builder-heavy. Skill to load: none specific; read `PhaseTraining/Voice/VoiceLogModel.swift` for the command rules these intents mirror.

## State today (measured 2026-11-19)

- Zero AppIntent code in the repo (`grep -rn AppIntent PhaseTraining PhaseTrainingWidgets Shared` is empty). 11c 7.1 is open, so this item creates the one `AppShortcutsProvider` and 7.1 adds to it later.
- `ActiveWorkoutController` (`PhaseTraining/Workout/ActiveWorkoutController.swift`) is created only in `TodayTab.ensureWorkout()` (`PhaseTraining/Screens/TodayTab.swift:87-92`) and dropped in `transition(_:)` (`:94-97`). Nothing outside the view tree can reach it.

## Design

1. `PhaseTraining/Workout/ActiveWorkoutRegistry.swift` (new):
   `@MainActor final class ActiveWorkoutRegistry { static let shared = ActiveWorkoutRegistry(); weak var current: ActiveWorkoutController? }`.
   `TodayTab` writes it wherever it assigns `workout` (after `ensureWorkout` builds one, and when `transition` sets it to nil). Weak, so a controller the view drops does not live on.

2. `PhaseTraining/Intents/WorkoutIntentActions.swift` (new): `@MainActor enum WorkoutIntentActions` with pure-ish static functions that take `ActiveWorkoutController?` and return the dialog `String`. All the testable logic lives here.
   - `noWorkout = "No workout running"`, `allLogged = "All sets are logged"` (same text as `VoiceLogModel.allLogged`).
   - `logSet(weight: Double?, reps: Int, in c: ActiveWorkoutController?) -> String`: nil c → `noWorkout`; `c.nextUp()` nil → `allLogged`; reps < 1 → `"Reps must be at least 1"` with no change; else `c.logSet(exIdx:setIdx:weight: weight.map(SpokenCue.format), reps: String(reps), rpe: nil)` on the next-up set, return `SpokenCue.readback(exercise:setIdx:)` for that set. Bodyweight exercise: ignore a given weight (pass nil). No unit conversion (the weight is taken in the exercise's own unit).
   - `skipRest(in:now:)`: nil → `noWorkout`; rest not running (`c.rest.remaining(at: now) == nil`) → `"No rest running"`; else `c.skipRest()`, `"Rest skipped"`.
   - `addRest(seconds: Int, in:now:)`: nil → `noWorkout`; not running → `"No rest running"`; else `c.addRest(seconds:)` and return `"Added \(seconds) seconds"` (negative: `"Cut \(abs) seconds"`). If the add ended the rest, `"Rest ended"`.
   - `whatsNext(in:)`: nil → `noWorkout`; nextUp nil → `allLogged`; else `SpokenCue.upNext(next:in:) + "."`.
   `now` parameters default to `Date()`; the controller's own clock is private, so tests pass the fixture clock.

3. `PhaseTraining/Intents/WorkoutIntents.swift` (new): four `AppIntent` structs, each `static var openAppWhenRun = false`, `@MainActor func perform() async throws -> some IntentResult & ProvidesDialog`, returning `.result(dialog: IntentDialog(stringLiteral: line))` from the action with `ActiveWorkoutRegistry.shared.current`.
   - `LogSetIntent`: `@Parameter(title: "Reps") var reps: Int` (required, `requestValueDialog` "How many reps?"), `@Parameter(title: "Weight") var weight: Double?` (optional).
   - `SkipRestIntent`, `AddRestIntent` (`@Parameter(title: "Seconds", default: 15) var seconds: Int`), `WhatsNextIntent`.
   Give each a memberwise-usable init so tests can build them (`init()` plus one with params).

4. `PhaseTraining/Intents/PhaseShortcuts.swift` (new): `struct PhaseShortcuts: AppShortcutsProvider` with one `AppShortcut` per intent. Every phrase includes `\(.applicationName)`. Int/Double parameters cannot appear in phrases, so LogSet phrases are like "Log a set in \(.applicationName)" and Siri asks for reps. Example phrases: "Skip rest in \(.applicationName)", "Add rest in \(.applicationName)", "What's next in \(.applicationName)". Add a one-line comment: 11c 7.1 adds its shortcuts here; an app may have only one provider.

5. `PhaseTrainingTests/WorkoutIntentTests.swift` (new, `@MainActor`): copy the fixture pattern from `ActiveWorkoutControllerTests` (suite-scoped defaults, fixed clock). Cases:
   - each of the four actions with nil controller returns "No workout running" and changes nothing;
   - logSet marks the next-up set done with the given weight and reps and returns the readback; a bodyweight exercise ignores the weight; all-done session returns "All sets are logged";
   - skipRest with a running rest clears it; with none returns "No rest running";
   - addRest extends `rest.duration` by 15; with none returns "No rest running";
   - whatsNext returns the up-next line; all-done returns "All sets are logged";
   - one wiring test per intent: set `ActiveWorkoutRegistry.shared.current` to a fixture controller, `_ = try await LogSetIntent(reps: 5, weight: 135).perform()`, assert the session changed (and SkipRest clears rest). Reset the registry in `tearDown`.

## Files to touch

New: the four files above plus the test. Edit: `PhaseTraining/Screens/TodayTab.swift` (registry writes only). Nothing else. `Project.yml` should need no change (sources are folder globs); confirm, and add the AppIntents framework only if the build demands it.

## Slot and build

- Slot A: UDID 3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2, `-derivedDataPath /Users/wilburpyn/Library/Developer/Xcode/DerivedData-A`.
- This builder runs `xcodegen generate` (new Swift files).

## Done

- `-only-testing:PhaseTrainingTests/WorkoutIntentTests` and `-only-testing:PhaseTrainingTests/ActiveWorkoutControllerTests` pass; full log to a file, grep per CLAUDE.md.
- The build log shows the App Intents metadata step ran for PhaseTraining without errors (`grep -n "appintentsmetadataprocessor\|Extract app intents metadata" <log>`).
- Do not commit. Return one final report: files changed, classes run with counts, decisions on anything left open.
