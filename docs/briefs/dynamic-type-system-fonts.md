# Brief: Dynamic Type for fixed-size system fonts

Backlog item: `docs/PLAN-gap-backlog-2026-11b.md`, "Later, not scheduled": "Dynamic Type: 4 fixed-size text sites (2 h), 173 fixed-size icons (6 h)." Audit finding 7 in `audits/2026-11-10-gap-round/accessibility.md`.

Agent: builder. Skills to load first: `phase-training2-gitignored-pbxproj`, `phase-training-xcodebuild-test-failed-grep-full-log`.

## Problem

Text drawn through the `TypeStyle` tokens and `Font.scaled` grows with the iOS text size setting. Every `.font(.system(size: N ...))` site stays at N points. At commit 23a5a84 there are 176 such sites in `PhaseTraining/` (66 files): SF Symbols beside text that grows, plus three text labels at 9pt and 7pt. At the accessibility sizes the icons look tiny beside their labels and the 9pt labels are unreadable.

## Rule

- At the default text size every site renders at exactly the point size it has today. No weight, colour, frame or layout change.
- At other text sizes the point size follows the system text style nearest the design size (`ScreenScale.textStyle(for:)`, the curve the text tokens use).
- A glyph inside a box of fixed size grows only until it reaches 70% of the box's smaller fixed side. It never shrinks below its design size because of the box.
- No device-width scaling is added. The four `WeekScreen` sites that pass `ScreenScale.scaled(N)` keep passing it.

## New file: `PhaseTraining/Theme/ScaledSystemFont.swift`

```swift
enum SystemFontScale {
    /// Share of a fixed box's smaller side a glyph may fill.
    static let boxFill: CGFloat = 0.7

    /// Pure. `scaled` is the design size after Dynamic Type scaling.
    /// With no box: returns `scaled`.
    /// With a box: returns min(scaled, max(design, box * boxFill)).
    static func pointSize(design: CGFloat, scaled: CGFloat, within box: CGFloat?) -> CGFloat
}

extension View {
    /// Replaces `.font(.system(size:weight:design:))` at every call site.
    func scaledSystemFont(_ size: CGFloat,
                          weight: Font.Weight = .regular,
                          design: Font.Design = .default,
                          within box: CGFloat? = nil) -> some View
}
```

The modifier is a private `ViewModifier` struct that holds `@ScaledMetric private var scaled: CGFloat`, set in `init` with `_scaled = ScaledMetric(wrappedValue: size, relativeTo: ScreenScale.textStyle(for: size))`, and applies `.font(.system(size: SystemFontScale.pointSize(design: size, scaled: scaled, within: box), weight: weight, design: design))`. This file is the only place in `PhaseTraining/` where `.system(size:` appears.

## Sites

Replace every `.font(.system(size: X, weight: W))` and `.font(.system(size: X))` in `PhaseTraining/` with `.scaledSystemFont(X, weight: W)` or `.scaledSystemFont(X)`. Keep the size expression as written, including `ScreenScale.scaled(N)` and `size * 0.4`.

Pass `within:` when the glyph sits in a fixed box:

- The glyph's own modifier chain, or the label of the button that encloses it, has `.frame(width:height:)` or a width-only or height-only `.frame` with fixed values. Pass the smaller fixed side. The scout counted about 50, among them `SettingsRow.swift:28` (width 22), `ExerciseTile.swift:178` (48x48), `:229` (28x32), `CoachDrawer.swift:106` (28x28), `LogScreen.swift:386` (28x28), `NowPlayingCard.swift:98` (40x40), `ProgressScreen+Heatmap.swift:139` (32x32), `OnboardingFlow.swift:315` (32x32), and the 14 to 24pt width-only icon columns in the banners, editor sheets and `ProfileScreen.swift:639`.
- The glyph is drawn over a sibling shape of fixed size in a `ZStack` (`LogExerciseBlock.swift:41`, a 9pt checkmark over an 18x18 circle). Pass the shape's smaller side.
- The glyph sits in a container of fixed height one or two levels up (a bar, header, pill or chip with `.frame(height:)`). Pass that height. List each of these in the report.
- `ExerciseThumbnail.swift:83`, `:92`: `.scaledSystemFont(size * 0.4, within: size)`.

