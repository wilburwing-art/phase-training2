# Brief: chart accessibility labels and descriptors

Backlog item: `docs/PLAN-gap-backlog-2026-11b.md`, "Later, not scheduled": "Chart accessibility labels and descriptors (2 h)". Audit finding 8 in `audits/2026-11-10-gap-round/accessibility.md` (line 72). The `lineStrong` border token on the same backlog line is a separate item and is out of scope.

Agent: builder. Skills to load first: `phase-training2-gitignored-pbxproj`, `phase-training-xcodebuild-test-failed-grep-full-log`, `phase-training-xcuitest-recipe`.

## Problem

VoiceOver gets little or nothing from the app's charts. Checked at commit 8ee5470:

- The two Swift Charts in the body-weight and body-composition log sheets have no label, and their series are named "date" and "weight", so the default audio graph is announced with those words.
- The hand-drawn charts on Progress (volume line, sessions bars, muscle balance bars, body-weight and body-composition sparklines, finger-strength sparkline, the sparkline on each TOP EXERCISES row) are shapes with no accessibility element. The text around them is read piecemeal: the volume card reads "0" then a bare number, the sessions card reads "8w ago", "target: 4/wk", "this week" and never the counts, a muscle row reads its name and no amount, a body-weight delta is read as a signed number with no unit or direction.

## Rule

- No visual change at all. Only accessibility modifiers, spoken strings, mark value names, one dead import and two stale comments.
- Each chart becomes one VoiceOver element with a label (what it is) and a value (what it shows, in words). The two log-sheet charts and the two Progress week charts also carry an audio-graph descriptor.
- Card title `Text`s ("VOLUME / WEEK", "BODY WEIGHT" and the rest) stay their own static texts. UI tests query them (`ProgressScreenUITests.swift:41-51`, `:71`, `:196-199`, `MotivationBatchUITests.swift:99`). Never put `.accessibilityElement(children: .ignore)` on a container that includes a card title.
- Existing accessibility identifiers keep working: `progress-mood-after`, `progress-body-weight-card`, `progress-top-exercise-<name>`, `progress-finger-latest`, `progress-finger-log`, `progress-heatmap-*`, `exercise-strength`, `strength-estimate`.
- Spoken strings use no em or en dash and no U+2212 minus. Direction is a word: "up", "down".

## New file: `PhaseTraining/Components/ChartSpeech.swift`

Pure, no SwiftUI state. Signatures are fixed; bodies are yours.

```swift
import Accessibility
import Foundation

enum ChartSpeech {
    /// "176.5 lb", "18.5%", "12". `unit` is "" for a bare number, "%" joins
    /// with no space, anything else joins with one space.
    static func amount(_ value: Double, unit: String, decimals: Int) -> String

    /// "up 3.5 lb", "down 3.5 lb", "no change". "no change" when the
    /// difference rounds to zero at `decimals`.
    static func change(from first: Double, to last: Double, unit: String, decimals: Int) -> String

    /// Value string for a line series, oldest first.
    /// 0 points: nil.
    /// 1 point:  "1 entry, 176.5 lb"
    /// 2+:       "8 entries, 180.0 lb to 176.5 lb, down 3.5 lb, low 175.9 lb, high 181.2 lb"
    /// `noun` and `nounPlural` name the points ("entry"/"entries",
    /// "reading"/"readings", "test"/"tests", "session"/"sessions").
    static func seriesValue(_ values: [Double], unit: String, decimals: Int,
                            noun: String, nounPlural: String) -> String?

    /// "Nov 3 to Nov 14"; adds the year to both when the years differ;
    /// one date when first and last fall on the same day. Takes a calendar
    /// and locale so tests are stable.
    static func dateRange(from first: Date, to last: Date,
                          calendar: Calendar = .current, locale: Locale = .current) -> String

    /// Value string for a weekly series, oldest first, last element is the
    /// current week.
    /// "This week 3, target 4. Last 8 weeks, oldest first: 2, 3, 4, 0, 3, 4, 4, 3"
    /// With `target` nil the target clause is left out. `format` turns each
    /// number into its spoken form (pass `ProgressStats.formatBigNum` for
    /// volume, an integer formatter for counts).
    static func weeklyValue(_ values: [Double], target: Int?,
                            format: (Double) -> String) -> String?

    /// "24 percent of the total" for a share bar. 0 when total is 0.
    static func share(_ part: Double, of total: Double) -> String

    /// Week labels for a categorical axis, oldest first:
    /// "7 weeks ago", ..., "1 week ago", "This week".
    static func weekLabels(count: Int) -> [String]
}

/// One-series audio graph. Used through `.accessibilityChartDescriptor`.
struct SeriesChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let summary: String?
    let xTitle: String
    let yTitle: String
    let points: [Point]
    let isBar: Bool

    enum X: Equatable { case date(Date), category(String) }
    struct Point: Equatable { let x: X; let y: Double; let spoken: String }

    func makeChartDescriptor() -> AXChartDescriptor
    func updateChartDescriptor(_ descriptor: AXChartDescriptor)
}
```

