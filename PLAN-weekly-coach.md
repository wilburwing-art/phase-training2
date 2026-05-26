# PLAN — Weekly Coach Redesign

Status: design locked, pre-implementation.
Owner: design discussion captured 2026-05-25.

This document captures the full design for the weekly planning + coaching
flow. It is the source of truth from which the implementation PRs derive.
Pair with `PLAN-weekly-coach-roadmap.md` for the delivery order.

---

## 1. Why this exists

The current weekly check-in is **optional, shallow, and uninformed**:

- A Sunday notification surfaces a wizard that captures only availability
  + sport events. Most users either skip it or tap through with defaults.
- The planner ignores most of the live signals the app already has
  (recent feedback, sport-log load, soreness) on its auto-regen path.
- There's no concept of "the rest of the week" — missed workouts disappear
  silently, abandoned workouts have no slot.
- There's no concrete long-term goal anchor. Every week is its own thing.

The redesign turns the weekly check-in from a constraints questionnaire
into an **intent-first painted strip**, layers a **rules engine** for
pushback, and introduces **autopilot resilience** when life interrupts
the plan. The chat LLM coach stays where it lives (the drawer) and
handles nuance, not routine flows.

## 2. Surfaces

Four structured surfaces, plus one conversational. None tries to capture
all training context — each owns a narrow slice and stays fast.

| Surface | Trigger | Time budget | Owns |
|---|---|---|---|
| Pre-workout | Tap "Start workout" | < 30s | Energy, soreness, time, equipment changes for today |
| Post-workout | Tap "Finish" or "Stop early" | < 30s | Difficulty, hurt areas, ran long, abandon reason if early |
| Missed-workout | 6 AM push next day | < 15s read | Transparent autopilot reschedule; user reviews, can undo |
| Weekly check-in | Sunday soft gate (optional) | < 2 min | Day-by-day intent for next week + lock-in to Week tab |
| LLM coach (chat drawer) | User taps "Coach" anywhere | Variable | Synthesis, explanation, nuance, plan-edit suggestions |

### 2.1 Weekly check-in — the painted strip

This is the headline surface. Replaces the current `WeeklyCheckInFlow`.

**Design principle**: the user states *intent per day* (what they want
to do); the planner builds the actual workouts. Surface stays lean —
no per-day duration sliders, no routine pickers in v1. Effort scales
with what actually changed from last week.

**Pre-fill**: each cell starts populated from
(a) the previous week's *actual* shape (from `WeekPlanSnapshot[]` history
    + matched `SavedSession` records), or
(b) the user's profile defaults (TrainingMemory) if no history exists.

A "typical week" should require zero edits — user scans the strip,
sees last week's pattern, accepts. Editing is only for the cells that
genuinely changed (traveling Friday, taking Thursday off, swapping a
lift for a sport day).

**Per-cell controls** — minimal:

- **Kind** (primary tap) — Lift / Sport / Rest / Event / Travel
- **Focus** (secondary tap, lift only) — Push / Pull / Legs / Upper /
  Lower / Full Body. Defaults to last week's pattern (planner picks
  if no history).
- **Sport pick** (secondary tap, sport only, surfaced only if user has
  multiple sports configured) — which sport
- **Note / event title** (event / travel only) — short label

That's it. ~8-10 micro-decisions maximum across a full edit (kind + focus
on each lift day, kind alone on rest/sport). Most weeks: 0-3 taps.

**Light context chip** at the bottom of the strip:

- `Typical` (default) — no bias
- `Recovery` — planner trims volume, prefers mobility
- `Build` — planner adds volume / intensity within safety bounds
- `Busy` — planner respects time budgets aggressively, allows shorter sessions

**Rules-engine validation** fires on edit + on accept. See §4.

**Add-workout affordance**: long-press a rest day → "Add workout here"
opens a small sheet to set kind + focus (matches the painted-strip
vocabulary). Added workouts feed `WeekPlanSnapshot` for next-week context.

**Lock-in summary** — accept dumps to Week tab with a 1-line recap:
> "3 lifts (Push/Pull/Legs), 2 climbing sessions, 1 rest, 1 mobility · ~5.5h total · 1 warning acknowledged"

