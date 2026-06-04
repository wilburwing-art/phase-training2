# PRD — Adaptive Week (cofounder vision)

Status: open questions resolved 2026-06-04; D1–D4 scoped for build.
Source: cofounder voice memo, captured 2026-06-03.
Pairs with: `PLAN-weekly-coach.md` (locked design spec) and
`PLAN-weekly-coach-roadmap.md` (PR sequence).

Note on current state (2026-06-04): the roadmap docs predate the code.
The foundation data layer is already on `main` — `WeekPlanSnapshot` +
`WeekShape` (PlanHistory.swift), `LiftFocus` / `WeekTone` / `WeekEvent` /
`DayKindOverride` (WeekOverrides.swift), the `PlanValidator` engine, and
`MissedWorkoutAutopilot`. The deltas below build on existing code, not
future PRs. The genuinely-unbuilt surface is the painted-strip UI
(`PaintedStripView`) plus D1–D4. A full doc-vs-code reconciliation of
§3/§5 is deferred to a separate pass.

## 1. The vision, in one paragraph

The app should adapt to your actual week instead of assuming an ideal
one. Sunday, it pings you and asks what your week looks like and how
many days you can train; you answer right from the notification, and it
builds the week from that answer plus your history and your profile
goal. During the week, if you miss a workout, it notices, asks you
about it, and offers a choice: keep the workout and reshuffle, or
consolidate the week (e.g. 3 lift days become 2, push/pull/legs merges
into legs+push and push+pull). And underneath all of it, the workouts
themselves need to be better.

## 2. Tangible goals

| # | Goal | Measurable when |
|---|---|---|
| G1 | Sunday check-in exists and drives the plan | User receives Sunday push; their response (in-notification or in-app) produces next week's plan |
| G2 | Plan generation uses history + profile goal | Generated week demonstrably differs based on prior weeks' actuals and the profile intention |
| G3 | Missed workouts are noticed and surfaced | Next-morning push fires when a planned lift passed with no session logged |
| G4 | Missed-workout response is a conversation, not a fait accompli | User can confirm the miss and choose: reschedule the workout vs consolidate the week |
| G5 | Consolidation produces a sane split | 3-day PPL collapsing to 2 days yields a best-practice merge (legs+push / push+pull), not a dropped body part |
| G6 | Workouts are "better" = better session structure (decided Q1) | A generated day contains ≥1 superset pairing where appropriate and follows a descending rep-band curve (heavy compound → moderate accessory → high-rep finisher), matching bundled-routine structure |

## 3. What's actually built (reconciled 2026-06-04)

Audited against `main`. The roadmap (`PLAN-weekly-coach-roadmap.md`)
sequenced this as PRs 4–12 and claimed none were open — but the data
layer and most engines already shipped. Status of each roadmap PR:

| PR | Scope | Status | Evidence |
|---|---|---|---|
| 4 | Plan history (`WeekPlanSnapshot`) | ✅ done + wired | `PlanHistory.swift`; `PlanStore.pastPlans` (12-wk cap, snapshot on `setPlan` + rollover); `CoachContext` reads history |
| 5 | Intent data model + planner support | ✅ done + wired | `WeekOverrides.swift` (`LiftFocus`/`WeekTone`/`WeekEvent`/`outOfTown`); `Planner` reads `weekTone` (L189), per-day `focus` (L360–377), `outOfTown`→bodyweight template (L433–454) |
| 6 | **Painted strip UI** | ⚠️ not as specced | No `PaintedStripView`. Equivalent function is spread across `WeekScreen` (563 L), `WeekDayEditSheet` (860 L), and the 6-screen `WeeklyCheckIn/` flow. The single painted-strip component is the real UI gap. |
| 7 | Rules engine + pushback | ✅ done + wired | `PlanValidator.swift` (6 rules), `WeeklyPlanOverride.swift`, `PlanValidationBanner.swift`; `PlanStore` persists overrides + self-suppresses after 3 dismissals |
| 8 | Missed-workout autopilot | ✅ done + wired | `MissedWorkoutAutopilot.swift`, `MissedWorkoutEntry.swift`, `MissedWorkoutBanner.swift`, `TodayScreen` accept path, 2-reshuffle cap in `PlanStore` |
| 9 | Abandoned workout state | ❌ not built | no `AbandonedWorkoutEntry` / `AbandonReason` |
| 10 | Planner intelligence | ◑ partial, inline | None of the 4 named engines exist. But `MesocycleProgression.swift` does 4-wk deload cycles (≈10A) and `WorkoutGenerator` does prior-best +2.5% targets + stagnation swap + readiness volume floor (≈10B core). Autoregulation-by-completion-ratio (10B), CNS reordering (10C), skip-streak (10D) are missing. |
| 11 | Goal templates | ❌ not built | no `GoalTemplate` / `UserGoal` |
| 12 | Notification budget | ❌ not built | no `NotificationBudget`; all pushes are tap-to-open |

