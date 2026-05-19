#!/usr/bin/env python3
"""One-shot: prune the 227 media-less exercises in {endurance, strength, power,
mobility, breathing, agility} modalities + 19 sport-niche routines that lean
on them.

Edits the JSON source files in db/source/*.json only — the SQLite is then
rebuilt by scripts/db/build_db.py. Idempotent: re-running is a no-op once
the deletions are applied.

Run:
    python3 scripts/db/prune_media_less.py
    python3 scripts/db/build_db.py
"""
from __future__ import annotations
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

DELETED_ROUTINE_IDS = {
    40, 92, 97, 203, 208, 212, 221, 225, 240, 243,
    253, 265, 268, 284, 286, 287, 288, 289, 290,
}

DOOMED_MODALITIES = {"endurance", "strength", "power", "mobility", "breathing", "agility"}


def load(name: str) -> list:
    return json.loads((SOURCE / f"{name}.json").read_text())


def save(name: str, rows: list) -> None:
    p = SOURCE / f"{name}.json"
    p.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")


def main() -> int:
    exercises = load("exercises")
    print(f"Loaded {len(exercises)} exercises")

    doomed_ids = {
        e["id"] for e in exercises
        if not e.get("image_url") and not e.get("video_url")
        and (e.get("modality") or "").lower() in DOOMED_MODALITIES
    }
    print(f"Doomed exercises ({len(doomed_ids)}): media-less in {sorted(DOOMED_MODALITIES)}")

    surviving_exercises = [e for e in exercises if e["id"] not in doomed_ids]
    save("exercises", surviving_exercises)
    print(f"  exercises.json: {len(exercises)} → {len(surviving_exercises)}")

    # Delete routines + their junctions
    routines = load("routines")
    surviving_routines = [r for r in routines if r["id"] not in DELETED_ROUTINE_IDS]
    save("routines", surviving_routines)
    print(f"  routines.json: {len(routines)} → {len(surviving_routines)} (-{len(routines) - len(surviving_routines)})")

    # Drop routine_exercises rows belonging to deleted routines OR referencing
    # doomed exercises. The latter handles routines that survive but had a
    # slot pointing at a now-deleted exercise (groups 2-3 from the report).
    re_rows = load("routine_exercises")
    surviving_re = [
        row for row in re_rows
        if row["routine_id"] not in DELETED_ROUTINE_IDS
        and row["exercise_id"] not in doomed_ids
    ]
    save("routine_exercises", surviving_re)
    print(f"  routine_exercises.json: {len(re_rows)} → {len(surviving_re)} (-{len(re_rows) - len(surviving_re)})")

    rs_rows = load("routine_sports")
    surviving_rs = [row for row in rs_rows if row["routine_id"] not in DELETED_ROUTINE_IDS]
    save("routine_sports", surviving_rs)
    print(f"  routine_sports.json: {len(rs_rows)} → {len(surviving_rs)} (-{len(rs_rows) - len(surviving_rs)})")

    # Drop every exercise-* junction row touching a doomed exercise.
    junctions = {
        "exercise_aliases": ["exercise_id"],
        "exercise_equipment": ["exercise_id"],
        "exercise_muscles": ["exercise_id"],
        "exercise_movement_patterns": ["exercise_id"],
        "exercise_phases": ["exercise_id"],
        "exercise_injury_relevance": ["exercise_id"],
        "exercise_sport_relevance": ["exercise_id"],
        "exercise_substitutions": ["exercise_id", "substitute_id"],
    }
    for table, id_cols in junctions.items():
        rows = load(table)
        surviving = [
            row for row in rows
            if not any(row.get(col) in doomed_ids for col in id_cols)
        ]
        save(table, surviving)
        print(f"  {table}.json: {len(rows)} → {len(surviving)} (-{len(rows) - len(surviving)})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
