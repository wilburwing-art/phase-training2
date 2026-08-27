---
name: phase-training-season-prescription-demand-scheme
description: How the ski/climb season engine decides sets/reps/rest/RPE/tempo in phase-training2 — a demand-keyed Swift SetScheme table (DemandScheme) modulated by the phase's ProgressionMode, NOT the movement's generic catalog default and NOT the dead per-movement default_scheme_by_phase seed. Verified 2026-06-27 building the demand-driven prescription on feat/season-aware-generator. Trigger when tuning ski/climb prescriptions, adding a Demand, asking "why does this movement prescribe these reps", or wiring prescription for a new sport in the season engine. Skip for the legacy WorkoutGenerator+Prescription path (nil-sport fallback only).
when-to-use: Changing or understanding how SportSeasonGenerator assigns sets/reps/rest/RPE/tempo for ski/climb, or extending it to a new sport/demand.
---

# Season-engine prescription = demand × phase (DemandScheme)

`SportSeasonGenerator.prescribe(_ m: SportMovement, demand: Demand, rule: PhaseRule)` keys off the
**demand the slot was allocated to** (each `Pick` carries its `.demand`), NOT the movement's catalog
default. Pipeline:

```
scheme = DemandScheme.scheme(for: demand, progression: rule.progression)
       = DemandScheme.base[demand].modulated(by: rule.progression)
emit GeneratedExercise(sets: scheme.setsMid, reps: scheme.repsString,
                       restSeconds: scheme.restSeconds, rpe: scheme.rpeString,
                       tempo: scheme.tempoString)
```

- **`DemandScheme.base: [Demand: SetScheme]`** (`Data/SportSeason/DemandScheme.swift`) — hand-tuned band
  per demand (all 15). Lives in Swift next to `PhaseRule`, same philosophy: edit a band, re-run
  `SeasonFidelityTest`, no DB rebuild. To tune ski/climb feel, edit THIS, not the seed.
- **`SetScheme.modulated(by: ProgressionMode)`** (`SportSeasonModels.swift`) — folds in what
  `progressedSets`+`rpe(for:)` used to do: PO/autoregulateHold = full dose; maintainMinimal = −1 set,
  RPE −1; deload = setsLow−1, RPE −2 (floored at 5). `PhaseRule.progression` supplies the mode.
- **`explosiveConcentric`** on `SetScheme` → `tempoString` emits `"2-0-X-0"` (power, contactStrength);
  `eccentricTempoSeconds` → `"4-0-1-0"` (eccentricLeg). `fatigueCost` for the volume cap comes from
  the **seed `SportMovement.fatigueCost`**, NOT `SetScheme.fatigueCost`.

## Traps
1. **`SetScheme` / `default_scheme_by_phase` was DEAD scaffolding.** The struct existed with a doc
   saying "decoded from the seed's default_scheme_by_phase" but the `sport_movements` table never had
   that column and the struct was never instantiated. Don't add a seed scheme column — the live design
   is the Swift `DemandScheme` table.
2. **`SportMovement` no longer carries `defaultSets/Reps/RestSeconds/Tempo`** — they were the generic
   catalog leak (a general-fitness number) and were removed from the model + the
   `CoachDatabase.sportMovements` join. Only `fatigueCost`, `isCompound`, `isUnilateral`, demands,
   phases, variants come from the join now.
3. **Adding a `Demand`?** add a `DemandScheme.base` row or it falls to `DemandScheme.fallback`
   (3×8-12). `SeasonFidelityTest.test_check8_prescription_tracks_demand` asserts the character
   (power/contact explosive + low reps, legEndurance/pullEndurance high reps, fingerStrength a hold).

Pairs with [[phase-training-season-engine-add-a-sport]] (the movement pool side) and
[[phase-training-delete-primaryfocus-goal-axis]] (the goal axis this replaced).
