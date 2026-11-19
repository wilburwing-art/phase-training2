# Brief: voice 1.2, LogScreen drives the controller

Backlog item: `docs/PLAN-backlog-2026-11-voice.md` 1.2. Behavior change: none.
The log screen must look and act the same; the controller from 1.1
(`PhaseTraining/Workout/ActiveWorkoutController.swift`) becomes the single
owner of the live `ActiveSession` and `RestTimerState`.

Skill to load: `phase-training-rootview-deferred-deps-need-notify` (read only;
no PlanStore change is expected).

Re-measured premise: `PhaseTrainingApp.swift:218` and `:303` are UI-test seed
hooks that write `pt_active_session` to UserDefaults. They hold nothing. The
only `LogScreen(` call site is `PhaseTraining/Screens/TodayTab.swift:47`, so the
controller is held there.

## Files to touch

- `PhaseTraining/Workout/ActiveWorkoutController.swift`
- `PhaseTraining/Screens/TodayTab.swift`
- `PhaseTraining/Screens/LogScreen.swift`
- `PhaseTraining/Screens/LogSetRow.swift`
- `PhaseTraining/Screens/LogExerciseBlock.swift`
- `PhaseTraining/Screens/LogScreenHelpers.swift`
- `PhaseTraining/Screens/RestTimerState.swift`

No new Swift files, so no `xcodegen generate` is needed. If you do add one,
you run `xcodegen generate` (you are the only builder on this item).

## Design

1. Controller: change `@Published private(set) var session` and
   `@Published private(set) var rest` to plain `@Published var` (internal
   set). Add a one-line comment: the log screen binds text fields through
   `session` and the rest card writes `rest`. Make
   `LogScreen.uiTestSuppressAutoRest` internal (drop `private`) so TodayTab
   can pass it.

2. TodayTab holds one instance per active workout:
   `@State private var workout: ActiveWorkoutController?`.
   - Build it whenever the route becomes `.log` and `workout == nil`, from
     `store.active`:
     `ActiveWorkoutController(store: store, session: active, suppressAutoRest: LogScreen.uiTestSuppressAutoRest)`.
     Covers `enterLiveSessionIfNeeded()` and `TodayScreen(onStart:)`. Put
     the creation in one helper called from both paths (and from
     `transition(.log)`), before `route` changes.
   - Set `workout = nil` in `onFinish` and `onCancel` and whenever the route
     leaves `.log`.
   - `case .log:` with a controller renders `LogScreen(workout:, onFinish:,
     onCancel:)`. Without one (no `store.active`) renders the existing
     no-session empty state. Move that state out of LogScreen into a small
     `LogNoSessionView(onCancel:)` struct at the bottom of `LogScreen.swift`
     (same text, same "Back to Today" button), and delete the `noSession`
     flag and its branch.

3. LogScreen:
   - New stored property `@ObservedObject var workout: ActiveWorkoutController`.
   - Delete `@State var session` and `@State var rest`. Replace them with
     computed forwarders so the extension files keep compiling with few edits:
     ```swift
     var session: ActiveSession {
         get { workout.session }
         nonmutating set { workout.session = newValue }
     }
     var rest: RestTimerState {
         get { workout.rest }
         nonmutating set { workout.rest = newValue }
     }
     ```
   - Every `$session...` binding becomes `$workout.session...`
     (`LogSetRow.swift` reps, rpe, weight; `LoggedForSheet(loggedFor:)` in
     LogScreen). `SupersetEditing.pairWithNext(&session.exercises, ...)` and
     `remove(&session.exercises, ...)` in `LogExerciseBlock.swift` can stay on
     the forwarder (inout through a nonmutating set works) or use
     `&workout.session.exercises`; pick one and use it for both.
   - Delete the LogScreen bodies of `setRIR`, `toggleSet`,
     `startRestAfterCompleting`, `addSet`, `reopenSet` and
     `isMidSupersetRound` (`LogScreenHelpers.swift:171`). Callers call
     `workout.<same name>(...)` directly. Remove the forwarder methods
     entirely; do not leave one-line wrappers.
   - Rest card in `RestTimerState.swift` `activeRestCard()`: `onAdd15` calls
     `workout.addRest(seconds: 15)`, `onSubtract15` calls
     `workout.addRest(seconds: -15)` (same rule as the old inline code), the
     non-flashing `onSkip` calls `workout.skipRest()`. `onSetDuration`,
     the flashing skip and `maybeFireRestExpiry` keep writing `rest` through
     the forwarder.
   - Persistence: delete `.onChange(of: session) { store.saveActive(...) }`.
     The controller's `didSet` saves. Keep `.onChange(of: rest)` for the Live
     Activity sync, keyed on `workout.rest`.
   - `saveActive` encodes JSON, writes UserDefaults and reschedules the
     inactivity notification on every call, and each forwarder write is one
     call. So any function that writes `session` more than once in a loop must
     build a local copy and assign once: `markAllSetsDone`,
     `logAllSetsAllExercises` (one assignment for the whole workout),
     `deleteSet` (remove plus renumber), `swapExercise`, and the
     `uiTestRestOverride` loop. Single writes stay as they are.
   - `loadIfNeeded`: drop the `store.active` read and the `session = existing`
     copy. Keep the `exercises.isEmpty → addingExercise = true` check and the
     `uiTestRestOverride` clamp (one assignment). Keep `didLoad`.
   - `.onReceive(store.$active)` stays in LogScreen: on an external change,
     `workout.session = external`, then `workout.startRestAfterCompleting` for
     each newly done set, same loop as now.
   - Delete the `placeholder` static if nothing reads it. Update both
     `#Preview`s to build a controller from the store's session.
   - Update the header comment block (lines 8 to 23) to say the controller
     owns session and rest.

## Out of scope

Voice, App Intents, `CompleteScreen`, the watch coordinator, any change to
what the controller methods do. If a controller method's behavior differs
from the old LogScreen copy in a way a user would see, record it in the
report and keep the controller's behavior.

## Done

- Build succeeds.
- These classes pass, run one at a time, full log to a file, grep per
  CLAUDE.md: `ActiveWorkoutControllerTests`, `SetPropagationTests`,
  `SessionStoreActiveSessionApplyTests`, `RestTimerStateTests`.
- `grep -n "@State var session\|@State var rest\|func toggleSet\|func startRestAfterCompleting\|func isMidSupersetRound" PhaseTraining/Screens/` prints nothing.
- Do not commit.

## Slot

Slot A: iPhone 17 Pro, UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`,
`-derivedDataPath /Users/wilburpyn/Library/Developer/Xcode/DerivedData-A`.
Every xcodebuild call passes
`-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'`.
If the first launch after a cold boot fails "Busy / failed preflight checks",
run `xcrun simctl bootstatus 3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2 -b` and retry.

## Report

One final report: files changed, each test class with pass/fail counts,
decisions on anything this brief left open, anything outside scope.
