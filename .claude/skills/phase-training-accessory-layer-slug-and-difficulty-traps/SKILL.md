---
name: phase-training-accessory-layer-slug-and-difficulty-traps
description: Two non-obvious gotchas when extending `WorkoutGenerator.swift`'s hypertrophy accessory-layer system (upper-push, lower-body, pull). (1) **Muscle-group vs muscle-component slug mismatch**: `existingMuscles.contains("calves")` misses Standing Calf Raise because coach.db tags its primaries as `["gastrocnemius", "soleus"]` (the components) not `"calves"` (the parent group). Result: accessory layer double-appends a redundant calf isolation slot. Same trap for quadriceps (vastus-lateralis/medialis/intermedius), glutes (glute-max/med/min). Fix: `existingMuscles.isDisjoint(with: ["calves", "gastrocnemius", "soleus"])`. (2) **Difficulty-bucket gating excludes canonical lower-difficulty staples**: `pickForSlot`'s per-bucket loop tries `profile.preferredDifficulties` one bucket at a time. An intermediate user's "intermediate" bucket may have ONLY sport-flavored alternatives (Jump Rope Double-Unders, Single-Leg Calf Raise Eccentric) while the canonical Standing Calf Raise sits in the "beginner" bucket — never reached. Fix: add a staples-across-all-allowed-difficulties pre-pass that queries with `Set(profile.preferredDifficulties)` (the full allowed set) and filters to staples BEFORE the per-bucket loop runs. (3) **Parallel-path filter bypass**: the accessory layer is appended AFTER the main slot loop (`WG:287-332`) via its own `appendHypertrophy*Accessories`→`pickAccessoryByName`→`makeAccessoryRow` path that is never passed `context` and never multiplies by `combinedSetsMul`. So it BYPASSES readiness set-scaling, deload multiplier, sore exclusion (`context.recentSoreAreas`), dislike keywords (`excludeKws`), and the duration budget — but DOES respect injury + env/equipment (inherits `pickedIds`). Fix = thread `context`+`excludeKws` in, apply the sore filter, scale `makeAccessoryRow` sets by `combinedSetsMul`, gate the append on budget. Trigger when adding `appendHypertrophyXAccessories` for a new focus (push pull legs lower upper), when an export shows weird picks (sport-flavored variants on a canonical slot, double-appended muscle isolation), when debugging "soreness/deload/readiness/dislike didn't change the accessory volume", or when extending the accessory layer's `existingMuscles.contains(...)` check to a new muscle group. Skip when adding a new pattern with no muscle-group/component split (e.g. biceps, traps — those use a single slug).
---

# Phase-training2 accessory + picker gotchas

## Trap 1 — muscle group ≠ muscle component slug

coach.db's `muscle_groups` table stores BOTH the parent group ("calves") AND each component ("gastrocnemius", "soleus") as separate slug rows. Different exercises tag at different levels:

```
Standing Calf Raise (112)       → primaries: gastrocnemius, soleus
Lying Leg Curl (934)            → primaries: hamstrings  ← single slug
```

So `existingMuscles.contains("calves")` after the picker filled a calf-raise slot returns `false` — the accessory layer thinks calves isn't covered yet and appends Standing Calf Raise, producing a duplicate.

Fix: use `isDisjoint(with:)` against the full slug family.

Same trap looms for:
- quadriceps vs vastus-lateralis / vastus-medialis / vastus-intermedius / rectus-femoris
- glutes vs glute-max / glute-med / glute-min
- triceps usually safe (single slug) but check coach.db before assuming

## Trap 2 — staples lower-difficulty than user's bucket

`pickForSlot` iterates `profile.preferredDifficulties` in order. For an intermediate user, that's `["intermediate", "beginner"]`. The first bucket query (intermediate-only) returns candidates, the staple filter runs, and a pick is made — the beginner bucket is never tried.

If the canonical staple is tagged "beginner" in coach.db (true for Standing Calf Raise, Seated Calf Raise, many foundational lifts), the intermediate bucket only has sport-flavored intermediate-tagged variants. Staple filter returns empty → no narrowing → random pick lands on Jump Rope Double-Unders or similar.

Fix (in `pickForSlot`, before the per-bucket loop):

```swift
let staplesPool = CoachDatabase.shared.exercises(
    matchingPattern: pattern,
    difficulties: Set(profile.preferredDifficulties),  // full allowed set
    environments: envs,
    // ... rest of constraints
).filter { ExerciseStaples.isStaple(name: $0.name, forPattern: pattern) }
if !staplesPool.isEmpty,
   let pick = deterministicPick(from: applyVariety(applySoreFilter(staplesPool)), ...) {
    return pick
}
// fall through to per-bucket loop
```

**Critical**: keep the `difficulties: Set(profile.preferredDifficulties)` constraint. Removing it makes a beginner get Explosive Pull-Up (advanced) — `PlannerTests.testBeginnerGeneratedExercisesRespectDifficulty` catches the regression.
