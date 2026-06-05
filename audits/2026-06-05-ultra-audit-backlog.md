# Ultra audit — tiered backlog (2026-06-05)

Source: part-by-part ultra audit (11 parts, 141 structured findings, absence- and
high-severity claims grep-verified). Flat findings are tiered here for an
overnight loop. **Read top-down. Tier 0 first. Tier 2 items begin with a verify
step. Do not start Tier 3 without the test gate (§9).**

Two findings are already fixed on branch `fix/checkin-readiness-context-and-event-kind`
(see Tier 1). One high-severity finding was a **false positive** — see §8.

---

## Tier 0 — Ship blockers / correctness blast radius

- [ ] **Paywall gates not wired.** `SubscriptionStore` product IDs are placeholders and `isPro` is checked in `PaywallView` but NOT at the Coach entitlement gates — Coach is effectively free. Decide: ship Coach free, or wire the gate before charging. `PhaseTraining/Data/SubscriptionStore.swift:17,25`, `PhaseTraining/Coach/CoachSettingsRow.swift:20`
- [ ] **Exercise match-by-name can mutate the wrong row.** `SessionStore.applyWorkoutDiffToActiveSession()` rebuilds exercises by case-insensitive name match; a coach-proposed exercise differing only in case updates an existing one instead of adding. No dedup by ID post-apply. `PhaseTraining/Data/SessionStore.swift:172,184`
- [ ] **Possible PlanStore→SessionStore retain cycle.** The memory-subscription sink captures `sessionStore` (not weak); `weak self` guards the PlanStore→MemoryStore edge but not PlanStore→SessionStore. Confirm with a leak instrument. `PhaseTraining/Data/PlanStore.swift:390`
- [ ] **LLM strategy overrides lack semantic validation.** `targetWeightOverrides/rpeOverrides/tempoOverrides` are type-checked (weight 0–1000) but not plausibility-checked — "RPE 15" / "tempo 99-99-99-99" pass through. `PhaseTraining/Data/WorkoutGenerator.swift:1636`
- [ ] **Backup restore is non-atomic.** `BackupManager.restore()` clears then repopulates in two steps; an error mid-populate leaves the DB partially cleared. `PhaseTraining/Data/BackupManager.swift:126`

---

## Tier 1 — User-facing bugs (one-screen fixes)

- [x] **Event kind hardcoded to `.race`.** `EventEditorSheet.save()` forced every event to `.race`, mislabeling sport sessions and travel. Fixed: added a TYPE picker (`WeekEventKind`); reused by `CheckInEventsScreen` so the check-in surface is fixed too. `PhaseTraining/Screens/WeekDayEditSheet.swift:708`
- [x] **Check-in regen ran with neutral readiness.** `WeeklyCheckInFlow.regenerateAndAdvance()` called `Planner.generate` without a `GeneratorContext`, silently skipping the Phase-2 readiness lift-day floor. Fixed: added `PlanStore.makeGeneratorContext` seam and threaded it. `PhaseTraining/Screens/WeeklyCheckIn/WeeklyCheckInFlow.swift:156`
- [ ] **Body-weight delete has no confirmation.** Swipe-delete wipes a tracking entry immediately. Add a confirm or undo. `PhaseTraining/Screens/BodyWeightLogSheet.swift:222`
- [ ] **Body-composition delete has no confirmation.** Same pattern. `PhaseTraining/Screens/BodyCompositionLogSheet.swift:280`
- [ ] **Coach chat drops one conversation turn.** `wireHistory()` drops the just-appended user message, then `history.dropLast()` drops another — one too many turns leave the LLM context. `PhaseTraining/Coach/CoachDrawer.swift:353`
- [ ] **Body-composition fields don't reset after logging.** Only `noteText` is cleared; `bfText/leanText/methodText` persist into the next entry. `PhaseTraining/Screens/BodyCompositionLogSheet.swift:349`
- [ ] **Weight propagation fires per-keystroke.** `LogScreen` `onChange` runs `propagateWeight` on every character, filling downstream sets with partial values. Debounce / fire on commit. `PhaseTraining/Screens/LogScreen.swift:790`
- [ ] **`editableTemplate` can silently discard edits.** If `onChange(of: template)` fires after the user starts editing, prior-version edits are dropped. `PhaseTraining/Screens/TodayScreen.swift:390`

---

## Tier 2 — Half-finished / dead scaffolding (VERIFY, then act)

Each item: re-grep first. Absence claims were grep-verified once in the audit but
verify again at action time — the codebase moves.

