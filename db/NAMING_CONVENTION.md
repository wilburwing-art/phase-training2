# Exercise naming convention

Single source of truth for how exercise rows in `db/source/exercises.json`
are named. The audit (`scripts/db/audit_equipment_variants.py`) and the
upcoming row-generation pass both consume these rules. Existing rows that
predate this convention will be progressively renamed; old names are kept
discoverable via `exercise_aliases.json`.

## Canonical format

```
[Modifier(s)] [Equipment] [LiftName]
```

Equipment goes **between** modifier(s) and the lift name, not at the end
in parentheses. So:

| Right                                | Wrong                              |
|--------------------------------------|------------------------------------|
| `Barbell Bench Press`                | `Bench Press (Barbell)`            |
| `Dumbbell Bench Press`               | `Bench Press (Dumbbell)`           |
| `Incline Dumbbell Bench Press`       | `Incline Bench Press (Dumbbell)`   |
| `Smith Machine Squat`                | `Squat (Smith Machine)`            |
| `Cable Crossover (High-to-Low)`      | `Crossover (Cable, High-to-Low)`   |

Grip / stance / range descriptors come *after* the lift name in a
parenthetical, to keep the lift name itself stable for sorting:

| Right                              | Wrong                              |
|------------------------------------|------------------------------------|
| `Barbell Bench Press (Wide Grip)`  | `Barbell Wide-Grip Bench Press`    |
| `Bulgarian Split Squat (Front-Foot Elevated)` | `Front-Foot-Elevated Bulgarian Split Squat` |

## Equipment vocabulary

These are the only equipment labels that appear in names. Pick one per
row. Use the spelling in the left column verbatim:

| Label             | Slug (`equipment.slug`) | Notes                                  |
|-------------------|-------------------------|----------------------------------------|
| `Barbell`         | `barbell`               | Default for compound lifts             |
| `Dumbbell`        | `dumbbell`              | Always singular ("Dumbbell" not "Dumbbells") |
| `Cable`           | `cable-machine`         | Includes cable-crossover variants when single-stack |
| `Smith Machine`   | `smith-machine`         | Spell out "Smith Machine", not just "Smith" |
| `Machine`         | `*-machine` (varies)    | Use when a dedicated plate-loaded / selectorized machine exists (Pec Deck, Hack Squat, etc.) |
| `EZ-Bar`          | `ez-bar`                | Hyphenated, capital EZ                 |
| `Trap Bar`        | `trap-bar`              | Two words                              |
| `Kettlebell`      | `kettlebell`            | Singular                               |
| `Landmine`        | `landmine`              |                                        |
| `Band`            | `resistance-band`       | For resistance-band-only variants      |
| `Plate`           | `weight-plate`          | Single 25/45 plate held with both hands |
| `Rings`           | `gymnastic-rings`       | Suspension-trainer variants → `TRX`    |
| `TRX`             | `trx`                   |                                        |
| `Bodyweight`      | `bodyweight`            | Implicit when no equipment word appears |

## Implicit-equipment rule

When the movement name itself implies the equipment, **don't repeat the
equipment word**. Implicit defaults:

| Lift name           | Implies        |
|---------------------|----------------|
| Hammer Curl         | Dumbbell       |
| Concentration Curl  | Dumbbell       |
| Goblet Squat        | Dumbbell or Kettlebell |
| Skullcrusher        | Barbell        |
| Pec Deck Fly        | Machine        |
| Leg Press           | Machine        |
| Leg Extension       | Machine        |
| Lat Pulldown        | Cable          |
| Face Pull           | Cable          |
| Tricep Pushdown     | Cable          |
| Cable Crossover     | Cable          |

When you want a *non-default* variant, prepend the explicit equipment:

- `Cable Hammer Curl` — non-default (default would be Dumbbell)
- `Kettlebell Goblet Squat` — explicit non-default
- `Dumbbell Skullcrusher` — non-default
- `Machine Lat Pulldown` — non-default selectorized variant

## Alias policy

Every rename leaves a breadcrumb in `exercise_aliases.json` so:

1. Existing user data (saved sessions, recent picks) keeps resolving
2. Users searching for the old name find the renamed row

When renaming `Bench Press (Cable)` → `Cable Bench Press`, add:

```json
{ "exercise_id": <id>, "alias": "Bench Press (Cable)" }
```

The picker already searches both `name` and `alias` columns (see
`CoachDatabase.swift:listExercises`).

## What this convention does NOT do

- It doesn't decide modality/difficulty/movement-pattern — those are
  separate fields driven by the exercise content, not the name.
- It doesn't apply to non-loaded movements (mobility drills, sport
  drills, rehab exercises) where there's no equipment-variant axis to
  standardize.
- It doesn't constrain how the LLM coach refers to exercises in chat —
  the chat layer resolves user-typed names through aliases anyway.
