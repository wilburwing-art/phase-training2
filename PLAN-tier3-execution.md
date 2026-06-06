# Tier-3 execution plan — god-object splits + localization

Living plan for the remaining open work from `audits/2026-06-05-ultra-audit-backlog.md`
("Everything is closed except the Tier 3 god-object splits and localization").
Grounded in a structural pass over each target file. **One PR per file**, each
gated on the §9 test suite. Check items off as PRs merge.

> Status legend: ☐ not started · ◐ in progress / PR open · ☑ merged

---

## 0. Current state & blockers (read first)

| PR | Branch | What | Status |
|----|--------|------|--------|
| #48 | `claude/coachdb-guard-version-stamp` | CI guard fix (coach.db logical-content compare) | ◐ open — **must merge first** |
| #47 | `claude/awesome-allen-8sTdu` | WorkoutGenerator split (Tier-3 #1) | ◐ open — blocked on #48 |

**Why #48 gates everything:** the `coach.db` drift guard (`verify_coachdb_sync.sh`)
raw-byte-diffed a SQLite file whose on-disk bytes vary by the libsqlite version
that wrote it. It was red on *every* PR and on `main`. #48 switches it to a
logical-content (`iterdump`) compare. **Until #48 lands on `main`, no other PR
can go green** — they all inherit the broken guard. Sequence:

1. #48 green → merge to `main`
2. merge `main` into #47 → #47 finally compiles + runs the suite → validates the
   extension-split pattern
3. only then fan out the remaining splits below, each branched off the fixed `main`

## 1. Execution model

- **No local Swift toolchain.** The authoring env is Linux; there's no
  `xcodebuild`/`swiftc`. The only compile+test gate is CI (`.github/workflows/test.yml`,
  macos-26), which runs on `pull_request`. So every split is verified *by opening
  its PR*, not locally. Static verification before push is mandatory (below).
- **One PR per file** (backlog rule). Each branches off the latest `main`. Don't
  stack splits on one branch — independent PRs.
- **XcodeGen globs `PhaseTraining/`** (`Project.yml` `sources: - path: PhaseTraining`),
  so new files are picked up automatically; no manifest edits.
- **Pre-push static checklist** (the no-compiler safety net), per the WorkoutGenerator
  precedent:
  1. every moved symbol defined exactly once across the file set
  2. braces balance in every file
  3. no new file references a symbol left `private`/`fileprivate` in another file
  4. for SwiftUI: every `@State`/`@Binding` a moved subview touches is threaded in
  5. imports match the origin file

### The one hazard for `extension`-style splits (non-View files)

Swift `private`/`fileprivate` are **file-scoped**. Moving a method into an
`extension Type {}` in a new file breaks any cross-file reference to a `private`
member — in *either* direction. Rule of thumb: a helper called only by members
that move *with* it can stay `private` (they share the new file); a helper
referenced across the new boundary must be relaxed to internal. Each section
below lists the exact relaxations.

### The one hazard for SwiftUI screen splits

Extracted subviews can't see the parent's `@State`. Nested mutation
(`session.exercises[i].sets[j]`) must be threaded as `Binding`s, or the mutation
kept in the parent and passed down as closures. `@FocusState`, `TimelineView`,
and `PreferenceKey` are extra-sensitive — keep them with the state they drive or
verify reactivity survives the move. These are riskier than the enum/class splits;
do them *after* the class splits prove the pattern under CI.

---

## 2. Recommended sequence (lowest risk → highest)

