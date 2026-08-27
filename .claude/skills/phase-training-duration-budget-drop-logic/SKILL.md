---
name: phase-training-duration-budget-drop-logic
description: Four non-obvious invariants in WorkoutGenerator.swift's duration-budgeting / optional-slot-drop logic (phase-training2 iOS). (1) The budget check and running total BOTH use baseSets/baseDurSec — the PRE-readiness/intensity-multiplier figures — not the scaled `sets`. This is deliberate (build 97): a deload shrinks volume within a fixed movement list, never frees time to pack in MORE accessories. (2) The hypertrophy accessory layer (appendHypertrophyUpperPush/LowerBodyAccessories) runs AFTER the main slot loop and BYPASSES the budget entirely — it appends unconditionally, so a hypertrophy session can finish over its duration cap. (3) Optional-slot dropping is purely POSITIONAL — later recipe slots lose first, there's no priority sort, so a high-value optional placed after a low-value one gets cut first. (4) The 5-min warmupBufferSec is subtracted from the budget but never added back to elapsedSec, so estimatedMinutes excludes warmup (real wall-clock ≈ estMin + 5). Trigger when editing the per-slot drop loop, changing how sessionMinutes maps to exercise count, adding budget awareness to the accessory layer, debugging "why did my workout lose/keep exercise X", or "why is the estimated time off". Skip for the exercise-PICKING filters (use the accessory-layer-slug skill) or prescription tables.
---

# Duration-budget drop logic — WorkoutGenerator.swift

Core loop `generate()` ~line 87-306. Constants: `warmupBufferSec = 5*60` (~1095); 45s/set + 30s/exercise baked into the formula.

## Budget setup (~100-104)
```
effectiveMinutes = strategy.durationMinutes (clamped [15,180]) ?? memory.sessionMinutes
budgetSec        = max(15*60, effectiveMinutes*60 - warmupBufferSec)   // floor 900s
```

## The drop gate (~176) — THREE conjuncts, all required
```swift
if elapsedSec + baseDurSec > budgetSec, slot.optional, !picks.isEmpty { continue }
```
- Required slots (primary compound + main movements) are NEVER dropped, even over budget.
- First pick always kept (`!picks.isEmpty`) — never an empty workout.

## The four gotchas

1. **Pre-multiplier budgeting (build 97 fix, ~167-171, 236-240).** `baseDurSec = baseSets*(45+restSec)+30` uses `baseSets`, NOT the readiness/intensity-scaled `sets` from ~165. Both the gate and `elapsedSec += baseDurSec` use base figures. Reason: deload = fewer sets across the SAME list, not a longer list. If you "fix" this to use scaled sets, deload days will silently grow extra accessories — the exact bug build 97 closed.

2. **Accessory layer bypasses the budget (~259-288).** `appendHypertrophy{UpperPush,LowerBody}Accessories` run after the slot loop and append unconditionally — `elapsedSec += ex.durSec` accrues but there's NO budget gate. Hypertrophy sessions can exceed their cap. Intentional: the rubric requirement to have isolation work wins over the time cap.

3. **Drop is positional, not priority-based.** The loop walks `focus.slots` in recipe order; the first optionals to bust the budget get cut — regardless of value. A hamstring curl placed after a calf raise drops first just by being later. To change: sort optionals by priority before the budget walk.

4. **estMin excludes warmup (~290).** `estMin = max(1, round(elapsedSec/60))`. The 5-min buffer was subtracted from budget but never added to elapsedSec, so displayed `~N min` is working time only; real ≈ estMin + 5.
