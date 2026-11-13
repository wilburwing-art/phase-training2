# Brief: 44pt tap targets (slot A)

Outcome 2026-11-13: built, measured, discarded. On iOS 26.4 the buttons already take taps past 44pt without the modifier, and no UI test could tell the two builds apart. Nothing from this brief is in the tree. See the backlog line under "Later, not scheduled".

## Backlog item

`docs/PLAN-gap-backlog-2026-11b.md`, "Later, not scheduled": "21 more tap targets under 44pt; one shared modifier (3 h)". Source finding: `audits/2026-11-10-gap-round/accessibility.md`, section 5.

## Problem

21 buttons have a hit area equal to their drawn frame (28 to 40pt a side). The Apple HIG minimum is 44 x 44. Growing the frames would move neighbours and change every screen's layout.

## Done

- Each of the 21 sites accepts a tap anywhere in a 44 x 44 box centred on the button, except where a neighbour or a clipping ancestor limits one edge (those limits are listed per site below).
- No site draws or lays out differently. No frame, padding, spacing, background or clip value on any existing view changes.
- `PhaseTrainingTests/TapTargetTests` passes.
- `PhaseTrainingUITests/LogFlowTests/testDiscardHitAreaExtendsPastDrawnCircle` passes, and it failed before the modifier was applied to that site.
- `PhaseTrainingUITests/LogFlowTests/testDiscardWorkoutPromptsConfirmation` still passes.

## Out of scope

- The six sites that already use `.frame(width: 44, height: 44)` and `HistoryScreen.swift:204-213`. Leave them as they are.
- Any layout, colour, icon size or Dynamic Type change.
- The other "Later" items (Reduce Motion, Dynamic Type, chart labels).
- The watch target.

## Design (fixed, do not redesign)

### New file: `PhaseTraining/Components/View+TapTarget.swift`

```swift
/// Caps on how far the hit box may grow past the drawn frame on each edge.
/// nil means no cap.
struct TapTargetCap: Equatable {
    var top: CGFloat? = nil
    var leading: CGFloat? = nil
    var bottom: CGFloat? = nil
    var trailing: CGFloat? = nil
    static let none = TapTargetCap()
}

enum TapTarget {
    static let minimum: CGFloat = 44

    /// Outsets that take a drawn width x height to `minimum` on each axis.
    static func outsets(width: CGFloat, height: CGFloat,
                        cap: TapTargetCap = .none,
                        minimum: CGFloat = TapTarget.minimum) -> EdgeInsets
}

extension View {
    /// Widens the hit area to 44 x 44 around a view drawn at width x height.
    /// Layout size and drawing are unchanged.
    func tapTarget(width: CGFloat, height: CGFloat, cap: TapTargetCap = .none) -> some View
}
```

`outsets` rules, per axis (horizontal shown; vertical is the same with top and bottom):

1. `need = max(0, minimum - width)`. Start with `need / 2` on each side.
2. Clamp each side to its cap when one is set.
3. If one side was clamped and the other has no cap, the other side takes the shortfall, so the two still sum to `need`. If the other side has a cap, it takes the shortfall up to that cap.
4. A drawn size of 44 or more on an axis gives 0 on both sides. Never return a negative value. A negative cap counts as 0.

`tapTarget` body:

```swift
let o = TapTarget.outsets(width: width, height: height, cap: cap)
return self
    .padding(o)
    .contentShape(Rectangle())
    .padding(EdgeInsets(top: -o.top, leading: -o.leading, bottom: -o.bottom, trailing: -o.trailing))
```

### Where it goes at each site

Inside the Button's label closure, as the last layout modifier on the label: after `.frame`, `.background`, `.overlay` and `.clipShape`, so the drawn shape keeps its clip. Accessibility modifiers already inside a label may stay where they are. Pass the site's existing drawn frame size as `width` and `height`. Do not touch the Button's own modifiers.

