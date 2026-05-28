# Part: Workout-Execution Flow

Scope: TodayScreen, TodayTab, LogScreen, CompleteScreen, DayWorkoutPreviewSheet, OverrideTodaySheet, PostWorkoutFeedbackSheet, SorenessCheckInSheet, SubstituteExerciseSheet, EditSessionSheet + components RestTimer, ExerciseTile, ExerciseActionSheet, TodayRecoveryCard. Verified against SessionStore + WeekPlan.

Scores: 1 (broken) – 5 (excellent).

---

### TodayScreen.swift
Correctness **2** · UX **3** · Data-gap **3** · Consistency **4** · Perf **2** · A11y **3**

- **Stale `editableTemplate` (correctness, P0).** It is seeded only once in `.onAppear` with `if editableTemplate == nil` (L345-347) and never re-synced. The screen is reused across day-kinds in TodayTab (no `.id()` remount). If the plan regenerates, a day-override is scheduled (OverrideTodaySheet → `scheduleOverride`), or `store.active` appears/clears while Today is alive, `editableTemplate` keeps the *old* exercise list. Start then builds the session from the stale shape (`startWorkout` L838-850 prefers `editableTemplate`). No `.onChange(of: template)`.
- **`onAppear` seeds even on non-workout days.** On a sport/rest day `template` is `nil`, so `editableTemplate` stays `nil` — fine — but if a stale active session exists it forces `.lift` (effectiveKind L64-67) regardless of plan, and the soreness pill + recovery card still render under a hero that may not match. The "active always wins" rule (header comment) is correct but means a *cleared-but-not-reloaded* state can mislead.
- **Heavy work in render path (perf).** `todayExerciseTile` (L524-543) calls `previous?.exercises.first(...)`, `bucketForExercise`, `thumbnailURLForExercise`, `exerciseID(forName:)` per row per render. These route through `ExerciseLookupCache` (good), but `previous` is a computed property that re-hits `store.getPreviousSession` on every body eval (L115-118), uncached. The inline `List` inside a `ScrollView` with `scrollDisabled` + fixed `listHeight` (L480, `count*88+56+8`) is a known-fragile pattern and the magic `88` will clip rows under Dynamic Type.
- **`saveCurrentTemplateToLibrary` does a coach.db search per exercise on the main thread (L737-760)** — `listExercises(search:)` for each row at save time. Acceptable (user-initiated) but duplicated logic vs DayWorkoutPreviewSheet's `lookupExerciseId`.
- **Data-gap:** `insightCopy`/`heroCaption` surface one coach line, but TrainingMemory has affinity, dislikes, soreness-by-muscle, and feedback history that never appears here. The "LAST SESSION" card shows only duration/sets/avgRPE (L462-466) — no PR/trend, despite `personalRecords` + sparkline data existing.
- A11y: soreness pill and recovery card have labels; exercise tiles get `today-edit-N` identifiers but no descriptive VoiceOver label (reads raw title+meta). Hero title injects `\n` (L129) which VoiceOver reads as a pause.

### TodayTab.swift
Correctness **4** · UX **4** · Consistency **4**

- Clean state machine. One concern: `onFinish` falls back to `.start` if `store.active` is nil (L41-46) — but `LogScreen.onFinish` is the Finish button, which never clears active, so this branch is effectively dead unless active is cleared mid-render. Minor.
- No `.id()` on TodayScreen across `.start` re-entries, compounding the editableTemplate staleness above.

### LogScreen.swift
Correctness **3** · UX **4** · Data-gap **3** · Consistency **3** · Perf **3** · A11y **3**

- **Effort picker is integer-only RPE 6–10 (L708) but display + avg use decimals (`effortCell` shows raw string; CompleteScreen avgRPE formats `%.1f`).** A user can never enter 7.5/8.5 through the menu, yet EditSessionSheet's RPE field (L155) and seed data assume decimals. Inconsistent capture granularity.
- **`prevLabel` reads `prevSets[setIdx]` positionally (L556-562).** After a mid-session swap (`swapExercise` keeps logged sets but the exercise identity changes) or add-set beyond `prevSets.count`, the "Last" column shows the *wrong* exercise's history or "—". Swap keeps `prevSets` from the original exercise (L161-167 only changes name/type), so post-swap the Last column lies.
- **Rest-expiry side effect inside TimelineView render (L818-826).** `maybeFireRestExpiry` is called from `.onChange(of: ctx.date)` AND `.onAppear` every tick. Guarded by `restAlertFiredFor` so it fires once — correct — but mutating `@State` (`restExpiredFlashUntil`) from within a TimelineView body's onChange is a re-entrancy smell; works but fragile.
- **`ForEach(... id: \.offset)` for set rows (L423) and grouped exercises (L192).** Index-keyed identity means delete/reorder/add can animate the wrong row and is the classic SwiftUI footgun for TextField focus jumps. Sets have a `num` and exercises have `id` — both should key on those.
- Auto-save on every `session` mutation (L65-68) writes the whole session to the store on each keystroke (every TextField change mutates `session`). For a long session this is repeated full-object encode on the main actor.
- Strong UX: superset round-robin rest suppression (`isMidSupersetRound`), inter-exercise auto-rest, "Log all sets", warmup pills, propagateWeight. Genuinely thoughtful.
- A11y: set cells have identifiers but numeric TextFields lack `accessibilityLabel` (VoiceOver reads "—, text field"). Check-dot button has no label.

