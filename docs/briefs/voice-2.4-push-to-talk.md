# Brief: voice 2.4, push-to-talk on the log screen

Backlog item: `docs/PLAN-backlog-2026-11-voice.md` 2.4. Spec: `docs/PLAN-voice.md` part 3.
Agent: builder. Written 2026-11-19 at 3e30578.

## Skills to load

`phase-training-tap-budget-is-a-floor`, `phase-training-xcuitest-recipe`,
`phase-training-freetext-weight-reps-parsing`, `phase-training2-gitignored-pbxproj`.

## Slot

Slot A: iPhone 17 Pro, UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`,
`-derivedDataPath /Users/wilburpyn/Library/Developer/Xcode/DerivedData-A`.
Every xcodebuild call passes `-project PhaseTraining.xcodeproj -scheme PhaseTraining
-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'`
and that derived data path. Full log to a file, then
`grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" <log>`.

This builder runs `xcodegen generate` (new Swift files). Do not commit. Do not push.

## Files

Create:
- `PhaseTraining/Voice/VoiceLogModel.swift` (all logic)
- `PhaseTraining/Screens/VoiceMicButton.swift` (button + heard card views)
- `PhaseTrainingTests/VoiceLogFlowTests.swift` (unit tests, fake transcriber)
- `PhaseTrainingUITests/VoiceLogUITests.swift` (one UI test, screenshot of the heard card)

Edit:
- `PhaseTraining/Screens/LogScreen.swift` (mic button in the sticky header, heard card overlay, model ownership)
- `PhaseTraining/Voice/SpokenCue.swift` (add one pure line function, below)
- `PhaseTraining/Voice/SpeechInput.swift` only if a canned transcriber for the UI-test launch flag needs a hook; prefer putting the canned transcriber and permissions in `VoiceLogModel.swift` under the flag.

Do not touch `ActiveWorkoutController.swift`, `VoiceCommand.swift`, `RestTimerState.swift`,
`SpeechOutput.swift`, any Intents or Live Activity file.

## Design

### 1. `VoiceLogModel` (`@MainActor final class`, `ObservableObject`)

```swift
init(workout: ActiveWorkoutController,
     input: SpeechInput?,                       // nil until prepare() builds the default
     readback: @escaping (LoggedExercise, Int) -> Void = { VoiceCuePlayer.shared.readback(exercise: $0, setIdx: $1) },
     now: @escaping () -> Date = Date.init)
func prepare() async            // input == nil → input = await SpeechInput.makeDefault(output: nil) (or the UI-test canned one)
func pressDown() async          // input.pressDown(exerciseNames: workout.session.exercises.map(\.name))
func release() async            // transcript = await input.release(); handle(transcript)
func cancel()                   // input.cancel()
func handle(_ transcript: String?)   // parse + apply; internal so tests call it directly
func undo()                     // the card's Undo button
@Published private(set) var card: HeardCard?
```

```swift
struct HeardCard: Equatable {
    enum Kind: Equatable { case applied, info, unparsed }
    let kind: Kind
    let heard: String          // the transcript, shown in quotes ("" when nil)
    let message: String        // what happened, e.g. "Bench Press, set 3: 185 × 5"
    let target: SetTarget?     // exIdx/setIdx the change landed on (applied only)
    let undoable: Bool
    let shownAt: Date
}
```

The card is shown for 5 s (`now()` based; the view hides it with a `Task.sleep`
keyed on `shownAt`, and the model exposes `cardIsLive(at:)` so tests check expiry
without sleeping). A new card replaces the old one.

Parse with `VoiceCommand.parse(transcript, context: VoiceContext(isBodyweight: target?.isBodyweight ?? false))`
where the target is `workout.nextUp()` (the first undone set, superset-aware).

Command mapping (target = `workout.nextUp()`):

| Command | Apply | Card message |
|---|---|---|
| nil transcript or `parse` nil | nothing | `.unparsed`, "Didn't catch that" |
| `logSet(w, r, rpe, unit)` | `workout.logSet(exIdx:setIdx:weight:reps:rpe:)` with weight formatted like `SpokenCue.format` (185.0 → "185", 102.5 → "102.5"), nil weight keeps the cell, rpe formatted the same, nil keeps | `.applied`, "<Exercise>, set n: 185 × 5" (bodyweight: "5 reps") |
| `logSet` with a spoken unit that differs from the exercise unit (`kg` vs anything but `"kg"`, `lb` vs `"kg"`; bodyweight exercise ignores the unit) | nothing | `.unparsed`, "Heard kg. <Exercise> logs in lb" (or the reverse). No conversion. |
| `sameAgain` | weight and reps of the latest done set in the target's exercise; none → `.info`, "Nothing to repeat yet" | `.applied`, same message shape as logSet |
| `completeSet` | `logSet` with all nils (cell values as they stand) | `.applied` |
| `skipRest` | `workout.skipRest()` if a rest is counting down (`workout.rest.remaining(at: now()) != nil`), else nothing | `.info`, "Rest skipped" / "No rest running" |
| `addRest(s)` | `workout.addRest(seconds: s)` with the same no-rest check | `.info`, "+15 s rest" / "-15 s rest" / "No rest running" |
| `whatsNext` | nothing | `.info`, `SpokenCue.upNext(next:in:)` (new, see 3) or "All sets are logged" |
| `setsLeft` | nothing | `.info`, "4 sets left" / "1 set left" / "All sets are logged" |
| `undo` | the last voice change (see 2) | `.info`, "Undid <Exercise>, set n" / "Nothing to undo" |
| any set command with `nextUp()` nil | nothing | `.info`, "All sets are logged" |

