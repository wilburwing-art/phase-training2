---
name: phase-training-prescription-precedence-and-dual-path
description: How phase-training2's one lift prescriber (SportSeasonGenerator.prescribe) decides sets, reps, rest and RPE, in what order, and the dual-path rule for any per-exercise prescription fix. Order: cited protocol on the movement wins; else the slot's Demand band (DemandScheme) modulated by the phase progression, then experience and age (SetScheme.adjusted; the advanced +1 set only on main-lift demands), then the ramp week on anchor demands; the catalog's default_reps keeps its unit (seconds, feet, per side) through SetScheme.reps(forCatalog:); strategy and readiness scale sets after budget fitting. Dual path: planned days (generate), the general-fitness complement and the custom-day refresh (prescribeRefresh) all call prescribe, but the authored routines (AuthoredRoutine) serve their own written prescriptions, so a fix to prescribe does not reach an authored day. Trigger when editing prescribe, DemandScheme, SetScheme.adjusted or reps(forCatalog:), when a timed or hold movement shows a rep count, when a beginner gets RPE 8 or more, when an advanced athlete's accessory gains a set, or when adding any per-exercise prescription rule. Skip for exercise picking (accessory-layer-slug skill) or progression math (generator-context-dead skill).
---

# Prescription precedence and the dual path (phase-training2)

Every engine-built lift row is prescribed by `SportSeasonGenerator.prescribe`
(`PhaseTraining/Data/SportSeason/SportSeasonGenerator.swift`). The legacy
`WorkoutGenerator` prescriber was deleted in 11d 2.2.

## Precedence, later wins
1. `DemandScheme.scheme(for: demand, progression:, goal:)`: the slot's demand sets the band.
2. `SetScheme.adjusted(experience:age:mainLift:)`: beginner caps sets at 3 and RPE at 7 and
   floors low bands at 6; advanced adds one set only when `mainLift`; 60 and over adds 30 s rest
   and caps RPE at 8.
3. `ramped(weekOfCycle:)` on anchor demands when the caller passes a ramp week.
4. A cited protocol on the movement (`protocolSets`, `protocolReps`, `protocolRestSeconds`)
   replaces the scheme's numbers.
5. Reps: `scheme.reps(forCatalog:)` keeps the catalog's unit ("20-45 sec per side", "40-60 ft")
   and takes only the count from the band.
6. After budget fitting: `strategyScaledSets` (skipped for a cited protocol), then
   `readinessScaledSets`.

## Trap 1: main-lift is a property of the demand
`mainLift` is true for `maxStrength`, `upperStrength`, `pullStrength` and `legStrength` under a
progressive-overload phase. `prescribeRefresh` has no slot allocation, so it derives a demand from
the exercise's movement category (`refreshDemand`). Legs map to `legStrength` on every row, so it
passes `accessory: true` for an unseeded row past the lead compound to keep the advanced extra set
on the lead only (11d 2.8). Push and pull accessories need no flag: they map to `upperPush` and
`upperPull`.

## Trap 2: the dual path
Three callers share `prescribe`: the planned day, the general-fitness complement, and the
custom-day refresh (`WorkoutGenerator.represcribe` → `prescribeRefresh`). The authored routines
(`AuthoredRoutine`, routine_exercises rows) serve the program's own sets, reps and rest and never
call `prescribe`. A fix to the engine band does not reach an authored day, and a fix to authored
rest parsing does not reach an engine day. Before calling a prescription fix done, check which of
the two paths the symptom is on and whether the other needs the same fix.

## History
Before 449bd8d planned days went through a legacy prescriber whose focus bias overwrote
non-numeric catalog reps and whose experience switch clamped sets only. 449bd8d moved planned days
to the season engine and lost both fixes; a 4,958-week sweep on 2026-11-10 measured 5,465 of
51,991 rows with rep counts on timed work (`audits/2026-11-10-gap-round/generator.md`).
`reps(forCatalog:)` and `SetScheme.adjusted` restored them in the engine.
