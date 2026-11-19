# Brief: voice 2.3, spoken rest end on a locked phone

Backlog item: `docs/PLAN-backlog-2026-11-voice.md` 2.3. Spec: `docs/PLAN-voice.md` part 4.
Built by the lead directly (context already loaded). Line numbers re-measured
2026-11-19 at 55e3df1: `scheduleExpiryNotification` is `RestTimerState.swift:93-113`,
`add` `:115`, `rescheduleExpiryNotification` `:134`. Callers:
`ActiveWorkoutController.swift:119` (start), `:95` and `:107` (reschedule).

## Files

Edit:
- `PhaseTraining/Screens/RestTimerState.swift` (schedule, add, reschedule, cancel)
- `PhaseTraining/Workout/ActiveWorkoutController.swift` (pass the cue line)
- `PhaseTraining/Voice/SpokenCue.swift` (`VoiceCuePlayer.lockedRestEndLine`, `render`)
- `PhaseTrainingTests/RestTimerStateTests.swift`

No new Swift files, so no `xcodegen generate`. No `UIBackgroundModes`.

## Design

1. Arm first, upgrade second. Every schedule adds the request with `.default`
   exactly as today. When a cue line is given, a main-actor task renders it with
   `RestTimerState.renderCue` (default: `VoiceCuePlayer.shared.render`, which calls
   `SpeechOutput.renderToFile` with the chosen voice). If the render returns while
   at least `cueLeadSeconds` (2 s) of the original countdown remain and no newer
   schedule or cancel has happened (`renderGeneration`), the request is replaced
   under the same id with `UNNotificationSound(named:)` for the file's name. A
   late or failed render leaves the `.default` request in place.
2. Lateness is measured on the wall clock as elapsed render time against the
   seconds left at schedule, so an injected `now` in tests does not make every
   render late.
3. The line is `SpokenCue.restEnd` behind the same gate as the foreground cue
   (`cuesOn`, VoiceOver off). nil means no render. `start` and
   `rescheduleExpiryNotification` take an optional `cue`; the controller passes
   `VoiceCuePlayer.shared.lockedRestEndLine(session:next: nextUp())`.
4. Stale files: after each render decision, delete every `pt_speech_*.caf` in
   `soundsDirectory` except the one now in use; a cancel deletes all of them.
5. Test seams: `lastRequestedSoundName` (nil = `.default`), `pendingRender` (await
   it), `renderCue`, `soundsDirectory`.

## Done

`RestTimerStateTests` gains: sound name set after an in-time render; `.default`
after a failed render; `.default` after a late render; a newer schedule wins over
a slower earlier render; stale files deleted and the in-use file kept. All of
`RestTimerStateTests`, `SpokenCueTests`, `ActiveWorkoutControllerTests` pass.
Locked-phone playback of the rendered `.caf` is a device check (2.7 covers
on-device audio).