- [ ] **Verify** `TabPlaceholder` has zero call sites (`grep -rn "TabPlaceholder(" PhaseTraining`), **then** delete or wire it. `PhaseTraining/Components/TabPlaceholder.swift:3`
- [ ] **Verify** `CoachWorkoutProposal.sourceConversationId` has no reader (`grep -rn "sourceConversationId"`), **then** implement "review in coach" or remove the field. `PhaseTraining/Coach/MiniWorkoutDiffCard.swift`
- [ ] **Verify** `GeneratorStrategy.emphasizePatterns` is still inert (audit N9, 2026-06-04 — recipes are single-alternative so reordering is a no-op), **then** remove it from the LLM tool surface so the model stops emitting a dead field. `PhaseTraining/Data/GeneratorStrategy.swift:37`
- [ ] **Verify** `SorenessCheckInSheet` still hardcodes `timeBudget=nil`/`equipmentChanged=false` with no UI, **then** add inputs or drop the fields from `SorenessEntry`. `PhaseTraining/Screens/SorenessCheckInSheet.swift:170`
- [ ] **Verify** `buildWorkout` tool callers all handle it despite exclusion from `CoachTools.chat`, **then** document or pass it explicitly. `PhaseTraining/Coach/CoachTools.swift:204`
- [ ] **Verify** `SettingsRow` callers want a disabled state (docstring claims one, initializer omits it), **then** add the param or fix the docstring. `PhaseTraining/Components/SettingsRow.swift:18`
- [ ] **Verify** the high-minute accessory layer only adds one accessory (the `break` at `:322`) despite "T1.4 two tiers", **then** implement tier-2 or fix the label. `PhaseTraining/Data/WorkoutGenerator.swift:306`
- [ ] **Verify** `OnboardingFlow` reaches `planPreview` without a `draft.sports` guard, **then** add the gate (Sports is a required step). `PhaseTraining/Screens/Onboarding/OnboardingFlow.swift:56`

---

## Tier 3 — Architecture debt (GATED on §9 tests — one PR per file)

**God-object splits** (sizes verified):
- [ ] `WorkoutGenerator.swift` (1679) — extract accessory layer + prescription/RPE math into focused files. `PhaseTraining/Data/WorkoutGenerator.swift:1`
- [ ] `LogScreen.swift` (1438) — 15 `@State` fields; collapse the 6 rest-timer fields into one struct, extract row/edit subviews. `PhaseTraining/Screens/LogScreen.swift:25,35`
- [ ] `PlanStore.swift` (1211) — separate generation / history / overrides / missed-workout autopilot / LLM refinement. `PhaseTraining/Data/PlanStore.swift:19`
- [ ] `TodayScreen.swift` (1177) — 18 `@State` fields; extract template editor + sheet coordination. `PhaseTraining/Screens/TodayScreen.swift:23`
- [ ] `ProgressScreen.swift` (1177) — 12+ card impls; split into card components. `PhaseTraining/Screens/ProgressScreen.swift:1`
- [ ] `CoachContext.swift` (971) — 30+ section/format helpers → extensions/files. `PhaseTraining/Coach/CoachContext.swift:1`
- [ ] `WeekDayEditSheet.swift` (875) — extract the inline sub-sheets (SportPicker/EventEditor/IntensityEditor). `PhaseTraining/Screens/WeekDayEditSheet.swift:24`
- [ ] `ProfileScreen.swift` (795) — 27 `@State` presentation flags; extract editor-sheet coordination. `PhaseTraining/Screens/ProfileScreen.swift:20`

**Duplication** (extract shared helpers):
- [ ] `metaLine` formatting duplicated across ExerciseTile / LibraryScreen / LibraryMuscleScreen / ExercisePickerSheet → `Exercise.metaLabel`. `PhaseTraining/Screens/LibraryScreen.swift:382`
- [ ] Three identical `Binding` wrappers (swapping/editing/actionSheet) across TodayScreen / DayWorkoutPreviewSheet / LogScreen. `PhaseTraining/Screens/TodayScreen.swift:770`
- [ ] `similarFiltersForExercise` duplicated (DayWorkoutPreviewSheet vs TodayScreen). `PhaseTraining/Screens/DayWorkoutPreviewSheet.swift:439`
- [ ] `sessionRow` date/duration formatting duplicated (HistoryScreen vs ProgressScreen). `PhaseTraining/Screens/ProgressScreen.swift:781`
- [ ] Per-call `DateFormatter` allocations (ProfileScreen `:738`, CoachSettingsRow `:124`) → cached statics.

**Hot-path queries:**
- [ ] `LibraryScreen.libraryEyebrowTrailing` runs the full 551-row query every render — cache it like `stockRoutines`. `PhaseTraining/Screens/LibraryScreen.swift:96`
- [ ] `WorkoutGenerator.pickForSlot` makes up to 9 uncached `CoachDatabase.shared` queries per slot. `PhaseTraining/Data/WorkoutGenerator.swift:596`

**Shared-mutable-state:**
- [ ] `PatternSlot` is a `final class` with mutable `satisfiedBy` shared across workouts via `WorkoutFocus.slots` → cross-workout drift. Make value-type or copy-on-pick. `PhaseTraining/Data/WorkoutGenerator.swift:1600`