**Deferred to v2** (out of v1 scope, kept here for reference):
- Per-day duration override on each cell (use global `sessionMinutes` for v1)
- Saved-routine picker inside the strip (Lift + focus is sufficient for v1)

### 2.2 Pre-workout check-in (extended, not redesigned)

Existing `SorenessEntry` schema is sufficient. Surface stays the same
except:

- Adds an explicit "Substitute exercise" path inline (already exists via
  picker; document the swap as a manual user action — no proactive coach
  swap offer).

### 2.3 Post-workout check-in (extended)

- New explicit "Stop early" affordance distinct from "Finish".
- When stopping early, capture **abandon reason** from a small typed set:
  `Equipment unavailable / Felt off / Time ran out / Pain / Lost motivation / Other (+note)`.
- Triggers mid-week reshuffle if applicable (see §5).

### 2.4 Missed-workout banner

- Fires 6 AM the day after a planned lift/mobility day passed with
  (a) no matching SavedSession AND (b) the day wasn't `.rest / .sport / .event`.
- Surfaces as a Today-tab banner + push notification.
- App has already computed the proposed reshuffle via §3 best-practices.
- User can:
  - **See changes** → reveals diff (which day moved where)
  - **Undo** → drops the reshuffle; the missed workout is discarded
  - Tap dismiss → accept

- One firing per missed day. After one dismissal, suppress.

### 2.5 LLM coach (chat drawer)

- **Reactive**: responds only when user opens the drawer.
- **Proactive milestones**: max 2 chat notifications per week, fired only
  on noteworthy events:
  - PR hit
  - Goal template milestone reached
  - Missed-day streak broken (or extended past threshold)
  - Arc transition (deload week entering)
- Existing tools (`propose_plan_edits`, `propose_workout_changes`) unchanged.
- Coach receives all new context (snapshots, miss/abandon history,
  overrides, goal templates, arc state) via `CoachContext.snapshot`.

## 3. Missed-workout autopilot — best-practice rules

App reschedules without asking. Rules:

1. **Missed 1 of N lifts**:
   - If N ≥ 4 → drop it (skip). Don't crowd the rest of the week.
   - If N ≤ 3 → redistribute to preserve body-part coverage.
2. **Body-part priority**: if missed day was Push in a PPL split, find a
   slot for Push before the week closes. Don't re-drop the same pattern.
3. **No stacking**: never reschedule a heavy lift to the day after
   another heavy lift or a hard sport day.
4. **Respect user intent**: never replace a user-locked Rest, Event, or
   Travel day.
5. **Reshuffle budget**: maximum 2 mid-week reshuffles per week (across
   missed + abandoned events combined). After the cap, no further
   reshuffles — the week finishes as-is and the gap surfaces in the
   next weekly check-in's context.

## 4. Rules engine — coach pushback

Synchronous, deterministic, runs in Swift on the device. Not the LLM.

### 4.1 Rules catalog (initial set)

| Rule | Severity | Triggers when |
|---|---|---|
| Stacked hard days | warn | ≥3 lift/sport days back-to-back without rest/mobility |
| Volume drift | info | This week's lift count diverges from declared `liftDaysPerWeek` by ≥2 |
| Pattern imbalance | info | Push/Pull ratio off by ≥2 in either direction |
| Recovery debt | warn | Hard sport day scheduled immediately after a hard lift day |
| Time budget reality | warn | Sum of declared minutes > realistic weekly budget (e.g. 7h+) |
| Single-pattern overload | info | Same lift focus 3+ times in one week |
| Skip-streak suppression | (silent) | Repeated misses on same weekday → silently de-emphasize |

### 4.2 Severity behavior

- **info**: shown in weekly check-in only; suppressed during mid-week edits
- **warn**: always shown, requires explicit acknowledgement tap to accept
- **strong**: always shown, harder to dismiss (e.g. "Are you sure? Tap twice to override")

User taps to acknowledge → log a `WeeklyPlanOverride` entry. After 3
consecutive overrides on the same rule for the same user pattern, the
rule self-suppresses for that pattern.

### 4.3 Disagreement resolution (when user explicitly rejects a coach
recommendation)

Coach **never refuses outright**. When user pushes against a coach-marked
Rest day, the coach offers a lighter alternative:

> "I was holding Tuesday as rest. If you want to move, here's a mobility
> session that won't dig into your recovery."

User can take the alternative or override into a full workout. Either
way, override is logged.

## 5. Three completion states

Each tracked at the SavedSession layer. Distinct effects:

| State | Trigger | Effect on this week | Effect on future weeks |
|---|---|---|---|
| **Completed** | SavedSession with ≥70% of planned sets done | None — workout done | Normal bias (feedback / soreness / sport-load signals) |
| **Abandoned** | SavedSession ended via "Stop early" before 70% completion | Rules engine adjusts remainder of week (within 2-reshuffle cap). If reason = Pain, soft-trigger coach check-in. | `AbandonedWorkoutEntry` feeds context; repeated abandons same exercise → bias against it |
| **Missed** | Past planned day, no SavedSession, not user-marked unavailable | 6 AM banner; app autopilots reshuffle | `MissedWorkoutEntry`; pattern detection (skip-streak on same weekday) |

Completion ratio is computed from existing `SavedSession.exercises[].sets[]`
data; no schema change required.

## 6. Planner intelligence (invisible to user)

All new behavior runs inside `Planner.generate` and its supporting
`GeneratorContext`. Users see better plans; they don't see the machinery.

### 6.1 Auto-detected arcs (Interpretation A)

- Planner tracks accumulated CNS / volume load across recent weeks via
  `WeekPlanSnapshot[]` + `SavedSession` history.
- When accumulated load crosses a threshold (e.g. 3 consecutive build
  weeks), the planner automatically injects a deload week — reduced
  volume, lighter intensity, more mobility.
- Arc length: 4-week default cycle (3 build + 1 deload).
- **Not visible to user.** No "Week 3 of 4" indicator. Each week stands
  on its own and adapts to the user's actual state.

### 6.2 Hybrid CNS budgeting

- Hard sport days (intensity = `.hard` in SportLogEntry) count as
  recovery-cost equivalent to a moderate lift day.
- Planner sequences lifts to avoid 3+ consecutive high-CNS days
  (lift + lift + lift, or lift + hard-climb + lift).