Descriptor details:
- Dated points: `AXNumericDataAxisDescriptor` for x over `timeIntervalSince1970`, with a `valueDescriptionProvider` that speaks the date as abbreviated month and day. Category points: `AXCategoricalDataAxisDescriptor` with the labels in order. All points in one descriptor share one X kind; `precondition` on a mix.
- y axis: `AXNumericDataAxisDescriptor`, range from the series minimum to maximum, widened by 1 on each side when they are equal (a flat series must not make an empty range). The `valueDescriptionProvider` returns the point's `spoken` string when the value matches a point, else the number.
- One `AXDataSeriesDescriptor`, `isContinuous: !isBar`, name equal to `yTitle`.
- `updateChartDescriptor` writes title, summary, axes and series onto the passed descriptor.

## Sites

Line numbers are from 8ee5470. If one has moved, apply the same change at its new place and say so in the report.

| # | Site | Change |
|---|---|---|
| 1 | `Screens/BodyWeightLogSheet.swift:150` Chart in `trendCard` | Mark value names "Date" and "Weight". On the Chart (after `.frame`): `.accessibilityElement(children: .ignore)`, label "Body weight over time", value `seriesValue(... unit: unitLabel, decimals: 1, noun: "entry"...)` followed by ", " and `dateRange` of the oldest and newest entry, and `.accessibilityChartDescriptor` with dated points, x title "Date", y title "Weight in \(unitLabel)", each point spoken with `amount`. The "TREND" label and the delta text beside it are left alone. |
| 2 | `Screens/BodyCompositionLogSheet.swift:196` Chart in `trendCard(title:points:suffix:)` | Add a `spokenTitle` parameter: "Body fat percent" from `bfTrendCard`, "Lean mass" from `leanTrendCard`. Mark value names "Date" and `spokenTitle`. Same four modifiers as site 1: label "\(spokenTitle) over time", noun "reading", unit `suffix`, decimals 1, y title "Body fat percent" or "Lean mass in \(massUnit)". |
| 3 | `Screens/Progress/ProgressScreen+StatCards.swift:139-152` `volumeCard` content `VStack` (inside `card`, so the title is outside it) | `.accessibilityElement(children: .ignore)`, label "Volume per week" or "Sets per week" (follows `useSetCount`), value `weeklyValue(series, target: nil, format: formatBigNum)`, descriptor with category points from `weekLabels`, `isBar: false`, x title "Week", y title same as the label. |
| 4 | Same file `:76-95`, `sessionsCard`: the bars `HStack` and the three-caption `HStack` | Wrap those two in one container (a `VStack` with the same spacing 10, so layout is unchanged) and give it `.accessibilityElement(children: .ignore)`, label "Sessions per week", value `weeklyValue(buckets as Double, target: target, format: integer)`, descriptor with category points, `isBar: true`, x title "Week", y title "Sessions". The mood line `Text` stays outside the container as its own element with its identifier. |
| 5 | `Screens/Progress/ProgressScreen+BodyCards.swift:352-371` `muscleBar` | On the row `HStack`: `.accessibilityElement(children: .ignore)`, label `row.label`, value `ChartSpeech.share(row.volume, of: total)` where `total` is the sum of all rows' volume, passed in from `muscleBalanceCard`. No descriptor. |
| 6 | Same file `:72-109` `bodyWeightCardBody` | See "Cards that are buttons" below. Spoken content: "\(latestDisplay), \(change) since the first entry, N entries". With one entry: "\(latestDisplay), 1 entry". `change` uses the display unit and 1 decimal. |
| 7 | Same file, body-composition card (`:157-193`) and `statBlock` (`:195-214`), `miniSeries` (`:216-227`) | `statBlock` takes a `spoken` label ("Body fat", "Lean mass") and stops using `label.capitalized`; its delta is spoken with `ChartSpeech.change`-style words ("up 0.4", "down 1.2 lb") built from the numeric delta, so pass the numeric delta and unit in addition to the display string, or build the spoken string at the call site. `miniSeries` gets `.accessibilityHidden(true)`: the stat block above it already speaks the latest value and the change. |
| 8 | `Screens/Progress/ProgressScreen+FingerCard.swift:29` | On the `BodyWeightSpark`: `.accessibilityElement()`, label "Finger strength trend", value `seriesValue(pts, unit: "%", decimals: 0, noun: "test", nounPlural: "tests")`. No descriptor. |
| 9 | `Screens/Progress/ProgressScreen+ExerciseCards.swift:40-59` TOP EXERCISES row button | `.accessibilityValue` on the `Button`: for 2 or more points, "\(change from first to last point weight, unit s.unit, decimals 0 when both are whole numbers else 1) over N sessions"; no value for fewer than 2 points. Leave the label as SwiftUI derives it (title and meta). |
| 10 | `Screens/Progress/ProgressCharts.swift:8` | Delete `import Charts` (nothing in the file uses it). Confirm the target still builds. |
| 11 | `Screens/ProgressScreen.swift:18` and `:25-27` | The comments say the per-exercise sparklines use Swift Charts. They are a hand-drawn `Canvas` (`Components/ExerciseTile.swift:314`). Correct the comments. |