At `ProgressScreen+Heatmap.swift` the label already has `.contentShape(Rectangle())` at line 140. Replace that line with the `tapTarget` call.

### Sites and caps

Line numbers are from commit f82a506. Find each by content if they moved.

| # | File (under `PhaseTraining/`) | Button line | Drawn | Cap |
|---|---|---|---|---|
| 1 | `Components/ExerciseTile.swift` info | 225 | 28 x 32 | `trailing: 1` |
| 2 | `Components/ExerciseTile.swift` swap | 234 | 28 x 32 | `leading: 1` |
| 3 | `Components/ExerciseTile.swift` overflow | 266 | 32 x 32 | none |
| 4 | `Components/ExerciseTile.swift` icon button | 276 | 32 x 32 | none |
| 5 | `Screens/LibraryMuscleScreen.swift` back | 66 | 32 x 32 | none |
| 6 | `Screens/WorkoutCategoryScreen.swift` back | 66 | 32 x 32 | none |
| 7, 8 | `Screens/Progress/ProgressScreen+Heatmap.swift` `heatmapPageButton` | 135 | 32 x 32 | see below |
| 9 | `Screens/WeeklyCheckIn/WeeklyCheckInFlow.swift` back | 414 | 32 x 32 | none |
| 10 | `Screens/WeeklyCheckIn/WeeklyCheckInFlow.swift` close | 434 | 32 x 32 | none |
| 11 | `Screens/Onboarding/OnboardingFlow.swift` back | 310 | 32 x 32 | none |
| 12 | `Screens/WeeklyCheckIn/CheckInEventsScreen.swift` trash | 196 | 32 x 32 | none |
| 13 | `Screens/ExercisePickerSheet.swift` info | 323 | 36 x 36 | none |
| 14 | `Screens/SubstituteExerciseSheet.swift` info in `row` | 173 | 36 x 36 | see below |
| 15 | `Screens/SubstituteExerciseSheet.swift` info in `fallbackRow` | 234 | 36 x 36 | see below |
| 16 | `Screens/OverrideTodaySheet.swift` edit | 219 | 36 x 36 | none |
| 17 | `Screens/LogScreen.swift` discard (`log-cancel`) | 379 | 28 x 28 | none |
| 18 | `Coach/CoachDrawer.swift` close | 99 | 28 x 28 | none |
| 19 | `Coach/CoachDrawer.swift` send | 247 | 38 x 38 | check neighbour |
| 20 | `Components/NowPlayingCard.swift` `control` | 94 | 40 x 40 | check neighbour |
| 21 | `Components/PlanAssumptionsRow.swift` `stepButton` | 208 | 40 x 40 | check neighbour |

Cap rule for every site: two hit boxes must never overlap, and a hit box must never reach into a neighbouring tappable view's drawn frame. Where a tappable sibling sits closer than the uncapped outset, cap that edge at half the gap between the two when both get `tapTarget`, or at the full gap when only this one does. The other edge then takes the shortfall (rule 3).

- Sites 1 and 2 sit in `HStack(spacing: 2)`. Each caps the shared edge at 1 and grows 15 on its outer edge.
- Sites 7 and 8 are one function called twice (prev at line 26, next at line 29) in `HStack(spacing: 8)`. Add a `cap` parameter to `heatmapPageButton`: prev passes `trailing: 4`, next passes `leading: 4`.
- Sites 14 and 15 are top-aligned in their row. Read the spacing between rows; if it is under 4, cap `top` at that spacing.
- Sites 19, 20 and 21: read the container spacing and the nearest tappable sibling, then apply the cap rule. `control` and `stepButton` are helpers called more than once, so they may need a `cap` parameter as `heatmapPageButton` does.
- For the "none" rows, confirm while editing that no tappable sibling sits inside the outset. If one does, apply the cap rule and record it in the report.

