# Phase-training2 → eval-rig adapter (scoping doc)

**Status:** spec only — not implementing yet. This doc unblocks the next session by pinning down the schema gaps and the export surface before code is written.

## Goal

Emit phase-training2's `GeneratedWorkout` as eval-rig-compatible JSON so the rig can grade real generator output against the same snap rubric we use for canonical programs. The contract is JSON-on-disk per `~/repos/eval-rig/README.md` — no direct Swift coupling.

## Shape mismatch

phase-training2's `GeneratedWorkout` (defined in `PhaseTraining/Data/WorkoutGenerator.swift` near the `WorkoutFocus` enum) is a flat list of `GeneratedExercise` rows with these fields per exercise:

| phase-training2 field   | type      | notes                                                  |
|-------------------------|-----------|--------------------------------------------------------|
| `exerciseId`            | Int       | coach.db row id                                        |
| `name`                  | String    | e.g. "Barbell Bench Press"                             |
| `pattern`               | String?   | movement_patterns.slug, e.g. "horizontal-push"         |
| `isCompound`            | Bool      |                                                        |
| `sets`                  | Int       | flat working-set count, no warm-up split               |
| `reps`                  | String    | e.g. "6-10" or "30s hold"                              |
| `restSeconds`           | Int       | single value, not per-set differentiated               |
| `rpe`                   | String?   | e.g. "7-8"                                             |
| `tempo`                 | String?   | e.g. "3-1-1-0"                                         |
| `notes`                 | String?   | progressive-overload hint                              |
| `source`                | enum      | `.recipe` or `.prehab(injurySlug:)` (prehab now dead)  |

The eval-rig workout schema (`~/repos/eval-rig/schemas/workout.schema.json`) requires:

| eval-rig field       | shape                                              | gap vs phase-training2                                |
|----------------------|----------------------------------------------------|-------------------------------------------------------|
| `order`              | per-exercise position                              | phase-training2 implicit by array index — derive      |
| `role`               | "compound" \| "isolation"                          | derive from `isCompound`                              |
| `prime_mover`        | string                                             | NOT in `GeneratedExercise` — need a join to coach.db `exercise_muscles WHERE role='primary'` |
| `movement_pattern`   | enum: horizontal-push / vertical-push / etc.       | `pattern` field maps, but eval-rig's enum is narrower (no squat/hip-hinge) — fold to "other" |
| `implement`          | enum: barbell / dumbbell / machine / cable / ...   | NOT in `GeneratedExercise` — need a join to coach.db `exercises.modality` or `exercise_equipment` |
| `warm_up_sets[]`     | array of sets (reps + load + rest)                 | phase-training2 has NO warm-up tracking per exercise — the 5-min `warmupBufferSec` is a time reservation, not per-exercise sets. Adapter emits empty `warm_up_sets`. |
| `working_sets[]`     | array with reps / load_intent / rest_seconds       | phase-training2 has flat `sets: Int, reps: String, restSeconds: Int` — adapter expands into N identical entries |
| `working_sets[].load_intent` | string with RPE / RIR / %1RM           | combine phase-training2's `rpe` + `tempo` + `notes` into one intent string |
| `swap_alternates[]`  | array of {name, implement}                         | NOT in `GeneratedExercise` — need to derive from `coach.db.exercise_substitutions` keyed by exerciseId |

## Two concrete gaps that need code

1. **`prime_mover`, `implement`, `swap_alternates`** require a coach.db join. The adapter has to query `exercise_muscles` (for prime_mover where role='primary'), `exercises.modality` or `exercise_equipment` (for implement), and `exercise_substitutions` (for swaps) by `exerciseId`. This means the adapter is not a pure phase-training2 file-write — it needs `CoachDatabase` access.

2. **`load_intent` derivation.** Phase-training2 separates `rpe` and `tempo` (and embeds `%1RM` in `notes` when set). The adapter concatenates: `"\(rpe.map { "RPE \($0)" } ?? "") \(tempo.map { "tempo \($0)" } ?? "")".trimmingCharacters(in: .whitespaces)`. If the result is empty (no rpe, no tempo, no %1RM hint), the eval-rig rubric Q6 will fail by construction — and that's a real signal about phase-training2's generator, not an adapter bug.

## Export surface — three options

a. **Debug-menu export.** Add a "Export workout JSON" button to the today screen's debug menu. User taps after a generation. Slow but precise — one workout at a time, manually triggered.
b. **Auto-watch.** Every `GeneratedWorkout` written to a `PlanStore` slot is also written to `~/Library/Application Support/PhaseTraining/eval-rig-export/<id>.json`. The user runs the eval rig against that folder. Highest signal but writes on every regenerate; needs a flag to enable.
c. **CLI in phase-training2.** A `swift run eval-export --archetype X --n 20 --out ~/repos/eval-rig/workouts/batch-002/` that synthesizes 20 workouts for a target archetype non-interactively. Best for batch grading; needs CoachDatabase + DemographicProfile fixtures.

**Recommendation: (c).** Batch sizes matter more than per-workout precision for the eval rig's "compare runs" workflow. The CLI lives at `PhaseTraining/Scripts/EvalExport/` (new sibling to `scripts/`), depends on `CoachDatabase` + `WorkoutGenerator` + `DemographicProfile`, and writes JSON one per workout. Fixtures (archetype → TrainingMemory) are hand-authored in the CLI, no UI dependency.

## Open questions for the implementing session

1. Does `WorkoutGenerator.generateLift` need ANY changes to support headless invocation (no SwiftUI), or does it already work outside the app? **Best guess: works as-is** — it's a static func with explicit memory/profile inputs.
2. How do we represent phase-training2's `tempo` field in the eval-rig schema? It's not in the snap rubric. Recommendation: embed in `load_intent` ("tempo 3-1-1-0") so it round-trips visibly without needing a schema field.
3. How do we handle the soreness context? Phase-training2's `GeneratedWorkout` doesn't carry the soreness inputs forward, but the eval-rig's `context.soreness` block matters for Q9. Adapter has to read `memory.soreness.last` at export time and embed.

## Next session prereqs

- This doc lives at `phase-training2/PLAN-eval-rig-adapter.md` (untracked alongside `PLAN-image-quality.md`)
- Eval-rig has ≥ 3 programs encoded (we just hit that)
- Eval-rig accessory-layer design resolved (we just hit that — layered model)

Ready to implement when the user gives the green light.
