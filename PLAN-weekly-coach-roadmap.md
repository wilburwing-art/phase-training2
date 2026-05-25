# PLAN — Weekly Coach Implementation Roadmap

Pairs with `PLAN-weekly-coach.md` (the design spec). Maps the design
onto a sequence of focused PRs. Each PR has a minimum-lovable scope so
it can ship and be reviewed independently.

Status: roadmap drafted, no PRs opened yet.

## Outstanding work from prior threads (not part of this roadmap)

- **PR #11** (exercise catalog additions) — open, awaiting merge
- **PR #12** (exercise filter taxonomy enums) — open, awaiting merge
- **Pending**: PR 3 — two-dropdown filter UI redesign (Library tab).
  User asked to pause; pick up after weekly-coach roadmap is in motion.
- **Spawned task**: fix flaky LogFlowTests rest-timer tests on main.
  Independent.

## Roadmap principles

1. **Foundation first** — schema and storage changes before any UI.
2. **Vertical slices** — each PR ships visible value, not just
   plumbing. (Foundation PRs are the exception; they pay off the
   PRs that follow.)
3. **Minimum lovable scope** — ship the core of each feature; leave
   polish for a follow-up.
4. **Test coverage is part of the PR** — no PR is "done" without
   passing tests for the new behavior.
5. **Auto-arc, autoregulation, and CNS budgeting** are planner
   internals — they ship behind the existing `Planner.generate`
   surface, no UI changes required.

## The PRs, in delivery order

### PR 4 — Plan history infrastructure (`weekly-coach: plan snapshots`)

**Scope:**
- Add `WeekPlanSnapshot` struct (defined in spec §11.1)
- Extend `PlanStore` to persist `pastPlans: [WeekPlanSnapshot]`
  (capped at last 12 weeks; rolling)
- Snapshot the active plan on every `setPlan(_:)` call (idempotent
  by week start date)
- Snapshot the active plan on weekly rollover (Monday morning detection)
- Add `PlanStore.shape(forWeek:)` helper to derive the "actual shape"
  from snapshots + SavedSession history — drives fallback generation
  and Progress tab features
- Update `CoachContext.snapshot` to include past-plan summary
  (just counts and completion ratios; full plans are too verbose)

**Files touched:**
- `PhaseTraining/Data/PlanStore.swift` (extend)
- `PhaseTraining/Data/PlanHistory.swift` (new — the snapshot type + helpers)
- `PhaseTraining/Coach/CoachContext.swift` (extend)
- `PhaseTrainingTests/PlanHistoryTests.swift` (new)

**Not in scope:**
- Time-machine UI (deferred to v2)
- Progress tab visualizations using snapshots (separate follow-up)

**Why first:** every other PR in this roadmap reads from this.

---

### PR 5 — Painted strip data model + planner support
(`weekly-coach: intent-first data model`)

**Scope:**
- Add `LiftFocus` enum (push/pull/legs/upper/lower/fullBody)
- Extend `DayKindOverride.lift` case with `focus: LiftFocus?`
- Add `WeekOverrides.durationByDate: [Date: Int]`
- Add `WeekTone` enum + `WeekOverrides.weekTone`
- Add `WeekEventKind.outOfTown` case → planner generates
  bodyweight/mobility template for those days
- `Planner.generate` reads new fields:
  - `LiftFocus` on a day overrides the auto-rotation pick
  - `durationByDate` overrides global `sessionMinutes` for that day
  - `weekTone` biases volume / intensity (recovery → -15%, build → +10%,
    busy → respect time budget aggressively)
  - `outOfTown` → bodyweight/mobility template

**Files touched:**
- `PhaseTraining/Data/WeekOverrides.swift` (extend)
- `PhaseTraining/Data/Planner.swift` (read new fields)
- `PhaseTraining/Data/WorkoutGenerator.swift` (respect focus + duration)
- `PhaseTrainingTests/PlannerTests.swift` (extend)

**Not in scope:**
- UI changes — the strip itself ships in PR 6
- Rules engine — ships in PR 7

**Why second:** the planner needs to understand the new intent
vocabulary before the UI lets users express it.

---

### PR 6 — Painted strip UI (`weekly-coach: painted strip`)

**Scope:**
- New `PaintedStripView` component — 7 day cells, edit-in-place
- Replace `WeeklyCheckInFlow` with this view (or wrap it as a new
  step in the flow)
- Unified Week tab: same `PaintedStripView` shown on Week tab;
  weekly check-in entry mode just opens it with the rules-engine
  banner enabled (PR 7 wires this)
