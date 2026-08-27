# 2026-08-23 architecture report (Tier 3 — no code this cycle)

Companion to `audits/2026-08-23-backlog.md`. Every item here is gated on the
test-coverage gate in that file. Sequencing matters: items are ordered so each
one shrinks the blast radius of the next. One PR per item.

## 1. Derived-data layer for per-render DB work

**Problem.** The same anti-pattern in six places: SQL or full-history walks
inside SwiftUI `body`. TodayScreen runs `proposeMissedReshuffle` plus one
`previousSession` query per exercise per render (TodayScreen.swift:104);
TodayRecoveryCard and ProgressRecoverySection both re-walk all saved sessions
through `MuscleFreshness.rows` (TodayRecoveryCard.swift:15,
ProgressRecoverySection.swift:19 — the latter bypassing ProgressAggregates on
the same screen); CompleteScreen re-runs the PR scan ~3× per keystroke while
typing a note (CompleteScreen.swift:81); InjuriesEditorSheet re-queries all 56
injuries per body pass (InjuriesEditorSheet.swift:80); LibraryScreen
materializes 582 structs to display a count (fixed at T2-13).

**Change.** One memoized derived-state object per store (SessionStore already
owns the invalidation points: save/delete/update). `MuscleFreshness.rows`,
`personalRecords`, `previousSession` become cached lookups invalidated on
session mutation. `listInjuries()` becomes a `lazy static` snapshot —
the catalog is immutable at runtime.

**Tests first.** Gate tests 1 (SessionStore round-trip) and 5 (matcher table);
add a freshness-invalidation test: save session → rows change; no save →
identical object.

**Blast radius.** Medium. Read-only call-site swaps; no schema changes.

## 2. Session write path: debounce + background

**Problem.** `saveActive` fires on every keystroke: full JSON encode +
detached task + notification-center XPC round-trip per character
(SessionStore.swift:91, LogScreen.swift:72). `syncEdits` writes the whole
session per keystroke on CompleteScreen (:169). Cold launch runs
`listSavedSessions()` — 1+N+N×M prepared statements — synchronously on main
before first frame (UserDatabase+Sessions.swift:18, SessionStore.swift:32).

