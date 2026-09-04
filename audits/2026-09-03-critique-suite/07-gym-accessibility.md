# 07. Gym-context accessibility

**Status:** closed 2026-09-03
**Lens:** experience

## Question

Can this be used with one thumb, at arm's length, at the largest Dynamic Type,
and by VoiceOver? The logging surface is the whole product during a workout.

## Depth actually reached

Static audit of the type system, the logging surface and the rest timer, with
every number read from the source. **Not run in the simulator at accessibility
text sizes**: the finding below makes that unnecessary for Dynamic Type (the
sizes cannot change), but a VoiceOver pass on device would still add value and
was not done.

## Findings

### F1 (critical, accessibility) The app ignores Dynamic Type completely, by construction

The whole type system is one table, and every entry is a fixed point size:

```swift
private struct TypeSpec {
    let fontName: String
    let size: CGFloat
    var font: Font { Font.custom(fontName, size: size) }   // Typography.swift:37
}
```

`Font.custom(_:size:)` produces a fixed-size font. The scaling variant is
`Font.custom(_:size:relativeTo:)`, and it is used **nowhere**: a grep for
`.custom(` across `PhaseTraining/` returns 134 call sites and `relativeTo`
appears in zero of them. A further 177 sites use `.system(size:)`, which is
fixed for the same reason.

So a user who has set Larger Text, including the accessibility sizes, sees this
app at exactly the sizes below:

| style | size | used for |
|---|---|---|
| `.body` | 13 | body copy |
| `.monoS` | 13.5 | set values |
| `.monoXS` | 11 | set numbers, rest label |
| `.micro` | 10 | section labels |
| `.monoL` | 22 | the rest timer countdown |

Body copy at 13pt and labels at 10pt, non-negotiable. There is no per-view
escape hatch either, because the table is the only source of sizes. The fix is
one line in `TypeSpec.font` plus a `relativeTo:` mapping per style, and then a
sweep of the fixed frames F3 covers.

There are no tests for this. A grep for `dynamicTypeSize`, `accessibilitySize`,
`AX5` or `UICTContentSizeCategory` across the app and both test targets returns
nothing.

### F2 (critical, accessibility) The set-completion control is 22pt, and the code already knows

`checkDot` (`LogSetRow.swift:275-289`) is a `Button` whose label is a
`Circle().frame(width: 22, height: 22)`, wrapped in `.frame(width: 24)` at the
call site (`:95`). Apple's minimum is 44 by 44.

This is the single most-tapped control in the product. A logged workout is
`sets x exercises` taps of this dot, in a gym, one-handed, with chalk or sweat.

The code comments on the size and reaches a different conclusion:

```
// .borderless instead of .plain. Visually identical here ... but
// iOS 26 XCUITest synthesized taps do not fire .plain Button actions
// when the label is < ~44pt — they DO fire .borderless. That broke
// every rest-card-after-set-done UI test (the 22pt check dot tap
```

The under-44pt target was diagnosed, and the fix restored the *test's* ability
to hit it rather than the *user's*. Extending the tappable area with padding or
`contentShape` would keep the 22pt visual and give the finger 44.

### F3 (high, accessibility) Fixed frames will clip the moment F1 is fixed

The logging row is built from hard widths: `.frame(width: 22)` for the set
number, `.frame(width: 58)` for the label column, `.frame(width: 52)` for the
effort cell, `.frame(width: 24)` for the check, and `.frame(width: 18,
height: 14)` for the warmup pill whose glyph is `.system(size: 9, weight:
.bold)` (`LogSetRow.swift:47,50,71,90,95`).

Every one of those is sized for the current fixed font. They are the reason F1
cannot be fixed by changing `TypeSpec` alone, and they should be converted to
`ScaledMetric` or intrinsic sizing in the same change.

A 9pt bold glyph in an 18x14 box is also below what is readable at arm's length
regardless of Dynamic Type.

### F4 (high, accessibility) VoiceOver has almost nothing to read on the logging surface

Counts across the four files that make up a workout:

| file | `accessibilityLabel` | `accessibilityIdentifier` |
|---|---|---|
| LogScreen.swift | 0 | 4 |
| LogSetRow.swift | 2 | 5 |
| LogExerciseBlock.swift | 1 | 4 |
| CompleteScreen.swift | 0 | 3 |

App-wide it is 34 labels against 117 identifiers. Identifiers serve XCUITest and
are invisible to VoiceOver.

The check dot is the clearest case: it carries
`accessibilityIdentifier("log-set-check-\(exIdx)-\(setIdx)")` and no label, so
VoiceOver announces an unlabelled button, with no indication of which set it
completes or whether that set is already done. The two labels that do exist
(`"Warmup set"`, `"Bodyweight, tap to add weight"`) show the right instinct
applied in two places out of dozens.

`CompleteScreen` having zero labels means the end-of-workout summary, the PR
callouts and the note field are all unannounced.

### F5 (medium, gym context) The rest timer is the one thing that must read at arm's length and it is 22pt

`RestTimer.swift:114` renders the countdown at `.styled(.monoL)`, 22pt fixed,
with its label at `.styled(.micro)`, 10pt fixed (`:61`). A phone propped against
a water bottle three feet away during a 180-second squat rest is the exact use
case, and 22pt is small for it. Since F1 means the user cannot enlarge it, this
is a fixed ceiling rather than a default.

The ski off-season session prescribes 180s rests on the squat, so this is not
hypothetical for the app's own output.

### F6 (medium, gym context) The one-thumb question is unanswerable from the code and worth a device pass

Reachability, the position of the check column on the trailing edge, and whether
the keyboard covers the row being edited are all layout-runtime questions. The
static audit cannot settle them, and this critique does not claim to. Noting it
so the next pass knows it is open rather than clean.

## Refuted

- **"`.styled()` handles scaling and the raw `.custom` counts overstate the
  problem."** Checked, and it does not. `styled(_:)` is
  `self.font(style.font).tracking(style.tracking)`
  (`Typography.swift:107`), and `style.font` resolves to the same
  `Font.custom(fontName, size: size)`. Every route to a font in this app is
  fixed-size.

## Ordering

F2 first: it is a `contentShape`/padding change on one view, it does not touch
layout, and it fixes the control the user touches hundreds of times per week.
F1 and F3 are one change and a real piece of work, since the fixed frames have
to move with the fonts. F4 is cheap and incremental and can be done a screen at
a time, starting with the check dot.
