# user.db

## Description

On-device workout history (Documents/user.db). Schema from the migrations in PhaseTraining/Data/UserDatabase.swift, versioned by PRAGMA user_version.

## Tables

| Name                                                | Columns | Comment                                                                                                                                                                                      | Type  |
| --------------------------------------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| [user_routines](user_routines.md)                   | 5       |                                                                                                                                                                                              | table |
| [user_routine_exercises](user_routine_exercises.md) | 9       |                                                                                                                                                                                              | table |
| [sessions](sessions.md)                             | 9       | One saved native workout. start_time (epoch seconds) is the session id, referenced from UserDefaults by DayOutcome.sessionId, WeekPlanSnapshot.actualSessionIDs and FeedbackEntry.sessionId. | table |
| [session_exercises](session_exercises.md)           | 10      |                                                                                                                                                                                              | table |
| [session_sets](session_sets.md)                     | 8       |                                                                                                                                                                                              | table |
| [imported_workouts](imported_workouts.md)           | 8       | HealthKit or CSV workouts, keyed by the source's own UUID so re-import is idempotent. Unioned with sessions in GeneratorContext.                                                             | table |
| [imported_sets](imported_sets.md)                   | 11      | Set-level CSV history. Attached to imported_workouts by performed_at proximity in Swift, not by FK.                                                                                          | table |
| [explore_sessions](explore_sessions.md)             | 10      | One row per visit to a browse surface (ExploreSession.swift). Not included in the backup envelope.                                                                                           | table |
| [import_name_map](import_name_map.md)               | 2       |                                                                                                                                                                                              | table |

## Relations

```mermaid
erDiagram

"user_routine_exercises" }o--|| "user_routines" : "FOREIGN KEY (routine_id) REFERENCES user_routines (id) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"
"session_exercises" |o--|| "sessions" : "FOREIGN KEY (session_start) REFERENCES sessions (start_time) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"
"session_sets" }o--|| "session_exercises" : "FOREIGN KEY (session_start, exercise_position) REFERENCES session_exercises (session_start, position) ON UPDATE NO ACTION ON DELETE CASCADE MATCH NONE"

"user_routines" {
  TEXT id PK
  TEXT name
  TEXT focus
  INTEGER created_at
  INTEGER updated_at
}
"user_routine_exercises" {
  TEXT id PK
  TEXT routine_id FK
  INTEGER exercise_id
  INTEGER position
  INTEGER sets
  TEXT reps
  TEXT rest
  TEXT notes
  TEXT name
}
"sessions" {
  INTEGER start_time
  TEXT template_id
  TEXT name
  TEXT category
  INTEGER end_time
  INTEGER duration
  TEXT feel
  TEXT note
  TEXT mood
}
"session_exercises" {
  INTEGER session_start PK
  INTEGER position PK
  TEXT exercise_template_id
  TEXT name
  TEXT type
  TEXT unit
  INTEGER target_sets
  INTEGER target_reps
  INTEGER rest
  TEXT prev_sets_json
}
"session_sets" {
  INTEGER session_start PK
  INTEGER exercise_position PK
  INTEGER num PK
  TEXT weight
  TEXT reps
  TEXT rpe
  INTEGER done
  INTEGER is_warmup
}
"imported_workouts" {
  TEXT id PK
  TEXT source
  TEXT hk_uuid
  TEXT kind
  INTEGER start_time
  REAL duration_seconds
  REAL energy_kcal
  INTEGER imported_at
}
"imported_sets" {
  TEXT id PK
  TEXT source
  INTEGER exercise_id
  TEXT exercise_name_raw
  INTEGER performed_at
  INTEGER set_num
  REAL weight
  INTEGER reps
  REAL rir
  REAL rpe
  INTEGER imported_at
}
"explore_sessions" {
  TEXT id PK
  TEXT surface
  REAL started_at
  REAL ended_at
  TEXT query
  INTEGER result_count
  INTEGER tier
  INTEGER broadened
  TEXT opens_json
  TEXT conversions_json
}
"import_name_map" {
  TEXT name_raw PK
  INTEGER exercise_id
}
```

---

> Generated by [tbls](https://github.com/k1LoW/tbls)