Left as they are, on purpose of this item: `ExerciseStrengthSection.swift:146` (the chart is hidden and the text rows beside it speak the estimate, trend and best), the heatmap (each day cell already has a label), the goal bars (combined with their percentage text), the stat strip.

### Cards that are buttons (sites 6 and 7)

The body-weight and body-composition cards are the label of a `Button`, and the card title sits inside that label. Two ways to give the button a spoken label:

A. Modifiers on the inner pieces (the header `HStack` of value, delta and count becomes one element with the spoken string; "Tap to add a new weight." and "Tap to log a new reading." get `.accessibilityHidden(true)`; the `Button` gets `.accessibilityHint("Opens the log")`).
B. One explicit `.accessibilityLabel` on the `Button`, starting with the card title in sentence case ("Body weight, 176.5 lb, down 3.5 lb since the first entry, 8 entries").

Try A first. Then run `ProgressScreenUITests` and `MotivationBatchUITests`. Whichever of A or B you end with, `app.staticTexts["BODY WEIGHT"]` and `app.staticTexts["BODY COMPOSITION"]` must still resolve and `app.buttons["progress-body-weight-card"]` must still open the sheet. If neither A nor B keeps those tests green, leave sites 6 and 7 at `miniSeries` hidden plus the `statBlock` spoken label, and report what each attempt did to the tests.

## Tests

New `PhaseTrainingTests/ChartSpeechTests.swift`, class `ChartSpeechTests`:
- `amount`: (176.5, "lb", 1) is "176.5 lb"; (18.5, "%", 1) is "18.5%"; (12, "", 0) is "12".
- `change`: 180 to 176.5 lb is "down 3.5 lb"; 176.5 to 180 is "up 3.5 lb"; 180.00 to 180.04 at 1 decimal is "no change"; no string contains U+2212, U+2013 or U+2014.
- `seriesValue`: empty is nil; one value is "1 entry, 176.5 lb"; `[180, 181.2, 175.9, 176.5]` is "4 entries, 180.0 lb to 176.5 lb, down 3.5 lb, low 175.9 lb, high 181.2 lb".
- `dateRange` with a fixed Gregorian calendar and `en_US` locale: same year is "Nov 3 to Nov 14"; across years both carry the year; same day is one date.
- `weeklyValue`: `[2, 3, 4, 0, 3, 4, 4, 3]` with target 4 is "This week 3, target 4. Last 8 weeks, oldest first: 2, 3, 4, 0, 3, 4, 4, 3"; target nil drops the clause; empty is nil.
- `share`: 24 of 100 is "24 percent of the total"; total 0 is "0 percent of the total".
- `weekLabels(count: 3)` is `["2 weeks ago", "1 week ago", "This week"]`.
- `SeriesChartDescriptor.makeChartDescriptor()`: title and summary carried; one series with as many data points as `points`; `isContinuous` false when `isBar`; a flat series gives a y range with lower bound below upper bound; category points produce a categorical x axis whose `categoryOrder` equals the labels.

UI: in `ProgressScreenUITests`, add one test (or extend the body-weight card test at `:170-185` if its seed already has two or more entries) asserting that the label or value of `progress-body-weight-card` contains "entries" or "entry". Skip this test, and say so in the report, if the seed has no body-weight entry and adding one means a new seed path.

## Done when

- `PhaseTrainingTests/ChartSpeechTests` passes.
- `PhaseTrainingTests/ProgressBodyCardTests` and `PhaseTrainingTests/ProgressFormattingTests` pass unchanged.
- `PhaseTrainingUITests/ProgressScreenUITests`, `PhaseTrainingUITests/MotivationBatchUITests`, `PhaseTrainingUITests/YourLiftsUITests` and `PhaseTrainingUITests/HoldTimerUITests` pass. A failure that also fails on a clean checkout of 8ee5470 is reported as pre-existing, with the failing line; do not fix it.
- `grep -rn "import Charts" PhaseTraining` prints three files: the two log sheets and `ExerciseStrengthSection.swift`.
- `bash scripts/quality/verify_font_tokens.sh` exits 0.
- The app target builds with no new warnings in the touched files.

## Build and test

Slot A only: UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`, `-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A`. Every `xcodebuild` call passes `-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'` and that `-derivedDataPath`. Run `xcodegen generate` after adding the two files. One class per run with `-only-testing:`; never a whole target, and never two runs at once. Send the full log to a file in your scratchpad and grep it:
`grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" <log>`

Do not turn VoiceOver on in the simulator and do not touch the other simulator. The lead checks the spoken output at review.

Out of scope: any visual or layout change, the `lineStrong` token, the watch and widget targets, the heatmap, goal bars, stat strip and `ExerciseStrengthView`, the recovery body diagram, in-app chart interaction (scrubbing, selection), new seed data paths for UI tests, `docs/`.

Do not commit.

## Report

One final report, no interim messages: files changed; test classes run with pass and fail counts; which of A or B sites 6 and 7 ended on and what the UI tests showed for each attempt; the exact spoken label and value strings each of the 9 sites produces for one sample input; each decision made where this brief left something open (pick the conservative option and keep going); anything noticed outside this item's scope.
