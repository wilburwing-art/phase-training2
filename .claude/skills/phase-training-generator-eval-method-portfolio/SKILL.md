---
name: phase-training-generator-eval-method-portfolio
description: >
  Decide what generator-quality eval method to add NEXT (and how much to trust the
  existing sweep) for phase-training-family WorkoutGenerator work. Frames the OFAT
  controlled-variable sweep as ONE axis of three, names what it structurally can't
  catch, and ranks the complementary methods. Trigger when the user asks "is the
  sweep enough", "can I trust the sweep", "what eval method should I add", "what
  does the generator sweep miss", "how do I validate generator quality beyond the
  sweep", or critiques the harness/methodology itself. ALSO trigger before running
  or citing GeneratorSweepReportTest / GeneratorInvariantTest / the eval-rig — all
  three were DELETED in 449bd8d (2026-06-27) and the season engine, the only
  generator left, has no property-based or invariant coverage at all.
when-to-use: choosing the next generator-eval method or judging the sweep's limits — NOT building the sweep (see phase-training-generator-sweep-report for that)
---

The sweep (`GeneratorSweepReportTest` → `/tmp/generator-sweep/report.html`) is a
**sensitivity / wiring test**, not a quality test. Its `live`/`DEAD` verdict
answers only "does this knob change the output, and when I predicted it would?"

## The load-bearing epistemic: LIVE and DEAD are asymmetric
- **DEAD is strong + actionable** — a signal plumbed in code but inert in output
  is invisible in normal use (app still emits *a* workout, just unresponsive).
  This is the bug class nothing else catches (e.g. `patternFrequency`,
  `emphasizePatterns` inert at single-alternative slots).
- **LIVE is nearly free** — ≥1 variant moved ≥1 char. A knob can move output the
  WRONG direction / WRONG magnitude and still read LIVE. A wall of green is a
  FLOOR, not a grade. The `expectsChange` NO-OP/UNEXPECTED anomalies are what
  give LIVE rows teeth — they're where the information is.

## Three axes (the sweep is excellent on #1, silent on #2 and #3)
1. **Is it wired** — the sweep owns this.
2. **Is it right** — direction / magnitude / correctness. Unjudged by the machine.
3. **Does it hold up** — interactions, over weeks, across the population.

## What the sweep structurally CANNOT do
- Correctness/magnitude (LIVE ≠ correct). OFAT can't see interactions by
  construction (`readiness×deload` set-floor, `soreness×focus`). Tests
  `generateLift` in isolation — Planner orchestration (taper/deload/reshuffle/
  lift-day-floor) untouched. One week only (periodization is multi-week). Two
  baselines = thin population sample. coach.db taken as ground truth (bad data →
  bad workout, still reads LIVE). Everything is a delta off baseline — no
  absolute floor.

## ⚠️ The sweep and the invariant harness NO LONGER EXIST (verified 2026-09-03)

