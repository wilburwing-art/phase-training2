# exercise_injury_relevance

## Description

<details>
<summary><strong>Table Definition</strong></summary>

```sql
CREATE TABLE exercise_injury_relevance (
  exercise_id     INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  injury_id       INTEGER NOT NULL REFERENCES common_injuries(id) ON DELETE CASCADE,
  role            TEXT NOT NULL CHECK (role IN ('prehab','rehab_early','rehab_late','contraindicated')),
  notes           TEXT,
  PRIMARY KEY (exercise_id, injury_id, role)
)
```

</details>

## Columns

| Name        | Type    | Default | Nullable | Children | Parents                               | Comment |
| ----------- | ------- | ------- | -------- | -------- | ------------------------------------- | ------- |
| exercise_id | INTEGER |         | false    |          | [exercises](exercises.md)             |         |
| injury_id   | INTEGER |         | false    |          | [common_injuries](common_injuries.md) |         |
| role        | TEXT    |         | false    |          |                                       |         |
| notes       | TEXT    |         | true     |          |                                       |         |

## Constraints

| Name                                         | Type        | Definition                                                                                               |
| -------------------------------------------- | ----------- | -------------------------------------------------------------------------------------------------------- |
| exercise_id                                  | PRIMARY KEY | PRIMARY KEY (exercise_id)                                                                                |
| injury_id                                    | PRIMARY KEY | PRIMARY KEY (injury_id)                                                                                  |
| role                                         | PRIMARY KEY | PRIMARY KEY (role)                                                                                       |
| - (Foreign key ID: 0)                        | FOREIGN KEY | FOREIGN KEY (injury_id) REFERENCES common_injuries (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE |
| - (Foreign key ID: 1)                        | FOREIGN KEY | FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE     |
| sqlite_autoindex_exercise_injury_relevance_1 | PRIMARY KEY | PRIMARY KEY (exercise_id, injury_id, role)                                                               |
| -                                            | CHECK       | CHECK (role IN ('prehab','rehab_early','rehab_late','contraindicated'))                                  |

## Indexes

| Name                                         | Definition                                                                             |
| -------------------------------------------- | -------------------------------------------------------------------------------------- |
| idx_exinj_injury                             | CREATE INDEX idx_exinj_injury                  ON exercise_injury_relevance(injury_id) |
| sqlite_autoindex_exercise_injury_relevance_1 | PRIMARY KEY (exercise_id, injury_id, role)                                             |

## Relations

```mermaid
erDiagram

"exercise_injury_relevance" |o--|| "exercises" : "FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"
"exercise_injury_relevance" |o--|| "common_injuries" : "FOREIGN KEY (injury_id) REFERENCES common_injuries (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"

"exercise_injury_relevance" {
  INTEGER exercise_id PK
  INTEGER injury_id PK
  TEXT role PK
  TEXT notes
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
"common_injuries" {
  INTEGER id
  TEXT name
  TEXT slug
  TEXT body_region
  TEXT description
  TEXT mechanism
  TEXT typical_recovery
  TEXT created_at
}
```

---

> Generated by [tbls](https://github.com/k1LoW/tbls)