### CompleteScreen.swift
Correctness **3** · UX **4** · Data-gap **4** · Consistency **4** · A11y **3**

- **Duration recomputed from `Date()` at view eval (`elapsedSeconds` L53-55).** CompleteScreen receives the still-running `ActiveSession` (active not cleared until `saveCompleted`). So the displayed DURATION keeps growing while the user fills feel/note, and the value saved (`saveCompleted` computes its own `endTime` L311) differs from what was shown. Off by however long the user lingers.
- **`stats.doneSets` counts warmup sets** (SessionStore.stats L417-444 has no warmup filter), but `personalRecords` excludes warmups (SessionStore L356). So the SETS stat and PR logic disagree on what a "set" is. The header SETS number includes warmups; the prototype intent was working sets.
- PR detection is solid (cross-template, per-rep, name-matched). Feel chips + note + auto-presented feedback sheet is a clean handoff.
- Hand-rolled `FlowLayout` (L421-463) duplicates `WrappingFlow` used in SubstituteExerciseSheet — two flow layouts in this part.

### DayWorkoutPreviewSheet.swift
Correctness **4** · UX **4** · Consistency **3** · Perf **3**

- `.environment(\.editMode, .constant(.active))` (L201) keeps the List permanently in edit mode for drag-reorder — but also disables row tap-to-select semantics and forces the reorder grips always on, which can fight the `onTap` action-sheet open. Verify taps still register in edit mode.
- `moveExercises` reorders the superset-grouped render view then writes back (L212-223) — clever, but `ForEach(... id: \.offset)` on grouped items (L167) again risks mis-animation.
- Parses `defaultRest`/`defaultReps` with its own static helpers (L592-604) that differ subtly from TodayScreen's instance copies (TodayScreen's `parseRestSeconds` doesn't accept `.`; this one does). Three near-duplicate `similarFiltersForExercise` implementations across this file, LogScreen, TodayScreen.

### OverrideTodaySheet.swift
Correctness **4** · UX **4** · Consistency **4**

- Dual-mode (start-now vs schedule-override via `targetDate`) is clear. `scheduleOverride` writes to PlanStore overrides and dismisses without feedback toast — user gets no confirmation the day changed (UX). Otherwise solid.

### PostWorkoutFeedbackSheet.swift / SorenessCheckInSheet.swift
Correctness **4** · UX **4** · Consistency **5** · A11y **4**

- Near-identical chip primitives (duplicated in both files + CompleteScreen feel chips — 3 copies of the same chip). Consistent vocabulary (hurtAreas joints vs soreness muscle slugs) is intentional and documented.
- PostWorkoutFeedback hardcodes `ranLong: false` (L175) — the session knows elapsed vs planned duration and could auto-detect overrun; data-gap.
- SorenessCheckInSheet rehydrate/edit-in-place is correct (`existingEntryIndex`, L196-208).

### SubstituteExerciseSheet.swift
Correctness **4** · UX **3** · Consistency **2**

- **Likely dead code.** LogScreen build-99 comment (L77-83) says it *switched away* from this sheet to ExercisePickerSheet because the curated substitute table was too sparse. No call site found in the execution flow. If unreferenced it should be deleted per repo hygiene rules — verify with a project-wide grep.

### EditSessionSheet.swift
Correctness **4** · UX **3** · A11y **3**

- `ForEach(... id: \.offset)` for both exercises and sets (L35, L101) — same index-identity risk; less severe since past sessions aren't reordered.
- Reps field uses `.numbersAndPunctuation` keyboard (L154) while LogScreen uses `.decimalPad` for the same field — inconsistent. Identity fields correctly immutable.