After a `.applied` set change, call `readback(exercise, setIdx)` with the exercise as it
stands after the apply (the player itself gates on cues on and level).

### 2. Undo

Before a set change, record `UndoEntry(exerciseID, setNum, before: LoggedSet, after: LoggedSet, restBefore: RestTimerState)`.
Undo (button or spoken) applies only when that set, found by exercise id and set num,
still equals `after`; otherwise "Nothing to undo" and nothing changes (a manual edit
in between wins). Undo writes `before` back into `workout.session`, and if the
current rest is anchored to that set (`rest.exIdx/setIdx`) and was started by this
change, `workout.skipRest()` (clear). Do not restore an older rest. One level of undo:
the entry is cleared after use. The button shows only while the card is live; spoken
undo works on the entry any time until the next voice set change.

### 3. `SpokenCue.upNext(next:in:)`

`"<Exercise>, set 3 of 4, 185 for 5"` (the restEnd line without "Rest's up. ", same
superset and last-set wording, no trailing period). Implement by sharing the body
with `restEnd`; `restEnd` output must not change (SpokenCueTests stays green).

### 4. Mic button (`VoiceMicButton`)

- In `stickyHeader`, between `Spacer()` and "Log all". 28pt circle like the cancel
  button, `mic` / `mic.fill` (listening, accent fill) / `mic.slash` (unavailable).
  Header must not wrap on a 393pt width at default Dynamic Type.
- Tap: idle → `pressDown`; listening → `release`. Hold (press longer than 0.35 s):
  `pressDown` on touch down, `release` on touch up. Use one gesture approach that does
  both; a `DragGesture(minimumDistance: 0)` with a start timestamp is fine.
- While listening, the card area shows the live partial ("Listening…" when empty).
- Unavailable: tapping shows a `.info` card with `SpeechInputUnavailable.message`.
- `.accessibilityLabel("Voice log")`, `.accessibilityHint("Double tap to talk, double tap again to stop")`,
  `.accessibilityInputLabels(["Voice log", "Microphone", "Talk"])`,
  `.accessibilityIdentifier("log-voice-mic")`. Listening adds `.isSelected` trait.
- Leaving the screen (`onDisappear`) calls `cancel()`.

### 5. Heard card

Overlay under the sticky header (top of the scroll area), not pushing rows down.
Shows `"heard"` in quotes (ink3), the message (ink), and an Undo button
(`log-voice-undo`) when `undoable`. Identifier `log-voice-card`. Posts
`UIAccessibility.post(notification: .announcement, argument: message)` when a card appears.

### 6. Model ownership

`LogScreen` owns it: `@StateObject private var voice: VoiceLogModel` initialised from
`workout` in `init` (add an explicit `init` keeping the current parameters, or a
lazy holder; keep the two `LogScreen(` call sites in previews and `TodayTab` compiling
unchanged). `.task { await voice.prepare() }`.

### 7. UI-test launch flag

`--ui-test-voice-transcript=<text>`: `prepare()` builds a `SpeechInput` with a canned
transcriber (supportsOnDevice true, finish returns `<text>`) and granted permissions,
so the simulator never asks for the mic. Read via `ProcessInfo.processInfo.arguments`.

## Done

1. `VoiceLogFlowTests` (new, `PhaseTrainingTests`) passes with at least these cases, using a
   real `ActiveWorkoutController` over a temp `SessionStore` (copy the setup in
   `ActiveWorkoutControllerTests`) and a fake transcriber (copy `FakeTranscriber` /
   `FakePermissions` from `SpeechInputTests`, they are private there):
   - "185 for 5" logs the next-up set (weight "185", reps "5", done) and calls readback once
   - "same again" copies the previous done set into the next one
   - "same again" with no done set is info, nothing changes
   - undo button restores the set and clears the rest it started
   - undo after a manual edit of that set does nothing
   - spoken "undo" reverts the last voice change
   - unparsed ("pizza") shows "Didn't catch that" and leaves `session` equal to before
   - nil transcript shows "Didn't catch that"
   - kg spoken on an lb exercise changes nothing
   - superset: "100 for 8" lands on the member `nextUp()` names
   - skip rest with and without a running rest
   - card expiry: `cardIsLive(at: shownAt + 4.9)` true, `+ 5.1` false
   - pressDown then release through the fake transcriber applies the transcript
2. `SpokenCueTests`, `ActiveWorkoutControllerTests`, `SpeechInputTests` still pass.
3. `VoiceLogUITests` (new, `PhaseTrainingUITests`): launch with the supersets demo seed used by
   `LogFlowTests` plus `--ui-test-voice-transcript=185 for 5`, open the log screen the way
   `LogFlowTests` does, tap `log-voice-mic` twice, assert `log-voice-card` exists and
   contains "185", attach a screenshot (`XCTAttachment`, lifetime `.keepAlways`).
4. Final report: files changed, each class with pass/fail counts, decisions on anything
   left open, anything outside scope.
