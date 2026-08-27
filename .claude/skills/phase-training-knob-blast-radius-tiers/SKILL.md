---
name: phase-training-knob-blast-radius-tiers
description: >
  Classify a WorkoutGenerator input knob (TrainingMemory / GeneratorContext /
  GeneratorStrategy field) by expected BLAST RADIUS before deciding what the
  sweep harness should assert about it, whether a DEAD verdict is a bug, or
  whether the field should be deleted. Trigger when adding a new generator
  input field, triaging a DEAD/NO-OP flag from GeneratorSweepReportTest,
  asking "should this knob change the whole week or just part of it", or
  deciding whether stored-but-unread data is trend telemetry vs dead weight.
  Sibling to phase-training-generator-sweep-report (harness mechanics).
when-to-use: designing or triaging generator input knobs in phase-training-family repos
---

Five tiers, sorted by how much output a knob is ALLOWED to move:

1. **Structural** — reshapes the whole week. liftDaysPerWeek (split shape),
   primaryFocus (every slot's scheme + accessory layer), equipment (SQL pool),
   experience (clamps), sessionMinutes (downward only — slots are fixed, so
   raising the budget is a designed no-op). Sweep assertion: "live" suffices.
2. **Surgical** — touches a slice, on TWO independent axes:
   - *by row*: recentSoreAreas / injuries / dislikes / recentlyPicked should
     only perturb matching slots;
   - *by field*: intensityBias=.deload hits every row but should only move the
     SETS number; memory.soreness should only cap RPE + suppress warmups, not
     change selection (that's recentSoreAreas's job — distinct on purpose).
3. **Annotative** — notes/prescription text only, never selection/structure.
   priorBest ("target: X" notes), tempoOverrides, rpeOverrides.
4. **Trend-inert** — stored for trend screens / Planner, correctly DEAD in
   generateLift (lifetime peaks, muscle freshness, insights). DEAD ≠ bug here.
5. **Delete** — stored, consumed nowhere. Confirmed kills: muscleVolume (N2),
   patternFrequency (N8, deleted 2026-06-04).

## The two rules that came out of this

**Tier-leakage is invisible to the binary check — so the harness now asserts
ceilings.** BUILT 2026-06-06 in GeneratorSweepReportTest: `ChangeClass` enum
(none < notesOnly < prescription < selection < structure), each `Variant`
carries `maxScope`, `classify()` diffs field-by-field, and a SCOPE anomaly
fires when observed > allowed. First run immediately caught two stale
assumptions: (a) era cohort and age are .structure, NOT .selection —
`eraStyle.splitPreference` replaces the focus rotation at totalLifts>=3
(WG:72-78), flipping PPL→U/L and retitling days; (b) "raising sessionMinutes
above need is a no-op" was false — 60-min baseline already drops optional
slots, so 90/120 restore them (expectsChange is now `mins != baseline`).
Lesson: code-reading agents missed the splitPreference path; the run-time
scope check found it in one pass. Triage SCOPE flags as wrong-ceiling vs
real leak by tracing the generator line before touching either.

**DEAD in the generator is necessary but NOT sufficient for deletion.**
Grep ALL consumers (UI trend screens, eval-rig export, Planner) before
killing a field — that check is what separated tier 4 from tier 5 for N2/N8.
Open case: ReadinessEvent.duration (N3) is collected, consumed nowhere,
untriaged.
