# Week tab: scaling on larger iPhones

**Status: DIAGNOSED, NOT IMPLEMENTED. No code changes on this branch.**
Branch `claude/week-tab-iphone-scaling-fva5bq` carries this document only.

**Blocked on one owner input** (see "Open question"). Do not pick an option
before that is answered: options 1 and 3 fix different symptoms and the
report is currently ambiguous between them.

## Report

Owner: "Week tab is scaled perfectly to my phone but my friend has a bigger
iPhone and it doesn't scale up." Friend's exact device and a screenshot were
requested but not yet supplied.

## Verified facts

Every claim below was read out of the tree at `e19b385`. Per house rule
(`verify-audit-claim-before-implementing`), re-verify the load-bearing line
before editing it.

- **The Week tab is the only elastic layout in the app that divides a fixed
  count into available height.** `WeekScreen.swift:155-157`:
  `let rowH = max(48, (geo.size.height - spacing * 6) / 7)`. Seven rows,
  no ScrollView, no LazyVStack (`WeekScreen.swift:126`), so row height is a
  pure function of viewport height.
- **Everything inside a row is fixed-size.** Day number 18pt
  (`WeekScreen.swift:417`), title uses `.displayS` (16pt design size,
  `Theme/Typography.swift:71`), 12pt horizontal padding, and
  `.frame(maxHeight: .infinity)` (`WeekScreen.swift:443`) vertically centers
  a single-line HStack inside whatever height it is given.
- **Net effect:** 16 (852pt tall) puts rows near 85pt; 16 Pro Max (956pt)
  puts them near 100pt. The box grows about 15pt per row, the contents grow
  zero. Rows read as stretched and hollow, with a fixed 26pt header
  (`WeekScreen.swift:186`) and fixed 32pt empty-state text
  (`WeekScreen.swift:77`, `:111`) floating in a wider bar.
- **This is not an iOS scaling bug.** iOS never scales a UI by screen size:
  a larger iPhone is more points of canvas at the same point size. Every
  other tab therefore shows *more* content rather than *larger* content,
  which is correct and expected. Week looks wrong only because its rows are
  elastic and their contents are not.

### Dynamic Type coverage is partial, and this matters here

The token table in `Theme/Typography.swift` wires all nine styles to a
`relativeTo:` text style, guarded by
`PhaseTrainingTests/TypographyDynamicTypeTests.swift`. So anything drawn via
`.styled(...)` scales with the system text-size setting.

The gap: **130 raw `.font(.custom(...))` call sites across 52 files, of which
zero pass `relativeTo:`.** These bypass the token table entirely and are
frozen at their literal point size. A further 178 `.font(.system(size:))`
calls are mostly SF Symbol glyph sizing. WeekScreen alone holds 6 raw
`.custom` and 6 raw `.system` against 14 `.styled(` uses.

Reproduce the counts:

```
grep -rn '\.font(\.custom(' PhaseTraining --include=*.swift | wc -l          # 130
grep -rn '\.font(\.custom(' PhaseTraining --include=*.swift | grep -c relativeTo  # 0
```

Consequence: on a Pro Max the friend *can* get larger text today via Display
Zoom (Larger Text) or the text-size slider, but the result is inconsistent,
because roughly a third of the app's typography will not move.

## Options, by blast radius

**Option 1: Week tab only. ~20 lines, contained, recommended first.**
The GeometryReader is already in place. Either cap `rowH` (around 88) and let
surplus height become spacing, or derive a scale factor from `rowH` and pass
it into `DayRow`'s font sizes and padding. Touches `WeekScreen.swift` only,
cannot regress any other screen. Downside: Week gains a bespoke scaling
mechanism no other screen uses.

**Option 2: global device-width scale factor in the theme. Not recommended.**
Multiplying design sizes by a screen-width ratio inside `.styled()` would
reach 353 call sites for free, but the 130 raw `.custom` sites would not
pick it up, and every hardcoded padding, frame, and width stays fixed. That
gives larger text inside unchanged boxes, so clipping across many screens.
Large regression surface for a modest payoff, and it fights the platform
convention described above.

**Option 3: finish the Dynamic Type migration. Background work, high value.**
Migrate the 130 raw `.font(.custom(...))` sites onto `.styled(...)` (or at
minimum add `relativeTo:`). Does not scale by device, but it is the knob iOS
actually gives users, and it is an accessibility win independent of this
report. Consider extending `TypographyDynamicTypeTests` with a source-grep
guard so new raw `.custom` call sites fail CI.

## Recommendation

Option 1 now, Option 3 as staged background work, skip Option 2.

## Open question (blocks implementation)

Which symptom is the friend actually reporting?

- "Stretched, empty, too much space between rows" points to Option 1, and
  Option 1 alone closes it.
- "Text is too small to read comfortably" points to Option 3, and Option 1
  would not help.

Ask for the device model and a Week tab screenshot before writing code.

## Notes for the implementing agent

- `project.pbxproj` is gitignored in this repo
  (`phase-training2-gitignored-pbxproj`); no new files are needed for
  Option 1 anyway.
- Build gate: `xcodebuild test` on the unit suite, and grep the full log on
  failure (`phase-training-xcodebuild-test-failed-grep-full-log`).
- Week row layout is covered by UI tests keyed on the
  `week-day-row-N` identifiers attached at `WeekScreen.swift:165`. Keep those
  identifiers on the container if the row view is restructured.