### RestTimer.swift / ExerciseTile.swift / ExerciseActionSheet.swift / TodayRecoveryCard.swift
Correctness **4** · Consistency **4** · A11y **3**

- ExerciseTile: well-factored single primitive; `.flat` density has `minHeight 0` and no chrome — fine inside TileList. `_VariadicView` use is documented and iOS17-safe.
- ExerciseActionSheet: pulls double-duty as both the action menu and the affinity/dislike writer (good — single surface). `Color.red` for delete tint vs the app's `Color.danger` token used elsewhere (TodayRecoveryCard L37) — token inconsistency.
- RestTimer: presentation-only, correct. Pulse animation auto-starts on appear.
- TodayRecoveryCard: recomputes `MuscleFreshness.rows(from: store.savedSessions)` on every body eval (L15) — O(sessions) scan in a card that re-renders with the parent. Cache candidate.

---

### Cross-cutting issues in this part

1. **Index-based `ForEach` identity** in LogScreen (sets + grouped exercises), DayWorkoutPreviewSheet, EditSessionSheet. The data has stable ids/nums; using `\.offset` invites focus loss and wrong-row animation on insert/delete/reorder.
2. **`similarFiltersForExercise` triplicated** (TodayScreen, LogScreen, DayWorkoutPreviewSheet) — same coach.db muscle+pattern resolution copy-pasted 3×. Plus 2 `parseRestSeconds`/`parseRepsLeading` copies that disagree on `.` handling.
3. **Chip + FlowLayout duplication** — the JetBrainsMono chip primitive exists in CompleteScreen, PostWorkoutFeedbackSheet, SorenessCheckInSheet; flow layout in CompleteScreen (`FlowLayout`) + SubstituteExerciseSheet (`WrappingFlow`).
4. **Warmup-set inconsistency**: `stats.doneSets` (header/Complete SETS) counts warmups; PR/volume/1RM paths exclude them. A single "working set count" definition should drive both.
5. **Main-thread coach.db lookups in render** (TodayScreen tiles, LogScreen `thumbnailURL`, recovery scan) — cached in some paths (ExerciseLookupCache) but not all.
6. **Data-richness gap**: affinity, dislikes, per-muscle soreness, feedback history, PR trends, and planned-vs-actual duration all exist in the model but never surface in Today's hero/last-session card or auto-populate `ranLong`.

### Tiered backlog

**P0 — correctness / blocking**
- Re-sync `editableTemplate` when `template` changes (add `.onChange(of: template)` or `.id` the screen per plan/active). — S — TodayScreen.swift
- Fix CompleteScreen DURATION drift: snapshot elapsed at entry, don't recompute from `Date()`. — S — CompleteScreen.swift
- Post-swap "Last" column shows wrong history (prevSets positional after identity change). Clear/realign prevSets on swap. — M — LogScreen.swift
- Unify warmup handling: make `stats.doneSets` exclude warmups (or surface a separate working-set count). — S — SessionStore.swift / CompleteScreen.swift

**P1 — high-value UX or data-gap**
- Key `ForEach` on stable ids (`set.num`, `ex.id`, grouping element id) instead of `\.offset`. — M — LogScreen / DayWorkoutPreviewSheet / EditSessionSheet
- Allow half-step RPE (7.5/8.5) in the effort menu to match decimal display + EditSession capture. — S — LogScreen.swift
- Auto-detect `ranLong` from elapsed vs planned minutes instead of hardcoding false. — S — PostWorkoutFeedbackSheet.swift / CompleteScreen.swift
- Surface PR/trend (sparkline) and a coach-richer line in the LAST SESSION card. — M — TodayScreen.swift
- Confirmation feedback after `scheduleOverride` (toast/haptic). — S — OverrideTodaySheet.swift

**P2 — polish**
- Extract shared `similarFiltersForExercise`, `parseRest/Reps`, chip primitive, and one FlowLayout. — M — TodayScreen/LogScreen/DayWorkoutPreviewSheet + sheets
- Delete SubstituteExerciseSheet if grep confirms no call sites. — S — SubstituteExerciseSheet.swift
- Cache `previous` (TodayScreen) and `MuscleFreshness.rows` (TodayRecoveryCard) instead of recomputing per render. — S — TodayScreen.swift / TodayRecoveryCard.swift
- Replace fixed `listHeight = count*88+56+8` with a Dynamic-Type-safe sizing approach. — M — TodayScreen.swift
- Use `Color.danger` token for delete tint instead of raw `Color.red`. — S — ExerciseActionSheet.swift
- Add VoiceOver labels to numeric set cells + check-dot in LogScreen. — S — LogScreen.swift
