# Accessibility gap analysis

Date: 2026-11-10. Commit: bb17ca1 (build 171). Scope: PhaseTraining/, PhaseTrainingWatch/, Shared/.
Method: grep sweeps for counts, spot reads for confirmation, WCAG 2.x relative-luminance arithmetic run in a script over every token in `PhaseTraining/Theme/Theme.swift`. No code was run in a simulator, so nothing here was checked with VoiceOver or Accessibility Inspector. Findings marked "verify on device" need that pass.

Previous round (2026-10-31) held: ink3 values below are 4.97 on surface and 4.54 on elevated; icon-only buttons in onboarding back, WorkoutCategoryScreen, TodayScreen+TemplateEditor, DayWorkoutPreviewSheet, PlanDiffSheet, InsightCard carry labels; screen-width and Dynamic Type scaling is wired through `TypeSpec.font` (`PhaseTraining/Theme/Typography.swift:44`). Not re-raised.

Totals by category:

| Category | Count |
|---|---|
| Contrast failures (text) | 3 sites, 7 call sites |
| VoiceOver gaps (unlabeled interactive) | 3 on watch, 1 phone alternative gap |
| Dynamic Type: fixed-size SF Symbols | 173 of 177 `.system(size:)` sites |
| Tap targets under 44pt | 26 buttons (list below) |
| Reduce Motion | 2 of 28 animation sites respect it |
| Color-only information | 2 weak spots |

The app is dark only: `PhaseTraining/Info.plist:74` sets `UIUserInterfaceStyle` and 4 `.preferredColorScheme(.dark)` calls. Light mode ratios do not apply. Increase Contrast and Reduce Transparency are not read anywhere (0 hits for `colorSchemeContrast`, `accessibilityReduceTransparency`).

## Findings, ranked

