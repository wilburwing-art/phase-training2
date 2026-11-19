# Voice mode

Specced 2026-11-18. Backlog: `docs/PLAN-backlog-2026-11-voice.md`.
Owner decisions (Phase 0 there): workout voice first, coach voice second;
on-device speech recognition; on-device system voices; push-to-talk and Siri
intents, with no always-on microphone.

## Problem

Mid-workout the lifter has chalk on their hands, the phone is on the floor or
in a pocket, and AirPods are in. Logging a set takes an unlock, a tap into the
row, two text fields and a check dot (`LogSetRow.swift:75`, `:178`, `:97`).
Rest end is a system sound and a haptic (`RestTimerState.swift:226`, `:241`)
or a "Rest's up" notification that says nothing about the next set. The app
has no microphone, speech or App Intent code. The coach, which ROADMAP wanted
to reach by voice on the walk into the gym, is text-only and is cut from the
store build (`DECISION-coach-at-launch.md`).

"Best in class" here means: a set is logged by voice in one utterance with
the phone locked, the app speaks the next set when rest ends even in the
background, and nothing it heard is applied without a readback and an undo.

## Parts

1. **Active workout controller.** The session lives in `LogScreen` `@State`
   (`LogScreen.swift:47`), so nothing outside the screen can log a set. That
   is why the Live Activity shipped without Skip and +15
   (`docs/HANDOFF-live-activity.md:47`). A `@MainActor` controller owns
   `ActiveSession` and `RestTimerState` and exposes `logSet`, `completeSet`,
   `skipRest`, `addRest`, `nextUp`. `LogScreen`, the voice layer, the intents
   and the Live Activity all call it.
2. **Command grammar.** A pure parser from a transcript to a `VoiceCommand`:
   "185 for 5", "one eighty five by five at RPE 8", "same again", "done",
   "skip rest", "add fifteen", "what's next", "how many left", "undo". Number
   words, lb and kg, and the free-text rules in
   `phase-training-freetext-weight-reps-parsing` (`SessionModels.swift:158`).
3. **Speech input.** `SpeechAnalyzer` on iOS 26 and `SFSpeechRecognizer` with
   `requiresOnDeviceRecognition` on iOS 17 to 25, behind one protocol with a
   fake for tests. Push-to-talk only. Contextual strings carry today's
   exercise names and the command words. Audio never leaves the device.
4. **Speech output.** `AVSpeechSynthesizer` with the best installed Premium or
   Enhanced voice, the audio session set to duck music and restore it after.
   For a locked phone, the rest-end line is rendered to a sound file with
   `AVSpeechSynthesizer.write` and attached to the existing `pt.rest_expiry`
   notification, so the app needs no background audio mode.
5. **Workout surfaces.** A push-to-talk button on the log screen with a heard
   card ("Bench, set 3: 185 x 5", Undo). App Intents for log set, skip rest,
   add rest and what's next, reachable from Siri, AirPods and the Action
   button. Skip and +15 buttons on the rest Live Activity.
6. **Coach voice** (only where `CoachEntitlement.coachAvailable`,
   `CoachEntitlement.swift:53`). A check-in screen that runs the same turn as
   the drawer (`CoachDrawer.swift:324`) with speech in and out. Proposals stay
   pending and surface after the workout (ROADMAP, settled).

## Where the data comes from and how often it updates

| Data | Source | Updates |
|---|---|---|
| Next set, target reps, last weight | `LoggedExercise` (`SessionModels.swift:194`), `prevSets` | each set logged |
| Rest remaining | `RestTimerState.remaining(at:)` (`:131`) | every second while resting |
| Recognizer vocabulary | today's session exercise names | session start |
| Voice choice, cue level | UserDefaults keys under `pt_voice_*` | on change in Settings |
| Coach turn | `CoachConversationStore` per-day thread (`CoachConversationStore.swift:37`) | each turn, same thread as keyboard chat |

## Gates

- Workout surfaces (part 5) start only after the controller (part 1) is
  under `LogScreen` with the existing set-logging tests green.
- Voice ships on by default only after the device check in Phase 2: at least
  95 of 100 recorded gym utterances parse to the intended command, with music
  playing through AirPods.
- Coach voice reaches only builds where `coachAvailable` is true. The store
  build shows none of it.
- A command is applied only after a readback. Destructive commands (delete a
  set, end the workout) are refused by voice.

## Out of scope

Always-on listening and wake words. Cloud speech in or out. Voice on the
watch (it already logs by tap, `WatchSessionModel.swift:76`). Voice control
of plan editing, Week or Progress. Body weight by voice (11c 7.1 owns the
first `AppShortcutsProvider`; this track adds phrases to it).
