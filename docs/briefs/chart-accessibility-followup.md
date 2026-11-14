# Follow-up brief: chart accessibility, review rulings

Follows `docs/briefs/chart-accessibility.md`. Same agent, same slot, same rules (no visual change, no commit, nothing under `docs/`). The lead read the diff on 2026-11-14 and accepts it with the three changes below. Approach A for the button cards stands.

Skills: `phase-training-xcuitest-recipe`, `phase-training-xcodebuild-test-failed-grep-full-log`.

## 1. Volume is spoken as a whole number

`volumeCard` passes `formatBigNum` as the spoken format, so VoiceOver gets "12.4k" and "42k". The display string truncates for space; speech has no such limit.

- Add to `ChartSpeech`:
  ```swift
  /// "12,400". Rounded to a whole number, grouped for the locale.
  static func wholeNumber(_ value: Double, locale: Locale = .current) -> String
  ```
- In `ProgressScreen+StatCards.swift`, `volumeCard` passes `{ ChartSpeech.wholeNumber($0) }` to both `weeklySpoken` and `weeklyDescriptor`. The visible text keeps `formatBigNum`.
- `sessionsCard` keeps its integer closure.
- `ChartSpeechTests`: `wholeNumber(12_449.6, locale: en_US)` is "12,450"; `wholeNumber(0, locale: en_US)` is "0".

## 2. The UI test must check the new strings

`test_bodyWeightCard_speaksEntryCount` asserts the label contains "entries", which the visible text "N entries" already satisfied before this change. Replace it with `test_chartsSpeakTheirData` in `ProgressScreenUITests`, same seed (`--seed-progress-demo`):

- `progress-body-weight-card` label contains "since the first entry". If the seed has one body-weight entry, assert "1 entry" instead and say so in the report.
- `app.staticTexts["BODY WEIGHT"]` exists.
- An element whose label is "Sessions per week" exists and its `value` (as a String) begins with "This week". Query with `app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Sessions per week")).firstMatch`.
- An element whose label is "Volume per week" or "Sets per week" exists and its value begins with "This week".
- Tap `progress-body-weight-card`; an element whose label is "Body weight over time" exists within 5 seconds and its value contains " to " or "1 entry".

If one of these elements cannot be found, print the element dump for that card (the file has `elementDump(app)`), and decide from the dump:
- the label is in the tree under another element type or the value sits in another attribute: fix the query;
- the label is absent from the tree: that is an app fault. Fix it in the app only when the fix is an accessibility modifier on the same view (for example `.accessibilityElement(children: .ignore)` ordering, or moving the modifiers to the enclosing container). Anything larger: leave the assertion out, and report the dump lines and what you tried.

## 3. Finish the report

The first report arrived cut off after site 2. The final report for this follow-up repeats, in full: the spoken label and value for sites 3 to 9, every decision made where either brief left something open, and anything noticed outside the item's scope.

## Done when

- `PhaseTrainingTests/ChartSpeechTests` passes.
- `PhaseTrainingUITests/ProgressScreenUITests` passes, `test_chartsSpeakTheirData` included.
- The app target builds with no new warnings in the touched files.

## Build and test

Slot A only: UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`, `-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A`. One class per run, full log to a scratchpad file, grep:
`grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" <log>`

## Report

One final report, no interim messages: files changed; test classes run with pass and fail counts; the items in section 3; for section 2, which assertions landed and the dump lines for any that did not.