- Per-cell expansion sheet: kind picker, focus chip, duration
  stepper, "Use saved routine" expansion
- Light context chip below the strip (`Typical/Recovery/Build/Busy`)
- Long-press a rest day → "Add workout here" sheet
- Accept flow → Week tab summary card (1-line recap)

**Files touched:**
- `PhaseTraining/Screens/PaintedStripView.swift` (new)
- `PhaseTraining/Screens/PaintedStripCell.swift` (new)
- `PhaseTraining/Screens/WeekScreen.swift` (integrate)
- `PhaseTraining/Screens/WeeklyCheckIn/WeeklyCheckInFlow.swift` (refactor)
- `PhaseTraining/Screens/AddWorkoutSheet.swift` (new — minimal)
- `PhaseTrainingUITests/PaintedStripFlowTests.swift` (new)

**Not in scope:**
- Rules-engine warnings (PR 7)
- Mid-week reshuffles (PR 8)
- Saved-routine library improvements

**Why third:** the headline feature. After this, users can paint
the week.

---

### PR 7 — Rules engine + coach pushback (`weekly-coach: validation`)

**Scope:**
- New `PlanValidator` module with rules catalog from spec §4.1
- `PlanValidationIssue` with severity (`info/warn/strong`)
- Inline rendering in `PaintedStripView`:
  - Show issues below the strip
  - Tap to expand explanation
  - `warn` and `strong` require explicit acknowledge tap before accept
- `WeeklyPlanOverride` logging on dismiss; integrated into
  `CoachContext.snapshot`
- Suppression — after 3 consecutive overrides on same rule+pattern,
  rule self-suppresses for that user pattern

**Files touched:**
- `PhaseTraining/Data/PlanValidator.swift` (new — pure Swift, no UI)
- `PhaseTraining/Data/WeeklyPlanOverride.swift` (new)
- `PhaseTraining/Data/PlanStore.swift` (persist overrides)
- `PhaseTraining/Screens/PaintedStripView.swift` (render warnings)
- `PhaseTraining/Screens/PlanValidationBanner.swift` (new)
- `PhaseTrainingTests/PlanValidatorTests.swift` (new — pure logic tests)

**Not in scope:**
- "Lighter alternative" suggestions on disagreement (PR 9 — abandoned/missed handling)
- LLM coach explanations of rule rationale (existing chat drawer suffices)

**Why fourth:** painted strip is editable without guardrails; rules
engine is the safety net that makes the customization usable without
the user shooting themselves in the foot.

---

### PR 8 — Missed-workout autopilot
(`weekly-coach: missed-workout reshuffle`)

**Scope:**
- Detection: scheduled on app-open + a once-per-day check at 6 AM
  via `BGTaskScheduler` (existing `WeeklyReminderScheduler` pattern)
- Trigger rule per spec §2.4: 24h after planned day passes,
  no SavedSession, not user-marked unavailable
- Best-practice reshuffle rules per spec §3 — pure Swift, returns
  a `PlanEdit` list
- New `MissedWorkoutEntry` type + persistence
- Today-tab banner + push notification with diff preview
- `CoachContext.snapshot` reads from `MissedWorkoutEntry[]` so the
  chat coach can see patterns
- Reshuffle counter on `PlanStore` (caps at 2/week, resets weekly)

**Files touched:**
- `PhaseTraining/Data/MissedWorkoutEntry.swift` (new)
- `PhaseTraining/Data/MissedWorkoutAutopilot.swift` (new — the rule engine)
- `PhaseTraining/Data/PlanStore.swift` (counter + persist entries)
- `PhaseTraining/Screens/MissedWorkoutBanner.swift` (new)
- `PhaseTraining/App/NotificationScheduler.swift` (extend)
- `PhaseTraining/Coach/CoachContext.swift` (extend)
- `PhaseTrainingTests/MissedWorkoutAutopilotTests.swift` (new)

**Not in scope:**
- Abandoned workouts (PR 9)
- Skip-streak chat surface (PR 10 — planner intelligence)

**Why fifth:** highest user-visible "the app is smart" win. People
notice when the app handles missed workouts gracefully.

---

### PR 9 — Abandoned workout state + reactive adjust
(`weekly-coach: abandon handling`)

**Scope:**
- "Stop early" affordance on `LogScreen` distinct from "Finish"
- Capture sheet on stop-early: reason picker (Equipment / Felt off /
  Time / Pain / Motivation / Other) + optional note
