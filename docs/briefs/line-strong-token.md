# Brief: `lineStrong` border token for inputs and chips

Backlog item: `docs/PLAN-gap-backlog-2026-11b.md`, "Later, not scheduled": "`lineStrong` border token for inputs (2 h)". Audit finding 11 in `audits/2026-11-10-gap-round/accessibility.md` (line 91).

Agent: builder. Skills to load first: `phase-training2-gitignored-pbxproj`, `phase-training-xcodebuild-test-failed-grep-full-log`.

Slot A. Every `xcodebuild` call passes both:

```
-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'
-derivedDataPath ~/Library/Developer/Xcode/DerivedData-A
```

## Problem

`Color.line` (#2A2E35) measures 1.44:1 on `bg`, 1.33:1 on `surface` and 1.21:1 on `elevated`. Text fields and unselected chips are drawn as a `surface` or `elevated` fill with a 0.5pt `line` outline, and the fills are about 1.2:1 apart from what they sit on. A low-vision user cannot find where a field or a chip starts. WCAG 1.4.11 asks for 3:1 on the boundary of a control.

## Design

### Token

In `PhaseTraining/Theme/Theme.swift`, under "Borders / dividers", after `lineSoft`:

```swift
// Outline of a control that holds or selects a value. 3.74:1 on bg, 3.44:1 on surface, 3.14:1 on elevated.
static let lineStrong = Color(red: 0x68 / 255, green: 0x6C / 255, blue: 0x75 / 255) // #686C75
```

The value is fixed. Add a swatch row for it in `Theme/StyleGuidePreview.swift` after `lineSoft` (`hex: "#686C75"`, `inkOnTop: .ink`).

### Rule for which sites change

A site changes when the outline belongs to a control that **holds or selects a value**: a text field, a text editor, a search field, a picker trigger that shows its current value, a chip or segment or row the user taps to select, a checkbox, a removable value pill.

A site stays on `Color.line` when it is a button that performs an action (back, info, Skip, +15, Regenerate, Erase, Discard), a card, a banner, a list container, a divider or a frame around an image or chart.

At a changed site, replace `Color.line` with `Color.lineStrong` and nothing else. Line widths, corner radii, fills and paddings stay. Where the stroke is conditional, only the `Color.line` branch changes: the focused branch (`Color.accent`), the selected branch (`Color.clear`, `Color.accent`, `Color.accentBorder`) stay as they are.

### Sites to change

Line numbers were read at commit 6202536 and may have moved by a few lines. Read each site before editing it and apply the rule above. If a listed site turns out to be an action button or a container, leave it and say so in the report. If you find a value-holding control with a `Color.line` outline that is missing from this list, change it and say so in the report.

Text inputs (all under `PhaseTraining/`, find the file by name):

| File | Line | What |
|---|---|---|
| ExercisePickerSheet.swift | 237 | search field |
| WorkoutCategoryScreen.swift | 123 | search field |
| LibraryScreen.swift | 277 | search field |
| LibraryMuscleScreen.swift | 123 | search field |
| HistoryScreen.swift | 219 | search field |
| InjuryPickerSheet.swift | 109 | search field |
| Coach/CoachDrawer.swift | 241 | chat composer |
| AbandonReasonSheet.swift | 78 | note field |
| SportLogSheet.swift | 208 | notes editor |
| PostWorkoutFeedbackSheet.swift | 138 | notes editor |
| CompleteScreen.swift | 455 | notes editor |
| WeeklyCheckIn/CheckInIntentScreen.swift | 55 | editor |
| WeeklyCheckIn/CheckInFeedbackScreen.swift | 75 | editor |
| CoachRequestScreen.swift | 238 | name field |
| AboutYouEditorSheet.swift | 144 | age field, unfocused branch |
| BodyMetricsEditor.swift | 215 | `inputCard`, unfocused branch |
| PlateCalculatorSheet.swift | 166 | `inputRow` |
| BodyWeightLogSheet.swift | 100, 116 | weight and note fields |
| BodyCompositionLogSheet.swift | 96, 107, 149 | method, note, `fieldRow` |
| DislikesEditorSheet.swift | 94 | input |
| EditSessionSheet.swift | 190 | `field()` |
| LogSetRow.swift | 238 | `numCell`, inactive branch |
| WeekDayEventSheets.swift | 111 | event title |

Chips, segments, selection rows, pickers and checkboxes (unselected branch only):

| File | Line | What |
|---|---|---|
| ExercisePickerSheet.swift | 355 | `SelectableChip` |
| ExercisePickerSheet.swift | 273 | "All filters" toggle |
| LibraryMuscleScreen.swift | 161, 180 | filter toggle, chip |
| LibraryScreen.swift | 241 | segment control |
| ExerciseFilterSheet.swift | 169 | row list |
| Onboarding/OnboardingFlow.swift | 427 | `OnboardingChip` |
| Onboarding/OnboardingFlow.swift | 478 | `OnboardingPickRow` |
| InjuryPickerSheet.swift | 147 | checkbox row |
| InjuriesEditorSheet.swift | 272, 296 | chip, removable pill |
| SportLogSheet.swift | 191 | intensity chip |
| PostWorkoutFeedbackSheet.swift | 205 | difficulty and hurt chips |
| CompleteScreen.swift | 398, 439 | feel chip, tag chip |
| HistoryScreen.swift | 257 | tag filter chip |
| PlateCalculatorSheet.swift | 99 | LB/KG segmented container |
| WeekDayEditComponents.swift | 78 | selectable option |
| WeekScreen.swift | 838 | tone option row |
| WeekScreen.swift | 745 | `WeekToneChip`, the `tone == nil` branch |
| SorenessCheckInSheet.swift | 291 | chip |
| AbandonReasonSheet.swift | 58 | radio row |
| GoalPickerSheet.swift | 76 | toggle card |
| RemindersEditorSheet.swift | 47 | on/off card |
| EquipmentEditorSheet.swift | 50 | tier card |
| LogSetRow.swift | 285 | effort menu trigger, inactive branch |
| LogSetRow.swift | 312 | done checkbox, unchecked circle |
| WeeklyCheckIn/CheckInEventsScreen.swift | 163 | date selector |
| FavoritesEditorSheet.swift | 98 | removable chip |
| DislikesEditorSheet.swift | 131 | removable pill |
| EditSessionSheet.swift | 150 | set-type menu trigger |

Two fields with no outline today get one: `CustomExerciseCreateSheet.swift` near lines 87 (name) and 124 (notes). Add `.overlay(RoundedRectangle(cornerRadius: <the field's own radius>).stroke(Color.lineStrong, lineWidth: 0.5))`, matching the corner radius the field's background already uses.

### Stays as it is (do not touch)

- Action buttons: ExercisePickerSheet 331 and 84, WorkoutCategoryScreen 73, LibraryMuscleScreen 73, OverrideTodaySheet 227, SubstituteExerciseSheet 181 and 242, WeekScreen 280, CheckInEventsScreen 86, CheckInPatternsScreen 83, ProfileScreen 654, ExerciseDetailSheet 324, CoachRequestScreen 319 and 331, CompleteScreen 595, HistoryScreen 453, RestTimer 148, CoachDrawer 157, DislikesEditorSheet 107, MissedWorkoutBanner 84, DetectedActivityBanner 59, SorenessCheckInPill 47.
- Every `lineSoft` and `accentBorder` stroke.
- `cardSurface`, cards, banners, list containers, dividers, image and chart frames.
- The watch and widget targets (neither has a line token).

### Test

New file `PhaseTrainingTests/ThemeContrastTests.swift`, class `ThemeContrastTests`. Run `xcodegen generate` after adding it.

- A private helper that resolves a `Color` through `UIColor(color).getRed(_:green:blue:alpha:)`, computes WCAG relative luminance (channel `c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)`, `L = 0.2126 R + 0.7152 G + 0.0722 B`) and returns `(lighter + 0.05) / (darker + 0.05)`.
- `test_lineStrongClearsThreeToOneOnEveryFill`: `lineStrong` against `bg`, `surface` and `elevated` is each `>= 3.0`.
- `test_lineStrongStaysBelowBodyTextInk`: `lineStrong` against `bg` is lower than `ink3` against `bg`, so an outline never reads as text.

## Done when

- `Color.lineStrong` exists with the value above and has a style guide swatch.
- Every listed site draws its resting outline with `Color.lineStrong`; no site in the "stays" list changed.
- The app target builds.
- `-only-testing:PhaseTrainingTests/ThemeContrastTests` passes (2 tests). Send the full log to a file in your scratchpad and grep it as CLAUDE.md says.

## Out of scope

- The contrast of `accentBorder` on a selected row (2.48:1 on surface).
- Outlines for the other unbordered text fields (ExerciseNoteSheet, MaxHangTestSheet, SkiReadinessTestSheet, CustomRoutineEditSheet).
- Action button outlines, card borders, any line width change.
- UI tests, the build number, the backlog doc, committing.

## Report

One final report, no interim messages: files changed with the count of sites changed per file, the test class run with pass and fail counts, each listed site you left alone and why, each unlisted site you changed and why, anything seen outside this item.
