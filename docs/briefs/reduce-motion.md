# Brief: Reduce Motion

Backlog item: `docs/PLAN-gap-backlog-2026-11b.md`, "Later, not scheduled": "Reduce Motion: 2 of 28 animation sites respect it, and the rest dot pulses forever (2 h)." Audit finding 6 in `audits/2026-11-10-gap-round/accessibility.md`.

Agent: builder. Skills to load first: `phase-training2-gitignored-pbxproj`, `phase-training-xcodebuild-test-failed-grep-full-log`.

## Problem

With the iOS Reduce Motion setting on, the app still moves, scales, springs and loops. Two sites read the setting (`KettleView`, the `WorkoutTitleWheel` pips). The rest dot loops forever, and exercise thumbnails flip between two frames forever on every list row, which the audit did not count.

## Rule under Reduce Motion

- No loop. A looping element holds one frame.
- No movement: no slide, scale, rotation, spring, size change or animated scroll. The change lands at once.
- A short crossfade of opacity or colour stays.
- A slide or scale transition becomes a plain opacity transition.

With the setting off, every site looks exactly as it does today. No duration, curve or transition changes.

## New file: `PhaseTraining/Components/Motion.swift`

```swift
enum Motion {
    enum Kind { case fade, movement }

    /// True when the launch argument `--ui-test-reduce-motion` is present. Read once.
    static let forcedByLaunchArgument: Bool

    /// The setting as seen outside a view body.
    static var systemReduced: Bool   // UIAccessibility.isReduceMotionEnabled || forcedByLaunchArgument

    /// The setting as seen from a view: the environment value or the launch argument.
    static func isReduced(_ environmentValue: Bool) -> Bool

    /// Pure. `.fade` returns the animation in both cases. `.movement` returns nil when reduced.
    static func animation(_ animation: Animation, _ kind: Kind, reduced: Bool) -> Animation?

    /// Pure. Returns `.opacity` when reduced, `full` otherwise.
    static func transition(_ full: AnyTransition, reduced: Bool) -> AnyTransition
}

/// Replaces `withAnimation` at every call site. Reads `Motion.systemReduced` at call time.
func withMotion<Result>(_ animation: Animation, _ kind: Motion.Kind,
                        _ body: () throws -> Result) rethrows -> Result

extension View {
    /// Replaces `.animation(_:value:)`. Reads `\.accessibilityReduceMotion` through `Motion.isReduced`.
    func motion<V: Equatable>(_ animation: Animation, _ kind: Motion.Kind, value: V) -> some View
    /// Replaces a `.transition` that slides or scales.
    func motionTransition(_ full: AnyTransition) -> some View
}
```

The two view modifiers are small `ViewModifier` structs holding `@Environment(\.accessibilityReduceMotion)`. A `ButtonStyle` cannot hold `@Environment` reliably across OS versions, so `CoachBubble`'s press style applies `.motion(...)` to its label view, which is a `View`.

## Sites

Every line number is from commit 08888a0. `fade` and `movement` are the `Kind` to pass.

