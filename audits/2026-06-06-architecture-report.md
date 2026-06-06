# Tier 3 architecture report — 2026-06-06

Report-only deliverable for the Tier 3 items in `audits/2026-06-06-backlog.md`.
No code changes in this cycle. Sections are ordered **safest-first** — execute
top to bottom. Every item is gated on the §9 test suite (backlog "Test coverage
gate"); per-item test requirements below name the load-bearing subset plus
supplemental suites that exist beyond the gate.

---

## 0. Prior art — reconcile before doing anything

### 0.1 `origin/claude/split-planstore` — ALREADY LANDED, branch is stale

Commits `3fdcd5f` + `4b85cb7` were squash-merged to main as **PR #51
(`21a8955`)**. Main today has the split: `PlanStore+Generation.swift` (211),
`PlanStore+History.swift` (84), `PlanStore+MissedWorkoutAutopilot.swift` (132),
`PlanStore+Validation.swift` (66), plus the pre-existing
`PlanStore+LLMRefinement.swift` (282). `PlanStore.swift` is down to **745
lines**. The backlog's "4 extensions exist" undercounts — it's 5.
**Verdict: do not touch the branch; safe to delete. Remaining work is §7
below (finish + document seams), not a re-split.**

### 0.2 `origin/claude/split-coachcontext` — READY, salvage as-is

Commit `788d420` executes the CoachContext split: 4 new extension files
(`CoachContext+ProfileBlocks/+InjuryBlocks/+MovementBlocks/+LoadBlocks.swift`),
main file 971 → 474, pure move. Merge-base is `21a8955`; main is only 2
commits ahead (`4f4629e`, `fa1797e`) and **neither touches any
CoachContext*.swift** (only CoachClient/CoachConfig/MiniMemoryDiffCard changed
in `Coach/` since the base). `git merge-tree` against current main shows a
clean merge — only "added in remote" entries, zero conflicts.

Two deviations from the tier3-execution-plan doc, both fine:
- `weekday`/`short` date helpers relaxed `private`→internal (LoadBlocks calls
  them cross-file); the plan predicted "zero relaxations".
- No separate `+TextUtils.swift`; `sanitizeFreeText` stays in the main file
  with `snapshot()` — arguably better (keeps the injection-hardening surface
  next to its orchestrator).

**Verdict: salvage. This is item #1 below — open the PR / merge after the §9
gate runs. Do not redo.**

### 0.3 `origin/claude/tier3-execution-plan` — salvage the method, redo the status

Single commit `8e3352c` adds `PLAN-tier3-execution.md` (268 lines), based on
`a2ccbf6` — **before** #47 (WorkoutGenerator split), #48 (coach.db CI guard
fix), and #51 (PlanStore split) merged. Stale parts: its §0 status table
(lists #47/#48 as open blockers — both landed), its sequencing table (steps
1–3 are done), its line counts, and its "no local Swift toolchain, CI is the
only gate" execution model (this environment has xcodebuild/XcodeBuildMCP —
local gate runs are possible). **Still valid and worth lifting wholesale:**
the per-file split maps for WeekDayEditSheet/ProgressScreen/ProfileScreen/
TodayScreen/LogScreen (§3.4–3.8), the file-scoped-`private` hazard analysis,
the SwiftUI binding-threading hazards, the pre-push static checklist, and the
localization phasing (§5). **Verdict: do not merge the branch; this report
supersedes the doc. Cite its split maps per item (done below). Delete or
leave the branch — it's documentation-only either way.**

### 0.4 Current-main facts that retire backlog text

