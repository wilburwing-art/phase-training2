# Brief: voice 1.1, ActiveWorkoutController

Backlog item: `docs/PLAN-backlog-2026-11-voice.md` 1.1. Spec: `docs/PLAN-voice.md`.
Agent: builder-heavy. Line numbers re-measured 2026-11-18 at e394258; all still match.

## Skills to load

`phase-training-autosave-complete-screen`, `phase-training-freetext-weight-reps-parsing`.

## Files

Create only:
- `PhaseTraining/Workout/ActiveWorkoutController.swift`
- `PhaseTrainingTests/ActiveWorkoutControllerTests.swift`

Do not edit `LogScreen.swift`, `LogScreenHelpers.swift`, `RestTimerState.swift`,
`SessionStore.swift` or any view. LogScreen keeps its own copies until item 1.2.
This builder runs `xcodegen generate` (two new Swift files).

## Design

```swift
@MainActor
final class ActiveWorkoutController: ObservableObject {
    @Published private(set) var session: ActiveSession   // didSet -> store.saveActive(session) when changed
    @Published private(set) var rest: RestTimerState

    init(store: SessionStore,
         session: ActiveSession,
         suppressAutoRest: Bool = false,               // mirrors LogScreen.uiTestSuppressAutoRest
         haptic: @escaping (UIImpactFeedbackGenerator.FeedbackStyle) -> Void = { UIImpactFeedbackGenerator(style: $0).impactOccurred() },
         now: @escaping () -> Date = Date.init)
}
```

Methods, bodies moved from LogScreen (same guards, same haptic styles, same rest rules):
- `setRIR(exIdx:setIdx:value:)` from `LogScreen.swift:588`
- `toggleSet(exIdx:setIdx:)` from `:595`
- `startRestAfterCompleting(exIdx:setIdx:)` from `:621`, including the superset mid-round rule
- `addSet(exIdx:)` from `:658`
- `reopenSet(exIdx:setIdx:)` from `:697`
- `isMidSupersetRound(exIdx:setIdx:)` from `LogScreenHelpers.swift:171` (copy; LogScreen keeps its own until 1.2)
- `skipRest()`: `rest.clear()`
- `addRest(seconds: Int)`: the +15 path in `RestTimerState.swift:163`, generalised. Positive extends `duration` and reschedules. Negative follows the -15 path (`:166`): if the new duration is at or under elapsed, clear; else shorten and reschedule. No-op when no rest is active.
- `logSet(exIdx:setIdx:weight:reps:rpe:)` with `String?` params: a nil param keeps the cell's current value; a non-nil one overwrites it. Then mark the set done (if not already) and run `startRestAfterCompleting`. Already-done set: update values, do not restart rest. Out-of-range indices: no-op.
- `nextUp() -> NextUp?`

```swift
struct NextUp: Equatable {
    let exIdx: Int
    let setIdx: Int
    let exerciseName: String
    let setNumber: Int      // setIdx + 1
    let totalSets: Int      // sets.count
    let targetReps: Int
    let lastWeight: String? // weight of the latest done set in this exercise, else this set's own non-empty weight, else nil
}
```

nextUp order: take the first exercise (session order) with any undone set. If it has no
`supersetGroup`, return its first undone set. If it has one, collect the group's members in
session order; find the lowest set index at which any member has an undone set; return the first
member (session order) with that set undone. nil when every set is done.

Saving: every mutation goes through `session`, and its didSet calls `store.saveActive` once per
change. No other persistence. Rest stays non-persistent.

## Done

- `ActiveWorkoutControllerTests` covers: logSet writes values and marks done and saves to the
  store (`store.active == controller.session`); toggle complete starts rest with `ex.rest`; final
  set of an exercise gets no rest; toggle off clears an anchored rest; skipRest clears; addRest(15)
  extends duration by 15; addRest(-N) past elapsed clears; nextUp in a plain session; nextUp
  across a two-member superset round (A1 done -> B1, then rest starts only after B1, then A2);
  nextUp nil when all done; suppressAutoRest blocks rest.
- Use `SessionStore(defaults:)` with a throwaway suite, as in `SessionStoreActiveSessionApplyTests.swift:48`.
- Test classes that must pass: `ActiveWorkoutControllerTests`, `RestTimerStateTests`.

## Slot

Slot A: `-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'`
`-derivedDataPath /Users/wilburpyn/Library/Developer/Xcode/DerivedData-A`.
Boot first with `xcrun simctl boot <UDID>; xcrun simctl bootstatus <UDID> -b` (a launch seconds
after a cold boot fails preflight with "Busy").
Full log to a file, then `grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" <log>`.

## Report

One final report: files changed, classes run with pass/fail counts, decisions on anything open,
anything outside scope. Do not commit.