- New `AbandonedWorkoutEntry` type
- Completion ratio computed at save time
- Rules engine + missed-workout autopilot both extended to handle
  abandonment events:
  - Reshuffle remainder of week (subject to 2-reshuffle cap shared
    with missed-workout autopilot)
  - If reason = `pain` → soft-trigger coach check-in (chat drawer
    opens with a pre-filled message)
- `CoachContext.snapshot` extended

**Files touched:**
- `PhaseTraining/Data/AbandonedWorkoutEntry.swift` (new)
- `PhaseTraining/Data/AbandonReason.swift` (new enum)
- `PhaseTraining/Screens/LogScreen.swift` (Stop-early button)
- `PhaseTraining/Screens/AbandonReasonSheet.swift` (new)
- `PhaseTraining/Data/SessionStore.swift` (save abandoned sessions)
- `PhaseTraining/Data/MissedWorkoutAutopilot.swift` (extend to abandonment)
- `PhaseTraining/Coach/CoachContext.swift` (extend)
- `PhaseTrainingTests/AbandonHandlingTests.swift` (new)

**Why sixth:** the other half of the resilience story. With PR 8
the app handles "didn't start". With PR 9 it handles "started but
bailed". Both feed the same rules engine for reshuffling.

---

### PR 10 — Planner intelligence — auto-arc, autoregulation, CNS budgeting
(`weekly-coach: planner intelligence`)

**Scope (largest single PR; could split if needed):**

**10A — Auto-arc periodization:**
- `Planner.generate` reads accumulated load from `WeekPlanSnapshot`
  history + completed sessions
- Threshold logic: 3 consecutive build weeks → inject deload week
- Deload application: -20% volume, -10% intensity, +mobility day
- Per spec §6.1: invisible to user, no "Week 3 of 4" indicator

**10B — Autoregulation:**
- Compute per-exercise completion ratio at session save
- Store in a new `ExercisePerformanceHistory` table (or computed
  on-the-fly from SavedSession)
- Planner reads when prescribing weights:
  - <80% on 2+ exercises in a session → -5% next week
  - ≥100% with target reps × 2 weeks → +5 lb / +10 lb next week

**10C — Hybrid CNS budgeting:**
- Extend `Planner.applyRecentSignalBias` to factor in lift+sport
  sequencing
- Avoid 3+ consecutive high-CNS days (lift+lift+lift or lift+hard-sport+lift)
- May require reordering planned days, not just trimming volume

**10D — Skip-streak detection + chat surface:**
- Pattern detection: 3+ misses on same weekday → de-emphasize that
  weekday in regen
- Surface to chat coach (uses milestone notification budget):
  "Want me to drop Thursday from rotation?"

**Files touched:**
- `PhaseTraining/Data/Planner.swift` (extend)
- `PhaseTraining/Data/GeneratorContext.swift` (extend)
- `PhaseTraining/Data/WorkoutGenerator.swift` (autoregulation weight picks)
- `PhaseTraining/Data/PlanArc.swift` (new — arc tracker)
- `PhaseTraining/Data/AutoregulationEngine.swift` (new)
- `PhaseTraining/Data/CNSBudgetEngine.swift` (new)
- `PhaseTraining/Data/SkipStreakDetector.swift` (new)
- `PhaseTrainingTests/AutoArcTests.swift` (new)
- `PhaseTrainingTests/AutoregulationTests.swift` (new)
- `PhaseTrainingTests/CNSBudgetTests.swift` (new)
- `PhaseTrainingTests/SkipStreakTests.swift` (new)

**Could split into 4 smaller PRs** (10A / 10B / 10C / 10D) if review
volume is a concern. Default: keep as one PR for atomic delivery of
"the planner got noticeably smarter".

**Why seventh:** without auto-arc, autoregulation, and CNS budgeting,
the planner stays as week-by-week static. With them, it becomes the
"intelligent" coach. Highest abstract value but invisible to user
without the prior PRs being in place.

---

### PR 11 — Goal templates + session tagging
(`weekly-coach: long-term goals`)

**Scope:**
- `GoalTemplate` enum with initial set (Bench bodyweight, Pull-up
  unweighted, Deadlift 2× BW, Squat 1.5× BW, OHP 0.75× BW, 5k under
  25 min, 100 climbs/month)
- `UserGoal` type + `TrainingMemory.userGoals: [UserGoal]`
- Goal picker UI on Profile tab (1-2 active goals)
- Session tagging: chip array on post-workout sheet (`Test day`,
  `Max attempt`, `Light day`, `Technique focus`)
