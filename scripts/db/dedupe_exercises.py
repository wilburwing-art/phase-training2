#!/usr/bin/env python3
"""One-shot dedupe + rename pass on db/source/*.json.

Run from repo root:
    uv run scripts/db/dedupe_exercises.py

After this lands, run scripts/db/build_db.py to regenerate db/coach.db and
PhaseTraining/Resources/coach.db.

Actions:
  * Merge 3 exact-name duplicate pairs (keep richer row, repoint all FK rows
    in related tables, de-dupe composite-PK collisions on the kept ID).
  * Merge id 693 'A-Skip Drill' into id 123 'A-Skip Running Drill' (true
    duplicate). Keep id 809 'Sprinting-Masters A-Skip' (real variant).
  * Rename id 713 'Capoeira Ginga Drill' -> 'Capoeira Ginga Step Drill' so
    it disambiguates from id 831 'Capoeira Ginga Flow'.

No sport-niche rows are deleted.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SRC = REPO_ROOT / "db" / "source"

# (drop_id, keep_id, source name) — drop row removed from exercises.json,
# all FK references rewritten to keep_id, then composite-PK collisions
# folded.
MERGES: list[tuple[int, int, str]] = [
    (473, 329, "Lateral Bound to Stick"),
    (405, 347, "Quadruped Thoracic Rotation"),
    (436, 359, "5-10-5 Pro Agility Shuttle"),
    (693, 123, "A-Skip Drill -> A-Skip Running Drill"),
]
DROP_IDS = {m[0] for m in MERGES}
REMAP: dict[int, int] = {m[0]: m[1] for m in MERGES}

# Rename only — keep id, just change name (and append a clearer description).
RENAMES: dict[int, dict] = {
    713: {
        "name": "Capoeira Ginga Step Drill",
        # leave slug capoeira-ginga to avoid breaking any external alias use;
        # the name disambiguates it from id 831 "Capoeira Ginga Flow".
    },
}

# Tables that carry exercise_id (or other FK-to-exercises columns) and the
# composite-PK columns we must respect when collapsing duplicates.
# Format: (json_filename, [list-of-exercise-fk-columns], [unique-key-columns])
RELATED: list[tuple[str, list[str], list[str] | None]] = [
    ("exercise_aliases",            ["exercise_id"], ["exercise_id", "alias"]),
    ("exercise_phases",             ["exercise_id"], ["exercise_id", "phase"]),
    ("exercise_equipment",          ["exercise_id"], ["exercise_id", "equipment_id"]),
    ("exercise_muscles",            ["exercise_id"], ["exercise_id", "muscle_group_id", "role"]),
    ("exercise_movement_patterns",  ["exercise_id"], ["exercise_id", "movement_pattern_id"]),
    ("exercise_substitutions",      ["exercise_id", "substitute_id"], ["exercise_id", "substitute_id", "context"]),
    ("exercise_injury_relevance",   ["exercise_id"], ["exercise_id", "injury_id"]),
    ("exercise_sport_relevance",    ["exercise_id"], ["exercise_id", "sport_id", "support_role"]),
    # routine_exercises has its own auto-id PK — no dedupe key, just repoint FKs.
    ("routine_exercises",           ["exercise_id"], None),
]


def load(name: str) -> list[dict]:
    with (SRC / f"{name}.json").open() as f:
        return json.load(f)


def dump(name: str, rows: list[dict]) -> None:
    with (SRC / f"{name}.json").open("w") as f:
        json.dump(rows, f, indent=2)
        f.write("\n")


def main() -> None:
    # 1. Update exercises.json — drop merged-away rows, apply renames.
    ex = load("exercises")
    kept_ex = []
    for row in ex:
        if row["id"] in DROP_IDS:
            continue
        if row["id"] in RENAMES:
            row.update(RENAMES[row["id"]])
        kept_ex.append(row)
    dump("exercises", kept_ex)
    print(f"exercises: {len(ex)} -> {len(kept_ex)} (dropped {len(ex) - len(kept_ex)})")

    # 2. Walk related tables — repoint FKs then dedupe composite keys.
    for name, fk_cols, uniq_cols in RELATED:
        rows = load(name)
        before = len(rows)
        if uniq_cols is None:
            # Auto-id table: just repoint FKs, never dedupe rows.
            for row in rows:
                for col in fk_cols:
                    if row.get(col) in REMAP:
                        row[col] = REMAP[row[col]]
            dump(name, rows)
            print(f"  {name}: {before} -> {len(rows)} (FK-repoint only)")
            continue
        seen: dict[tuple, dict] = {}
        out: list[dict] = []
        for row in rows:
            # Repoint each FK column.
            for col in fk_cols:
                if row.get(col) in REMAP:
                    row[col] = REMAP[row[col]]
            key = tuple(row.get(c) for c in uniq_cols)
            if key in seen:
                # Composite-PK collision after repoint. Merge: prefer the
                # row with more non-empty fields. For exercise_sport_relevance,
                # also prefer the higher relevance_score on ties.
                existing = seen[key]
                if _row_score(row) > _row_score(existing):
                    # Replace prior entry in out with this one.
                    for i, r in enumerate(out):
                        if r is existing:
                            out[i] = row
                            seen[key] = row
                            break
                # else keep existing — drop incoming.
                continue
            seen[key] = row
            out.append(row)
        dump(name, out)
        print(f"  {name}: {before} -> {len(out)}")

    # 3. Verify no remaining duplicate names in exercises.
    names = {}
    for r in kept_ex:
        names.setdefault(r["name"], []).append(r["id"])
    dups = {n: ids for n, ids in names.items() if len(ids) > 1}
    if dups:
        raise SystemExit(f"Duplicate names still present: {dups}")
    print("ok: no duplicate exercise names")


def _row_score(row: dict) -> tuple:
    non_empty = sum(1 for v in row.values() if v not in (None, "", [], 0))
    relevance = row.get("relevance_score") or 0.0
    return (non_empty, relevance)


if __name__ == "__main__":
    main()
