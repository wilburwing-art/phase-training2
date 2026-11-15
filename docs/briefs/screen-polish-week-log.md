# Brief: screen polish, Week header stack and the Log music card

Backlog item: `docs/PLAN-gap-backlog-2026-11b.md`, "Later, not scheduled": "Screen polish from `screens.md`: Week header stack, Library muscle icons, Profile 23-row list, Log tab bar under the music card." This brief covers the Week and Log parts. Audit findings: `audits/2026-11-10-gap-round/screens.md`, Week 1 to 3 and Log 2. Screenshots: `audits/2026-11-10-gap-round/screens/02-week.png` and `06-log.png`.

Agent: builder. Skills to load first: `phase-training-tab-time-horizon-rule`, `phase-training2-gitignored-pbxproj`, `phase-training-xcodebuild-test-failed-grep-full-log`, `phase-training-xcuitest-recipe`.

Slot A. Every `xcodebuild` call passes both:

```
-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'
-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A
```

A second builder is working in this same checkout on slot B. Its files are `ProfileScreen.swift`, `ProfileScreen+RowSummaries.swift`, `LibraryScreen.swift`, `ExerciseFilters.swift`, `MuscleChipBadge.swift` and the Profile and Library tests. Do not edit those. If your build fails with an error in one of them, the other builder is mid-edit: run the build again, up to five times, before reporting it.

## Files to touch

- `PhaseTraining/Screens/WeekScreen.swift`
- `PhaseTraining/Components/PlanAssumptionsRow.swift` (the row and chip only; leave `ProfileFieldEditorHost` and `AvailabilityEditorSheet` alone)
- `PhaseTraining/Screens/PlanValidationBanner.swift`
- `PhaseTraining/Screens/LogScreen.swift`
- `PhaseTraining/Components/NowPlayingCard.swift` (only if the card needs an identifier)
- `PhaseTrainingUITests/NowPlayingCardUITests.swift`
- A Week UI test: extend `OnboardingLandingUITests` or `ArcDeloadNoticeUITests`, whichever already lands on the Week tab with the pieces you need

## Part 1: Week header stack

### Problem

The Week tab has no scroll view. Its seven day rows share whatever height the header leaves (`GeometryReader`, `rowH = max(48, ...)` in `WeekScreen.content`). In the audit screenshot the first day row starts 42% of the way down the screen. Three things above it cost height or read badly:

1. The header spends two rows on "7 lift" + Set tone, then Plan next week (+ Same as last week).
2. The assumed chips have a caption line of their own ("ASSUMED · TAP TO CHANGE") and the chip row is cut at the right edge with nothing to show it scrolls.
3. "+2 more" under the issue banners is bare mono text and reads as a label.

### Design

**Header, `WeekScreen.header(plan:)`.** Three rows in place of four:

1. Eyebrow row: unchanged ("THIS WEEK", `SeasonPhaseBadge`).
2. Title row: an `HStack(alignment: .firstTextBaseline)` with `plan.rangeLabel` leading and `planSummary(plan)` trailing, same fonts and colours as now. Title gets `.lineLimit(1)` and `.minimumScaleFactor(0.8)`; the summary gets `.lineLimit(1)` and `.layoutPriority(1)` so it is never the one that truncates.
3. Actions row: "Plan next week" chip, "Same as last week" chip (still gated on `planStore.hasPriorWeekShape`), `Spacer`, `WeekToneChip` trailing. Wrap the row in `ViewThatFits(in: .horizontal)` with a second candidate in which the "Same as last week" chip's title is "Last week" (same icon, same identifier, and an `.accessibilityLabel("Same as last week")`). Build the row from one helper that takes the short flag so the two candidates do not duplicate code.

Identifiers stay: `week-tone-chip`, `week-same-as-last`, `week-plan-next`. Their actions stay.