**Change.** (a) Debounce saveActive ~500ms with a flush on scenePhase
background/inactive; (b) coalesce the inactivity-reminder reschedule to the
debounced save (T1-55's generation token makes this safe); (c) move
listSavedSessions off main behind an async load with a lightweight header
query for first frame.

**Tests first.** Gate test 1, plus an active-session crash-recovery test
(kill after debounce window → session restored).

**Blast radius.** Medium-high (touches the live workout path). Do after §1.

## 3. Image memory: bounded cache

**Problem.** ExerciseThumbnail decodes WebP synchronously in `body` and
retains every decoded image in an unbounded `[Int: UIImage]` — ~150MB if the
catalog is browsed (ExerciseThumbnail.swift:94,106).

**Change.** NSCache with a cost limit + decode off-main (the existing
CachedAsyncImage async path is the template; T1-17/T1-18 already touch it).

**Tests.** None meaningful in unit scope; verify with the memory gauge.
**Blast radius.** Low. Do any time after Tier 1 lands.

## 4. CoachContext snapshot: parameter object

**Problem.** 13-parameter `snapshot` where 5 params default to empty; four
call sites each pass a different subset, so what the model sees is
caller-dependent and untraceable (CoachContext.swift:15). T2-3 wires the dead
blocks but makes the signature worse.

**Change.** A `CoachContextInput` struct built by ONE composer that takes the
stores and returns the full input; call sites choose a profile
(`.chat`, `.insight`, `.refinement`) rather than a parameter subset.

**Tests first.** Gate test 3 (`wireHistory` contract) + a snapshot test per
profile asserting which sections appear.

**Blast radius.** Medium. Pure refactor, but it defines the privacy surface —
land after T0-5 so the consent copy and the payload are reconciled first.

## 5. Conversation token growth

**Problem.** Every turn resends the whole day's transcript + a fresh
multi-KB context snapshot; only the static header is cached; input tokens grow
quadratically to the 100-turn cap (CoachDrawer.swift:335).

**Change.** Sliding window (last N turns + a running summary block), and move
the per-turn context snapshot into a cacheable system block that only
invalidates when plan/memory actually change.

**Tests first.** Gate test 3.
**Blast radius.** Medium. Sequence after §4 (the composer owns the blocks).

## 6. UserDatabase error model

**Problem.** T0-4 surfaces open/migration failure, but the underlying model —
every read returns `[]` and every write silently no-ops on any error — stays.
`isOpen` is test-only. The migration list's "append to v1" house style
(UserDatabase.swift:157) survives only because the runner shipped later.

**Change.** Writes return `Result`/throw; reads distinguish empty-vs-failed at
the store layer; new DDL goes in as v2 to re-establish the convention.

**Tests first.** Gate tests 1 and 2, plus a migration test (v1 DB → migrated).

**Blast radius.** High (every store). Do LAST, after §1/§2 shrink the call-site
count. Never edit or reorder existing v1 entries.

## 7. Component dedup

Duplicates, each a one-PR extraction into Components/:
- Wrapping flow layout ×2: `FlowLayout` (ExerciseFilterSheet.swift:163) vs
  `WrappingFlow` (OnboardingSportsScreen.swift:79).
- Day-badge/plan-summary row ×3: CheckInPreviewScreen.swift:49/114,
  WeekScreen.swift:230/523, OnboardingPlanPreviewScreen's private row.
- `parseRestSeconds` ×6 with divergent behavior (M:SS handled only in
  AuthoredRoutine.swift:181; list at BundledRoutineRow.swift:93 finding).
  Canonicalize on the AuthoredRoutine variant.
- Equipment-tier classifier ×2 (EquipmentEditorSheet.swift:81,
  ProfileScreen+RowSummaries.swift:138) — T1-36 makes tier explicit state,
  which may delete both derivations; check after it lands.
- DateFormatter statics: adopt the cached-static convention everywhere
  (WeekDayEditSheet.swift:174 et al).
- `BodyMetricsEditor` (293 lines) out of OnboardingAboutScreen.swift into
  Components/ — ProfileScreen already imports it across concerns.

**Blast radius.** Low each. Good warm-up PRs before §2/§6. Remember: new
files need the 4-edit pbxproj dance, and pbxproj is gitignored — coordinate
on one machine.

## 8. Dynamic Type

**Problem.** Every custom font in the app is fixed-point — `Font.custom(name,
size:)` with no `relativeTo:` (Typography.swift:37); Coach chat and the whole
onboarding questionnaire are frozen at 10-14pt.

**Change.** Add `relativeTo:` at the Typography layer (one file), then audit
fixed `Spacer().frame(height:)` layouts that break at accessibility sizes
(OnboardingFlow.swift:175's magic 140 first). Pairs with the cross-cutting
accessibility sitting from the backlog.

**Blast radius.** Visually broad, mechanically shallow. Screenshot-diff the
main screens before/after.

## 9. Naming: split "Coach"

**Problem.** `CoachDatabase` (1347-line read-only SQLite DAO, no AI) shares
the Coach name with the LLM subsystem, conflating the deterministic catalog
with the privacy/cost surface (CoachDatabase.swift:4).

**Change.** Rename to `CatalogDatabase` (with `coach.db` filename unchanged).
Mechanical, wide diff — do it in a quiet moment, not alongside feature work.

## 10. Deferred product decisions (not architecture, parked here so they're not lost)

- Bundled workouts are browse-only (LibraryScreen.swift:536) — highest-value
  Tier 4 item; promote to a feature PR.
- Rest/event-day "train anyway" beyond T1-5's minimal affordance.
- **Support-sport placement (from T2-8, resolved-as-deferred 2026-08-26).**
  VERIFIED: `SupportScheduler.schedule` — the placement half (rules 1-3, 5,
  `evenSpread`, forced-stack fallback) — has no production caller; only
  `deconflictInPlace` is wired, at Planner.swift:852. Not dead code: tested,
  correct, and the declared design in PLAN-primary-support.md.
  **Why it wasn't wired inline:** `schedule` assigns weekdays for a whole lift
  week from `[GeneratedWorkout]`, but Planner has already placed lift days via
  WeeklyShape before the support pass runs. Adopting it means replacing
  WeeklyShape-driven placement with SupportScheduler-driven placement — an
  architectural swap with regression surface across the planner suite, not a
  Tier-2 fix. **Tests first:** a Planner-level test asserting current placement
  for a ski+climbing pattern week, so the swap is diffable.
  The file header now states the wiring gap so it can't be misread again.
- `regenerateToday` re-roll exhaustion against small sport pools
  (PlanStore.swift:576) — needs a pool-size-aware salt or an honest "pool
  exhausted" notice; interacts with the parked adaptive layer.