`449bd8d` (2026-06-27, "remove the legacy demographic selection engine +
eval-rig") deleted `GeneratorSweepReportTest.swift` (902 lines),
`GeneratorInvariantTest.swift` (312) and `EvalRigExportSmokeTest.swift` (426),
along with `scripts/generator-sweep.sh` and `EvalRigExporter.swift`. That was
correct — they tested the selection engine the same commit removed — but nothing
replaced them for the engine that survived.

**So everything above describes a harness you cannot run.** Read it as the design
to port from, not as available tooling. `git show --stat 449bd8d` recovers all
three files.

What DOES exist for the season engine: `SeasonFidelityTest` (18 assertions,
writes `/tmp/season-fidelity/report.md` with every session dumped — the fastest
way to get real output to grade). It is a fidelity test over 2 sports × 5
phases, not a property-based one. The injury-contraindication safety invariant
in particular has no successor, and a 2026-09-03 critique found a live
injury-filter hole on the authored-routine path that it would have caught.

**Check `git log --oneline --all -- '<path>'` before trusting any "BUILT" claim
in a skill.** A refactor that correctly deletes a harness leaves the skill
describing it, and the skill reads as current.

## Complementary methods, ranked by leverage
1. ❌ **Property-based / invariant fuzzing — BUILT 2026-06-04, DELETED 2026-06-27**,
   see [[phase-training-generator-invariant-metamorphic-test]]
   (`GeneratorInvariantTest.swift`, Parts A + C): must-hold-for-all-inputs over a
   486-cell grid (sets ∈ [1,8]; no empty day; no dup; non-empty reps; dislikes
   never leak), PLUS the injury-contraindication safety invariant (coach.db
   differential probe) and two named pairwise interaction cells
   (`readiness×deload`, `soreness×focus`). Fuzzing the whole vector at once is
   the only cheap attack on the OFAT gap. **Highest-value thing to port back.**
2. ❌ **Metamorphic assertions — BUILT 2026-06-04, DELETED 2026-06-27** (same file,
   Part B): the expected-direction rubric as CI gates (deload≤normal≤push;
   readiness 0≤.5≤1; beginner≤inter≤adv; age70≤age32; shorter budget never adds).
   Non-strict so sparse cells don't flake. Note deload≤normal is now false by
   construction: `weekNumber` reaches only the seed string, so a deload week
   carries the same prescription.
3. **LLM-coach grader** (`PLAN-eval-rig-adapter.md` is ALSO gone — spec survives
   only in `eval-rig-close-the-loop-workflow`) — the absolute-quality complement. Keep the
   two-loop split: sweep = fast/deterministic inner, grader = slow/noisy batch.
   Don't let the noisy grader into the inner loop.
4. **Pairwise covering-array sweep** — 2-way over named high-risk pairs; in-framework.
5. **Longitudinal mesocycle sim** — N weeks w/ feedback; only method that tests the
   Planner + periodization thesis. Heavier.
6. **Real-data backtest** — vs the ~5,440-set Fitbod history in `workout-plan`. The
   only non-proxy; north star, not next sprint.

Pairs with [[phase-training-generator-sweep-report]] (build/use the sweep),
[[phase-training-generator-context-dead-and-broken-signals]] (what DEAD means),
[[eval-rig-close-the-loop-workflow]] (the long loop).

## The OFAT gap is not theoretical: it hid a 17.5% defect (2026-09-05)

This skill has said since it was written that "OFAT can't see interactions by
construction". Here is the bill for it.

Two filters shipped two days apart, each with its own test that switched the
other OFF:

- `testAuthoredPathNeverServesEquipmentTheUserLacks` — gear tiers, **no injuries**
- `testInjuryFilterNeverLeavesASessionUnderTheMovementFloor` — injuries, **all `.fullGym`**
- `SeasonInvariantTests`'s 10-sport grid — equipment dimension, **no injury dimension at all**

So the user who declares both (bodyweight only AND a bad knee, an ordinary
person) was exercised by nothing. `FilterCompositionTests` walks the cross
product -- 8 sports x 5 injuries x 3 equipment tiers x 5 phases x 3 slots,
1,800 days -- and **315 failed on the first run**, all of them the Easy
Strength last resort served at one or two movements while still titled
"Easy Strength — 5-Lift Base". Zero failures under `.fullGym`, which is
exactly why every existing test passed.

**Assert the whole contract in one place** rather than one property per test:
either a session at or above the movement floor with nothing contraindicated
and no gear the user lacks, or an empty day the app DECLARES (a known
provenance plus a non-empty summary). A silent empty then cannot pass as "not
applicable", which is how the previous floor test lost the same case.

Cheap rule: **when a second guard lands on a path that already has one, the
next test is their cross product, not another single-factor test.**

### The stale-decision half

The cause was a comment that was right when written: the last resort skipped
the viability filter because "serving what remained beat serving nothing". True
until R2-05 added an honest nothing (`authored-no-fit`, which names the reason
and points at Profile), after which it was simply wrong. **A decision comment
justified by the absence of an option needs re-reading when someone adds that
option.** Grep for "beats nothing", "better than empty", "rather than fail" in
a path you are about to extend.
