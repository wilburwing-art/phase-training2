# exercise_sport_relevance

## Description

<details>
<summary><strong>Table Definition</strong></summary>

```sql
CREATE TABLE exercise_sport_relevance (
  exercise_id                INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  sport_id                   INTEGER NOT NULL REFERENCES sport_categories(id) ON DELETE CASCADE,
  relevance_score            REAL NOT NULL DEFAULT 0.5 CHECK (relevance_score BETWEEN 0.0 AND 1.0),
  specificity                TEXT CHECK (specificity IN ('general','related','highly_specific')),
  support_role               TEXT NOT NULL CHECK (support_role IN (
                               'direct_strength','antagonist','prehab','mobility',
                               'power','conditioning','general_foundation','recovery')),
  season_emphasis            TEXT,  -- JSON array: any of pre_season, in_season, off_season, all
  in_season_volume_modifier  REAL DEFAULT 1.0,
  off_season_volume_modifier REAL DEFAULT 1.0,
  notes                      TEXT,
  PRIMARY KEY (exercise_id, sport_id, support_role)
)
```

</details>

## Columns

| Name                       | Type    | Default | Nullable | Children | Parents                                 | Comment |
| -------------------------- | ------- | ------- | -------- | -------- | --------------------------------------- | ------- |
| exercise_id                | INTEGER |         | false    |          | [exercises](exercises.md)               |         |
| sport_id                   | INTEGER |         | false    |          | [sport_categories](sport_categories.md) |         |
| relevance_score            | REAL    | 0.5     | false    |          |                                         |         |
| specificity                | TEXT    |         | true     |          |                                         |         |
| support_role               | TEXT    |         | false    |          |                                         |         |
| season_emphasis            | TEXT    |         | true     |          |                                         |         |
| in_season_volume_modifier  | REAL    | 1.0     | true     |          |                                         |         |
| off_season_volume_modifier | REAL    | 1.0     | true     |          |                                         |         |
| notes                      | TEXT    |         | true     |          |                                         |         |

## Constraints

| Name                                        | Type        | Definition                                                                                                                            |
| ------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| exercise_id                                 | PRIMARY KEY | PRIMARY KEY (exercise_id)                                                                                                             |
| sport_id                                    | PRIMARY KEY | PRIMARY KEY (sport_id)                                                                                                                |
| support_role                                | PRIMARY KEY | PRIMARY KEY (support_role)                                                                                                            |
| - (Foreign key ID: 0)                       | FOREIGN KEY | FOREIGN KEY (sport_id) REFERENCES sport_categories (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE                              |
| - (Foreign key ID: 1)                       | FOREIGN KEY | FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE                                  |
| sqlite_autoindex_exercise_sport_relevance_1 | PRIMARY KEY | PRIMARY KEY (exercise_id, sport_id, support_role)                                                                                     |
| -                                           | CHECK       | CHECK (relevance_score BETWEEN 0.0 AND 1.0)                                                                                           |
| -                                           | CHECK       | CHECK (specificity IN ('general','related','highly_specific'))                                                                        |
| -                                           | CHECK       | CHECK (support_role IN ( 'direct_strength','antagonist','prehab','mobility', 'power','conditioning','general_foundation','recovery')) |

## Indexes

| Name                                        | Definition                                                                                         |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| idx_esr_support_role                        | CREATE INDEX idx_esr_support_role              ON exercise_sport_relevance(support_role)           |
| idx_esr_sport_role                          | CREATE INDEX idx_esr_sport_role                ON exercise_sport_relevance(sport_id, support_role) |
| idx_esr_sport_id                            | CREATE INDEX idx_esr_sport_id                  ON exercise_sport_relevance(sport_id)               |
| sqlite_autoindex_exercise_sport_relevance_1 | PRIMARY KEY (exercise_id, sport_id, support_role)                                                  |

## Relations

```mermaid
erDiagram

"exercise_sport_relevance" |o--|| "exercises" : "FOREIGN KEY (exercise_id) REFERENCES exercises (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"
"exercise_sport_relevance" |o--|| "sport_categories" : "FOREIGN KEY (sport_id) REFERENCES sport_categories (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"

"exercise_sport_relevance" {
  INTEGER exercise_id PK
  INTEGER sport_id PK
  REAL relevance_score
  TEXT specificity
  TEXT support_role PK
  TEXT season_emphasis
  REAL in_season_volume_modifier
  REAL off_season_volume_modifier
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
```

---

> Generated by [tbls](https://github.com/k1LoW/tbls)
