#!/usr/bin/env python3
"""Export the exercise library to a single flat CSV for review or editing.

The DB's source-of-truth is `db/source/*.json` — exercises in one file plus
several many-to-many join tables (equipment, muscles, movement_patterns,
aliases). This script denormalizes all of that into ONE CSV row per exercise
so you can open it in Numbers / Excel / Google Sheets, scroll the catalog,
add or remove rows, and tweak fields.

Pair with `import_exercises.py` to round-trip changes back into the JSON
files + rebuild coach.db.

Multi-value columns (equipment, muscles, movement_patterns, aliases) are
semicolon-separated so commas inside field values don't break the CSV.

Run:
    python3 scripts/db/export_exercises.py                 # → exercises.csv in cwd
    python3 scripts/db/export_exercises.py --out path.csv  # → custom output path
"""

import argparse
import csv
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = REPO_ROOT / "db" / "source"

# Column ordering. The fields a curator touches most go first, then the
# descriptive blob, then the long tail. All 51 exercise fields + join
# columns are included so import is lossless.
PRIMARY_COLS = [
    "id", "name", "slug",
    "category",            # derived from primary muscle group
    "equipment",           # semicolon-joined slugs
    "muscles_primary",     # semicolon-joined slugs (role=primary)
    "muscles_secondary",   # semicolon-joined slugs (role=secondary / stabilizer)
    "movement_patterns",   # semicolon-joined slugs
    "aliases",             # semicolon-joined alternative names
    "difficulty", "modality", "environment",
    "default_sets", "default_reps", "default_rest", "default_tempo", "default_duration",
    "is_compound", "is_unilateral",
    "movement_plane", "energy_system", "contraction_type",
    "recovery_demand", "cns_load", "intensity_category", "fatigue_type",
    "low_energy_suitable", "pre_event_safe", "warmup_compatible",
    "swap_group",
    "description", "instructions", "cues",
    "regression", "progression",
    "time_efficient_variation", "home_variation", "age_considerations",
    "desk_worker_notes",
    "injury_prevention_notes", "contraindications",
    "pt_rehab_relevance", "common_compensations",
    "image_url", "thumbnail_url", "video_url",
    "image_source", "image_license", "image_attribution",
    "source_name", "source_url", "source_type", "source_year",
    "source_video_attribution",
    "tags",
    "created_at", "updated_at",
]


def load(name: str):
    with (SOURCE_DIR / f"{name}.json").open() as f:
        return json.load(f)


def build_lookup(rows: list, key: str = "id", value: str = "slug") -> dict:
    return {row[key]: row[value] for row in rows}


def category_from_muscle(muscle_slug: str) -> str:
    """Cheap heuristic: derive a body-part category from a muscle-group slug.

    Maps things like `pectoralis-major` → `Chest`, `gluteus-maximus` → `Legs`.
    Used to populate the new `category` column the filter UI will read.
    """
    s = (muscle_slug or "").lower()
    if any(t in s for t in ("pectoralis", "pec-")):
        return "Chest"
    if any(t in s for t in ("lat", "rhomboid", "trapez", "erector", "spinae", "teres", "infraspinatus", "supraspinatus")):
        return "Back"
    if any(t in s for t in ("deltoid", "rotator-cuff")):
        return "Shoulders"
    if any(t in s for t in ("bicep", "tricep", "brachialis", "brachioradialis", "forearm", "wrist")):
        return "Arms"
    if any(t in s for t in ("quadricep", "hamstring", "glute", "calf", "gastroc", "soleus", "adductor", "abductor", "tibialis", "vastus", "rectus-femoris", "semitend", "semimembr")):
        return "Legs"
    if any(t in s for t in ("abdominal", "oblique", "transverse", "rectus-abd", "core", "psoas")):
        return "Core"
    return "Other"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default="exercises.csv", help="output CSV path")
    args = parser.parse_args()

    exercises = load("exercises")
    equipment_lookup = build_lookup(load("equipment"))
    muscle_lookup = build_lookup(load("muscle_groups"))
    pattern_lookup = build_lookup(load("movement_patterns"))

    # Build per-exercise join indexes once.
    eq_by_ex: dict[int, list[str]] = {}
    for row in load("exercise_equipment"):
        eq_by_ex.setdefault(row["exercise_id"], []).append(equipment_lookup.get(row["equipment_id"], ""))

    primary_by_ex: dict[int, list[str]] = {}
    secondary_by_ex: dict[int, list[str]] = {}
    for row in load("exercise_muscles"):
        slug = muscle_lookup.get(row["muscle_group_id"], "")
        if row.get("role") == "primary":
            primary_by_ex.setdefault(row["exercise_id"], []).append(slug)
        else:
            secondary_by_ex.setdefault(row["exercise_id"], []).append(slug)

    patterns_by_ex: dict[int, list[str]] = {}
    for row in load("exercise_movement_patterns"):
        patterns_by_ex.setdefault(row["exercise_id"], []).append(pattern_lookup.get(row["movement_pattern_id"], ""))

    aliases_by_ex: dict[int, list[str]] = {}
    aliases_file = SOURCE_DIR / "exercise_aliases.json"
    if aliases_file.exists():
        for row in json.loads(aliases_file.read_text() or "[]"):
            if isinstance(row, dict) and "exercise_id" in row:
                aliases_by_ex.setdefault(row["exercise_id"], []).append(row.get("alias", ""))

    out_path = Path(args.out).resolve()
    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=PRIMARY_COLS, extrasaction="ignore")
        writer.writeheader()
        for ex in exercises:
            ex_id = ex["id"]
            primary_muscles = primary_by_ex.get(ex_id, [])
            row = dict(ex)
            # JSON-encoded fields like cues/tags/fatigue_type/contraindications/
            # common_compensations stay as raw JSON strings — round-trippable.
            if isinstance(row.get("cues"), list):
                row["cues"] = json.dumps(row["cues"], ensure_ascii=False)
            row["equipment"] = ";".join(sorted(set(eq_by_ex.get(ex_id, []))))
            row["muscles_primary"] = ";".join(sorted(set(primary_muscles)))
            row["muscles_secondary"] = ";".join(sorted(set(secondary_by_ex.get(ex_id, []))))
            row["movement_patterns"] = ";".join(sorted(set(patterns_by_ex.get(ex_id, []))))
            row["aliases"] = ";".join(aliases_by_ex.get(ex_id, []))
            # Derive body-part category from the FIRST primary muscle (most
            # exercises only have one primary; for the rare multi-primary, the
            # category UX uses the first hit anyway).
            row["category"] = category_from_muscle(primary_muscles[0]) if primary_muscles else "Other"
            writer.writerow(row)

    print(f"Wrote {len(exercises)} exercises → {out_path}")


if __name__ == "__main__":
    main()
