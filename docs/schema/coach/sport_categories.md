# sport_categories

## Description

<details>
<summary><strong>Table Definition</strong></summary>

```sql
CREATE TABLE sport_categories (
  id                       INTEGER PRIMARY KEY,
  name                     TEXT NOT NULL UNIQUE,
  slug                     TEXT NOT NULL UNIQUE,
  description              TEXT,
  parent_id                INTEGER REFERENCES sport_categories(id),
  depth                    INTEGER NOT NULL DEFAULT 0,
  sort_order               INTEGER DEFAULT 0,
  typical_session_minutes  INTEGER,
  common_training_days     TEXT,
  peak_season              TEXT,
  common_injuries          TEXT,   -- JSON array of strings
  governing_body           TEXT,
  -- Phase 1.2 sport-coverage floor. When a depth<=1 sport is intentionally
  -- out of scope for training-plan generation, populate this with a short
  -- rationale (e.g. "No general-strength transfer; niche audience"). NULL =
  -- in scope. See scripts/validate_coverage.sql.
  unsupported_reason       TEXT,
  created_at               TEXT DEFAULT (datetime('now')),
  updated_at               TEXT DEFAULT (datetime('now'))
)
```

</details>

## Columns

| Name                    | Type    | Default         | Nullable | Children                                                                                                                                                                                                                                        | Parents                                 | Comment                                  |
| ----------------------- | ------- | --------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- | ---------------------------------------- |
| id                      | INTEGER |                 | true     | [exercise_sport_relevance](exercise_sport_relevance.md) [injury_sport_prevalence](injury_sport_prevalence.md) [routine_sports](routine_sports.md) [sport_categories](sport_categories.md) [sport_recovery_profiles](sport_recovery_profiles.md) |                                         |                                          |
| name                    | TEXT    |                 | false    |                                                                                                                                                                                                                                                 |                                         |                                          |
| slug                    | TEXT    |                 | false    | [sport_movements](sport_movements.md)                                                                                                                                                                                                           |                                         |                                          |
| description             | TEXT    |                 | true     |                                                                                                                                                                                                                                                 |                                         |                                          |
| parent_id               | INTEGER |                 | true     |                                                                                                                                                                                                                                                 | [sport_categories](sport_categories.md) |                                          |
| depth                   | INTEGER | 0               | false    |                                                                                                                                                                                                                                                 |                                         |                                          |
| sort_order              | INTEGER | 0               | true     |                                                                                                                                                                                                                                                 |                                         |                                          |
| typical_session_minutes | INTEGER |                 | true     |                                                                                                                                                                                                                                                 |                                         |                                          |
| common_training_days    | TEXT    |                 | true     |                                                                                                                                                                                                                                                 |                                         |                                          |
| peak_season             | TEXT    |                 | true     |                                                                                                                                                                                                                                                 |                                         |                                          |
| common_injuries         | TEXT    |                 | true     |                                                                                                                                                                                                                                                 |                                         |                                          |
| governing_body          | TEXT    |                 | true     |                                                                                                                                                                                                                                                 |                                         |                                          |
| unsupported_reason      | TEXT    |                 | true     |                                                                                                                                                                                                                                                 |                                         | NULL means in scope for plan generation. |
| created_at              | TEXT    | datetime('now') | true     |                                                                                                                                                                                                                                                 |                                         |                                          |
| updated_at              | TEXT    | datetime('now') | true     |                                                                                                                                                                                                                                                 |                                         |                                          |

## Constraints

| Name                                | Type        | Definition                                                                                                  |
| ----------------------------------- | ----------- | ----------------------------------------------------------------------------------------------------------- |
| id                                  | PRIMARY KEY | PRIMARY KEY (id)                                                                                            |
| - (Foreign key ID: 0)               | FOREIGN KEY | FOREIGN KEY (parent_id) REFERENCES sport_categories (id) ON UPDATE NO ACTION ON DELETE NO ACTION MATCH NONE |
| sqlite_autoindex_sport_categories_2 | UNIQUE      | UNIQUE (slug)                                                                                               |
| sqlite_autoindex_sport_categories_1 | UNIQUE      | UNIQUE (name)                                                                                               |

## Indexes

| Name                                | Definition                                                                    |
| ----------------------------------- | ----------------------------------------------------------------------------- |
| idx_sport_parent                    | CREATE INDEX idx_sport_parent                  ON sport_categories(parent_id) |
| idx_sport_depth                     | CREATE INDEX idx_sport_depth                   ON sport_categories(depth)     |
| sqlite_autoindex_sport_categories_2 | UNIQUE (slug)                                                                 |
| sqlite_autoindex_sport_categories_1 | UNIQUE (name)                                                                 |

## Relations

```mermaid
erDiagram

"exercise_sport_relevance" |o--|| "sport_categories" : "FOREIGN KEY (sport_id) REFERENCES sport_categories (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"
"injury_sport_prevalence" |o--|| "sport_categories" : "FOREIGN KEY (sport_id) REFERENCES sport_categories (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"
"routine_sports" |o--|| "sport_categories" : "FOREIGN KEY (sport_id) REFERENCES sport_categories (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"
"sport_categories" }o--o| "sport_categories" : "FOREIGN KEY (parent_id) REFERENCES sport_categories (id) ON UPDATE NO ACTION ON DELETE NO ACTION MATCH NONE"
"sport_recovery_profiles" |o--o| "sport_categories" : "FOREIGN KEY (sport_id) REFERENCES sport_categories (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"
"sport_movements" }o--|| "sport_categories" : "text join on slug, no FK (sport_movements.sport)"

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
"injury_sport_prevalence" {
  INTEGER injury_id PK
  INTEGER sport_id PK
  TEXT prevalence
  TEXT notes
}
"routine_sports" {
  INTEGER routine_id PK
  INTEGER sport_id PK
}
"sport_recovery_profiles" {
  INTEGER sport_id FK
  INTEGER typical_recovery_hours
  TEXT primary_fatigue_type
  TEXT muscles_loaded
  TEXT avoid_before_session
  TEXT ideal_supplement_timing
  TEXT notes
}
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
```

---

> Generated by [tbls](https://github.com/k1LoW/tbls)