Goal mapping: **G2** fully covered (PR 4+5). **G3** + G5-machinery covered
(PR 8). **G1** partial (push fires, but the strip + day-count capture are
the gap, see D1). **G6** unaddressed in the session-structure sense decided
in §6/D4 (progression exists; session structure does not).

## 4. Deltas — what the vision adds that the spec does not have

These are the new asks. Each needs a decision before implementation.

### D1 — Reply to the notification itself

Vision: "you should respond to that notification with what your week
looks like."

Code today: every notification is tap-to-open — no `UNNotificationCategory`
or `UNNotificationAction` exists (`WeeklyReminderScheduler`,
`InactivityReminderScheduler`, `NotificationDelegate`). The deep-link
scheme (`phasetraining://plan-week`) takes no parameters. The check-in
also has no "how many days" input today — it captures *which* days
(toggle chips) and *why* (intent), not a day count.

**Decided (Q2): quick-action buttons only for v1; free-text deferred.**

Free-text is out for v1: notification action responses are
fire-and-forget, so a reply like "traveling Wed-Fri, 2 days" can't
round-trip through the coach LLM to be parsed — that parser is net-new
and HIGH effort for a marginal win, since the user lands in the app
anyway. Scope:

- **Sunday push**: `UNNotificationAction` quick actions for day count
  ("Same as usual", "2 days", "3 days", "4 days", "Open to edit").
  Tapping one deep-links into the strip pre-seeded with that day count
  (new query param on the scheme, e.g. `?days=3`); day *placement* still
  happens in the strip in-app.
- **Missed-workout push**: quick actions "Yep, missed it" /
  "I actually did it" / "Open". Confirming the miss advances to D2.

Scope note: notification replies feed the same data the strip captures.
The strip remains the source of truth; the notification is a fast path
into it, not a second planner input. Free-text reply is a v1.1 candidate
only if buttons prove too coarse.

### D2 — Consultative miss flow (choice, not autopilot)

Vision: app asks "do you still want to do that workout, or consolidate
the week to 2 days instead of 3?" and rebuilds from the answer.

Code today: not silent autopilot — `MissedWorkoutBanner` already shows
the missed day with Accept / Skip / "See changes"
(`TodayScreen.acceptMissedReshuffle`). But it pre-computes exactly *one*
reshuffle and Accept applies it; there is no choice and no consolidation
path.

**Decided (Q3): ask-first with a real choice; banner persists if no
reply — no silent end-of-day autopilot.**

Rationale: a silent end-of-day reshuffle (the original proposal)
contradicts G4 — restructuring someone's week while they aren't looking
is the fait accompli the vision rejects. So when a miss is confirmed,
present:

1. **Keep it** — reshuffle per existing §3 rules.
2. **Consolidate** — re-plan remaining days at N-1 (D3). **Shown only
   when reshuffle can't find a clean slot** — see Q4 / D3.

If the user never responds, the banner simply persists into the next
day; the plan is not mutated silently. The 2-reshuffle cap applies to
the reshuffle path; consolidation has its own cap (D3).

### D3 — Consolidation engine

Vision: 3-day PPL with one day gone becomes a 2-day week, e.g.
legs+push one day, push+pull the other.

Code today: no consolidation/merge logic exists anywhere.
`MissedWorkoutAutopilot.proposeReshuffle()` returns `[]` when the week
is full (≥4 lifts), there's no valid rest day, or the budget is spent;
`Planner` has no path to re-plan at N-1 days mid-week. That empty-return
is the natural trigger hook.

**Decided (Q4): consolidation is the escalation path — offered only when
reshuffle finds no clean slot.**

Distinguish the empty-return reasons: the *week-full / no-valid-rest-day*
case is where consolidation earns its place; the *budget-exhausted* case
does not auto-offer it (the user already reshuffled twice this week).
Offering "collapse your week to 2 days" on every miss is decision
fatigue — most misses just want a bump to tomorrow.

Proposal: a `consolidate(week:remainingDays:)` planner path that
re-plans the rest of the week at N-1 days using best-practice merges:

| Original split | 2-day merge |
|---|---|
| Push / Pull / Legs | Legs + Push, Push-accessory + Pull |
| Upper / Lower / Full | Full, Upper-biased Full |
| 4-day U/L | Upper, Lower (drop the repeats, keep volume per pattern) |

Rules: preserve weekly coverage of every pattern the original week had,
respect CNS budgeting (no two merged heavy days back to back), trim
accessory volume before compound volume. Consolidation has its **own
weekly cap (1/week)**, separate from the 2-reshuffle budget, since it's
a bigger structural change.

### D4 — "Workouts need to be better"

**Decided (Q1): "better workouts" = better session structure.**

Why not progression: it's already ~80% built. The generator does
prior-best +2.5% targets, stagnation swaps, readiness volume floors,
recent-signal day trims, and a 4-week mesocycle deload
(`WorkoutGenerator.swift`, `MesocycleProgression.swift`, `Planner.swift`).
Picking progression as the answer to G6 buys little.

