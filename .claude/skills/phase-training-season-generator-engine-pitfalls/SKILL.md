---
name: phase-training-season-generator-engine-pitfalls
description: >
  Six correctness pitfalls when implementing or debugging phase-training2's
  SportSeasonGenerator (the demand-weighted, fatigue-capped, deterministic §5
  engine) and its SeasonFidelityTest eval, including what breaks when slot
  allocation moves from per-session to per-week (signature coverage, rotation
  coverage, and a stale intended-vs-realized eval). Each one cost a test-failure→fix
  cycle building the skiing M1. Trigger when writing/editing SportSeasonGenerator
  slot allocation / fatigue cap / selection ranking, when a SeasonFidelity check
  fails (phase fidelity L1, fatigue ceiling, signature coverage), or when adding
  a sport/phase/variant to the season engine. Sibling to
  phase-training-season-aware-generator-reuse-map (which covers STARTING the
  build — what exists, the seam, the seed traps); this covers the ENGINE math.
when-to-use: implementing or debugging the SportSeasonGenerator demand-weighted engine + its fidelity eval
---

Verified building skiing M1 (2026-06-26). All four bit as real test failures, then fixed.

1. **Phase-fidelity can't be measured against the raw weight vector.** A K-slot
   session (4 in-season) cannot represent an 8-demand continuous target within
   L1 0.15 — the quantization floor for 4 slots vs in-season weights is ~0.60,
   not a defect. Fix: the eval asserts realized SLOT-demand mix vs the
   generator's OWN intended allocation (`intendedSlotDistribution(for:rule)` =
   normalized `allocateSlots`), within a small delta. That catches real pool
   coverage gaps without false-failing on slot math. Measure realized from the
   SLOT demand (parse it out of `provenance`), NOT the movement's primaryDemand —
   multi-demand movements differ.

2. **The fatigue cap can't trim when every movement is a sole demand-carrier.**
   An in-season 4-move session at 4+4+2+2=12 > cap 10 deadlocks if the cap
   protects "last carrier of every demand." Fix: protect only the SIGNATURE
   demand (eccentricLeg for ski), drop highest-fatigue otherwise, floor at 3
   movements. AND bias selection toward low fatigue in shedding phases so it
   rarely binds.

3. **Low-fatigue selection bias must key on `rule.deferToSport`, NOT progression
   mode.** eventPrep is a taper (shed fatigue) but its progression is
   `autoregulateHold` (shared with pre-season, which BUILDS). Keying low-fatigue
   on progression makes eventPrep pick heavy → blows its cap-14. `deferToSport`
   is true for exactly the shedding phases (in / transition / eventPrep) and
   false for building phases (off / pre).

4. **eventPrep has no movements of its own — draw the pre-season pool.** Tagging
   every seed row with `event_prep` is duplication; instead the generator maps
   `phase == .eventPrep → .preSeason` for the allowed-phase filter (eventPrep IS
   "pre-season tapered"). Without this, the eventPrep maxStrength slot can't fill
   (no maxStrength movement tagged event_prep) → realized drops a slot → fidelity
   drift exactly 0.40.

Plus the determinism trap: `allocateSlots` iterating a Swift `Dictionary` makes
tie-breaks non-deterministic across runs — sort demands by (weight desc, then
`rawValue`) so the fixed-seed promise holds. Pairs with
[[phase-training-season-aware-generator-reuse-map]].

## 5. A new generation input must be wired into `intendedSlotDistribution` too

Added 2026-08-26 (T2-7), and it cost a full diagnostic cycle.

`SeasonFidelityTest` check-1 compares REALIZED slot mix against
`SportSeasonGenerator.intendedSlotDistribution(for: rule)`. Both sides go
through `targetMovementCount`. So the check is only meaningful while both sides
size the session **from the same inputs**.

T2-7 wired the user's declared `sessionMinutes` into generation:

```swift
targetMovementCount(rule, preferredMinutes: athlete.preferredSessionMinutes)
```

…and left `intendedSlotDistribution` computing from `rule.sessionMinutesTarget
.upperBound`. The fixture athlete carries `TrainingMemory`'s default 45 min,
which clamps to the off-season band's lower bound 50 → **4** movements, while
"intended" still described a **6**-movement session. Check-1 drifted **0.50**
against a 0.20 bound, on 4 of 10 sport×phase cells.

That reads exactly like a pool-coverage regression — the assertion message even
says "pool coverage gap?" — but nothing about the pool changed. **The eval was
measuring a differently-sized session than the one generated.**

- Any parameter that reaches `targetMovementCount` or `allocateSlots` must be
  threaded into `intendedSlotDistribution` in the SAME commit, and the test must
  pass the fixture's actual value (not a literal).