---

## Tier 4 — UX polish (separate sitting, batch together)

- [ ] Stale onboarding step comments ("step N of 8" → 12). `OnboardingFlow.swift:1`, `OnboardingWelcomeScreen.swift:1`, `OnboardingSportsScreen.swift:1`
- [ ] Self-drop on Week returns false silently — add a disabled drop-zone cue. `PhaseTraining/Screens/WeekScreen.swift:284`
- [ ] "Add sport session"/"Add event" silently clobber an existing event — surface the one-per-day rule. `PhaseTraining/Screens/WeekDayEditSheet.swift:314`
- [ ] Warmup rows at 0.6 opacity are hard to read mid-workout. `PhaseTraining/Screens/LogScreen.swift:737`
- [ ] Plate-calculator custom bar weight not persisted across opens. `PhaseTraining/Screens/PlateCalculatorSheet.swift:62`
- [ ] Duration buttons clamp 5–600 silently with no custom entry. `PhaseTraining/Screens/SportLogSheet.swift:100`
- [ ] Profile numeric fields clamp on commit with no live feedback (type 999 → 120). `PhaseTraining/Screens/ProfileScreen.swift:289`
- [ ] Consolidation modal closes whether or not it did anything. `PhaseTraining/Data/PlanStore.swift:1049`

---

## Cross-cutting

- [ ] **Typography system bypassed.** `styled()` uppercase branch is dead (`base : base`) so `.micro` never uppercases via the system; callers hand-`.uppercased()` or hardcode `Font.custom`. Fix `styled()` to apply `.textCase(.uppercase)`, then drop the workarounds. `PhaseTraining/Theme/Typography.swift:89,86`; `TabPlaceholder.swift:14`; `SeasonPhaseBadge.swift:85`
- [ ] **No localization** — `PlanEdit.label`, event/intensity labels are hardcoded English enums. `PhaseTraining/Data/PlanEdit.swift:31`
- [ ] **DST off-by-one** in `daysSinceLastWorkout` (uses raw `startTime` deltas). `PhaseTraining/Screens/ProgressRecoverySection.swift:202`
- [ ] **InsightGenerator** has no debounce on foreground — rapid fg/bg cycles can race the `hasInsightForToday` guard. `PhaseTraining/Coach/InsightGenerator.swift:24`

---

## What NOT to touch (load-bearing — do not "simplify")

- **`PhaseTraining/Generated/CoachSecrets.swift`** — GENERATED by the build-script phase "Generate CoachSecrets.swift" and gitignored (`.gitignore:23`). It is **not** a committed secret (audit's HIGH "committed API key" was a false positive — `git ls-files` finds it untracked, absent from history). Do not delete, commit, or "remediate."
- **`RootTabView.task` → `planStore.objectWillChange.send()`** — load-bearing nudge that makes the cold-launch missed-workout banner appear; injected stores aren't `@Published`. `RootTabView.swift:90`
- **Memory-driven auto-regen subscription** (`resubscribeToMemory`, `planInputsHash`, `migrateIfStale`) — drives silent week rebuild on profile drift. Don't decouple. `PlanStore.swift:390`
- **`PlanStore.apply` persist-before-set ordering** — deliberate watchdog-timeout defense. Don't reorder. `PlanStore.swift:804`
- **The "PURE" check-in regen** (no mutation until `accept()`) — don't add side effects to `regenerateAndAdvance`. `WeeklyCheckInFlow.swift:146`
- **`readinessScore` clamp / "cap is a safety floor, not coercion"** — intentional; don't turn clamps into rejections. `WorkoutGenerator.swift:1617`

---

## Test coverage gate (must be green before ANY Tier 3 refactor)

- `GeneratorInvariantTest` + `WorkoutGeneratorTests` — guard WorkoutGenerator/accessory splits.
- `PlannerTests` + `ReadinessGeneratorShipGateTests` + `ReadinessSignalTests` — guard Planner/readiness (also covers the Tier-1 check-in fix).
- `PlanStoreRegenTests` + `PlanStoreValidationOverrideTests` — guard PlanStore splits.
- `SessionStoreActiveSessionApplyTests` — guard the apply/dedup path (Tier-0 name-match bug).
- `WeekConsolidatorTests` — guard consolidation.

---

## Notes for the runner

- One PR per checkbox. Don't bundle across tiers.
- Tier 0 / Tier 1 can target `main`. Tier 3 wants one PR per file, gated on §9.
- Tier 2: the **verify** step is the work — if the consumer exists, close the item as a false positive, don't force a change.
- Tier 4 is UX-mode; batch in one sitting separate from code-mode tiers.
- Before deleting anything in §8, stop and re-read the file — those are load-bearing.