### 1. Heatmap day numbers fail contrast on level-1 cells (WCAG 1.4.3, AA)
Evidence: `PhaseTraining/Screens/Progress/ProgressScreen+Heatmap.swift:108-112` draws the day number in `ink3` for levels 0 and 1 and `accentInk` for 2 and up. Fills at `:155-162`: level 1 is accent at 0.25 over surface.
Arithmetic: accent 25% over surface #14161A gives #445023 (L 0.07). ink3 #83868E (L 0.2383) gives (0.2383+0.05)/(0.07+0.05) = 2.38:1. Level 2 (#6A7F2A): accentInk gives 4.39:1, just under 4.5. Level 0 (lineSoft #1F2229): ink3 gives 4.37:1, just under 4.5.
Effect: low-vision users reading the training calendar, the main place the app shows consistency. Text is `monoXS` (11pt scaled), so the 4.5 threshold applies.
Fix: level 1 text `Color.ink` (about 8:1 on #445023); level 2 `Color.ink` is not enough contrast on a 45% fill either, so raise level 2 fill alpha to 0.55 or keep accentInk and darken the fill; level 0 use `ink2`. Effort: 1 h.

### 2. Dimmed ink3 at 0.6 to 0.7 opacity is 2.6 to 3.2:1 (WCAG 1.4.3, AA)
Evidence (5 sites, 4 are text):
- `PhaseTraining/Screens/SorenessCheckInSheet.swift:144` and `:166`, `PostWorkoutFeedbackSheet.swift:115`: "(optional)" label at ink3 x 0.6.
- `PhaseTraining/Screens/CustomRoutineEditSheet.swift:383`: field-bound hint at ink3 x 0.7 (explains why a value was clamped).
- `PhaseTraining/Components/ExerciseTile.swift:186`: drag handle glyph at ink3 x 0.7 (UI component, 3:1 needed).
Arithmetic: ink3 x 0.6 over bg #0A0B0D gives #53555A, 2.64:1; over surface gives #575960, 2.59:1. At 0.7: 3.18 on bg, 3.07 on surface. The 10-31 round raised ink3 to 4.5 and these sites take it back below.
Effect: low-vision users miss the "optional" cue and the clamp explanation. The hint at CustomRoutineEditSheet:383 is meaningful content.
Fix: drop the opacity (use plain ink3). The drag handle at 0.7 passes 3:1 on bg but is marginal on surface and elevated; use plain ink3. Effort: 0.5 h.

### 3. Watch app: three interactive controls with no usable label (WCAG 4.1.2, A)
Evidence in `PhaseTrainingWatch/PhaseTrainingWatchApp.swift`:
- `:107-111` rest "skip" button is `Image(systemName: "forward.fill")` with no `accessibilityLabel`; VoiceOver reads the symbol name.
- `:128-134` set-complete toggle is a bare `checkmark.circle.fill` or `circle` image. VoiceOver says the symbol name and conveys no set number or state in words.
- `:103-106` the "−15" and "+15" buttons are text, but "−15" uses U+2212 and is read inconsistently; give them "Shorten rest 15 seconds" and "Extend rest 15 seconds".
Effect: VoiceOver users on Apple Watch cannot tell what the main in-workout controls do. Reduces the watch app to guesswork mid-set.
Fix: add `.accessibilityLabel("Skip rest")`, `.accessibilityLabel("Set N done" / "Mark set N done")` plus `.accessibilityValue`. Effort: 0.5 h.

### 4. Delete buttons are 12pt glyphs with no frame (WCAG 2.5.8 AA, 2.5.5 AAA; Apple HIG 44pt)
Evidence: `PhaseTraining/Screens/BodyWeightLogSheet.swift:243-248` and `BodyCompositionLogSheet.swift:300-305`: `Image(systemName: "trash").font(.system(size: 12))` inside a plain button with no `.frame` or `.contentShape`. The hit area is the glyph, roughly 12 x 14pt. These are destructive (they trigger `pendingDelete`, with a confirm step).
Effect: motor-impaired users and anyone one-handed. Also adjacent to row content, so mis-taps are likely.
Fix: `.frame(width: 44, height: 44).contentShape(Rectangle())`. Effort: 0.5 h.

### 5. Other tap targets under 44pt (WCAG 2.5.8 AA: 24pt minimum met; HIG 44pt not met)
All are Buttons confirmed by reading the label closure and finding no `contentShape` or padding that reaches 44:
- 28 x 32: `PhaseTraining/Components/ExerciseTile.swift:229`, `:238` (info, swap in the workout list, used on every exercise row).
- 32 x 32: `ExerciseTile.swift:270` (overflow), `:280` (icon button); `LibraryMuscleScreen.swift:70` and `WorkoutCategoryScreen.swift:70` (back); `ProgressScreen+Heatmap.swift:139` (month paging, has `contentShape` but still 32); `WeeklyCheckInFlow.swift:395`, `:415` (back, close); `OnboardingFlow.swift:287`; `CheckInEventsScreen.swift:202` (trash).
- 36 x 36: `ExercisePickerSheet.swift:281`, `SubstituteExerciseSheet.swift:179`, `:240` (info), `OverrideTodaySheet.swift:225` (edit).
- 28 x 28: `LogScreen.swift:370` (discard workout), `CoachDrawer.swift:106` (close coach).
- 18 x 14: `EditSessionSheet.swift:135-141` (warmup "W" toggle). This is the worst: 18 x 14pt, 5.41:1 text but a 252 square-point target.
Held fine: the check-dot at `LogSetRow.swift:307-309` is 22 drawn inside a 44 x 44 hit box.
Effect: users with tremor, limited dexterity; gloved or chalked hands in a gym.
Fix: a shared `.tapTarget()` modifier (`.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())`) applied at those 26 sites; visual size stays the same. Effort: 3 h.

### 6. Reduce Motion respected in 2 of 28 animation sites (WCAG 2.3.3 AAA; Apple review expectation)
Evidence: `accessibilityReduceMotion` appears in `Components/WorkoutTitleWheel.swift:84` and `Components/KettleView.swift:81` only. Unhandled: `Components/RestTimer.swift:53-60` pulses the rest dot forever with `.repeatForever` (the one continuous animation in the app), 13 `withAnimation` sites (for example `WeeklyCheckIn/WeeklyCheckInFlow.swift:212,223`, `Onboarding/OnboardingFlow.swift:175,181`, `TodayTab.swift:74`, `PlanValidationBanner.swift:37,42,53`), and 14 `.animation(` sites (`RootTabView.swift:97`, `ExerciseThumbnail.swift:59,258` crossfade, `CoachBubble.swift:132` spring).
Effect: vestibular-sensitive users. Most are short 0.15 to 0.3s fades, which are low risk; the infinite pulse and the spring are the real cases.
Fix: gate `RestTimer` pulse; add one `View.motionSafe(_:value:)` helper that returns nil animation under Reduce Motion and migrate the 27 sites. Effort: 2 h.

### 7. Dynamic Type: 173 icon sites use fixed `.system(size:)`, 4 text sites do too
Evidence: 177 `.font(.system(size:` sites; 173 are SF Symbols and 4 are text: `EditSessionSheet.swift:139`, `LogSetRow.swift:45` (both the 9pt "W" pill), `PlateCalculatorSheet.swift:250`, `:267` (9pt plate numbers). The text tokens do scale (`Typography.swift:44`, `Font.scaled` at `:168`). `WeekScreen.swift:90,262,520,596` use `ScreenScale.scaled(...)` but that scales for screen width only.
Effect: at accessibility sizes, text grows while its icons stay put, so icon buttons beside large text look tiny. The 9pt "W" and plate labels never grow and are under 11pt at default size.
Fix: for icons, use `@ScaledMetric` or `.font(.system(size: ...).leading(...))` is not enough; use `Image(...).imageScale` with a text style font instead. Start with the 4 text sites. Effort: 2 h for the 4 text sites; 6 h for a sweep of icons.

### 8. No accessibility representation for the custom sparklines; Swift Charts use default marks
Evidence: `ProgressCharts.swift:63-108` `BodyWeightSpark` is a hand-drawn `Path` with no label or hidden flag, hosted in `ProgressScreen+BodyCards.swift:72,191` and `ProgressScreen+FingerCard.swift:29`. The 191 host has an element label with value and change (`:179-180`); the 72 and FingerCard hosts need checking on device. `ExerciseStrengthSection.swift:146` hides its chart (`accessibilityHidden(true)`), acceptable only if the adjacent summary rows carry the numbers (they appear to, `:148-150`). Three full Swift Charts (`BodyWeightLogSheet.swift:150`, `BodyCompositionLogSheet.swift:196`) rely on default Audio Graph with generic series names "date" and "weight" and no `.accessibilityLabel`. The log lists below them list every entry as text, which is the real alternative.
Effect: blind users get a vague audio graph. Moderate, because list rows carry the data.
Fix: label the charts ("Body weight over time, N entries, from X to Y") and add `.accessibilityChartDescriptor` on the two log-sheet charts; hide the Path sparkline where a text value is adjacent. Effort: 2 h.

### 9. Drag-only day swap has an alternative, but the row hides it
Evidence: `WeekScreen.swift:423-446` `.draggable`/`.dropDestination`. A non-drag path exists (`WeekDayEditSheet.swift:420`, `WeekDayEventSheets.swift:272` "Move to which day?"). The row collapses to one VoiceOver element with `.accessibilityElement(children: .ignore)` at `:550` and has no hint pointing at it.
Effect: VoiceOver Switch Control users must discover the edit sheet on their own. Low.
Fix: `.accessibilityHint("Double tap to edit or move this day")`. Effort: 0.25 h.

### 10. Color-only or weak non-color signals
- Watch set toggle (`PhaseTrainingWatchApp.swift:133`): done is green vs secondary, but the glyph also changes (filled check vs circle), so sighted non-color users are fine. The VoiceOver gap is finding 3.
- `Components/RestTimer.swift:53-60` expired state: DONE text and a green tint change; the dot color alone does not carry it. Fine.
- `MuscleFreshness.swift:75` and `BodyAnatomyView.swift:46-47`: muscle shading uses orange (#F39C12) and yellow (#F1C40F) tiers for secondary and tertiary. Orange and yellow are close for deuteranopia. Evidence the anatomy figure is the only carrier for which muscles are worked on that screen was not confirmed. Verify whether a text list sits next to it.
- `PlanValidationBanner.swift:152-160`: danger tint at 8% with 40% border, with text severity words; fine.
- `LogExerciseBlock.swift:38-42`: ok-tinted completion state has a glyph.
Effort to verify and fix the anatomy case: 1 h.

### 11. Borders and dividers are below 3:1 (WCAG 1.4.11, AA), mostly decorative
Arithmetic: `line` #2A2E35 vs surface 1.33:1, vs bg 1.44:1, vs elevated 1.21:1; `lineSoft` vs surface 1.14:1; accentBorder (30% accent) vs surface 2.48:1. Where a border is the only boundary of an input or a chip, it fails 1.4.11. Cards also have a fill difference, which usually satisfies the rule. The search field (`ExercisePickerSheet.swift:149-170`) and filter chips (`:205-213`) are the cases most reliant on borders (surface fill on a bg that is 1.2:1 apart).
Effect: low-vision users locating input fields.
Fix: a `lineStrong` token at 3:1 on bg for input and chip outlines. Effort: 2 h.

## Contrast table (arithmetic)

Method: sRGB channel to linear (c <= 0.03928 ? c/12.92 : ((c+0.055)/1.055)^2.4), L = 0.2126R + 0.7152G + 0.0722B, ratio = (L1+0.05)/(L2+0.05).
Luminance: bg 0.0033, surface 0.0080, elevated 0.0135; ink 0.9101, ink2 0.4736, ink3 0.2383, accent 0.8585, accentDim 0.3401, ok 0.6317, danger 0.3227.

| Text token | on bg | on surface | on elevated | Pass 4.5 |
|---|---|---|---|---|
| ink | 18.00 | 16.56 | 15.11 | yes |
| ink2 | 9.82 | 9.03 | 8.24 | yes |
| ink3 | 5.41 | 4.97 | 4.54 | yes |
| accent | 17.04 | 15.67 | 14.30 | yes |
| accentDim | 7.32 | 6.73 | 6.14 | yes |
| ok | 12.78 | 11.76 | 10.73 | yes |
| danger | 6.99 | 6.43 | 5.87 | yes |

Pairs: accentInk on accent 17.04; accentInk on accentDim 7.32 (PlanDiffSheet no-op button); ink3 on accentWash 4.57; bg on ink3 (warmup pill) 5.41; ok on ok 18% wash 7.72; danger on danger 8% wash 5.82. The ink3-on-elevated margin is 0.04, so any opacity applied there fails.
Light mode: not applicable.

## Checked and fine

- All 7 text tokens pass AA on bg, surface and elevated (table above).
- Icon-only buttons: 34 found by a brace-balanced scan; the 10 flagged unlabeled turned out to be 6 text buttons (false positives) and 4 real (all on watch, finding 3, plus 1 phone check dot which does have a label at `LogSetRow.swift:318`).
- Phone buttons with labels: `ExerciseTile.swift:229-282`, `ExercisePickerSheet.swift:285`, `SubstituteExerciseSheet.swift:182`, `OverrideTodaySheet.swift:230` (name-specific labels), `LibraryMuscleScreen.swift:76`, `CheckInEventsScreen.swift:203`, `WeeklyCheckInFlow.swift:400+`, `CoachDrawer.swift:111`, `LogScreen.swift:376`.
- Custom controls: workout wheel has value, adjustable action, and a see-all action (`WorkoutTitleWheel.swift:134-155`); effort menu has label and value (`LogSetRow.swift:285-286`); week rows and stat cards collapse to single spoken elements (`WeekScreen.swift:550-562`, `ProgressScreen+StatCards.swift:63-64`); heatmap day cells have spoken date, session count and duration (`ProgressScreen+Heatmap.swift:147-153`).
- Reorder lists use native `.onMove` in a `List` with `editMode` active (`DayWorkoutPreviewSheet.swift:178,203`, `CustomRoutineEditSheet.swift:136,205`), which gives VoiceOver move actions for free. Verify on device.
- Kettle mascot has a label (`KettleView.swift:94`) and honors Reduce Motion (`:85`).
- Fixed-height containers: 16 `.frame(height:)` sites over 44 are spacers, sparklines and the mascot, none wrapping text.
- `lineLimit(1)` (32 sites): the important ones (`ExerciseTile.swift:89`, `WeekScreen.swift:513`, `LogScreen.swift:390`) either sit on secondary meta or carry `minimumScaleFactor`/truncation. Exercise names in `ExerciseTile` were not confirmed single-line; verify at AX5 on device. `PhaseTrainingWatchApp.swift:163` truncates the exercise name on the watch.
- `LogSetRow` uses `@ScaledMetric` widths (`LogScreen.swift:34-39`), so set rows do not clip at accessibility sizes.
- Rest timer check-dot hit target is 44 x 44 (`LogSetRow.swift:307-309`).
- Text weights tied to color: done state uses glyph plus color.
- Accessibility identifiers: 211 on main and UI-test surfaces; no conflict with labels found.
