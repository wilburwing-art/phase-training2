# Brief: voice 1.3, voice command grammar

Backlog item: `docs/PLAN-backlog-2026-11-voice.md` 1.3. Spec: `docs/PLAN-voice.md` part 2.
Agent: builder-heavy. Measured 2026-11-18 at 00e7df8: `PhaseTraining/Voice/` does not exist;
`LoggedSet.leadingNumber` is `private static` at `Shared/Models/SessionModels.swift:176`.

## Skills to load

`phase-training-freetext-weight-reps-parsing`.

## Files

Create only:
- `PhaseTraining/Voice/VoiceCommand.swift`
- `PhaseTrainingTests/VoiceCommandParserTests.swift`

Do not edit `SessionModels.swift` or `ActiveWorkoutController.swift`. Reproduce the
`leadingNumber` rules inside the parser for digit tokens (trim, leading `+`, lone `,` is a
decimal, `,` with `.` is thousands). This builder runs `xcodegen generate`.

## Slot

Slot B: iPhone 17 Pro B, UDID 0929A7A4-66C6-454B-873E-F8349E2FD397,
`-derivedDataPath /Users/wilburpyn/Library/Developer/Xcode/DerivedData-B`.
Boot it first: `xcrun simctl boot <UDID>; xcrun simctl bootstatus <UDID> -b`.
Slot A is in use by another session. Do not touch it.

## Types

```swift
enum VoiceUnit: Equatable { case lb, kg }

struct VoiceContext: Equatable {
    /// Current exercise logs reps only (LoggedExercise.isBodyweight).
    var isBodyweight: Bool = false
}

enum VoiceCommand: Equatable {
    /// weight nil = keep the set's current or last weight ("same weight for 5",
    /// bodyweight reps). unit nil = not spoken; the caller uses the exercise unit.
    case logSet(weight: Double?, reps: Int, rpe: Double?, unit: VoiceUnit?)
    case sameAgain, completeSet, skipRest
    case addRest(seconds: Int)
    case whatsNext, setsLeft, undo

    static func parse(_ transcript: String, context: VoiceContext) -> VoiceCommand?
}
```

Pure: no UIKit, no Speech, no controller reference. `nonisolated` (no `@MainActor`).

## Rules, in this order

1. **Normalize.** Lowercase. `'` removed ("what's" -> "whats"). `-` and `,`-between-words
   become spaces. Split digit runs from letters ("185x5" -> 185 x 5, "60kg" -> 60 kg,
   "5reps" -> 5 reps). Keep `.` and `,` inside a digit run (62.5, 60,5). Drop other
   punctuation. Empty -> nil.
2. **Refuse.** Any token in {delete, remove, erase, clear, end, ending, finish, finished,
   cancel, discard, quit, stop, reset, restart, abandon} -> nil. Checked before anything else,
   so "finish workout", "end rest", "delete that set" are all nil.
3. **Fillers** dropped: uh, um, er, ok, okay, hey, please, so, like, alright, yeah, then,
   and the exercise words the recognizer may prepend are unknown words (rule 7).
4. **Fixed phrases** (whole remaining token stream, after fillers):
   - sameAgain: "same again", "same", "again", "same as last", "same as last time",
     "same as before", "repeat", "repeat that", "same thing", "one more".
   - completeSet: "done", "set done", "got it", "complete", "completed", "set complete", "check".
   - skipRest: "skip", "skip rest", "skip the rest", "skip timer", "skip the timer", "im ready", "ready".
   - whatsNext: "whats next", "what is next", "next", "whats up next", "what now", "next set", "next exercise".
   - setsLeft: "how many left", "how many sets left", "sets left", "how many more",
     "how many to go", "how many sets to go", "how many remaining".
   - undo: "undo", "undo that", "scratch that", "take that back", "go back", "oops".
5. **addRest.** "add N", "add N seconds", "plus N", "N more seconds", "give me N more",
   "add a minute" (60), "add N minute(s)" (N*60), "add half a minute" (30). Default unit is
   seconds. Valid 1...600, else nil.
6. **Numbers.** One number = a maximal run of number tokens:
   - digits: "185", "62.5", "60,5".
   - words: zero/oh, one..nineteen, twenty..ninety, hundred, "a hundred", "and" inside a
     hundred ("a hundred and five" = 105), "point" ("sixty point five" = 60.5), "and a half"
     (+0.5, "eight and a half" = 8.5).
   - spoken loads: digit-word followed by a tens or teen word is hundreds:
     "one eighty five" = 185, "two twenty five" = 225, "three fifteen" = 315,
     "one oh five" = 105, "one twenty" = 120, "ninety five" = 95, "forty five" = 45.
   - homophones as numbers: "to"/"too" = 2 only when not between two numbers;
     "won" = 1, "ate" = 8.
7. **logSet** forms, unknown words dropped first ("bench 185 for 5" works):
   - `W [unit] SEP R [reps] [RPE]`, SEP in {for, four, fore, by, x, times, ×}.
     "four"/"for" between two numbers is SEP, never a digit: "185 four 5" = 185 x 5.
   - `R reps [RPE]` -> weight nil ("12 reps").
   - `same weight SEP R` / `weight SEP R` / `wait SEP R` -> weight nil ("wait for 5" is the
     recognizer hearing "weight for 5").
   - bodyweight only: a lone number `R [RPE]` -> weight nil.
   - unit tokens: lb, lbs, pound, pounds -> .lb; kg, kgs, kilo, kilos, kilogram(s) -> .kg.
     Unit may follow W or R ("185 for 5 pounds").
   - RPE: "rpe N", "at rpe N", "r p e N", "rp N". 1...10, halves allowed. Out of range -> nil
     for the whole command.
   - Bounds: weight 0 < w <= 2000, reps 1...100 (Int(exactly:) after rounding), else nil.
   - Two bare numbers with no SEP ("185 5"), three numbers ("185 4 5" as digits), or any
     leftover number token -> nil. A wrong log is worse than a re-ask.
8. Anything else -> nil.

## Done

- `VoiceCommandParserTests` with at least 80 fixtures, table-driven
  (`[(String, VoiceContext, VoiceCommand?)]`), each rule above covered, including:
  "185 for 5", "one eighty five by five at RPE 8", "185x5", "100 kilos for 5",
  "two twenty-five for five", "a hundred and five for eight", "185 four 5", "wait for 5",
  "sixty point five for ten", "60,5 x 8", "same again", "done", "skip rest", "add fifteen",
  "add a minute", "what's next", "how many left", "undo", "bench 185 for 5", plus nil cases:
  "finish workout", "end rest", "delete that set", "185 5", "185 for 5 at rpe 12",
  "5000 for 5", "185 for 500", "", "hello", "add 900", and bodyweight vs non-bodyweight "twelve".
- Run on slot B:
  `xcodebuild test -project PhaseTraining.xcodeproj -scheme PhaseTraining -destination 'platform=iOS Simulator,id=0929A7A4-66C6-454B-873E-F8349E2FD397' -derivedDataPath /Users/wilburpyn/Library/Developer/Xcode/DerivedData-B -only-testing:PhaseTrainingTests/VoiceCommandParserTests > <scratch>/voice13.log 2>&1`
  then `grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" <log>` shows nothing.
- Do not commit. One final report: files, test count and result, any rule you had to
  decide, anything outside scope.