| Site | Today | Change |
|---|---|---|
| `Components/RestTimer.swift:53-60` | dot opacity loops 1 to 0.35 forever | When reduced, never set `pulse` and attach no animation: the dot stays at opacity 1. Read the environment in `RestTimer`. |
| `Components/RestTimer.swift:90` | band colour on expiry | `.motion(..., .fade, value: expired)` |
| `Components/ExerciseThumbnail.swift:50-59` | start and end frames flip forever | When reduced, take the existing static branch with the start image: no `TimelineView`. |
| `Components/ExerciseThumbnail.swift:251-258` (`LineArtHero`) | same, in the detail sheet | When reduced, show `start` through the existing static branch. |
| `Components/WorkoutTitleWheel.swift:178` | already gated by hand | `.motion(..., .movement, value: selectedId)`; delete the hand-written ternary. Keep the `reduceMotion` property only if something else in the file reads it. |
| `Components/KettleView.swift:85` | already gated | `animated && !Motion.isReduced(reduceMotion)` so the launch argument reaches it. |
| `App/RootTabView.swift:97` | coach bubble appears on tab change | `.motion(..., .fade, value:)` |
| `Coach/CoachBubble.swift:44` | opacity plus scale 0.8 | `.motionTransition(.opacity.combined(with: .scale(scale: 0.8)))` |
| `Coach/CoachBubble.swift:132` | spring press scale | `.motion(..., .movement, value:)` |
| `Coach/CoachDrawer.swift:536` | animated scroll to bottom | `withMotion(..., .movement)` |
| `Screens/WeekScreen.swift:177` | move banner leaves, list shifts up | `withMotion(..., .movement)` |
| `Screens/WeekScreen.swift:593`, `:594` | drop-target stroke and opacity | `.motion(..., .fade, value:)` |
| `Screens/MissedWorkoutBanner.swift:66` | expand | `withMotion(..., .movement)` |
| `Screens/LogSetRow.swift:198` | weight field revealed | `withMotion(..., .movement)` |
| `Screens/HistoryScreen.swift:374` | chevron rotates | `.motion(..., .movement, value:)` |
| `Screens/PlanValidationBanner.swift:37`, `:42`, `:53` | expand, acknowledge, show all | `withMotion(..., .movement)` |
| `Screens/TodayTab.swift:74` | route swap, default opacity transition | `withMotion(..., .fade)` |
| `Screens/WeeklyCheckIn/CheckInPatternsScreen.swift:128` | row removed | `withMotion(..., .movement)` |
| `Screens/LogScreen.swift:361` | media card slides up | `.motionTransition(.move(edge: .bottom).combined(with: .opacity))` |
| `Screens/LogScreen.swift:364` | drives the card | `.motion(..., .fade, value:)` |
| `Screens/LogScreen.swift:469` | progress bar width | `.motion(..., .movement, value:)` |
| `Screens/WeeklyCheckIn/WeeklyCheckInFlow.swift:135` | step slides from trailing | `.motionTransition(...)` |
| `Screens/WeeklyCheckIn/WeeklyCheckInFlow.swift:226`, `:237` | step change | `withMotion(..., .fade)` |
| `Screens/WeeklyCheckIn/WeeklyCheckInFlow.swift:461` | progress bar width | `.motion(..., .movement, value:)` |
| `Screens/Onboarding/OnboardingFlow.swift:102` | step slides from trailing | `.motionTransition(...)` |
| `Screens/Onboarding/OnboardingFlow.swift:206`, `:211` | step change | `withMotion(..., .fade)` |
| `Screens/Onboarding/OnboardingFlow.swift:357` | progress bar width | `.motion(..., .movement, value:)` |

Left alone: the plain `.transition(.opacity)` at `RestTimerState.swift:189`, `:206` and `WeekScreen.swift:172`; every `TimelineView(.periodic(by: 1.0))` clock (Log, rest countdown, the watch); the watch and widget targets, which have no animation.

If a site has moved or a new one has appeared since 08888a0, apply the rule above and list it in the report.

## Tests

New `PhaseTrainingTests/MotionTests.swift`:
- `animation(_, .fade, reduced:)` returns the same animation for true and false (`Animation` is `Equatable`);
- `animation(_, .movement, reduced: true)` is nil, and `reduced: false` returns the animation;
- `isReduced(true)` is true; `isReduced(false)` equals `forcedByLaunchArgument`.

`AnyTransition` cannot be compared, so `transition` has no test.

## Done when

- `grep -rnE "withAnimation\(|\.animation\(|repeatForever" --include='*.swift' PhaseTraining` prints only lines inside `Components/Motion.swift`. Paste the output in the report.
- `grep -rnE "\.transition\(" --include='*.swift' PhaseTraining` prints only `.transition(.opacity)` lines and lines inside `Motion.swift`.
- `PhaseTrainingTests/MotionTests` passes.
- `PhaseTrainingUITests/OnboardingGoalUITests` passes unchanged (it walks the migrated onboarding steps with the setting off).
- The app target builds with no new warnings in the touched files.

## Build and test

Slot A only: UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`, `-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A`. Every `xcodebuild` call passes `-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'` and that `-derivedDataPath`. Run `xcodegen generate` after adding the two files. One class per run with `-only-testing:`; never a whole target. Send the full log to a file and grep it:
`grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" <log>`

Out of scope: Dynamic Type, chart labels, any change to durations or curves, new UI tests, the watch and widget targets, `docs/`.

Do not commit.

## Report

One final report, no interim messages: files changed; test classes run with pass and fail counts; the two grep outputs; each decision made where this brief left something open (pick the conservative option and keep going); anything noticed outside this item's scope.