- **WorkoutGenerator is already split** (PR #47, `8479fa4`):
  `WorkoutGenerator+Accessories.swift` + `WorkoutGenerator+Prescription.swift`
  exist; main file is 1,047 (backlog says 1679 — stale). No further
  WorkoutGenerator work in this report.
- Current line counts (working tree, 2026-06-06): LogScreen 1,428;
  TodayScreen 1,157; ProgressScreen 1,169; **WeekDayEditSheet 922** (grew from
  875 — the event-replace flow landed in `fa1797e`); ProfileScreen 812;
  CoachContext 971; PlanStore 745; UserDatabase 1,121; HealthImportsScreen 508.

### 0.5 Working-tree caution (sequencing constraint for everything)

The shared tree currently carries **uncommitted Tier 0–2 work**: ~28 modified
files including `UserDatabase.swift`, `BackupManager.swift`,
`TodayScreen.swift`, `MiniWorkoutDiffCard.swift`, `PlanStore+LLMRefinement.swift`,
plus new `TrainingConstraints.swift` and `CoachSurfaceGatingTests.swift`.
**No Tier 3 extraction may start until those commits land and the §9 gate is
green on the resulting main.** Items below that touch in-flight files are
flagged individually.

### 0.6 Project plumbing

phase-training2 is XcodeGen-managed (`Project.yml` globs `PhaseTraining/`;
pbxproj is gitignored). New `.swift` files are picked up automatically — no
manifest edits for any split. CI runs `xcodegen generate` first.

---

## 1. §9 test gate — status and mapping

All eleven gate suites exist in `PhaseTrainingTests/`:

| Gate cluster | Suites | Guards which Tier 3 items |
|---|---|---|
| Generator | `GeneratorInvariantTest`, `WorkoutGeneratorTests` | (done — #47) regression backstop for anything touching plan composition |
| Planner/readiness | `PlannerTests`, `ReadinessGeneratorShipGateTests`, `ReadinessSignalTests` | PlanStore finish, WeekDayEditSheet |
| PlanStore seams | `PlanStoreRegenTests`, `PlanStoreValidationOverrideTests` (+ supplemental `PlanStoreSeamsTests`, `PlanStoreMissedWorkoutTests`, `PlanStoreWorkoutDiffTests`) | PlanStore finish, Mini*DiffCard, TodayScreen |
| Session apply | `SessionStoreActiveSessionApplyTests` | Mini*DiffCard, LogScreen |
| Consolidation | `WeekConsolidatorTests` | PlanStore finish, WeekDayEditSheet |
| Restore/migrations | `BackupManagerTests`, `UserDatabaseMigrationTests` | UserDatabase split, ProfileScreen/BackupCoordinator |

Gate status at write time: **not yet run this cycle** (backlog: Phase 4 runs
it). Run it once after the Tier 0–2 commits land; that green run is the
baseline every split below diffs against. Supplemental (non-gate) suites named
per item are equally load-bearing for that item.

---

## 2. Sequencing overview (safest → riskiest)

| # | Item | Kind | Risk | Blocked by |
|---|------|------|------|-----------|
| 1 | CoachContext split (merge existing branch) | enum-statics move | minimal | §9 gate green |
| 2 | Typography lockstep | value-table refactor | minimal | nothing |
| 3 | ExerciseSheetCoordination adoption | mechanical dedup | low | nothing |
| 4 | Mini*DiffCard triplication | view dedup | low-med | Tier 2 DateFormatter batch commit |
| 5 | PlanStore: finish + document seams | extension move + docs | medium | gate green |
| 6 | UserDatabase scope split | extension move (locked DB) | medium | Tier 0/2 UserDatabase commits |
| 7 | HealthImportsScreen split | SwiftUI section split | medium | nothing |
| 8 | Progress hot-path memoization | perf/behavior change | medium | item 9 recommended first |
| 9 | ProgressScreen view split | SwiftUI pure move | medium-low | gate green |
| 10 | WeekDayEditSheet split + sheet-enum routing | SwiftUI, 2-stage | medium | Tier 1 replace-alert fix |
| 11 | ProfileScreen (BackupCoordinator first) | SwiftUI + state machine | med-high | Tier 2 BackupManager commits |
| 12 | TodayScreen split | SwiftUI, shared mutable state | high | Tier 1 TodayScreen fixes |
| 13 | LogScreen split | SwiftUI, timer + nested bindings | highest | everything above proven |

Rationale: 1–5 are extension-of-a-type or pure-value moves with compile-time
failure modes; 6 adds a locking discipline hazard; 7–9 are the easiest SwiftUI
moves; 10–13 escalate binding/threading risk, matching the execution-plan
doc's proven ordering (sheet → read-only screen → flag-heavy screen →
mutation-heavy screens).

---

## 3. Item 1 — CoachContext split (carried god-object; branch ready)

**(a) Suggested change.** Merge `origin/claude/split-coachcontext`
(`788d420`) as-is. It is the complete split: `snapshot()` orchestrator +
`sanitizeFreeText` + date helpers stay in `CoachContext.swift` (474 lines);
section builders move to four `extension CoachContext` files grouped by
concern (profile / injury / movement / load). Pure move, enum-namespace
statics, no behavior change.

**(b) Affected files.**
- `PhaseTraining/Coach/CoachContext.swift` (971 → 474)
- New: `CoachContext+ProfileBlocks.swift`, `CoachContext+InjuryBlocks.swift`,
  `CoachContext+MovementBlocks.swift`, `CoachContext+LoadBlocks.swift`
- `audits/2026-06-05-ultra-audit-backlog.md` (checkbox, included in commit)

**(c) Tests first.** §9 gate green as policy, plus the suites that actually
exercise this code: `CoachContextTests`, `CoachContextSnapshotDetailTests`,
`CoachPromptSanitizationTests` (all exist). These pin `snapshot()` output and
the free-text sanitization — the only behavior that could regress.

**(d) Sequencing + blast radius.** First Tier 3 action — it is review-and-merge,
not new work. Verified clean against current main via `git merge-tree` (no
conflicting paths; nothing on main has touched CoachContext since the
branch's base). Blast radius if done wrong: the coach's entire context feed
(every prompt the coach sees) — but failure modes are compile-time
(file-scoped `private` cross-references) or snapshot-text drift, which the
three suites above catch. The one semantic tripwire: `sanitizeFreeText` is
part of the prompt-injection hardening — it stays in the main file on this
branch, which is correct; don't relocate it in review.

---

## 4. Item 2 — Typography (size, tracking) lockstep

**(a) Suggested change.** `Typography.swift` defines each style's size twice:
once in the `Font` extension (`Font.custom(..., size: 34)`) and again inside
`TypeStyle.tracking` (`-0.03 * 34`). The em-ratio × size products are
hand-multiplied, so a size change silently leaves tracking computed against
the old size. Extract one per-style spec table — e.g.
`private struct TypeSpec { let fontName: String; let size: CGFloat; let trackingEm: CGFloat }`
with a single `static let specs: [TypeStyle: TypeSpec]` — and derive both
`font` (`Font.custom(spec.fontName, size: spec.size)`) and `tracking`
(`spec.trackingEm * spec.size`) from it. Keep the public `TypeStyle` API and
`styled(_:)` extensions byte-identical.

**(b) Affected files.** `PhaseTraining/Theme/Typography.swift` only (104
lines). The `Font.displayL`-style statics are referenced app-wide; keep them
as derived `static let`s so no call site changes.

**(c) Tests first.** No gate suite covers typography; §9 green is policy
only. Verification is arithmetic (the 5 non-zero tracking products must be
value-identical: −1.02, −0.78, −0.32, −0.44, +1.4) plus a manual
StyleGuidePreview pass in the sim.

**(d) Sequencing + blast radius.** Anytime; zero dependencies. Blast radius
if done wrong: app-wide visual drift (every Text uses these tokens) — but
mis-transcription is the only failure mode, and it's caught by comparing the
computed constants before/after. Lowest-stakes item in the report.

---

## 5. Item 3 — ExerciseSheetCoordination adoption follow-up (mechanical)

**(a) Suggested change.** `a256935` extracted
`Components/ExerciseSheetCoordination.swift` (`ExerciseSheetIndex`,
`ExerciseSheetName`, the `Binding<Int?>`/`Binding<String?>`
`.exerciseSheetItem` lifts, and the `ExerciseFilters.similar(toExerciseNamed:)`
pre-filter). TodayScreen, DayWorkoutPreviewSheet, and LogScreen adopted it.
Two screens still hand-roll the identical plumbing:

- `CoachRequestScreen.swift` — private `PreviewRowIndex` (:578) and
  `CoachReqNamedExercise` (:651) are byte-for-byte duplicates of
  `ExerciseSheetIndex`/`ExerciseSheetName` (same `id` semantics: index/name).
  Plus 3 hand-rolled `Binding(get:set:)` wrappers at :272, :280, :512.
  Replace structs with the shared types; replace the index/name bindings with
  `.exerciseSheetItem`.
- `CustomRoutineEditSheet.swift` — `swappingExerciseId: String?` (:25) with a
  hand-rolled `Binding` at :240. Note the wrapped value is an exercise **id**
  string, not a display name — `ExerciseSheetName` still works mechanically
  (Identifiable-String wrapper), but verify nothing reads `.name` as a display
  string before substituting; if it does, rename-or-keep rather than force-fit.

**(b) Affected files.** `PhaseTraining/Screens/CoachRequestScreen.swift`
(654), `PhaseTraining/Screens/CustomRoutineEditSheet.swift` (451). No change
to `ExerciseSheetCoordination.swift` itself (unless the id-vs-name review in
(a) argues for a third wrapper — keep that to a rename, not new machinery).

**(c) Tests first.** §9 gate green (policy). No unit suite renders these
sheets; the load-bearing check is behavioral identity of sheet
presentation/dismissal, which the wrapper-equivalence makes a compile-time
question. `CustomRoutineTemplateTests` exists for the underlying model if the
edit sheet's bindings are touched.

**(d) Sequencing + blast radius.** Anytime; neither file is in the dirty
tree. Blast radius if done wrong: sheet identity churn — `.sheet(item:)`
re-presents when `id` changes, so substituting a wrapper with different `id`
semantics would dismiss/re-present sheets mid-flow. Both substitutions here
are id-identical, so the risk is confined to the CustomRoutineEditSheet
id-vs-name nuance flagged above. One commit, mechanical.

---

## 6. Item 4 — Mini*DiffCard triplication

**(a) Suggested change.** `MiniPlanDiffCard` (216), `MiniWorkoutDiffCard`
(221), `MiniMemoryDiffCard` (183) share near-identical chrome: `header`,
`statusLabel`/`statusColor`, `actionBar` (Apply/Reject pair + isApplying/
resolution state), and the row-prefix coloring. Extract the shared chrome
into one generic container — e.g.
`MiniDiffCardChrome<Rows: View>(status:, title:, canApply:, onApply:, onReject:, rows:)`
in `PhaseTraining/Coach/` — and keep per-card *logic* (resolve/apply/reject
against PlanStore vs SessionStore vs MemoryStore, and the per-type row
renderers) in the three thin call sites. Do **not** unify the apply paths:
they intentionally hit different stores with different resolution semantics
(workout diffs apply by id, not name — see
`phase-training-coach-diff-apply-by-id-not-name`).

**(b) Affected files.**
- New: `PhaseTraining/Coach/MiniDiffCardChrome.swift` (or similar)
- `PhaseTraining/Coach/MiniPlanDiffCard.swift`, `MiniWorkoutDiffCard.swift`,
  `MiniMemoryDiffCard.swift` (each shrinks to status mapping + rows + apply
  logic)

**(c) Tests first.** §9 gate, specifically `PlanStoreWorkoutDiffTests`,
`SessionStoreActiveSessionApplyTests` (the apply seams behind the cards), and
`CoachConversationStoreTests` (resolution-note persistence). No suite renders
the cards; keep the refactor chrome-only so the tested seams are untouched.

**(d) Sequencing + blast radius.** **Wait for the Tier 2 DateFormatter batch
to commit** — `MiniWorkoutDiffCard.swift` is dirty in the tree right now
(MiniWorkoutDiffCard:171+186 is in that batch), and `MiniMemoryDiffCard` +
`CoachClient`/`CoachConfig` changed on main this week (`fa1797e`). Extracting
chrome while those edits are uncommitted guarantees conflicts. Blast radius
if done wrong: the coach's accept/reject surface for all three diff types —
a chrome bug (wrong `canApply` wiring) silently disables Apply across every
coach proposal. Keep the per-card `canApply` computations in the cards and
pass them in; don't centralize that logic.

---

## 7. Item 5 — PlanStore: finish the split + document seams (carried)

**(a) Suggested change.** The heavy lifting landed in #51 (see §0.1). What
"finish" means now, in value order:

1. **Document the seams** (the explicitly-open half of the backlog item): add
   a header comment in `PlanStore.swift` mapping the six files
   (core / Generation / History / Validation / MissedWorkoutAutopilot /
   LLMRefinement) and stating the load-bearing invariants in-place:
   `apply(_:)` persist-before-set ordering (watchdog defense),
   `resubscribeToMemory` + `planInputsHash` + `migrateIfStale` (memory-driven
   auto-regen), and the LLMRefinement custom-routine exclusion (anti-clobber
   guard). These are all in the backlog's What-NOT-to-touch list; the doc
   comment is what keeps the next split honest.
2. **Optional final extraction — `PlanStore+Persistence.swift`**: the `save*`
   family + `encoder()`/`decoder()` (PlanStore.swift:678-744, ~66 lines). The
   execution-plan doc listed this as optional; most `save*` members are
   already internal (cross-file callers exist), only `saveConsolidationCount`
   and the coder factories are still `private` — moving them together with
   their callers' file keeps relaxations at zero-to-two.
3. **Stop there.** What remains in the 745-line core — init/reload/
   resubscribe, the PlanEdit pipeline (`propose`/`apply`/`applyWorkoutDiff`,
   :308-467), drag-drop `swap`, drift detection, and targeted regeneration
   (`regenerateToday`/`regenerateWeek`/`consolidateWeek`/`migrateIfStale`,
   :507-676) — is the load-bearing center. A `+PlanEdit` or `+Regeneration`
   extraction is possible but every one of those methods is on the
   What-NOT-to-touch list or adjacent to it; the value curve has flattened.
   Recommend declaring the split done at 6 files + doc comment.

**(b) Affected files.** `PhaseTraining/Data/PlanStore.swift` (doc comment;
−66 lines if step 2 runs); new `PlanStore+Persistence.swift` (optional).

**(c) Tests first.** The PlanStore cluster of the §9 gate:
`PlanStoreRegenTests` + `PlanStoreValidationOverrideTests`, plus the
supplemental `PlanStoreSeamsTests` (added 06-05/06 — it characterizes
context/compose/rollover seams specifically so this split can be finished
safely), `PlanStoreMissedWorkoutTests`, `PlanStoreWorkoutDiffTests`.

**(d) Sequencing + blast radius.** After the gate baseline run;
`PlanStore+LLMRefinement.swift` is dirty in the tree (Tier 0 sportLogs
threading), so wait for that commit. Blast radius if done wrong: plan loss.
Specifically — reordering `apply(_:)`'s persist-before-set breaks the
watchdog defense (plan vanishes on a watchdog kill mid-apply); breaking
`resubscribeToMemory` or `migrateIfStale` either kills memory-driven regen or
causes regen loops; touching the LLMRefinement candidate exclusion
resurrects the override-clobber bug
(`phase-training-llm-refinement-clobbers-edits`). All of which is why step 1
(documentation) is the highest-value remaining move and step 3 is "stop".

---

## 8. Item 6 — UserDatabase scope split (new this cycle)

**(a) Suggested change.** `UserDatabase.swift` (1,121 lines) is one class
with four clean MARK-delimited scopes that already behave like modules:

- **Routines** — `listRoutines`/`routine(id:)`/`save`/`delete`/`clearAll` +
  `loadExercisesLocked(routineId:)` (:274-434)
- **Saved sessions + PR aggregation** — `listSavedSessions`,
  `previousSession`, `mostRecentExerciseByName`, `saveSession`,
  `deleteSession`, the `load*Locked` family, `qualifyingSetsForPRs`,
  `bestWeightsByExerciseAndReps` (:436-851)
- **Imports** — imported workouts + imported sets + summaries + `deleteImports`
  (:876-1121)
- **Core** — open/`withLock`, the versioned-migration runner (:62-272), and
  the shared helpers `countLocked`/`text`/`intOrNil` (:853-874)

Split as `extension UserDatabase` files mirroring those scopes
(`UserDatabase+Routines.swift`, `UserDatabase+Sessions.swift`,
`UserDatabase+Imports.swift`), keeping core + migrations + shared helpers in
the main file. Required access relaxations (file-scoped `private`):
`countLocked`, `text`, `intOrNil` go `private`→internal (called from all
three extensions); each scope's own `*Locked` loaders move with their sole
callers and stay `private`.

**(b) Affected files.** `PhaseTraining/Data/UserDatabase.swift` (→ ~350); new
`UserDatabase+Routines.swift` (~160), `UserDatabase+Sessions.swift` (~420),
`UserDatabase+Imports.swift` (~250).

**(c) Tests first.** §9 gate's `UserDatabaseMigrationTests` +
`BackupManagerTests` (restore drives every read/write path), plus
supplemental `DatabaseDerivedQueriesTests`, `ImportedWorkoutsDatabaseTests`,
`SessionStoreTests`/`SessionStorePRTests` (PR aggregation),
`CustomRoutineTemplateTests`, `WorkoutCSVImporterTests` (import scope, just
characterized in `a2ccbf6`). This item has the best characterization coverage
of any split in the report — that's recent deliberate prep; use it.

**(d) Sequencing + blast radius.** **Blocked until the Tier 0/2
UserDatabase + BackupManager commits land** — `UserDatabase.swift` is dirty
right now (saveSession orphan fix, COUNT(*) aggregates). Blast radius if done
wrong, two distinct failure modes: (1) the locking discipline — every public
method body runs inside `withLock`; the `*Locked` helpers assume the lock is
held. Moving a `*Locked` helper where an extension calls it outside `withLock`
is a data race the compiler will not catch. Audit rule for review: in the
extensions, `withLock` appears at every public entry point and `*Locked`
appears only inside them. (2) The migration runner is on the
What-NOT-to-touch list (just landed in `ff3f51e`): never edit/reorder past
migration entries, the 0→1 warmup shim is intentional, the per-connection
`PRAGMA foreign_keys` placement is correct — keep all of it in the main file
untouched.

---

## 9. Item 7 — HealthImportsScreen split (new this cycle)

**(a) Suggested change.** One 508-line view holds three features with
disjoint state: workout sync (`syncing`/`lastError`/`summary`/
`debugReadiness`), body-metrics sync (`bodyMetricsSyncing`/
`lastBodyMetricsSummary`/`bodyMetricsError`), CSV import
(`presentingCSVPicker`/`csvImporting`/`csvError`/`csvSummary`/`lastImport`).
The state groups never cross-reference. Extract three section views that each
**own** their state — `WorkoutSyncSection`, `BodyMetricsSyncSection`,
`CSVImportSection` — leaving HealthImportsScreen as a ~60-line shell
composing them. Because state moves *into* the extracted views (not threaded
down), this is structurally the easiest SwiftUI split in the report: no
bindings cross the new boundaries.

**(b) Affected files.** `PhaseTraining/Screens/HealthImportsScreen.swift`
(508 → shell); 3 new files (either in `Screens/` or a
`Screens/HealthImports/` group — XcodeGen picks up both).

**(c) Tests first.** §9 gate (policy). Logic under the screen is covered:
`HealthKitImporterTests`, `BodyMetricsMergerTests`, `WorkoutCSVImporterTests`
+ `ImportedWorkoutsDatabaseTests`. No view-level suite exists; the screen is
thin enough that sim smoke (sync once, import one CSV) is the verification.

**(d) Sequencing + blast radius.** Not blocked by dirty-tree files. Blast
radius if done wrong: an async task losing its `@State` anchor — each
section's in-flight `Task` must live in the same struct as the flags it sets,
or a sync that completes after extraction writes to a dead binding and the
spinner never clears. Moving state+task+actions as a unit (the whole point of
the split) avoids it. Failure is visible and recoverable (UI-only); no data
path changes.

---

## 10. Item 8 — Progress-tab hot paths (new) + Item 9 — ProgressScreen view split (carried)

These two interlock; do the **view split first** (pure move, lower risk),
then memoize — moving code after memoizing would churn the cache plumbing.

**(a) Suggested change.**
- *View split (carried god-object):* per the execution-plan doc §3.5 —
  ProgressScreen is read-only (3 `@State`, all sheet toggles), ~12 cards are
  computed-var renderers. Extract `ProgressCharts.swift` (LineSpark,
  BodyWeightSpark, ExerciseSparkline), `ProgressScreen+StatCards.swift`,
  `ProgressScreen+BodyCards.swift`, `ProgressScreen+ExerciseCards.swift`;
  keep `body`/`content`/`emptyState` + the generic `card()` wrapper in main.
  No parent-state threading.
- *Memoization (new):* `weeklyBuckets(value:)` (:820) re-walks
  `store.savedSessions` once per card (6+ calls per render: :148, :393, :405,
  plus the count/filter walks at :108, :741, :848, :860);
  `topExerciseSeries` (:905) sorts + double-iterates; `StrengthStandards.rows`
  (:192) is O(sessions×exercises×sets) per render (:429). Add **one**
  memoization layer keyed on the sessions array identity: a
  `ProgressAggregates` struct computed once per `savedSessions` change
  (e.g. `@State` + `.onChange(of: store.savedSessions)` / `onAppear`, or a
  small `@MainActor` cache object) exposing weekly buckets, per-exercise
  series, muscle-volume rows, and the strength-standards rows. Cards read the
  aggregate; no card walks `savedSessions` directly afterward.

**(b) Affected files.** `PhaseTraining/Screens/ProgressScreen.swift` (1,169 →
~300 core); 4 new view files; new `ProgressAggregates.swift` (Data or
Screens); `PhaseTraining/Data/StrengthStandards.swift` unchanged (its `rows`
stays pure — the *caching of its output* lives in the aggregates layer, not
in the standards code).

**(c) Tests first.** §9 gate (policy) plus the suites that pin the math the
memoization must not change: `StrengthStandardsTests`, `MuscleVolumeTests`,
`SessionStoreTests`/`SessionStorePRTests`. For the aggregates layer itself,
add a small characterization test (same sessions in → same buckets/series out
as the previous per-render computation) before switching the cards over.

**(d) Sequencing + blast radius.** View split: after gate baseline; pure
move; failure modes compile-time. Memoization: the classic failure is a
**stale cache** — finish a workout, Progress tab still shows yesterday's
numbers. The invalidation key must be the savedSessions content/identity, not
view lifecycle (`onAppear` alone misses saves that happen while the tab is
live). Second-order risk: `StrengthStandards.rows` also depends on
`bodyweightKg`/`gender` — those must be part of the cache key or excluded
from the cached layer. Keep `rows` pure and cache only at the screen; do not
push caching into Data/ types.

---

## 11. Item 10 — WeekDayEditSheet (carried; grew to 922)

**(a) Suggested change.** Two stages, separate commits:

1. *Pure file move* (execution-plan §3.4): the 7 sibling structs already
   in-file are the seams — move `SportPickerSheet`, `EventEditorSheet`,
   `MoveDayPickerSheet`, `IntensityEditorSheet` to `WeekDayEventSheets.swift`
   and `LiftFocusPickerSheet`, `FocusChip`, `ActionRow` to
   `WeekDayEditComponents.swift`. All are closure-driven and self-contained;
   no bindings into the parent. Keep `body`, `actionList`, all flags/alerts,
   and the mutation funcs (they all call `planStore.updateOverrides`) in main.
2. *Sheet-enum routing + currentEvent caching* (behavior-adjacent, do
   second): current main has **8 `.sheet` modifiers driven by 10 boolean
   flags plus `pendingEventReplace`** (the audit counted 9 — the
   event-replace flow added one since). Collapse to one
   `enum WeekDaySheet: Identifiable` + single `.sheet(item:)`. And
   `currentEvent` is a computed var re-evaluated 7× per body evaluation
   (:103, :140, :263, :273, :295, :331…) — hoist it once per `body` into a
   local `let`.

**(b) Affected files.** `PhaseTraining/Screens/WeekDayEditSheet.swift` (922 →
~430 after stage 1, smaller after 2); 2 new files.

**(c) Tests first.** §9 gate, specifically `WeekConsolidatorTests`,
`PlannerTests`, `WeekOverridesClearTests`, `PlanStoreValidationOverrideTests`
(the overrides paths every action here mutates). No view test; stage 2 needs
sim verification of each sheet flow plus the replace-event confirm path.

**(d) Sequencing + blast radius.** Stage 1 anytime after gate baseline; stage
2 **after the Tier 1 "replace-event alert stale incumbent" fix resolves** —
that fix and the enum routing both touch `pendingEventReplace`/
`confirmingEventReplace`, and the Tier 1 verify may snapshot the incumbent
title into `@State`; doing the enum collapse first would force the Tier 1 fix
to re-land. Blast radius if done wrong: stage 1 is compile-time-safe; stage 2
changes sheet identity — a wrong `Identifiable` id dismisses an open sheet
when state changes underneath (e.g. plan regen while the editor is up). Keep
the one-event-per-day gate (`requestAdd` coordination) in the parent.

---

## 12. Item 11 — ProfileScreen: extract BackupCoordinator first (carried)

**(a) Suggested change.** Backlog calls BackupCoordinator "the cleanest
seam" — extract it before any view-split of ProfileScreen. Pull the
backup/restore/erase state machine (the 7 backup/restore `@State`s +
`exportBackup`/`handleImport`/`performRestore`/`eraseAllData`) into an
`@MainActor final class BackupCoordinator: ObservableObject` (or
`@Observable`) owned by ProfileScreen via `@StateObject`. The view keeps only
`.sheet`/`.alert`/`.fileImporter` modifiers bound to coordinator-published
state. Then, as a follow-up commit, the execution-plan §3.6 pure extractions:
`ProfileScreen+RowSummaries.swift` (the 14 read-only summary props),
`ShareSheet.swift` lift-out. The 18-presentation-flag collapse into one
`enum EditorSheet: Identifiable` is a third, optional commit (same
sheet-identity caveats as item 10 stage 2).

**(b) Affected files.** `PhaseTraining/Screens/ProfileScreen.swift` (812 →
~450 after both commits); new `BackupCoordinator.swift` (Data or Screens),
`ProfileScreen+RowSummaries.swift`, `ShareSheet.swift`.

**(c) Tests first.** §9 gate, specifically `BackupManagerTests` (including
the new Tier 0 UserDefaults-atomicity coverage) and `EraseAllDataTests` —
both pin the flows the coordinator wraps. The coordinator itself becomes
unit-testable (that's half the point); add a test that restore-failure
surfaces `restoreIncomplete` state without partial UI flags stuck on.

**(d) Sequencing + blast radius.** **After the Tier 0 BackupManager
atomic-restore commit lands** (`BackupManager.swift` is dirty now). Blast
radius if done wrong: restore is a small state machine spanning file-import →
decode → restore → reload (`planStore`/`sessionStore`/`customStore` reloads
must still fire on success) — splitting its pieces across view and
coordinator can drop a reload and leave the app showing pre-restore state
until relaunch. Keep the entire sequence in the coordinator; the view only
presents. Erase-all spans UserDefaults + SQLite
(`phase-training-wipe-spans-userdefaults-and-sqlite`) — move it whole.

---

## 13. Item 12 — TodayScreen split (carried; high risk)

**(a) Suggested change.** Per execution-plan §3.7: extract
`TodayScreen+TemplateEditor.swift` (inline exercise cards + the immutable
`editableTemplate` rebuild mutations, threading
`editableTemplate`/`didModify`/`didSaveToLibrary` bindings),
`TodayScreen+Derived.swift` (read-only computed props + stateless helpers),
`CoachPolishedExplanationSheet.swift` (lift the nested struct), and
optionally a sheet-coordination collapse (the screen already uses
`.exerciseSheetItem` from item 3's shared plumbing — fewer raw flags than the
plan doc assumed).

**(b) Affected files.** `PhaseTraining/Screens/TodayScreen.swift` (1,157 →
~500); 3 new files.

**(c) Tests first.** Full §9 gate — TodayScreen sits on PlanStore +
SessionStore + the coach-badge entitlement seams, so `PlanStoreRegenTests`,
`PlanStoreWorkoutDiffTests`, `SessionStoreActiveSessionApplyTests`, plus the
new `CoachSurfaceGatingTests` (in flight) must be green first. The Tier 1
pill-state fix should also have landed with its behavior pinned.

**(d) Sequencing + blast radius.** **After the Tier 1 TodayScreen fixes
(coach-badge gating, pill reset) commit** — the file is dirty now. Blast
radius if done wrong: the `didModify` guard on `onChange(of: template)` IS
the edit protection (What-NOT-to-touch) — if the extraction reorders or
duplicates that onChange, user edits get silently clobbered by plan refreshes
(the exact bug class of
`phase-training-llm-refinement-clobbers-edits`). Thread the guard's state as
bindings; never re-derive it in the extracted editor. Mutations rebuild
`editableTemplate` immutably, which makes them safe to relocate — keep that
pattern.

---

## 14. Item 13 — LogScreen split (carried; highest risk, do LAST)

**(a) Suggested change.** Per execution-plan §3.8, in order: first commit
collapses the 6 rest-timer `@State` fields into one
`struct RestTimerState` (+ `clear()`/`remaining(at:)`) — the structural
change the backlog explicitly asks for — moving `activeRestCard`/
`maybeFireRestExpiry` with it (`TimelineView` must move with the state or
take `Binding<RestTimerState>`). Then `LogSetRow.swift` (set row + cells,
threading nested `Binding`s into `session.exercises[i].sets[j]`),
`LogExerciseBlock.swift`, and `LogScreenHelpers.swift` (pure logic) as
separate commits.

**(b) Affected files.** `PhaseTraining/Screens/LogScreen.swift` (1,428 →
~500); new `LogScreen+RestTimer.swift` (or `RestTimerState.swift`),
`LogSetRow.swift`, `LogExerciseBlock.swift`, `LogScreenHelpers.swift`.
`Components/RestTimer.swift` already exists — name the new state file to
avoid collision.

**(c) Tests first.** Full §9 gate + `SessionStoreActiveSessionApplyTests`,
`LoggedSetParsingTests`/`LoggedSetValueParsingTests`/`LoggedSetRIRTests`
(free-text set parsing the rows depend on, characterized in `21d535d`), and
the XCUITest path: the `phase-training-xcuitest-recipe` launch args
(`--seed-supersets-demo`, `--ui-test-rest-seconds=N`) exist precisely to
verify rest-timer expiry and in-workout flows after this split — run those
UI tests per commit here even though they're not in the §9 list.

**(d) Sequencing + blast radius.** Last, after the binding-threading
technique is proven on items 10–12. Blast radius if done wrong: the in-workout
surface — broken nested bindings silently stop persisting logged sets
(auto-save rides `onChange` of `session`), and a TimelineView separated from
its driving state stops ticking, so rest expiry never fires. Both failures
are quiet in unit tests; the seeded XCUITest run is the real gate. Also
respect the per-set TapBudget/auto-rest interaction just stabilized in
`072aae1` — don't reorder rest-fire side effects.

---

## 15. Out-of-scope notes

- **Localization** (cross-cutting in the backlog, not Tier 3): the
  execution-plan doc's §5 phasing (L0 catalog → L1 enum labels → L2 static UI
  → L3 plurals) remains the right plan; it's a separate track, not part of
  this sequence.
- **WorkoutGenerator**: done (#47). Any future generator work goes through
  the knob-blast-radius and invariant-test skills, not this report.
- After items 1–4 land, re-run the audit's line counts before starting items
  10–13 — Tier 1/2 commits will have shifted them again.
