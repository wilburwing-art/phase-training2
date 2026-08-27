---
name: phase-training-staples-broad-vs-canonical
description: When a phase-training-family workout generator export grades well structurally (9/9 on the eval-rig rubric) but the actual exercise picks look weird to a human eye (Single-Leg Deadlift (Backpack) instead of Romanian Deadlift, Jumping Switch Lunge (TKD Power) instead of Walking Lunge, Single-Leg Calf Raise (Eccentric, Loaded) instead of Standing Calf Raise), the fix is in `PhaseTraining/Data/ExerciseStaples.swift`'s `keywordsByPattern` — NOT in the rubric, the accessory layer, or coach.db. The bug pattern is bare movement-name keywords (`"deadlift"`, `"lunge"`, `"calf raise"`) that substring-match canonical AND sport-flavored variants equally, so the staple-preference filter sees the weird variant as "a staple" and picks it. Tighten by replacing bare names with canonical bilateral fragments (`"romanian deadlift"`, `"conventional deadlift"`, `"walking lunge"`, `"reverse lunge"`, `"standing calf raise"`, `"seated calf raise"`). Trigger when the user says "the workout picks look weird" / "why am I getting sporty variants" / "TKD lunges showed up in my export" / when reviewing a passed close-the-loop run and spotting Single-Leg / sport-flavored / backpack / TKD / ballet / sambo / capoeira lifts in slots that should hold canonical bilateral compounds. Skip when the rubric ALSO fails (then it's a generator or accessory-layer bug, not a staples bug).
---

# Staples: broad keywords mask sport-flavored variants

## The discovery path

A lower-body eval-rig export graded 9/9 on the structural rubric. Looked at the actual picks: Single-Leg Deadlift (Backpack), Jumping Switch Lunge (TKD Power), Single-Leg Calf Raise (Eccentric, Loaded). All structurally-valid (each tagged hamstring/quad/calf isolation correctly), all weird in practice.

The chain: `WorkoutGenerator.pickForSlot` → `applyStaplePreference` → `ExerciseStaples.isStaple(name:, forPattern:)` → `keywordsByPattern[pattern]`. The check is substring-match against `name`. Broad keywords like `"deadlift"` matched Conventional Deadlift, Romanian Deadlift, AND Single-Leg Deadlift (Backpack). All three were "staples" by the broad check, so the picker happily picked the sport-flavored one.

## The fix

Replace bare keywords with canonical bilateral name fragments. For phase-training2 as of this session:

```swift
"hip-hinge": ["romanian deadlift", "conventional deadlift", "trap bar deadlift",
              "sumo deadlift", "stiff-leg deadlift", "kettlebell swing", "good morning"],
"single-leg-squat": ["bulgarian split squat", "split squat",
                     "walking lunge", "reverse lunge", "forward lunge", "lateral lunge"],
"calf-raise": ["standing calf raise", "seated calf raise"],
```

Verify by re-running `EvalRigExportSmokeTest.test_export_lower_body_emits` and inspecting `/tmp/eval-rig-export-lower/*.json`. Canonical bilateral lifts should now lead. Re-grade the workout against the same rubric — it should still PASS at the same score, since the structural dimensions (warm-ups, rest, accessory coverage, RPE, swaps) don't care which canonical variant fills the slot.

## Why the rubric doesn't catch it

The eval-rig rubric is structural — it asks "is there a hamstring isolation slot?", not "is the hamstring isolation slot filled with something an intermediate lifter would expect to see?" Sport-flavored variants tag the same prime_mover + role as canonical lifts, so they're invisible to the rubric. That's by design; the rubric measures programming shape, not naming polish. UX polish lives in `ExerciseStaples`.