The real gap: the generator emits a **flat list** of exercises — no
supersets, no within-day intensity curve, no finishers — even though
`LoggedExercise` already carries `supersetGroup` and the bundled routines
already use `exercise_superset_pairs`. The data model supports structure;
the generator ignores it.

Status (2026-06-04): **supersets shipped.**
`WorkoutGenerator.assignAntagonistSupersets` pairs antagonist movements
(push↔pull, extension↔flexion) among non-primary picks; the top heavy
compound stays solo; single-emphasis days correctly get none.
`GeneratedExercise.supersetGroup` now propagates through
`toWorkoutTemplate` → `ExerciseTemplate` → `LoggedExercise`. Covered by 5
tests in `WorkoutGeneratorTests`.

Rep-band curve + finisher: **deprioritized** after an eval-rig baseline of
the non-anchor archetypes (lower/pull). Coverage (Q2) + order (Q4) already
pass, and no rubric question grades a rep-band curve — so Part B isn't
measurable without authoring one (`eval-rig-author-new-archetype-rubric`).
The baseline's *actual* finding was **Q7 (rest differentiation)**: secondary
compounds rested like isolations (60s). Fixed in `WorkoutGenerator` —
non-primary compounds are lifted to the focus's primary-rest tier — taking
lower + pull from 7→8/9, anchor maintained. The export harness also had to
be corrected: the age-derived era `splitPreference` was hijacking the
`liftIndex`→focus mapping, so non-anchor exports were mislabeled.

Scope (measurable per G6):

- **Supersets/pairing** — ✅ done (see status above). `WorkoutGenerator`
  emits superset groups for antagonist patterns instead of unpaired
  singles, reusing the existing `supersetGroup` field.
- **Within-day rep-band curve** — a descending intensity arc across the
  day: heavy compound (low reps) → moderate accessory → high-rep
  finisher, rather than one focus-wide scheme applied to every exercise.
- **Finisher** — a terminal high-rep/isolation slot where the focus
  warrants it (generalize the current hypertrophy-only isolation append).

Out of scope for this delta: exercise-selection variety (already has
soft-filter + pattern-frequency reorder + staple bias) and per-goal
sub-tuning/tempo (coarse today but lower-visibility — a later G6.x).

## 5. Delivery plan (reconciled 2026-06-04)

PRs 4, 5, 7, 8 are done; PR 6 (the painted strip) is the only unbuilt
foundation; PRs 9–12 are unbuilt. The deltas no longer "slot into a
future roadmap" — they extend shipped code. Recommended order:

| Step | What | Builds on | Notes |
|---|---|---|---|
| 1 | **D4 — session structure** in `WorkoutGenerator` (supersets ✅ + rep-band curve + finisher) | PR 5 (done) | supersets shipped 2026-06-04 + tested; rep-band curve + finisher remain |
| 2 | **D3 — consolidation engine** (`consolidate(week:remainingDays:)`, own 1/wk cap) | PR 8 (done) | pure Swift; hooks the existing empty-reshuffle return |
| 3 | **D2 — consultative miss flow** (reshuffle-vs-consolidate choice; banner persists) | step 2, `MissedWorkoutBanner` (done) | extends existing banner; no silent autopilot |
| 4 | **PR 6 — painted strip UI** (remaining foundation) | PR 5 (done) | largest UI lift; D1 seeds into it |
| 5 | **PR 12 — notification budget** | independent | land before D1 (Sunday push gets chattier) |
| 6 | **D1 — Sunday + miss push quick actions** (buttons only) | PR 6, PR 12 | `UNNotificationAction` + `?days=N` deep-link param |

PRs 9 (abandon), 10 (remaining autoregulation/CNS/skip-streak), 11 (goals)
are independent and unscheduled here. D4 leads because it's the highest-
leverage self-contained win and needs nothing unbuilt.

## 6. Decisions (resolved 2026-06-04)

All four resolved against the actual codebase state, not the stale docs.

1. **"Better workouts" = session structure.** Supersets/pairing +
   within-day rep-band curve + finishers (D4). Not progression — that's
   already ~80% built. G6 is now measurable (see §2).
2. **Notification reply depth: quick-action buttons only for v1.**
   Day-count buttons that deep-link into the strip; free-text deferred
   to v1.1 because fire-and-forget notification replies can't round-trip
   the LLM parser (D1).
3. **Autopilot vs ask: ask-first, banner persists if no reply.** No
   silent end-of-day autopilot — it would contradict G4. Offer a real
   choice when a miss is confirmed (D2).
4. **Consolidation trigger: only when reshuffle finds no clean slot.**
   Escalation path hooked to the existing empty-reshuffle return; own
   weekly cap, separate from the 2-reshuffle budget (D3, D4).

## 7. Out of scope (already deferred in the locked spec)

Per-day duration sliders, saved-routine picker in the strip, visible
periodization blocks, HealthKit/HRV, calendar integration, coach tone
settings, quiet-hours customization (all spec §12).