When the frame's sides are `@ScaledMetric` values, or the frame is `minWidth`, `minHeight`, `maxWidth` or `maxHeight` only, pass no `within:`.

The text sites:

| Site | Today | Change |
|---|---|---|
| `Screens/EditSessionSheet.swift:143` | 9pt set-type letter in an 18x14 pill | `.scaledSystemFont(9, weight: .bold)` for the letter, with no `within:`. Two `@ScaledMetric(relativeTo: .caption2)` properties on the view for the frame (width 18, height 14), the values `LogScreen.swift:38-39` declares. Pass the literal 9 to the modifier: a `@ScaledMetric` font size passed in would be scaled twice. |
| `Screens/LogSetRow.swift:43` | `setTypePillFont`, a `@ScaledMetric` on `LogScreen` | `.scaledSystemFont(9, weight: .bold)`; delete `setTypePillFont` from `LogScreen.swift:40`. The pill width and height stay as they are. |
| `Screens/PlateCalculatorSheet.swift:250` | 9pt plate weight in a 30x30 tile | `.scaledSystemFont(9, weight: .bold)` and a `@ScaledMetric(relativeTo: .caption2)` tile side of 30 used for both width and height. |
| `Screens/PlateCalculatorSheet.swift:267` | 7pt rotated weight on an 8pt-wide bar plate | `.scaledSystemFont(7, weight: .bold, within: 8)`. The bar drawing has fixed geometry, so this label stays at 7pt. Leave the bar alone. |

If a site has moved or a new one has appeared since 23a5a84, apply the rule and list it in the report.

## Lint

Extend `scripts/quality/verify_font_tokens.sh` (it runs in CI from `.github/actions/ios-setup/action.yml`) with a second check: `grep -rn '\.system(size:' --include='*.swift' PhaseTraining`, excluding `PhaseTraining/Theme/ScaledSystemFont.swift`, must print nothing. Same failure style as the existing check, with the fix named: `.scaledSystemFont(N, weight:)`. Update the header comment and the final ok line to cover both checks.

## Tests

New `PhaseTrainingTests/SystemFontScaleTests.swift`, class `SystemFontScaleTests`:
- no box: `pointSize(design: 14, scaled: 14, within: nil)` is 14 and `scaled: 30` gives 30;
- default size inside a box is unchanged: `pointSize(design: 14, scaled: 14, within: 28)` is 14;
- growth stops at 70% of the box: `pointSize(design: 14, scaled: 40, within: 28)` is 19.6 (accuracy 0.001);
- a design size already over the cap is kept: `pointSize(design: 7, scaled: 20, within: 8)` is 7;
- a smaller text size still shrinks inside a box: `pointSize(design: 14, scaled: 12, within: 28)` is 12.

## Done when

- `bash scripts/quality/verify_font_tokens.sh` exits 0. Paste its output in the report.
- `grep -rn '\.system(size:' --include='*.swift' PhaseTraining` prints only lines in `Theme/ScaledSystemFont.swift`. Paste the output.
- `PhaseTrainingTests/SystemFontScaleTests` passes.
- `PhaseTrainingTests/TypographyDynamicTypeTests` passes unchanged.
- `PhaseTrainingUITests/OnboardingGoalUITests` passes unchanged (default text size, walks migrated screens).
- The app target builds with no new warnings in the touched files.

## Build and test

Slot A only: UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`, `-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A`. Every `xcodebuild` call passes `-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'` and that `-derivedDataPath`. Run `xcodegen generate` after adding the two files. One class per run with `-only-testing:`; never a whole target, and never two runs at once. Send the full log to a file and grep it:
`grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" <log>`

Do not change the simulator's text size setting. The lead checks the accessibility sizes on the other simulator at review.

Out of scope: `PhaseTrainingWidgets` (the two Live Activity sites), the watch target, chart labels, turning fixed boxes into scaling boxes beyond the two named in the text-site table, any size, weight or layout change at the default text size, new UI tests, `docs/`.

Do not commit.

## Report

One final report, no interim messages: files changed; test classes run with pass and fail counts; the lint and grep outputs; the count of sites migrated and the count given `within:`; the list of sites capped by a container further up; each decision made where this brief left something open (pick the conservative option and keep going); anything noticed outside this item's scope.