**Assumed chips, `PlanAssumptionsRow`.** Delete the caption `Text` line. Put a short "ASSUMED" label (`.styled(.micro)`, `Color.ink3`) as the first item inside the horizontal scroll `HStack`, before the chips, so it scrolls with them. Keep the unconditional container and `.sheet` exactly as the comment in the file explains. On the scroll view add a trailing fade: a `.mask` of an `HStack(spacing: 0)` holding `Color.black` and a 24pt-wide `LinearGradient` from black to clear, and give the scroll content 24pt of trailing padding so the last chip can scroll clear of the fade. Each chip gets `.accessibilityHint("Assumed. Tap to change.")` unless the chip already says so in its label; check before adding. The `plan-assumptions-row` and `assumption-chip-<field>` identifiers stay.

**"+N more", `PlanValidationBanner`.** The toggle becomes text plus a chevron (`chevron.down`, `chevron.up` when `showAll`), sized through `scaledSystemFont` like the other chevrons in the app, in an `HStack` with `.frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)` and `.contentShape(Rectangle())`. `visibleByDefault` stays 2. Add `.accessibilityLabel` of "Show \(hiddenCount) more issues" or "Show fewer issues". Identifier `plan-issues-show-more` stays.

Nothing else on Week changes: the banners' order, `MoveBanner`, `ArcDeloadBanner`, the day rows.

### Out of scope

A second line on day rows (audit Week 4), a header menu, changing how many issues show, anything on Today.

## Part 2: Log, the music card over the set rows

### Problem

`LogScreen` attaches `NowPlayingCard` with `.safeAreaInset(edge: .bottom)` on its scroll view (around line 352). The inset has no background, so set rows scroll visibly behind the card's 20pt side gutters, through the 8pt gap under it and through the translucent tab bar below it. Two floating layers sit on top of the logging inputs (`06-log.png`).

### Design

The tab bar stays. A lifter can still switch to Library or Progress mid-workout and come back.

While the card shows, the card and everything below it become one opaque dock:

- The `safeAreaInset` content, when `nowPlaying.state != .hidden`, is a `VStack(spacing: 0)`: a 12pt-tall `LinearGradient` from `Color.bg.opacity(0)` to `Color.bg` (top to bottom), then the card with its current paddings on a `Color.bg` background. The background extends under the tab bar with `.background(Color.bg.ignoresSafeArea(edges: .bottom))` or the equivalent that works; confirm in the simulator that no row text is visible behind or below the card.
- The gradient strip is `.allowsHitTesting(false)` and `.accessibilityHidden(true)`.
- The existing transition and `.motion` on the card stay and apply to the whole dock.
- The 120pt `Color.clear` spacer at the end of the scroll content exists to clear the tab bar when nothing else is inset. Keep 120 when the card is hidden. When the card shows, the safe area inset already ends the content above the dock, so use 16. Update the comment above the spacer to say both cases.

When the card is hidden, Log looks exactly as it does today.

### Test

In `NowPlayingCardUITests`, add a test (same launch arguments as the existing one, so the fake player shows the card): swipe up on the Log scroll view until the last exercise's "Log all sets" control (or the last element of the scroll content, whichever has a stable identifier; add one if none exists) stops moving, then assert that element is hittable and its `frame.maxY` is at or above the card's `frame.minY`. Give the card container an identifier (`now-playing-card`) if it has none.

### Out of scope

Hiding the tab bar, the Today CTA inset, the "Stop early" and discard copy (audit Log 3).

## Done

- App target builds on slot A.
- `PhaseTrainingUITests/NowPlayingCardUITests` passes, with the new test.
- The Week UI test classes that touch the header pass: `OnboardingLandingUITests`, `OnboardingGoalUITests`, `ArcDeloadNoticeUITests`, `ConsolidateFlowTests`. Run them one class at a time.
- One screenshot each of the Week tab and of Log with the card showing, taken on slot A after your change and saved under the scratchpad directory; give their full paths in the report. For Week, use the launch arguments `StoreScreenshotUITests.test_planScreens` uses, so it compares with `02-week.png`.
- In the report, state the y position of the first day row before and after if you can read it from the UI test frames (`week-day-row-0`), and each day row's height.

Do not commit, push or bump the build. Return one final report: files changed, test classes run with pass and fail counts, decisions made on anything this brief left open, and anything you noticed outside its scope.
