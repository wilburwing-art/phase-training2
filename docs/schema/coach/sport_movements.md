# sport_movements

## Description

Season-aware movement pool. `sport` is a sport_categories slug with no FK.

<details>
<summary><strong>Table Definition</strong></summary>

```sql
CREATE TABLE sport_movements (
  id                INTEGER PRIMARY KEY,
  slug              TEXT NOT NULL,
  name              TEXT NOT NULL,
  sport             TEXT NOT NULL,            -- sport_categories.slug (e.g. alpine-skiing)
  exercise_id       INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  demands           TEXT NOT NULL,            -- JSON array of Demand rawValues, primary first
  allowed_phases    TEXT NOT NULL,            -- JSON array of SeasonPhase rawValues
  allowed_variants  TEXT,                     -- JSON array of SportVariant rawValues; NULL = all
  fatigue_cost      INTEGER NOT NULL DEFAULT 2 CHECK (fatigue_cost BETWEEN 1 AND 5),
  min_experience    TEXT,                     -- novice|intermediate|advanced; NULL = no gate
  injury_caution    TEXT,
  -- Optional per-movement prescription (R3-9). The engine prescribes by DEMAND
  -- (DemandScheme), which is right for a generic squat and wrong for a movement
  -- that carries a cited protocol: the no-hang finger pull is a 3 s overcoming
  -- isometric and was being served as 5x8s holds. When these are set the
  -- scheme's sets/reps/rest yield to them; RPE and tempo still come from the scheme.
  protocol_sets         INTEGER CHECK (protocol_sets BETWEEN 1 AND 10),
  protocol_reps         TEXT,
  protocol_rest_seconds INTEGER CHECK (protocol_rest_seconds BETWEEN 0 AND 600)
)
```

</details>

## Columns

| Name                  | Type    | Default | Nullable | Children | Parents                                 | Comment |
| --------------------- | ------- | ------- | -------- | -------- | --------------------------------------- | ------- |
| id                    | INTEGER |         | true     |          |                                         |         |
| slug                  | TEXT    |         | false    |          |                                         |         |
| name                  | TEXT    |         | false    |          |                                         |         |
| sport                 | TEXT    |         | false    |          | [sport_categories](sport_categories.md) |         |
| exercise_id           | INTEGER |         | false    |          | [exercises](exercises.md)               |         |
| demands               | TEXT    |         | false    |          |                                         |         |
| allowed_phases        | TEXT    |         | false    |          |                                         |         |
| allowed_variants      | TEXT    |         | true     |          |                                         |         |
| fatigue_cost          | INTEGER | 2       | false    |          |                                         |         |
| min_experience        | TEXT    |         | true     |          |                                         |         |
| injury_caution        | TEXT    |         | true     |          |                                         |         |
| protocol_sets         | INTEGER |         | true     |          |                                         |         |
| protocol_reps         | TEXT    |         | true     |          |                                         |         |
| protocol_rest_seconds | INTEGER |         | true     |          |                                         |         |

## Constraints

| Name                  | Type        | Definition                                                                                           |
| --------------------- | ----------- | ---------------------------------------------------------------------------------------------------- |
| id                    | PRIMARY KEY | PRIMARY KEY (id)                                                                                     |
| - (Foreign key ID: 0) | FOREIGN KEY | FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE |
| -                     | CHECK       | CHECK (fatigue_cost BETWEEN 1 AND 5)                                                                 |
| -                     | CHECK       | CHECK (protocol_sets BETWEEN 1 AND 10)                                                               |
| -                     | CHECK       | CHECK (protocol_rest_seconds BETWEEN 0 AND 600)                                                      |

## Indexes

| Name                         | Definition                                                                     |
| ---------------------------- | ------------------------------------------------------------------------------ |
| idx_sport_movements_exercise | CREATE INDEX idx_sport_movements_exercise      ON sport_movements(exercise_id) |
| idx_sport_movements_sport    | CREATE INDEX idx_sport_movements_sport         ON sport_movements(sport)       |

## Relations

```mermaid
erDiagram

"sport_movements" }o--|| "sport_categories" : "text join on slug, no FK (sport_movements.sport)"
"sport_movements" }o--|| "exercises" : "FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"

"sport_movements" {
  INTEGER id
  TEXT slug
  TEXT name
  TEXT sport
  INTEGER exercise_id FK
  TEXT demands
  TEXT allowed_phases
  TEXT allowed_variants
  INTEGER fatigue_cost
  TEXT min_experience
  TEXT injury_caution
  INTEGER protocol_sets
  TEXT protocol_reps
  INTEGER protocol_rest_seconds
}
"sport_categories" {
  INTEGER id
  TEXT name
  TEXT slug
  TEXT description
  INTEGER parent_id FK
  INTEGER depth
  INTEGER sort_order
  INTEGER typical_session_minutes
  TEXT common_training_days
  TEXT peak_season
  TEXT common_injuries
  TEXT governing_body
  TEXT unsupported_reason
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
