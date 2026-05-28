# Full Review — phase-training2 — 2026-05-26

Synthesis of 9 parallel read-only workstreams. Source reports in this folder:

| # | Report | Scope |
|---|--------|-------|
| 01 | architecture-map | system diagram, load-bearing files, subsystem deep-dives |
| 02 | critique-today-log-execution | daily-use workout flow |
| 03 | critique-onboarding-profile | data-capture surface |
| 04 | critique-coach | LLM coach + tool-calling + diffs |
| 05 | critique-library-progress-history | browse + review surface |
| 06 | architecture-review | module depth / coupling / testability |
| 07 | diff-review | the 4 uncommitted files |
| 08 | strategy | competitive landscape + MRR + roadmap |
| 09 | catalog-audit | coach.db ERD + population/usage matrix |

---

## The one-paragraph verdict

The app is **feature-complete and architecturally clean on the read side, but pre-revenue, under-wired, and carrying a cluster of state-desync correctness bugs in the daily-use flow.** The catalog (coach.db) is genuinely rich — and roughly a third of that richness is invisible to the UI and the planner. The single highest-leverage move is not more features: it's **ship a paywall and submit to the App Store.** Every queued roadmap bet (image-quality, voice coach) is either already-done-and-invisible or the most expensive least-validated option. Before shipping, two trust/correctness issues must close: the coach's *silent* plan mutation, and the execution-flow desync bugs.

---

## Cross-cutting themes (ranked by leverage)

### T1 — Ship + monetize is the actual bottleneck (from 08)
Build 110 on TestFlight, feature-complete, **zero monetization code.** Coach unit economics work (~85% margin at $9.99 with the existing 50/100 turn/day caps). Niche ("strength that *serves your sport*") is still open but the "AI coach" itself is no longer a differentiator — Hevy, MacroFactor, Forge, Ray all shipped AI coaching in 2025-26. Positioning + speed to store is the moat, not feature count.

### T2 — The coach can mutate plans without preview (from 04, 06)
`PlanStore+LLMRefinement` rewrites every lift day from LLM `build_workout` output with **no diff, no card, no Apply** — fired on plan generation and after every accepted edit (`PlanStore.swift:362`, `:420`). It's consent-gated, but consent ≠ per-change preview, directly contradicting `CoachSystemPrompt.swift:49`. Bounded (can't corrupt plan *shape*) but silently changes exercise selection/sets/RPE. This is a trust bug to fix before public launch. Separately, `build_workout` is half-wired in chat — drawer sends the tool but has no handler case (`CoachDrawer.swift:356`), so "build me a push day" in chat silently returns an empty bubble.

### T3 — Rich catalog, under-wired UI + planner (from 09, 05, 01 — triple-confirmed)
~2,150 rows across 4 relational tables have **zero Swift query sites.** Biggest: `exercise_phases` (1,133 rows, 326 exercises, all 5 phases, with priority + volume_guidance) — never read; the planner uses `routines.phase` instead. Also unread: substitutions in detail view (989), sport-relevance display (2,303 used only for ranking), injury-relevance (224), and `recovery_demand`/`cns_load`/`intensity_category` populated on all 551 exercises but never loaded. **148 stock routines ship in coach.db and are completely invisible** (Library "Workouts" shows only user customs). Verdict from 09: rich-but-underwired (wiring opportunity), NOT messy (no cleanup needed — <1% NULL, no orphans).

### T4 — State-desync correctness bugs in the daily flow (from 02)
- `editableTemplate` seeded once in `.onAppear` and never re-synced → stale exercise list / wrong session if plan regenerates while Today is alive (`TodayScreen.swift:345`).
- CompleteScreen duration keeps ticking against the still-running session while the user fills feedback; saved duration ≠ displayed (`CompleteScreen.swift:53`).
- Post-swap "Last" column shows the *previous* exercise's history (`LogScreen.swift:161`).
- Two disagreeing definitions of "a set" (warmups counted in header, excluded from PR/volume).

### T5 — Untestable core: `CoachDatabase.shared` global (from 06)
Non-injectable singleton hit from 23 sites incl. `TrainingMemory.init(from:)` mid-decode → a value type can't deserialize without the bundled SQLite, and the generator/profile logic can't be unit-tested in isolation. `WorkoutGenerator` (1,124 lines, 6 jobs) has its densest branches (stagnation swap, both accessory layers, duration-budget dropping) **untested.** Persistence fails silently (`try?`-swallowed encodes, fire-and-forget SQLite writes).

### T6 — Data-loss bug: `Double(weight)` (from 05)
ProgressScreen volume + trends parse weight via `Double(set.weight)`, which returns nil on the app's own "+25"/"BW" logging format → those sets contribute 0 volume and vanish from trends (`ProgressScreen.swift:201,732`).

