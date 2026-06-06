# Ultra audit — tiered backlog (2026-06-05)

Source: part-by-part ultra audit (11 parts, 141 structured findings, absence- and
high-severity claims grep-verified). Flat findings are tiered here for an
overnight loop. **Read top-down. Tier 0 first. Tier 2 items begin with a verify
step. Do not start Tier 3 without the test gate (§9).**

**Reconciled 2026-06-05 PM** after two implementation waves (verify-first →
implement → adversarial review per file-disjoint group). Wave 1: 12 fixed, 5
closed as false-positive/already-fixed. Wave 2: 9 fixed (incl. paywall decision +
gate), 2 more false positives (PatternSlot, the editableTemplate class). Plus the
morning loop's 12. **Everything is closed except the Tier 3 god-object splits and
localization.** One stale test fixed in passing (`aa6f67a`).

---

## Tier 0 — Ship blockers / correctness blast radius

- [x] **Paywall gates not wired.** Resolved `c50a528`: `CoachEntitlement` wired at every coach surface (bubble, insights, LLM refinement, build-request, consent toggle → paywall). **Product decision 2026-06-05: coach SHIPS FREE** — `proRequired = false` holds the gate open, locked by `test_shippedState_isFree`. To charge: flip the flag + create ASC products.
- [x] **Exercise match-by-name can mutate the wrong row.** Fixed `298284a`: diff exercises match by id so swaps keep logged sets.
- [x] ~~Possible PlanStore→SessionStore retain cycle.~~ **False positive.** The sink captures `[weak self]` only and reaches sessionStore via `self.sessionStore?.active`; `memorySubscription` is the file's sole stored closure. No strong cross-store edge exists (verified via git log -L: shipped with `[weak self]` in 49dc999).
- [x] **LLM strategy overrides lack semantic validation.** Fixed `22a7591`: RPE caps at 10 via shared `capRPE`, tempo components cap at 10 s; unparseable strings pass through (clamp, don't reject).
- [x] **Backup restore is non-atomic.** Fixed `f6e0326`: capture prior rows → repopulate → verify counts → rollback + `restoreIncomplete` on shortfall, all before any UserDefaults write. Known limit (documented in-code): rollback shares the populate's write path, so a genuinely failing disk can defeat it.

---

## Tier 1 — User-facing bugs (one-screen fixes)

- [x] **Event kind hardcoded to `.race`.** Fixed `b6b3d6c` (TYPE picker, reused by CheckInEventsScreen).
- [x] **Check-in regen ran with neutral readiness.** Fixed `29b430c` (`PlanStore.makeGeneratorContext` seam).
- [x] **Body-weight delete has no confirmation.** Fixed `b05782b`.
- [x] **Body-composition delete has no confirmation.** Fixed `98802ec`.
- [x] **Coach chat drops one conversation turn.** Fixed `3d50437`.
- [x] **Body-composition fields don't reset after logging.** Fixed `d2bd3ff`.
- [x] **Weight propagation fires per-keystroke.** Fixed `594cb6b` (debounced).
- [x] ~~`editableTemplate` can silently discard edits.~~ **False positive.** The handler has carried `if !didModify { editableTemplate = newTemplate }` since it was introduced (17f5955, "Keeps user edits."); every edit path sets `didModify`. Matches the `phase-training-llm-refinement-clobbers-edits` skill's "NOT a trap — don't fix it" note.

---

## Tier 2 — Half-finished / dead scaffolding (VERIFY, then act)

- [x] **TabPlaceholder** deleted `7277b1d`.
- [x] **`CoachWorkoutProposal.sourceConversationId`** removed `01ce1b5`.
- [x] ~~`GeneratorStrategy.emphasizePatterns` is inert~~ **False positive — it is NOT inert.** fullBodyA (loaded-carry/single-leg-squat) and fullBodyB (calf-raise/single-leg-squat) are two-alternative slots where the emphasize reorder flips the pick. The sweep-test "byte-identical" proof used patterns that only occur in single-alternative slots. Stale INERT note corrected `f892a80`; field stays on the tool surface.
- [x] **SorenessCheckInSheet timeBudget/equipmentChanged** wired `d67fe28`.
- [x] **`buildWorkout` exclusion from `CoachTools.chat`** — already fixed `17f5955`: 8-line doc comment explains it (chat drawer can't render a built workout); CoachRequestScreen + LLMRefinement pass it explicitly.
- [x] **SettingsRow stale docstring** fixed `6ae180a`.
- [x] **High-minute accessory layer "two tiers"** — already fixed `5080094`: tier 1 (≥90 min) adds ONE accessory by design; tier 2 (≥120 min) is the +1-set compound bump. Covered by `test_highMinuteBudget_addsVolumeOver60min`.
- [x] ~~`OnboardingFlow` reaches `planPreview` without a sports guard~~ **False positive.** `step` only moves ±1, so every path passes `.sports`, whose Continue is disabled while `draft.sports.isEmpty`; no mid-flow jump exists. The sports-empty branch in OnboardingSportSeasonsScreen is defensive UI for sports added later via Profile.

---

## Tier 3 — Architecture debt (GATED on §9 tests — one PR per file)

**God-object splits** (sizes verified):
- [ ] `WorkoutGenerator.swift` (1679) — extract accessory layer + prescription/RPE math into focused files. `PhaseTraining/Data/WorkoutGenerator.swift:1`
- [ ] `LogScreen.swift` (1438) — 15 `@State` fields; collapse the 6 rest-timer fields into one struct, extract row/edit subviews. `PhaseTraining/Screens/LogScreen.swift:25,35`
- [ ] `PlanStore.swift` (1211) — separate generation / history / overrides / missed-workout autopilot / LLM refinement. `PhaseTraining/Data/PlanStore.swift:19`
- [ ] `TodayScreen.swift` (1177) — 18 `@State` fields; extract template editor + sheet coordination. `PhaseTraining/Screens/TodayScreen.swift:23`
- [ ] `ProgressScreen.swift` (1177) — 12+ card impls; split into card components. `PhaseTraining/Screens/ProgressScreen.swift:1`
- [x] `CoachContext.swift` (971→474) — section builders split into `CoachContext+{ProfileBlocks,InjuryBlocks,MovementBlocks,LoadBlocks}.swift`. `snapshot` + shared helpers (`sanitizeFreeText`, `averageRecentDurationMinutes`, date helpers) stay in main. Only access change: `weekday`/`short` relaxed `private`→internal (called cross-file by LoadBlocks); `longDate` stays private (snapshot-only); per-group private helpers stay with their sole caller. No behavior change.
- [ ] `WeekDayEditSheet.swift` (875) — extract the inline sub-sheets (SportPicker/EventEditor/IntensityEditor). `PhaseTraining/Screens/WeekDayEditSheet.swift:24`
- [ ] `ProfileScreen.swift` (795) — 27 `@State` presentation flags; extract editor-sheet coordination. `PhaseTraining/Screens/ProfileScreen.swift:20`

**Duplication** (extract shared helpers):
- [x] `metaLine` formatting dedup → `Exercise.metaLabel(includeCompound:)` `7400290`. Audit was partially off: ExerciseTile takes pre-formatted meta, LibraryScreen's copy was dead (deleted). Follow-up candidates outside the run's scope: SubstituteExerciseSheet + ExerciseDetailSheet carry the same pattern.
- [x] Binding wrappers dedup → `Components/ExerciseSheetCoordination` `a256935` (was actually 9 wrappers + 4 duplicate Identifiable structs, not 3). Follow-up candidates: CoachRequestScreen + CustomRoutineEditSheet repeat the pattern.
- [x] `similarFiltersForExercise` dedup → `ExerciseFilters.similar(toExerciseNamed:)` `a256935`, also adopted by LogScreen's name-based variant.
- [x] `sessionRow` date/duration formatting dedup → `Components/SessionRowMeta` `8909b1d` (compact/spelled knob keeps each screen's exact output).
- [x] Per-call `DateFormatter` → cached statics: ProfileScreen `1527f33`; WeekScreen (5 sites), MissedWorkoutBanner (4 sites), BodyWeightLogSheet `41e6ab0`. ~~CoachSettingsRow `:124`~~ **false positive** — that file has never contained a DateFormatter.

**Hot-path queries:**
- [x] `LibraryScreen.libraryEyebrowTrailing` full-catalog query per render → cached like `stockRoutines` `7400290`.
- [x] `WorkoutGenerator.pickForSlot` uncached queries → per-generation `ExerciseQueryCache` `fb417d4`, byte-identical output.

**Shared-mutable-state:**
- [x] ~~`PatternSlot` shared across workouts via `WorkoutFocus.slots`~~ **False positive.** `WorkoutFocus.slots` is a COMPUTED property — fresh instances on every access; `generate()` reads it once per call and `PatternSlot` never escapes the file. Locked in by the new `test_generationIsOrderIndependent` (`fb417d4`).

---

## Tier 4 — UX polish (separate sitting, batch together)

- [x] Stale onboarding step comments → un-hardcoded `75b4e85` (count had drifted twice; actual: 12 cases, 11 user-visible).
- [x] Self-drop on Week silent no-op → disabled drop-zone cue `95027c4`.
- [x] "Add sport session"/"Add event" silent clobber → Replace/Keep alert naming the incumbent `5124380`.
- [x] Warmup rows 0.6 opacity → 0.85, W pill stays primary cue `2bcea8b`.
- [x] Plate-calculator custom bar weight persisted via `@AppStorage` `a7c3ad9`.
- [x] Sport-log duration: tappable value opens numberPad alert stating the 5–600 range `a7794ce`.
- [x] Profile numeric clamp now surfaces the valid range inline `1527f33`.
- [x] Consolidation no-op now surfaced `447b283` (the PlanStore half already existed since `c000f3c` — `consolidateWeek` returned `Bool`; TodayScreen's banner glue discarded it).

---

## Cross-cutting

- [x] **Typography `styled()` dead uppercase branch** resolved `b6998b9` — option B: branch removed, caller-owned casing documented. Rationale: `styled()` returns `Text`, `textCase` is View-only (system uppercasing would force `some View` across 300+ sites), and ~15 deliberately mixed-case `.micro` labels (Apply/Reject/Regenerate/…) plus coach-generated text depend on no-uppercasing. Idiom-unification follow-ups listed in the run output (CompleteScreen:429, LogScreen:647, ExerciseTile:346, RestTimer:63, et al.).
- [ ] **No localization** — `PlanEdit.label`, event/intensity labels are hardcoded English enums. `PhaseTraining/Data/PlanEdit.swift:31`
- [x] **DST off-by-one** in `daysSinceLastWorkout` → Calendar day-boundary diff `6896717`.
- [x] **InsightGenerator foreground race** → in-flight flag `89714a9`.

---

## What NOT to touch (load-bearing — do not "simplify")

- **`PhaseTraining/Generated/CoachSecrets.swift`** — GENERATED by the build-script phase "Generate CoachSecrets.swift" and gitignored (`.gitignore:23`). It is **not** a committed secret (audit's HIGH "committed API key" was a false positive — `git ls-files` finds it untracked, absent from history). Do not delete, commit, or "remediate."
- **`RootTabView.task` → `planStore.objectWillChange.send()`** — load-bearing nudge that makes the cold-launch missed-workout banner appear; injected stores aren't `@Published`. `RootTabView.swift:90`
- **Memory-driven auto-regen subscription** (`resubscribeToMemory`, `planInputsHash`, `migrateIfStale`) — drives silent week rebuild on profile drift. Don't decouple. `PlanStore.swift:390`
- **`PlanStore.apply` persist-before-set ordering** — deliberate watchdog-timeout defense. Don't reorder. `PlanStore.swift:804`
- **The "PURE" check-in regen** (no mutation until `accept()`) — don't add side effects to `regenerateAndAdvance`. `WeeklyCheckInFlow.swift:146`
- **`readinessScore` clamp / "cap is a safety floor, not coercion"** — intentional; don't turn clamps into rejections. `WorkoutGenerator.swift:1617`
- **TodayScreen `didModify` guard** on `onChange(of: template)` — this IS the edit-protection; don't "simplify" it away. `TodayScreen.swift:390`

---

## Test coverage gate (must be green before ANY Tier 3 refactor)

- `GeneratorInvariantTest` + `WorkoutGeneratorTests` — guard WorkoutGenerator/accessory splits.
- `PlannerTests` + `ReadinessGeneratorShipGateTests` + `ReadinessSignalTests` — guard Planner/readiness (also covers the Tier-1 check-in fix).
- `PlanStoreRegenTests` + `PlanStoreValidationOverrideTests` — guard PlanStore splits.
- `SessionStoreActiveSessionApplyTests` — guard the apply/dedup path (Tier-0 name-match bug).
- `WeekConsolidatorTests` — guard consolidation.

Gate status 2026-06-05 PM: full unit suite green (647 passed; 8 CoachDatabase
0-results flakes pass on serial rerun per `ios-coachdb-mass-fail-rerun-first`;
1 stale test fixed in `aa6f67a`).

---

## Notes for the runner

- One PR per checkbox. Don't bundle across tiers.
- Tier 0 / Tier 1 can target `main`. Tier 3 wants one PR per file, gated on §9.
- Tier 2: the **verify** step is the work — if the consumer exists, close the item as a false positive, don't force a change.
- Tier 4 is UX-mode; batch in one sitting separate from code-mode tiers.
- Before deleting anything in §8, stop and re-read the file — those are load-bearing.