Ancestors that clip (`ExerciseTile` row at line 105, the Progress `card`, the check-in event row) also cut the hit box at their edge. Do not remove or move those clips. Where the room between the button and the clip edge is less than the outset (for example `ExerciseTile` at `.flat` density, horizontal padding 0), leave it and list the site and the shortfall in the report.

### Unit test: `PhaseTrainingTests/TapTargetTests.swift` (new)

Tests on `TapTarget.outsets` only:

- 28 x 28, no cap: 8 on all four edges.
- 32 x 32: 6 on all four. 36 x 36: 4. 40 x 40: 2. 38 x 38: 3.
- 28 x 32, `trailing: 1`: leading 15, trailing 1, top 6, bottom 6.
- 28 x 32, `leading: 1`: leading 1, trailing 15.
- 32 x 32, `leading: 4, trailing: 4`: leading 4, trailing 4 (both capped, total stays short).
- 32 x 32, `leading: 2, trailing: 8`: leading 2, trailing 8.
- 44 x 44 and 60 x 20: 0 on the axis that already reaches 44.
- A negative cap gives 0 on that edge.
- For every drawn size from 20 to 44 with no cap: `width + leading + trailing == 44` and `height + top + bottom == 44`.

### UI test: `PhaseTrainingUITests/LogFlowTests.swift`, new `testDiscardHitAreaExtendsPastDrawnCircle`

Use `launchInLog()` as `testDiscardWorkoutPromptsConfirmation` (line 470) does. Take `app.buttons["log-cancel"]`, and tap the point 18pt left of its centre:

```swift
let cancel = app.buttons["log-cancel"]
cancel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    .withOffset(CGVector(dx: -18, dy: 0)).tap()
```

Expect `app.buttons["Discard"]` to exist, then tap "Keep going". The drawn circle is 28 wide (half 14) and the hit box 44 (half 22), so 18 from the centre is outside the circle and inside the box whichever of the two the accessibility frame reports.

Order of work for this test: write it and run it before applying `tapTarget` to site 17. It must fail there. Then apply the modifier and run it again. Put both results in the report.

If the test still fails after the modifier is applied, the padding approach does not widen a plain Button's hit area in this layout. Stop there: do not switch to `.frame(minWidth: 44, minHeight: 44)` or any change that alters layout. Leave the work in the tree and report what you tried.

## Skills to load

`phase-training2-gitignored-pbxproj`, `phase-training-xcodebuild-test-failed-grep-full-log`, and `phase-training-xcuitest-recipe` before the UI test.

## Simulator and DerivedData (slot A, yours alone)

- iPhone 17 Pro, UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`
- `-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A`
- Every `xcodebuild` call passes `-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'` and that `-derivedDataPath`.
- Project `PhaseTraining.xcodeproj`, scheme `PhaseTraining`. Run `xcodegen generate` after adding the two new Swift files.
- One test run at a time. Send each full log to a file in your scratchpad and grep it as the skill says.

## Test runs required

1. `-only-testing:PhaseTrainingTests/TapTargetTests`
2. `-only-testing:PhaseTrainingUITests/LogFlowTests/testDiscardHitAreaExtendsPastDrawnCircle` (once before site 17 is changed, once after)
3. `-only-testing:PhaseTrainingUITests/LogFlowTests/testDiscardWorkoutPromptsConfirmation`

Do not run the full unit suite or the full UI target.

## Rules

- Do not commit. Do not edit the backlog doc.
- No comments or text crediting a tool or an assistant anywhere.
- No em or en dashes in comments or strings.
- If something here is ambiguous, pick the conservative option (the smaller hit box, the unchanged layout), record it, and keep going.

## Final report (one message, no interim messages)

- Files changed.
- Test classes and tests run, with pass and fail counts, including the red run of the UI test.
- The cap used at every site that got one, and the gap it came from.
- Sites where a clipping ancestor leaves the hit box under 44 on an axis, with the size reached.
- Decisions made on anything this brief left open.
- Anything noticed outside this item's scope.
