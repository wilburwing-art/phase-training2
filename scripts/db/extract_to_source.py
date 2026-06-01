#!/usr/bin/env python3
"""One-shot extractor: dump the current PhaseTraining/Resources/coach.db
tables we keep into db/source/*.json files.

Run once to bootstrap the source-of-truth pipeline. After that the workflow
is: edit JSON files → run build_db.py → commit JSON + regenerated coach.db.

Tables that aren't in TABLES below are *intentionally dropped*. The old
server-product schema bundled chat threads, idempotency caches, user
profile tables — none of those are referenced by the iOS app.

JSON-array text columns (cues, season_emphasis, etc.) get deserialized into
real lists for clean diffs.

Records get sorted deterministically (by ID for record tables, by composite
key for relation tables) so re-extracting the same DB always produces the
same byte-identical JSON files.
"""

import json
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = REPO_ROOT / "db" / "source"
SCHEMA_FILE = SOURCE_DIR / "_schema.sql"
DB_PATH = REPO_ROOT / "PhaseTraining" / "Resources" / "coach.db"

# Same list as build_db.py — keep in sync.
TABLES = [
    "movement_patterns",
    "muscle_groups",
    "equipment",
    "common_injuries",
    "sport_categories",
    "sport_recovery_profiles",
    "exercises",
    "exercise_aliases",
    "exercise_phases",
    "exercise_equipment",
    "exercise_muscles",
    "exercise_movement_patterns",
    "exercise_substitutions",
    "exercise_injury_relevance",
    "exercise_sport_relevance",
    "injury_sport_prevalence",
    "routines",
    "routine_exercises",
    "routine_sports",
]

JSON_ARRAY_COLUMNS = {
    ("exercises", "cues"),
    ("sport_categories", "common_injuries"),
    ("sport_recovery_profiles", "primary_fatigue_type"),
    ("sport_recovery_profiles", "muscles_loaded"),
    ("sport_recovery_profiles", "avoid_before_session"),
    ("exercise_sport_relevance", "season_emphasis"),
}

# Sort key per table for deterministic output. For record tables: by id. For
# relation tables: by composite key in the same order the schema declares it.
SORT_KEYS = {
    "movement_patterns": ["id"],
    "muscle_groups": ["id"],
    "equipment": ["id"],
    "common_injuries": ["id"],
    "sport_categories": ["id"],
    "sport_recovery_profiles": ["sport_id"],
    "exercises": ["id"],
    "exercise_aliases": ["id"],
    "exercise_phases": ["exercise_id", "phase"],
    "exercise_equipment": ["exercise_id", "equipment_id"],
    "exercise_muscles": ["exercise_id", "muscle_group_id"],
    "exercise_movement_patterns": ["exercise_id", "movement_pattern_id"],
    "exercise_substitutions": ["exercise_id", "substitute_id", "context"],
    "exercise_injury_relevance": ["exercise_id", "injury_id", "role"],
    "exercise_sport_relevance": ["exercise_id", "sport_id", "support_role"],
    "injury_sport_prevalence": ["injury_id", "sport_id"],
    "routines": ["id"],
    "routine_exercises": ["routine_id", "position", "id"],
    "routine_sports": ["routine_id", "sport_id"],
}


def extract():
    if not DB_PATH.exists():
        sys.exit(f"missing bundled DB: {DB_PATH}")

    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    # 1. Save schema for build_db.py to consume
    schema_rows = conn.execute(
        """
        SELECT type, name, tbl_name, sql FROM sqlite_master
        WHERE sql IS NOT NULL
          AND name NOT LIKE 'sqlite_%'
        ORDER BY type DESC, name ASC
        """
    ).fetchall()
    kept = set(TABLES)
    schema_parts = []
    for row in schema_rows:
        if row["tbl_name"] in kept:
            schema_parts.append(row["sql"] + ";")
    SCHEMA_FILE.write_text("\n\n".join(schema_parts) + "\n")
    print(f"  wrote schema {SCHEMA_FILE.relative_to(REPO_ROOT)}")

    # 2. Dump each table's rows
    for table in TABLES:
        try:
            cur = conn.execute(f"SELECT * FROM {table}")
        except sqlite3.OperationalError as e:
            print(f"  SKIP {table}: {e}")
            continue
        rows = [dict(row) for row in cur.fetchall()]

        # Deserialize JSON-encoded text columns into native lists
        for row in rows:
            for col in list(row.keys()):
                if (table, col) in JSON_ARRAY_COLUMNS and row[col]:
                    try:
                        row[col] = json.loads(row[col])
                    except (json.JSONDecodeError, TypeError):
                        pass  # leave as-is if not valid JSON

        # Sort deterministically
        keys = SORT_KEYS.get(table, [])
        if keys:
            rows.sort(
                key=lambda r: tuple(
                    (r[k] if r[k] is not None else "") for k in keys
                )
            )

        path = SOURCE_DIR / f"{table}.json"
        path.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")
        print(f"  extracted {table:<35} {len(rows):>5} rows")

    conn.close()


if __name__ == "__main__":
    extract()