- Symptom to recognize: drift jumps to a large round-ish number across MANY
  cells at once, including phases you didn't touch. A real pool gap hits the
  specific phase whose tags are thin (see pitfall 4's 0.40 eventPrep case).
- The general form: an oracle-free "intended vs realized" eval has two sides,
  and adding an input to one side silently invalidates the comparison. It is not
  a regression in the thing under test — it's the eval going stale.


## 6. Moving allocation from per-session to per-WEEK breaks two invariants at once

Added 2026-09-04 (T1-3). The change was right and it cost three test-fix cycles,
because two checks encode properties that per-session allocation satisfied by
accident.

The motivation: `allocateSlots(weights, count: target)` quantises at `1/target`.
With 5 slots, any demand under 0.20 rounds to zero in every session — for ski
off-season that silently deleted `power`, `legEndurance`, `prehab` and
`hipLateral`, the last two being what the phase's own "fix imbalances" objective
depends on. It also asked for the same top-K demands every session, which is why
a three-day week generated the same workout three times. `weekSlots` apportions
over `perSession * sessionsInWeek` and deals the flat list round-robin.

What breaks, in the order you will hit it:

- **check-2, signature coverage.** Dealing spreads the sport-defining demand
  (`eccentricLeg` for ski, `fingerStrength` for climbing) across the week, so
  some session gets none. Every session must carry it. `guaranteeSignature`
  takes the slot from the largest non-signature group, which means realized
  signature reads ABOVE target on purpose.
- **check-7, rotation preserves coverage.** This one only fires *because* the
  change worked. Once a 0.05 demand is reachable it gets one slot in the week,
  and the ski pool has exactly one `hipLateral`-primary movement; when that
  movement was recently used, the slot went to a movement that merely LISTS the
  demand. Fix is ordering inside the slot: **primary-demand match must outrank
  recency**. Rotation should vary which movement serves a demand, never whether
  it is served. Also fill scarcest-demand-first, so a one-candidate demand is
  not consumed by a six-candidate one.
- **check-1** goes stale exactly as pitfall 5 describes — confirmed again here.
  `intendedSlotDistribution` has to model `weekSlots` AND `guaranteeSignature`,
  which means summing per-session slots rather than apportioning once.

Read a check-2 or check-7 failure after an allocator change as the invariant
doing its job, not as a regression to suppress. Both named a real defect.

## 7. A duplicate exercise in a sport pool takes the whole test host down

Retiring `Step-Up with Pack` (622) and retargeting its ski row to `Loaded
Step-Up` (238) put 238 in the alpine-skiing pool twice. The generator builds
`Dictionary(uniqueKeysWithValues:)` over the pool, so the run did not fail
one test: `Swift/NativeDictionary.swift:792: Fatal error: Duplicate values
for key: '238'` killed the host three times (the runner restarts it), and
the summary read "1 failed" with the real damage in the crash lines.

- Grep the log for `Fatal error` next to `preflight checks`; both produce a
  low-assertion run that looks like infra.
- Before rebuilding coach.db after any retire-and-remap:
  `SELECT sport, exercise_id FROM sport_movements GROUP BY 1,2 HAVING COUNT(*)>1`.
- `test_pools_have_no_duplicate_exercise_ids` (SeasonFidelityTest) pins it.

## 8. A new Demand can carry weight the allocator never pays, and nothing fails

Adding `.upperStrength` to `PhaseRule.skiing` with 0.10 / 0.05 / 0.05 across
off / pre / in-season passed every test and realized in ONE of the three
phases. `/tmp/season-fidelity/report.md` is where it shows:

    | upperStrength | 0.10 | 0.07 |   off-season, fine
    | upperStrength | 0.05 | 0.00 |   pre-season
    | upperStrength | 0.05 | 0.00 |   in-season

Two independent causes, both in `allocateSlots`:

- **The remainder tie-break is alphabetical on `rawValue`.** Pre-season ties
  four demands at 0.05 with three remainder slots; `core`, `hipLateral`,
  `kneeStability` take them and `upperStrength` loses deterministically, every
  week. A demand whose name sorts late needs a weight that does not tie.
- **A weight below `1/weekSlots` floors to zero.** In-season is 2 sessions x 4
  slots; 0.05 x 8 = 0.4, and its remainder loses the ranking.

So the floor is `1/(perSession * sessionsInWeek)`, and at a tie the name
decides. Check a new demand against the phase's ACTUAL slot budget (read it off
the realized table: the fractions are n/weekSlots), not against intuition about
"5 percent".

The general gate this repo lacks: **every demand with a non-zero target must
realize at least one slot somewhere in the week.** Add it to SeasonFidelity and
this class stops shipping. Sibling of pitfall 5 (a new INPUT must be wired into
`intendedSlotDistribution`); this is a new OUTPUT category that is wired and
still inert, the DEAD-signal class from
[[phase-training-generator-eval-method-portfolio]].
