---
name: phase-training-prescription-precedence-and-dual-path
description: Two precedence traps in phase-training2's WorkoutGenerator.prescription() + the dual-path rule for any per-exercise generator fix. (1) **focusBias clobbers coach.db default_reps**: prescription computes focusBias(primaryFocus) FIRST; if non-nil (every focus except mobility) reps = bias.reps, which OVERRIDES exercise.defaultReps — the defaultReps/formula branch only runs when bias is nil. Then for hypertrophy the era repRangeBias overrides AGAIN. So 71 catalog exercises that store a TIME/DISTANCE/HOLD string in default_reps ("30-60 sec", "40-60 ft", "5-10 sec hold") get turned into rep counts ("8-15"). Fix: preserve non-numeric default_reps over the bias/era band via isNumericRepBand BEFORE the era branch. (2) **experience clamps SETS only**: the switch on memory.experience caps sets (beginner min 3 / intermediate min 4 / advanced uncapped) but reps and RPE are NOT experience-modulated, so a beginner gets the focus's full near-max scheme (RPE 8-9, 3-5 reps). (3) **DUAL-PATH rule**: the hypertrophy accessory layer is a SEPARATE prescribe path (appendHypertrophy*Accessories → pickAccessoryByName → makeAccessoryRow, which calls prescription with focus:.push) — any prescription/filter/scaling fix applied to the main slot loop must ALSO be applied to the accessory path, or it leaks there. Same for dislike-by-equipment: matched name-only in BOTH CoachDatabase.exercises() AND pickAccessoryByName. Trigger when editing prescription / focusBias / rpeTempoHints, when an isometric/carry shows a rep count, when a beginner gets RPE 8-9 or sub-6-rep work, when a dislike ('machine'/'cable') doesn't filter an exercise, when a grafted/appended/consolidated-merged-day compound is loaded as an accessory (no warm-up ramp, fewer sets — Trap 4), or when adding any per-exercise rule to the generator. Skip for the accessory PICK logic (accessory-layer-slug skill) or dead signals / sore filter / progression math (generator-context-dead skill).
---

# Prescription precedence + dual-path (phase-training2)

`WorkoutGenerator.prescription()` decides reps in this order — later wins:

```
focusBias(primaryFocus)  → if non-nil, reps = bias.reps        (overrides default_reps)
  else                   → exercise.defaultReps ?? formula     (ONLY when bias is nil = mobility)
era repRangeBias         → if hypertrophy + eraStyle, overrides reps AGAIN
```

## Trap 1 — bias clobbers non-numeric default_reps
71 exercises store a non-rep prescription in `default_reps`: time (`30-60 sec`),
distance (`40-60 ft`), holds (`5-10 sec hold`). The bias/era band overwrites all
of them → "isometrics/carries prescribed in reps". Fix (shipped, commit b9c4527):

```swift
let exerciseReps = exercise.defaultReps?.trimmingCharacters(in: .whitespaces).nilIfEmpty
if let exerciseReps, !isNumericRepBand(exerciseReps) { finalReps = exerciseReps }   // preserve
else if eraStyle/hypertrophy { ... } else { finalReps = reps }
// isNumericRepBand = matches ^\d+(\s*-\s*\d+)?$  → "5","6-12" numeric; "30-60 sec" not
```
NOTE: ~5 more exercises store the time only in `default_duration` with NULL
`default_reps` (Tuck Hold). `exercises()` already SELECTs `e.default_duration`,
so the model loads it — preserving those is a small follow-up.

## Trap 2 — experience clamps sets, not reps/RPE
The `switch memory.experience` only does `sets = min(sets, 3/4)`; reps + RPE come
straight from focusBias unmodulated. Beginner guardrail (commit ec361b5): cap RPE
≤7 in rpeTempoHints (extracted `capRPE` from `capCompoundRPE`) + floor numeric
bands <6 to 6-8 in prescription. (Floor 6 also bumps novice 5×5 → 6-8; drop to 5
to preserve 5×5.)

## Trap 4 — isPrimary / warm-up key on slotIdx==0 ONLY (appended slots = accessory)
`prescription` sets `isPrimary = slotIdx == 0`, and the warm-up ramp fires only
for `slotIdx == 0 && isCompound`. So ONLY the first slot gets primary-compound
loading (e.g. generalStrength 5×5) + a ramp; any slot APPENDED after the focus
recipe is loaded as an accessory even when it's a heavy compound. D3 instance
(review 2026-06-04): `generateConsolidated` grafts the secondary focus's lead
compound as `extraSlots` → `(focus.slots + extraSlots).enumerated()` (WG:~159),
so a squat merged onto a push day lands at slotIdx>0 → 3×6-8 + no warm-up ramp,
not 5×5. The merged day keeps the compound MOVEMENT, not its LOADING — defensible
for a consolidation rescue, but unstated. If a grafted compound should carry
compound loading, prescribe slot 0 by focus or special-case the graft.

## Trap 3 — DUAL PATH: fix the accessory layer too
The hypertrophy accessory layer re-prescribes through `makeAccessoryRow` and
re-filters through `pickAccessoryByName` — a parallel path that does NOT inherit
the main loop's `context`/`excludeKws`/scaling. Every per-exercise fix lands in
two places. Examples this session: readiness/deload/sore/dislike/budget (T0.1,
commit aaf8cb9) and equipment-dislike matching (T1.7, commit 5a591f1) both had to
be added to `pickAccessoryByName` separately. Before declaring a generator fix
done, grep for a second prescribe/filter path and apply it there.