### Reconciled disagreement — coach-consent default (03 vs 07)
03 (opus, onboarding critic) called the consent default a P0; 07 (the diff reviewer reading the actual uncommitted code) found it **functionally correct** on the happy path — `.onAppear` + `hasMadeChoice` lands consent-ON when the user reaches the step. The real residue: (a) a comment-vs-code mismatch (`= false` under a "defaults ON" comment), and (b) a user who *abandons onboarding before* the consent step stays coach-off despite the "ON for new installs" intent. Net: **S-effort cleanup, not a blocker** — but worth closing because consent writes mid-flow while every other answer commits atomically in `finish()`.

---

## Unified master backlog

Filtered through T1: P0 = "blocks shipping a trustworthy paid v1." Effort: S ≤2h / M ≤1d / L >1d.

### P0 — before public App Store submission
| Item | Source | Effort |
|------|--------|--------|
| Add StoreKit 2 paywall gating the LLM coach; submit to App Store | 08 | L |
| Stop silent plan mutation — route `PlanStore+LLMRefinement` workout rewrites through the same Mini*DiffCard preview, or disable it for v1 | 04,06 | M |
| Fix `editableTemplate` stale-sync (re-sync on plan/override/active change) | 02 | S |
| Fix CompleteScreen duration drift (stamp end once, stop live recompute) | 02 | S |
| Fix `Double(weight)` data loss for "+25"/"BW" sets in Progress | 05 | S |
| Wire `build_workout` handler into CoachDrawer (or remove the tool from the drawer's tool list) | 04 | S |

### P1 — high-value, post-launch fast-follow
| Item | Source | Effort |
|------|--------|--------|
| Wire `exercise_phases` into the planner (replaces routines.phase shortcut) | 09,01 | M |
| Surface substitutions + sport/injury relevance + recovery_demand in ExerciseDetailSheet | 05,09 | M |
| Expose the 148 stock routines in Library "Workouts" | 05,09 | M |
| Introduce `CoachCatalog` protocol seam (default arg = `.shared`); unlock generator/profile unit tests | 06 | M |
| Add end-to-end tests for stagnation swap + both accessory layers + duration-budget dropping | 06 | M |
| Fix post-swap "Last" column + unify the "what counts as a set" definition | 02 | S |
| Onboarding: gate the planner's load-bearing inputs (focus/experience/startingState) so a user can't ship a blank generic profile | 03 | M |
| Consolidate injury capture — route onboarding to structured `userInjuries`, retire free-text `constraints[]` path | 03 | M |
| Consent cleanup (comment-vs-code, early-exit path, atomic commit) | 03,07 | S |
| Add diff-card accessibility (VoiceOver labels, grouped rows, non-strikethrough removal cues) | 04 | S |

### P2 — polish / debt
| Item | Source | Effort |
|------|--------|--------|
| Stop silent persistence failures (`try?` encodes, fire-and-forget SQLite writes) | 06 | M |
| Library perf: add `countExercises()`, stop double-firing `rows` query per keystroke | 05 | S |
| Replace ~19 live 36pt `BodyAnatomyView` in ProgressRecoverySection with MuscleChipBadge | 05 | S |
| Remove dead code (ExerciseSparkline/import Charts, SubstituteExerciseSheet?, fallbackModel/turn-cap config) | 02,04,05 | S |
| Make cardio/mobility exercises reachable in Library; expose all 17 modalities in filter | 05 | S |
| Fix index-based `ForEach` identity across Log/Preview/EditSession | 02 | S |
| RPE picker decimals (integer-only picker vs decimal display everywhere else) | 02 | S |
| `UserDatabase` concurrency test (write surface untested vs CoachDatabase) | 06 | S |
| iOS 26 double keyboard-toolbar crash risk in OnboardingAboutScreen | 03 | S |

---

## Deferred execution verbs → concrete targets

The user's open-ended verbs now have grounded targets (pick to execute):
- **Implement** → P1 "wire `exercise_phases`" or "surface stock routines" (both pure additions, high data-richness payoff).
- **Refactor** → P1 `CoachCatalog` protocol seam (unblocks all generator/profile testing; near-zero call-site churn).
- **TDD** → P1 accessory-layer + stagnation-swap tests (folds into existing `WorkoutGeneratorTests.swift`, avoids the gitignored-pbxproj hand-patch).
- **Data/catalog** → no cleanup needed (09 verdict); the work is wiring, covered by P1 above.
- **Schedule/web** → not blocked on anything here; App Store Connect paywall config (08 P0) is the natural web task.
