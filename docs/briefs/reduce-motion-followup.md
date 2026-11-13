# Brief: Reduce Motion, follow-up

Follows `docs/briefs/reduce-motion.md`. Agent: builder. Same skills, same Slot A (UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`, `-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A` on every `xcodebuild` call).

## Rulings on the first report

- `Motion.pulse(duration:)`: accepted.
- `RestTimer` re-sync on `onChange(of: reduceMotion)`: accepted.
- Thumbnail and hero crossfade lines as `.motion(..., .fade, ...)`: accepted.

## One change

`motionTransition` sets the transition from inside a `ViewModifier`. The slide and scale then depend on SwiftUI carrying the transition trait out through a custom modifier, and nothing in this repo checks that with the setting off. Put the transition back on the view itself, where it was before the migration.

At each of the four sites, add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to the enclosing view and write:

```swift
.transition(Motion.transition(<the original transition>, reduced: Motion.isReduced(reduceMotion)))
```

| Site | Original transition |
|---|---|
| `Coach/CoachBubble.swift:44` | `.opacity.combined(with: .scale(scale: 0.8))` |
| `Screens/LogScreen.swift:361` | `.move(edge: .bottom).combined(with: .opacity)` |
| `Screens/WeeklyCheckIn/WeeklyCheckInFlow.swift:135` | `.opacity.combined(with: .move(edge: .trailing))` |
| `Screens/Onboarding/OnboardingFlow.swift:102` | `.opacity.combined(with: .move(edge: .trailing))` |

The property goes on the struct whose `body` (or computed view property) contains the `.transition` line. If that struct already has the property, reuse it.

Then delete `View.motionTransition` and `MotionTransitionModifier` from `Components/Motion.swift` and fix the file's header comment, which names `.motionTransition(_:)`.

## Done when

- `grep -rn "motionTransition\|MotionTransitionModifier" PhaseTraining` prints nothing.
- `grep -rnE "\.transition\(" --include='*.swift' PhaseTraining` prints the five `.transition(.opacity)` lines and the four `Motion.transition(` lines above.
- `PhaseTrainingTests/MotionTests` and `PhaseTrainingUITests/OnboardingGoalUITests` pass, one class per run.

Do not commit. Do not touch `docs/`.

## Report

One final report: files changed, test classes with pass and fail counts, the two grep outputs, anything that did not match this brief.
