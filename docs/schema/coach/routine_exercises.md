# routine_exercises

## Description

<details>
<summary><strong>Table Definition</strong></summary>

```sql
CREATE TABLE routine_exercises (
  id                       INTEGER PRIMARY KEY AUTOINCREMENT,
  routine_id               INTEGER NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
  exercise_id              INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  position                 INTEGER NOT NULL,
  superset_group           INTEGER,
  sets                     INTEGER,
  reps                     TEXT,
  rest                     TEXT,
  tempo                    TEXT,
  duration                 TEXT,
  notes                    TEXT,
  UNIQUE (routine_id, position)
)
```

</details>

## Columns

| Name           | Type    | Default | Nullable | Children | Parents                   | Comment |
| -------------- | ------- | ------- | -------- | -------- | ------------------------- | ------- |
| id             | INTEGER |         | true     |          |                           |         |
| routine_id     | INTEGER |         | false    |          | [routines](routines.md)   |         |
| exercise_id    | INTEGER |         | false    |          | [exercises](exercises.md) |         |
| position       | INTEGER |         | false    |          |                           |         |
| superset_group | INTEGER |         | true     |          |                           |         |
| sets           | INTEGER |         | true     |          |                           |         |
| reps           | TEXT    |         | true     |          |                           |         |
| rest           | TEXT    |         | true     |          |                           |         |
| tempo          | TEXT    |         | true     |          |                           |         |
| duration       | TEXT    |         | true     |          |                           |         |
| notes          | TEXT    |         | true     |          |                           |         |

## Constraints

| Name                                 | Type        | Definition                                                                                           |
| ------------------------------------ | ----------- | ---------------------------------------------------------------------------------------------------- |
| id                                   | PRIMARY KEY | PRIMARY KEY (id)                                                                                     |
| - (Foreign key ID: 0)                | FOREIGN KEY | FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE |
| - (Foreign key ID: 1)                | FOREIGN KEY | FOREIGN KEY (routine_id) REFERENCES routines (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE   |
| sqlite_autoindex_routine_exercises_1 | UNIQUE      | UNIQUE (routine_id, position)                                                                        |

## Indexes

| Name                                 | Definition                                                                      |
| ------------------------------------ | ------------------------------------------------------------------------------- |
| idx_routine_ex_routine               | CREATE INDEX idx_routine_ex_routine            ON routine_exercises(routine_id) |
| sqlite_autoindex_routine_exercises_1 | UNIQUE (routine_id, position)                                                   |

## Relations

```mermaid
erDiagram

"routine_exercises" }o--|| "routines" : "FOREIGN KEY (routine_id) REFERENCES routines (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"
"routine_exercises" }o--|| "exercises" : "FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"

"routine_exercises" {
  INTEGER id
  INTEGER routine_id FK
  INTEGER exercise_id FK
  INTEGER position
  INTEGER superset_group
  INTEGER sets
  TEXT reps
  TEXT rest
  TEXT tempo
  TEXT duration
  TEXT notes
}
"routines" {
  INTEGER id
  TEXT name
  TEXT slug
  TEXT description
  TEXT goal
  TEXT difficulty
  TEXT phase
  INTEGER duration_minutes
  TEXT frequency
  TEXT environment
  TEXT time_commitment
  TEXT ideal_schedule
  TEXT notes
  TEXT source_name
  TEXT source_url
  TEXT tags
  TEXT created_at
  TEXT updated_at
}
"exercises" {
  INTEGER id
  TEXT name
  TEXT slug
  TEXT description
  TEXT instructions
  TEXT cues
  TEXT difficulty
  TEXT modality
  TEXT movement_plane
  TEXT energy_system
  TEXT contraction_type
  INTEGER is_unilateral
  INTEGER is_compound
  TEXT environment
  INTEGER default_sets
  TEXT default_reps
  TEXT default_rest
  TEXT default_tempo
  TEXT default_duration
  TEXT time_efficient_variation
  TEXT home_variation
  TEXT age_considerations
  TEXT desk_worker_notes
  INTEGER recovery_demand
  INTEGER cns_load
  TEXT intensity_category
  TEXT fatigue_type
  TEXT swap_group
  INTEGER low_energy_suitable
  INTEGER pre_event_safe
  INTEGER warmup_compatible
  TEXT injury_prevention_notes
  TEXT contraindications
  TEXT pt_rehab_relevance
  TEXT common_compensations
  TEXT regression
  TEXT progression
  TEXT video_url
  TEXT image_url
  TEXT thumbnail_url
  TEXT source_video_attribution
  TEXT image_source
  TEXT image_license
  TEXT image_attribution
  TEXT source_name
  TEXT source_url
  TEXT source_type
  INTEGER source_year
  TEXT tags
  TEXT created_at
  TEXT updated_at
}
```

---

> Generated by [tbls](https://github.com/k1LoW/tbls)