- Reads from `SportLogStore.entries` already plumbed into the planner
  (PR #11 catalog work).

### 6.3 Autoregulation

- After each completed lift session, planner computes per-exercise
  completion ratio (`done sets / planned sets` with weight × reps
  validation).
- Next week's prescription:
  - Completion < 80% on 2+ exercises in a session → deload weight 5%
    next week
  - Completion ≥ 100% with target reps hit for 2+ consecutive weeks →
    bump weight 5 lb (upper body) / 10 lb (lower body)
  - Between thresholds → hold weight
- Per-exercise, not blanket — bench may bump while deadlift holds.

### 6.4 Skip-streak detection

- After 3 consecutive same-weekday misses, planner de-emphasizes that
  weekday in future regens (treats as "low expected adherence" slot).
- Surfaces to chat coach: "I noticed you've missed Thursday 3 weeks
  running. Want me to drop it from the default rotation?"
- User dismissal = keep current rotation; user accept = update
  `liftDaysPerWeek` or `unavailableDays`.

### 6.5 Fallback generation when check-in is skipped

If user doesn't open the Sunday check-in by Monday morning:

- Planner generates from `TrainingMemory` (profile) + inferred shape
  from previous week's actual sessions.
- "Actual shape" is computed: which weekdays the user actually trained,
  how long sessions actually ran, what kinds (lift/sport).
- This shape biases next week — declared 4 lifts but consistently
  completed 3 → fallback generates 3.
- Today tab shows a "your plan is stale — review week" banner that links
  to the Week tab.

## 7. Long-term goals

Two-pronged, both lightweight:

### 7.1 Session tagging (model #2 from design discussion)

- Add an optional `sessionTags: [String]` field on SavedSession (or
  ActiveSession).
- Tag options surfaced at end-of-session: `Test day`, `Max attempt`,
  `Light day`, `Technique focus`.
- Tagged sessions get PR detection prioritized + appear as anchor
  points on Progress tab strength charts.
- Zero new types beyond a tag string array.

### 7.2 Goal templates (model #4)

- New `GoalTemplate` enum: pre-baked goals with progression logic:
  - `Bench bodyweight`
  - `Pull-up unweighted` (then `Pull-up 5 reps weighted`, etc.)
  - `Deadlift 2× bodyweight`
  - `Squat 1.5× bodyweight`
  - `Overhead press 0.75× bodyweight`
  - `5k under 25 min` (cardio goal — uses sport log data)
  - `100 climbs in a month` (consistency goal)
- User picks 1-2 active templates. App tracks progress, shows on
  Progress tab, celebrates milestones (% complete + chat notification at
  thresholds).
- Implementation: `GoalTemplate` Codable enum + `userGoals: [UserGoal]`
  on TrainingMemory.

### 7.3 What's deferred

Training-block periodization (mesocycle / macrocycle planning per
discussion) → v2. Concrete custom weight + date goals (full LiftGoal
model) → v2.

## 8. LLM coach role

The LLM stays at the chat drawer. Structured check-ins use forms + the
rules engine for speed, determinism, offline robustness, and to avoid
sending soreness/energy state to Anthropic when the user is opted out.

LLM coach reads everything via `CoachContext.snapshot`:

- All existing context (memory, recent sessions, feedback, soreness,
  sport logs, plan)
- New: `WeekPlanSnapshot[]` history, `MissedWorkoutEntry[]`,
  `AbandonedWorkoutEntry[]`, `WeeklyPlanOverride[]`, active
  `UserGoal[]`, current arc state

LLM coach contributions:
- **Explainability expansion**: when user taps "Why this exercise?",
  the existing `provenance` field shows; if user wants more, the chat
  drawer can elaborate.
- **Plan-edit proposals**: existing `propose_plan_edits` and
  `propose_workout_changes` tools.
- **Proactive milestones** (capped at 2/week): noteworthy events open
  the drawer with a short note.

## 9. Coach behavior contract

- **Assertiveness**: warn-severity issues require explicit
  acknowledgement before plan accept. Never blocks outright.
- **Tone**: fixed default — moderate, supportive, explanatory. No
  per-user tone toggle in v1.
- **Explainability**: tap-to-reveal at day-card and exercise-row level.
  Uses existing `generatedReason` and `provenance` fields. No "always
  shown" mode.
- **Disagreement**: offer lighter alternative; never refuse.

## 10. Notification strategy

- **Hard cap**: 3 push notifications per day across all classes.
- **Order on collision**: missed-workout banner → weekly check-in
  reminder → coach milestone.
- **Suppression**: 3 dismissals on the same notification class for the
  same trigger → stop firing.
- **Quiet hours**: v2 customization. Default sensible (6 AM - 9 PM
  local time).
- **In-app banners** (Today tab) are not push notifications and don't
  count against the cap.

## 11. Data model additions

All additive — no migrations of existing data, no breaking changes.

### 11.1 New types

```swift
struct WeekPlanSnapshot: Codable {
    let weekStart: Date
    let plan: WeekPlan
    let actualSessions: [SavedSession.ID]  // joined at query time
    let capturedAt: Date
}

struct MissedWorkoutEntry: Codable, Identifiable {
    var id: UUID
    var date: Date              // start-of-day of missed day
    var plannedKind: DayKind
    var plannedTitle: String?
    var resolution: MissResolution  // .reshuffledTo(Date) / .dropped / .userDismissed
    var loggedAt: Date
}

struct AbandonedWorkoutEntry: Codable, Identifiable {
    var id: UUID
    var date: Date
    var plannedTitle: String?
    var reason: AbandonReason  // .equipmentUnavailable / .feltOff / .timeOut / .pain / .motivation / .other
    var completionRatio: Double  // 0.0 - 1.0
    var note: String?
    var loggedAt: Date
}

struct WeeklyPlanOverride: Codable, Identifiable {
    var id: UUID
    var weekStart: Date
    var rule: String            // rule identifier
    var pattern: String         // what specifically the user overrode
    var loggedAt: Date
}

enum WeekTone: String, Codable {
    case typical, recovery, build, busy
}

enum GoalTemplate: String, Codable, CaseIterable {
    case benchBodyweight
    case pullupUnweighted
    case deadliftDoubleBW
    // ... (defined in detail in PR 4-5)
}

struct UserGoal: Codable, Identifiable {
    var id: UUID
    var template: GoalTemplate
    var startedAt: Date
    var targetMet: Bool
    var milestonesReached: [Date]
}

enum LiftFocus: String, Codable {
    case push, pull, legs, upper, lower, fullBody
}
```

### 11.2 Extensions to existing types

```swift
// WeekOverrides additions (v1)
extension WeekOverrides {
    var weekTone: WeekTone           // light context chip
    // Note: per-day duration override (durationByDate) deferred to v2.
    // v1 uses the global TrainingMemory.sessionMinutes for every day.
}

// DayKindOverride.lift gains a focus
enum DayKindOverride {
    case rest
    case mobility(routineId: Int? = nil)
    case lift(routineId: Int? = nil, focus: LiftFocus? = nil)  // focus added
    case sport(sportSlug: String? = nil)
}

// WeekEventKind gains travel
enum WeekEventKind: String, Codable {
    case sportSession, race, outOfTown  // new: outOfTown
}

// SavedSession gains tag support
extension SavedSession {
    var sessionTags: [String]  // "test-day", "max-attempt", "light-day", etc.
}

// TrainingMemory gains goals
extension TrainingMemory {
    var userGoals: [UserGoal]
}
```

### 11.3 New storage on PlanStore

```swift
final class PlanStore: ObservableObject {
    @Published var pastPlans: [WeekPlanSnapshot]   // last 12 weeks
    @Published var missedWorkouts: [MissedWorkoutEntry]   // last 90 days
    @Published var abandonedWorkouts: [AbandonedWorkoutEntry]   // last 90 days
    @Published var overrides: [WeeklyPlanOverride]
    @Published var midWeekReshuffleCount: Int   // reset weekly
    // ... existing fields
}
```

Persisted under existing UserDefaults keys with new sub-keys.

### 11.4 Rules engine module

```swift
// Pure Swift, no async, fully testable.
enum PlanValidationRule: String, CaseIterable {
    case stackedHardDays
    case volumeDrift
    case patternImbalance
    case recoveryDebt
    case timeBudgetReality
    case singlePatternOverload
    // ...
}

struct PlanValidationIssue {
    let rule: PlanValidationRule
    let severity: Severity   // .info, .warn, .strong
    let message: String
    let suggestedFix: PlanEdit?  // optional one-tap fix
}

enum PlanValidator {
    static func validate(
        plan: WeekPlan,
        context: GeneratorContext,
        overrides: [WeeklyPlanOverride]
    ) -> [PlanValidationIssue]
}
```

## 12. What's deferred to v2

| Capability | Deferred because |
|---|---|
| **Per-day duration override** on the painted strip | v1 uses the global `TrainingMemory.sessionMinutes` for every day; per-day duration is a power-user surface that adds a slider to every cell |
| **Saved-routine picker** inside the painted strip (pick a CustomRoutine for a specific day) | Lift + focus chip gives the planner enough to build a great workout; pinning to a saved routine is a power-user override |
| Training-block periodization (explicit blocks visible to user) | Auto-arc covers 70% of value; explicit blocks add UX surface area we'd rather earn |
| HRV / sleep / Apple Watch integration | HealthKit infra is non-trivial; users get value without it for v1 |
| Calendar app integration | Manual "unavailable" works; auto-pull is convenience |
| Coach tone customization | v1 ships one default; tone toggle is a tuning knob |
| Quiet-hours customization | Default 6 AM - 9 PM is sensible; user customization is polish |
| Re-engagement (user goes dark) | Risk of being intrusive; needs careful design |
| Plan time-machine (restore old plan) | Snapshots enable it; UX is v2 |
| External human-coach coexistence | Power user feature; niche |
| Multi-user / family device sharing | Not the target audience |

## 13. Open questions

None. All decisions captured. The next document is the PR roadmap:
`PLAN-weekly-coach-roadmap.md`.

## 14. Glossary

- **Painted strip**: the 7-cell intent-first weekly editor
- **Arc**: an internally-tracked 4-week build/deload cycle
- **Pushback**: rules-engine warnings shown during plan edits
- **Reshuffle**: mid-week rebalance triggered by missed or abandoned workout
- **Autoregulation**: weight adjustment based on prior-week completion ratio
- **Skip-streak**: pattern of repeated misses on the same weekday
