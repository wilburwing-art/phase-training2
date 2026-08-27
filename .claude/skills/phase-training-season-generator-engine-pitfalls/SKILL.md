---
name: phase-training-season-generator-engine-pitfalls
description: >
  Four correctness pitfalls when implementing or debugging phase-training2's
  SportSeasonGenerator (the demand-weighted, fatigue-capped, deterministic §5
  engine) and its SeasonFidelityTest eval. Each one cost a test-failure→fix
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

