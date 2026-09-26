---
name: phase-training-behavior-signal-inventory
description: Map of every user-behavior signal phase-training2 captures (did / chose / looked), where each lives, and which are consumed by anything. Trigger when scoping recommendations, personalization, "predict what the user wants", "learn from what they search or swap", or any feature that reads user behavior into the planner or coach. Records that the explore tier (search, browse, detail opens, routine previews) has ZERO capture, the affinity tier feeds the season engine comparator (A1), and planned-vs-actual is frozen per session as DayOutcome (A2) with no reader yet. Skip for generator inertness questions (phase-training-season-engine-sidelines-adaptive-layer) or how to bias the slot picker (phase-training-generator-bias-weight-pool-not-reorder).
when-to-use: Before designing any behavior-driven recommendation or ranking in phase-training2, so the scan of what is already captured is not redone from scratch.
---

# Behavior signals in phase-training2 (surveyed 2026-09-25)

Three tiers by strength. Read the "consumed" column before proposing capture: most of the
work is wiring, and the one tier with no capture is the weakest signal.

| Tier | Signal | Lives in | Consumed by |
|---|---|---|---|
| Did | Completed sessions, sets, loads | `SavedSession` (SQLite via `UserDatabase+Sessions`) | priorBest / lastAttempt, coach context |
| Did | Abandoned workout + typed `AbandonReason` | `pt_abandoned_workouts`, 90-day window | coach context only |
| Did | Planned vs actual per saved session (`DayOutcome`: asPlanned / modified / switched / unplanned / abandoned, swap pairs, drops, sets) | `pt_day_outcomes` on PlanStore, 90-day window, since 2026-09-25 | nothing yet (A4) |
| Did | Missed workout + `MissResolution` | `pt_missed_workouts`; `SkipStreakDetector` | Planner softens rotation; coach |
| Chose | Swap away X into Y | `TrainingMemory.exerciseAffinities`, `swapAwayCounts` (writers: `LogScreen`, `TodayScreen+TemplateEditor`, `ExerciseActionSheet`) | **nothing in production** |
| Chose | Wheel / override switch to saved or sample workout | `overrides.customRoutineByDate` | plan application only, never read as a preference |
| Chose | Hand-built routines | `pt_custom_routines` | wheel options; never read as a preference |
| Looked | Search terms, library browse, detail opens, routine previews | **nowhere**: `query` is `@State`, `previewingStock` is `@State` | nothing |

## Facts that change the design

- **Affinities are parked, not dead.** `GeneratorContext.from(... includeParkedSignals:)`
  zeroes `exerciseAffinities`, `recentSoreAreas`, `stagnantExercises` unless true, and no
  production caller passes true (grep `includeParkedSignals: true` hits tests only). Comment
  T2-11 at `GeneratorContext.swift:244` says why: `buildStagnantExercises` walks four weeks of
  sessions computing Epley 1RMs per regen. Unparking costs regen time; measure before flipping.
- **Planned-vs-actual is persisted as `DayOutcome` (A2, 2026-09-25)**, frozen at save time.
  Do not rebuild it from `pastPlans`: `snapshotCurrentPlan` replaces the week's snapshot on every
  capture and `overrides.displacedPlanByDate` resets every Monday, so a read-time derivation
  loses the switched days. Logged rows keep the planned id (`gex-<GeneratedExercise.id>`)
  through a mid-session swap, which is how swaps are paired.
- **Sample sessions on the wheel are demos.** A switch onto one is plan rejection, never a
  preference for that sample's contents. Filter them before counting wheel switches.
- **Explore intent converts or it does not count.** A search while swapping may be a
  library-existence check. Log the funnel (search -> detail -> add/start) and weight conversion.
- **Privacy posture forbids fan-out.** `MemoryStore.swift` header: no backend, no analytics
  SDK, SENSITIVE fields never logged. Any event log is on-device with a rolling window
  (match the 90-day missed/abandoned convention).
- **Direction constraint.** Owner's recorded decision is authored spines, engine as
  within-program assist. Recommendations rank authored routines (118 in coach.db) and
  re-rank `SubstituteExerciseSheet`'s 1,795 curated rows; they never generate. Default the
  coach to asking rather than the planner acting.

Pairs with [[phase-training-generator-bias-weight-pool-not-reorder]] (how to consume affinities),
[[phase-training-personalization-two-axes]] (never derive experience from behavior),
[[scorer-outcome-feedback-loop]] (at personal N, rules and counts beat weights).

Full plan and the next-gen idea list: `PLAN-predictive-recommendations.md` (Part A grounded, Part B unlimited-resources). Iteration order A1 to A4 lives there; do not restate it here.