- Add `sessionTags: [String]` to `SavedSession`
- Progress tab: goal progress bars + tagged-session anchor points on
  strength charts
- PR detection prioritizes tagged sessions
- Milestone notifications (uses 2/week proactive cap)

**Files touched:**
- `PhaseTraining/Data/GoalTemplate.swift` (new)
- `PhaseTraining/Data/UserGoal.swift` (new)
- `PhaseTraining/Data/TrainingMemory.swift` (extend)
- `PhaseTraining/Data/Session.swift` (extend SavedSession)
- `PhaseTraining/Screens/GoalPickerSheet.swift` (new)
- `PhaseTraining/Screens/ProgressScreen.swift` (extend)
- `PhaseTraining/Screens/CompleteScreen.swift` (tag chips)
- `PhaseTraining/Data/PRDetector.swift` (extend to prioritize tags)
- `PhaseTrainingTests/GoalTemplateTests.swift` (new)

**Why eighth:** completes the long-term-engagement loop. Users see
progress against goals, not just history.

---

### PR 12 — Notification budget + suppression
(`weekly-coach: notification governance`)

**Scope:**
- Hard cap: 3 push notifications per day, tracked in UserDefaults
- Priority order on overflow: missed → weekly → coach milestone
- Suppression: 3 dismissals same class same trigger → stop firing
- In-app banner remains unaffected (doesn't count against cap)
- Settings toggle to disable a class of notifications entirely

**Files touched:**
- `PhaseTraining/App/NotificationScheduler.swift` (extend)
- `PhaseTraining/App/NotificationBudget.swift` (new)
- `PhaseTraining/Screens/NotificationSettingsScreen.swift` (new minor)
- `PhaseTrainingTests/NotificationBudgetTests.swift` (new)

**Why ninth (could be earlier):** could be slipped in earlier as a
foundation PR, but isn't blocking until PRs 8-11 add notifications.
Slot here when "the app is talking too much" becomes a real risk.

---

## Cadence and parallelism

**Sequence-critical chain** (must ship in this order):

1. PR 4 — Plan history (foundation)
2. PR 5 — Painted strip data model (planner reads new fields)
3. PR 6 — Painted strip UI (user can express the new intent)
4. PR 7 — Rules engine (guardrails for the UI)
5. PR 8 — Missed-workout autopilot

**Parallelizable after PR 4-5 land:**

- PR 9 (abandoned state) — independent of UI
- PR 10 (planner intelligence) — depends only on PR 4-5
- PR 11 (goal templates) — independent of everything else
- PR 12 (notification budget) — independent

So after PR 4-5 are merged, PRs 9-12 can be developed in parallel
streams if you have multiple sessions / agents.

## Estimated effort

Rough order of magnitude, assuming I'm doing the work in focused
sessions:

| PR | Code size | Test coverage | Sessions to land |
|---|---|---|---|
| 4 | Small | Solid | 1 |
| 5 | Medium | Solid | 1-2 |
| 6 | Large | Solid + UI tests | 2-3 |
| 7 | Medium | Heavy unit tests | 1-2 |
| 8 | Medium | Heavy unit + integration | 2 |
| 9 | Medium | Solid | 1-2 |
| 10 | Large (or 4 small) | Heavy unit | 2-3 (or 4×1) |
| 11 | Medium | Solid | 2 |
| 12 | Small | Solid | 1 |

Total: 13-18 focused sessions for the full roadmap. PRs 4-8 deliver
the headline weekly-coach experience and could ship in ~8-10 sessions.

## Minimum viable launch — if forced to cut

If you needed to ship "the weekly coach" with the smallest possible
scope:

1. PR 4 (plan history) — required infrastructure
2. PR 5 (data model) — required for the painter to mean anything
3. PR 6 (painted strip UI) — the headline feature
4. PR 8 (missed-workout autopilot) — the most user-noticeable smartness

Skip PR 7 (rules engine) at your peril — users can shoot themselves
in the foot without it, but the painted strip works without guardrails.
PR 9-12 are all valuable but defer-able.

## What to do next

1. **Read the spec** (`PLAN-weekly-coach.md`) and this roadmap. Push
   back on anything you don't like.
2. **Pick the starting point** — recommend PR 4 (plan history).
3. **Confirm or adjust the cadence** — sequential vs parallel; full
   scope vs minimum viable.

Then I'll start with the chosen PR.
