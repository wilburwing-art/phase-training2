# Brief: voice 2.2, spoken cues in the foreground

Backlog item: `docs/PLAN-backlog-2026-11-voice.md` 2.2. Spec: `docs/PLAN-voice.md` part 4.
Agent: builder. Line numbers re-measured 2026-11-19 at f75f7a3: `maybeFireRestExpiry`
is now `RestTimerState.swift:213` (backlog said 226) and the system sound is `:228`
(backlog said 241).

## Skills to load

`phase-training-freetext-weight-reps-parsing` (weight strings are free text).

## Files

Create:
- `PhaseTraining/Voice/SpokenCue.swift`
- `PhaseTrainingTests/SpokenCueTests.swift`

Edit:
- `PhaseTraining/Screens/RestTimerState.swift` (expiry tick, warning tick, one new field)
- `PhaseTraining/Data/WeeklyReminderScheduler.swift` (`NotificationDelegate.willPresent` only)

Do not touch `SpeechOutput.swift`, `VoiceSettings.swift`, `ActiveWorkoutController.swift`,
`LogScreen.swift` or any Live Activity file. This builder runs `xcodegen generate`
(two new Swift files).

## Design

### 1. Line text: `enum SpokenCue` (pure, no state)

```swift
enum SpokenCue {
    static func restEnd(next: NextUp, in session: ActiveSession) -> String
    static func warning(next: NextUp, in session: ActiveSession) -> String
    static func readback(exercise: LoggedExercise, setIdx: Int) -> String
}
```

Rules:
- Load phrase: weight from `next.lastWeight` read with the free-text number rule
  (`LoggedSet(weight:…).weightValue` or an equivalent leading-number parse; do not
  re-implement a different parser). Format a whole number without decimals ("185"),
  else one decimal trimmed ("92.5"). No unit word.
  - weight present and targetReps > 0: `"185 for 5"`
  - weight absent (or exercise `isBodyweight` with no weight) and targetReps > 0: `"5 reps"`
  - targetReps <= 0: weight alone `"185"`, or no load phrase at all
- Straight sets (exercise has no `supersetGroup`):
  - not last: `"Rest's up. Bench Press, set 3 of 4, 185 for 5."`
  - last set (`setNumber == totalSets`): `"Rest's up. Bench Press, last set, 185 for 5."`
- Superset (`supersetGroup != nil`): round = `setNumber`, rounds = max `sets.count` across
  the group's members.
  - `"Rest's up. Superset, round 2 of 3. Bench Press, 185 for 5."`
  - last round: `"Rest's up. Superset, last round. Bench Press, 185 for 5."`
- Missing load phrase drops its comma: `"Rest's up. Plank, set 2 of 3."`
- `warning`: `"10 seconds. Bench Press next."`
- `readback(exercise:setIdx:)` reads the logged set: `"Bench Press, set 3, 185 for 5."`,
  bodyweight `"Pull-up, set 2, 8 reps."`. Uses the set's own weight and reps, not targets.
  Nothing calls it yet; item 2.4 (push-to-talk) calls it after a voice-logged set.

### 2. Gate and speaker: `@MainActor final class VoiceCuePlayer`

```swift
@MainActor
final class VoiceCuePlayer {
    static let shared = VoiceCuePlayer()
    init(output: (() -> SpeechOutputting)? = nil,          // lazy; default builds SpeechOutput()
         defaults: UserDefaults = .standard,
         voiceOverRunning: @escaping () -> Bool = { UIAccessibility.isVoiceOverRunning })

    /// Speaks the rest-end line. Returns true when it spoke, false when cues are
    /// off, VoiceOver is running, or there is no next set.
    @discardableResult func restEnded(session: ActiveSession, next: NextUp?) -> Bool
    /// Level `.full` only.
    @discardableResult func restWarning(session: ActiveSession, next: NextUp?) -> Bool
    /// Level `.full` only. For item 2.4.
    @discardableResult func readback(exercise: LoggedExercise, setIdx: Int) -> Bool

    /// The pure gate, also used by the notification delegate.
    nonisolated static func speaksRestEnd(settings: VoiceSettings, voiceOverRunning: Bool) -> Bool
}
```

- Reads `VoiceSettings.load(from: defaults)` on every call (the sheet can change it mid-workout).
- Before speaking, sets the output's `voiceIdentifier` to `settings.voiceId` when the
  output is a `SpeechOutput` (cast; the protocol stays as is).
- VoiceOver running: never speak. The existing `AccessibilityNotification.Announcement("Rest done")`
  stays the VoiceOver path.

### 3. Wiring in `RestTimerState.swift`

- `maybeFireRestExpiry(at:)`: after setting `alertFiredFor`, call
  `VoiceCuePlayer.shared.restEnded(session: session, next: workout.nextUp())`. The system
  sound 1322 plays only when the cue did not speak AND notifications are not authorized
  (today's rule, plus the cue check). Haptic, Live Activity and VoiceOver announcement unchanged.
- New field `warningFiredFor: Date?` on `RestTimerState`, reset in `start` and `clear`.
- New `maybeFireRestWarning(at:)` called from the same tick `onChange` and `onAppear`:
  fires once per rest start when `duration >= 20` and remaining is in `1...10`. Sets
  `warningFiredFor = startedAt` whether or not it spoke, so it never fires late.
- Keep the TimelineView structure as is.

### 4. `NotificationDelegate.willPresent`

For the `RestTimerState.expiryNotificationId` request only: when
`VoiceCuePlayer.speaksRestEnd(settings: VoiceSettings.load(), voiceOverRunning: UIAccessibility.isVoiceOverRunning)`
is true, present `[.banner]` without `.sound` so the banner chime does not talk over the
spoken line. Every other notification and the cues-off case keep `[.banner, .sound]`.
Put the choice in a static pure func (for example
`NotificationDelegate.presentationOptions(identifier:speaksRestEnd:)`) so a test covers it.

## Done

`SpokenCueTests` passes, with cases for:
- straight set mid-exercise, last set, superset round, superset last round
- bodyweight (no weight), weight string with unit suffix ("60kg" reads "60"), decimal weight
- targetReps 0
- warning line, readback line (weighted and bodyweight)
- `VoiceCuePlayer` with `FakeSpeechOutput` and a suite `UserDefaults`: cues off speaks nothing;
  VoiceOver on speaks nothing; level `.restEnd` speaks rest end but not warning or readback;
  level `.full` speaks all three; nil next speaks nothing
- `presentationOptions`: rest id + speaking drops `.sound`; other ids keep it

Also run `RestTimerStateTests` and `SpeechOutputTests` (must stay green).

## Slot

Slot A: iPhone 17 Pro, UDID 3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2,
`-derivedDataPath /Users/wilburpyn/Library/Developer/Xcode/DerivedData-A`.
Every xcodebuild call passes `-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'`.
Full log to a file, then `grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" <log>`.

## Report

One final report: files changed, test classes run with pass/fail counts, decisions on
anything this brief left open, anything outside scope. Do not commit.