| # | File | Lines | Kind | Risk | Why this order |
|---|------|-------|------|------|----------------|
| 1 | WorkoutGenerator | 1679→1041 | enum statics | low | ☑ done (#47) — proves the extension pattern |
| 2 | CoachContext | 971 | enum statics | **lowest** | stateless; **zero** access relaxations needed |
| 3 | PlanStore | 1211 | ObservableObject class | medium | extension-style; 7 `private`→internal relaxations, already has 1 extension |
| 4 | WeekDayEditSheet | 875 | SwiftUI sheet | medium | self-contained sub-sheets, fewer cross-bindings |
| 5 | ProgressScreen | 1177 | SwiftUI screen | medium | card structs are mostly read-only → clean extraction |
| 6 | ProfileScreen | 795 | SwiftUI screen | med-high | ~27 presentation flags; sheet-coordination threading |
| 7 | TodayScreen | 1177 | SwiftUI screen | high | template editor mutates shared state via bindings |
| 8 | LogScreen | 1438 | SwiftUI screen | **highest** | rest-timer + nested set/exercise bindings + TimelineView |
| 9 | Localization | — | cross-cutting | phased | separate track; see §5 |

Rationale: do the two `extension`-of-a-type splits (CoachContext, PlanStore)
first — they mirror the proven WorkoutGenerator pattern and carry no SwiftUI
binding risk. Then the SwiftUI screens, easiest first, so the binding-threading
technique is proven on a small sheet before the 1438-line LogScreen.

---

## 3. The splits (one PR each)

### 3.1 ☑ WorkoutGenerator.swift — DONE (#47)
- `WorkoutGenerator+Accessories.swift` (accessory layer)
- `WorkoutGenerator+Prescription.swift` (prescription / RPE / progressive-overload)
- Relaxed: `isMuscleSoreForExercise` + 3 accessory entry points `private`→internal.
- Main: 1679 → 1041.

### 3.2 ☐ CoachContext.swift (971) — **lowest risk, do next**

`enum CoachContext` — stateless namespace of `static` section/format helpers, one
giant `snapshot(...)` orchestrator (lines 15–389) that calls the rest. Mirrors
WorkoutGenerator exactly. **No access relaxations needed** — every helper is
`static`, every `private` helper is used only by a sibling in its own group.

New files (`extension CoachContext`):
- `CoachContext+ProfileBlocks.swift` — `seasonSummary`, `bodySection`, `strengthSection`
- `CoachContext+InjuryBlocks.swift` — `injuryNameLookup`, `injuryByLookup` (private, stays), `structuredInjuriesSection`, `injuryFiltersSection`
- `CoachContext+MovementBlocks.swift` — `patternFrequencySection`, `muscleBalanceSection`, `familiaritySection`, `formatPattern` (private, stays)
- `CoachContext+LoadBlocks.swift` — `lastSessionDetailSection` + `renderWorkingSets` (private), `weekAdherenceSection`, `recoveryTrendSection`, `averageRecentDurationMinutes`, `histogramSummary` (private)
- `CoachContext+TextUtils.swift` — `sanitizeFreeText` (public), `longDate`/`weekday`/`short` (private date helpers)

Keep `snapshot(...)` + the `extension AppTab` in the main file.
**Relaxations: none.** Verify: each `private` helper ships in the same file as its only caller.

### 3.3 ☐ PlanStore.swift (1211) — extension-style, medium

`final class PlanStore: ObservableObject`. Already has one extension
(`PlanStore+LLMRefinement.swift`), so the pattern exists. 7 `@Published` props +
several injected stores. Split by the backlog's named responsibilities:

New files (`extension PlanStore`):
- `PlanStore+Generation.swift` — `generate`, `applyCustomRoutineOverrides`, `composeWorkout(fromCustom:)`, `parseRest`, `buildGeneratorContext`, `makeGeneratorContext`, `recordPickedExercises`, `setPlan`, `composeWorkout(for:in:memory:)`
- `PlanStore+History.swift` — `snapshotCurrentPlan`, `shape(forWeek:)`, `captureRolloverIfNeeded`, `hasPriorWeekShape`, `adoptLastWeekShape`, `liftFocus`
- `PlanStore+Validation.swift` — `currentValidationIssues`, `suppressedRulePatterns`, `recordPlanOverride`, `updateOverrides`
- `PlanStore+MissedWorkoutAutopilot.swift` — `pendingMissedWorkouts`, `proposeMissedReshuffle`, `shouldOfferConsolidation`, `applyMissedReshuffle`, `dismissMissed`, `recordMiss` (private, stays), `consolidateWeek`, `clear`
- `PlanStore+Persistence.swift` (optional) — the `save*` family + `encoder`/`decoder`

Keep `init`, `reloadFromDefaults`, `resubscribeToMemory` (private, init-only) in the main class.

**Relaxations required `private`→internal** (cross-file refs):
- `saveOverrides`, `savePastPlans`, `savePlanOverrides`, `saveMissedWorkouts`, `saveReshuffleCount`, `saveConsolidationCount` (called from autopilot/validation extensions)
- `buildGeneratorContext` (called from both Generation and PlanEdit/regen paths)

Watch: the existing `+LLMRefinement` extension calls `currentRefinementTask`,
`plan`, `overrides`, `sessionStore`, `kickOffLLMRefinementIfConsented` — all stay
accessible (internal/published). `apply(_:)` is called cross-bucket → keep it internal (it's `public` already).

### 3.4 ☐ WeekDayEditSheet.swift (875) — SwiftUI, medium

`struct WeekDayEditSheet` (2 `@EnvironmentObject`, 10 presentation flags) plus
**7 sibling structs already in-file** — exactly the seams. Most are pure
presentation taking a closure; the lowest-binding-risk screen split.

New files:
- `WeekDayEventSheets.swift` — `SportPickerSheet`, `EventEditorSheet` (5 own `@State` + a nested `SportPickerSheet`), `MoveDayPickerSheet`, `IntensityEditorSheet` (each already self-contained, taking `onPick`/`onSave` closures + their own env)
- `WeekDayEditComponents.swift` — `LiftFocusPickerSheet`, `FocusChip`, `ActionRow` (reused 11× in `actionList`)

Keep in main: `body`, `header`, `actionList`, the 10 flags, all alerts, and the
mutation funcs (`toggleUnavailable`, `addSportSession`, `addEvent`,
`clearOverrides`, `swap`, `setIntensity`, `setLiftFocus`, `addOutOfTownEvent`) —
they all call `planStore.updateOverrides`, and the one-event-per-day gate
(`requestAdd`) is coordination that stays with the parent.
Risk: low — the sub-sheets are already decoupled via closures; just relocate. No nested `Binding`s into the parent's state.

### 3.5 ☐ ProgressScreen.swift (1177) — SwiftUI, medium

`struct ProgressScreen` is **read-only** (only 3 `@State`: two body-log sheet
toggles + `showingHistory`; mutates nothing). ~12 cards are computed-var renderers
of derived data → the cleanest screen split. 3 private chart structs already exist.

New files:
- `ProgressCharts.swift` — `LineSpark`, `BodyWeightSpark`, `ExerciseSparkline`
- `ProgressScreen+StatCards.swift` — `statStrip`/`statCell`, `sessionsCard`, `volumeCard`, `strengthRatiosCard`/`strengthRow`, `muscleBalanceCard`/`muscleBar` + `weeklyBuckets`/`startOfWeek` helpers
- `ProgressScreen+BodyCards.swift` — `bodyWeightTrendCard`/`bodyCompositionTrendCard` (+ their bodies) and the 2 sheet toggles
- `ProgressScreen+ExerciseCards.swift` — `perExerciseCard`, `prFeedCard`, `feedbackCard`, `recentSessionsCard` + `ExerciseSeries`/`SparkPoint` + `topExerciseSeries` and friends

Keep in main: `body`, `content`, `emptyState`, the generic `card<C:View>()`
`@ViewBuilder` wrapper (shared by all cards — keep it reachable, ie. in main or a
shared file). These are `extension ProgressScreen`/sibling-struct moves with no
parent-state threading → very low risk.
Risk: medium only because it's the largest screen; mechanically the safest of the SwiftUI set.

### 3.6 ☐ ProfileScreen.swift (795) — SwiftUI, med-high

`struct ProfileScreen`, 5 `@EnvironmentObject`, **~27 `@State`** (19 editor-sheet
flags + 7 backup/restore + 3 tap-to-edit + erase). The flags are coordination
state bound to `.sheet(isPresented:)` modifiers, so they **stay in the body**.
Extract the pure pieces, not the flags.

New files:
- `ProfileScreen+RowSummaries.swift` — the 14 read-only summary computed props (`sportsSummary`, `seasonsSummary`, … `currentTier`) + `tuningRow`, `settingsGroup`, `sectionLabel`
- `ProfileScreen+BackupRestore.swift` — `exportBackup`, `handleImport`, `performRestore`, `eraseAllData`, the `beginEditing`/`commitEditingValue` tap-to-edit logic, and the `EditingField` enum
- `ShareSheet.swift` — lift the `UIActivityViewController` wrapper out

Keep in main: `body` (all `.sheet`/`.alert`/`fileImporter` modifiers + the 27
flags), `header`, `planTuningSection`, `dangerZoneSection`. Optional polish (own
PR): collapse the 19 editor flags into one `enum EditorSheet: Identifiable` +
single `.sheet(item:)` — but that's behavior-adjacent; do the pure extraction
first, the flag-collapse second.
Risk: med-high — backup/restore is a small state machine; keep its pieces together and verify the restore reloads (`planStore`/`sessionStore`/`customStore`) still fire.

### 3.7 ☐ TodayScreen.swift (1177) — SwiftUI, high

`struct TodayScreen`, 6 `@EnvironmentObject`, 18 `@State` (6 template-editor +
9 sheet-coordination + misc). Mutations rebuild `editableTemplate` immutably
(safe to pass around). One nested `CoachPolishedExplanationSheet`.

New files:
- `TodayScreen+TemplateEditor.swift` — `inlineExerciseCard`, `todayExerciseTile`, `inlineAddExerciseRow` + template mutations (`updateExercise`, `swapExercise`, `appendExercise`, `moveExercise`, `deleteExercise`, `saveCurrentTemplateToLibrary`); thread `editableTemplate`/`didModify`/`didSaveToLibrary` + sheet idx bindings
- `TodayScreen+Derived.swift` — the read-only computed props (`template`, `heroTitle`, `heroSubtitle`, `insightCopy`, …) + stateless helpers (`computeStats`, `formatDuration`, `parseReps*`)
- `TodayScreen+SheetCoordination.swift` — the `.sheet(...)` stack + callbacks
- `CoachPolishedExplanationSheet.swift` — lift the nested struct out

Recommended: collapse the 9 sheet fields into one `enum SheetState: Identifiable`
+ a single `.sheet(item:)`. **Respect the load-bearing `didModify` guard** on
`onChange(of: template)` (backlog §"What NOT to touch") — don't simplify it away.

### 3.8 ☐ LogScreen.swift (1438) — SwiftUI, highest risk, do LAST

`struct LogScreen`, `@EnvironmentObject store`, 15 `@State`. Mutates `session`
in place (auto-saved via `onChange`). 6 tightly-coupled rest-timer fields.

New files (per backlog "collapse 6 rest-timer fields into one struct, extract row/edit subviews"):
- `LogScreen+RestTimer.swift` — new `struct RestTimerState` (the 6 fields + `clear()`/`remaining(at:)`); move `activeRestCard`, `restDivider`, `maybeFireRestExpiry`, `currentRestRemaining`. **TimelineView must move with the state** or take a `Binding<RestTimerState>`.
- `LogSetRow.swift` — `setRow` + `weightCell`/`numCell`/`effortCell`/`checkDot`/`bodyweightCell`; needs nested `Binding`s into `session.exercises[i].sets[j]` + rest-timer + weight-propagation bindings
- `LogExerciseBlock.swift` — `exerciseBlock` + `coachingHintsRow`/`progressionPill`/`columnHeaders`/`supersetBand`
- `LogScreenHelpers.swift` — pure logic (`thumbnailURL`, `showsWeightInput`, `weightColumnLabel`, `computeProgressionSuggestion`, `propagateWeight`, `markAllSetsDone`, `isMidSupersetRound`, `hasFollowingWork`, `fmtTime`, `fmtElapsed`)

Hardest part: threading nested `Binding`s for set/exercise mutation across files.
Replace the 6 `@State` rest fields with one `@State var rest = RestTimerState()`
in the first PR (the struct collapse the backlog explicitly asks for).

---

## 4. Per-PR checklist (paste into each PR body)

```
- [ ] Branched off latest main (post-#48)
- [ ] New files compile-clean locally via static checks (defs once / braces / no cross-file private)
- [ ] No behavior change intended (pure move) OR behavior delta called out
- [ ] §9 gate suite green in CI (GeneratorInvariant, WorkoutGenerator, Planner,
      ReadinessGeneratorShipGate, ReadinessSignal, PlanStoreRegen,
      PlanStoreValidationOverride, SessionStoreActiveSessionApply, WeekConsolidator)
- [ ] audits/2026-06-05-ultra-audit-backlog.md item checked off w/ commit ref
```

---

## 5. Localization (separate track — §6 of backlog)

Currently **zero** infra: no `.xcstrings`/`.strings`/`.lproj`, no `NSLocalizedString`/
`String(localized:)`/`LocalizedStringKey`. ~258 hardcoded enum-label cases across
~25 files, ~328 `Text("…")` + ~95 `Button("…")` literals, ~350+ interpolated/plural
strings. **~800+ distinct user-facing strings.** Out of scope: LLM coach output,
user-generated content, (initially) system/backup errors.

Phased:
- **L0 — Infra:** add a String Catalog (`.xcstrings`); set dev language English; pick target languages.
- **L1 — Enum labels (low risk, high reuse):** wrap `var label` returns in `String(localized:)` — `WeekPlan.DayKind`, `WeekOverrides.*`, `TrainingMemory.*`, `ExerciseFilters.*`, `ExerciseTaxonomy.*`, `StrengthStandards.*`, `PlanEdit` (the audit's named starting point, `PlanEdit.swift:31`).
- **L2 — Static screen UI:** buttons, section headers, alert titles/messages across `Screens/`.
- **L3 — Plurals/interpolation (hard):** `.stringsdict`/catalog plural rules for "X entries", "Xw ago", "X sets", etc.
- **L4 — (optional) coach/system text.**

L1 is mechanical and PR-able file-by-file like the splits. L3 needs a linguist +
per-language QA — treat as its own project, not part of the Tier-3 sweep.

---

## 6. Risk register

| Risk | Where | Mitigation |
|------|-------|------------|
| No local compiler → silent break | all | static checklist §1; CI-per-PR; small PRs |
| `private` cross-file ref | CoachContext (none), PlanStore (7) | relaxations enumerated per file |
| Nested `Binding` threading | Log/Today screens | thread `$session.exercises[i].sets[j]` or keep mutation in parent + closures |
| `TimelineView`/`@FocusState` reactivity lost on move | LogScreen | move with owning state; verify ticking in CI UI tests |
| Touching load-bearing code | Today (`didModify`), PlanStore (`apply` ordering, memory resubscribe) | see backlog "What NOT to touch"; pure moves only |
| PRs stacking red while #48 unmerged | sequencing | land #48 first; branch each split off fixed main |
| God-object split changes behavior | all | characterization tests (the §9 gate) are the backstop |
