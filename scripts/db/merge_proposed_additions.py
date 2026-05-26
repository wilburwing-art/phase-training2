#!/usr/bin/env python3
"""Additive merger — appends the proposed new exercises + aliases into the
canonical db/source/*.json files, then runs build_db.py to regenerate
coach.db.

Inputs (created by draft_new_exercises.py + fill_images_from_fedb.py +
build_aliases.py):
  - proposed_new_exercises.csv (133 rows)
  - proposed_aliases.json       (107 alias rows)

Side effects:
  - db/source/exercises.json                ← appended
  - db/source/exercise_equipment.json       ← appended
  - db/source/exercise_muscles.json         ← appended
  - db/source/exercise_movement_patterns.json ← appended
  - db/source/exercise_aliases.json         ← appended (existing aliases preserved)
  - db/coach.db + PhaseTraining/Resources/coach.db ← regenerated

Idempotent guard: if a slug already exists in exercises.json, the script
errors out rather than appending a duplicate. Same for alias rows that
already exist.

Run:
    python3 scripts/db/merge_proposed_additions.py [--dry-run] [--no-build]
"""
from __future__ import annotations
import argparse
import csv
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = REPO_ROOT / "db" / "source"
CSV_PATH = REPO_ROOT / "proposed_new_exercises.csv"
ALIASES_PATH = REPO_ROOT / "proposed_aliases.json"
BUILD_SCRIPT = REPO_ROOT / "scripts" / "db" / "build_db.py"

PASSTHROUGH_FIELDS = [
    "name", "slug", "difficulty", "modality", "environment",
    "default_sets", "default_reps", "default_rest", "default_tempo", "default_duration",
    "is_compound", "is_unilateral",
    "movement_plane", "energy_system", "contraction_type",
    "recovery_demand", "cns_load", "intensity_category", "fatigue_type",
    "low_energy_suitable", "pre_event_safe", "warmup_compatible",
    "swap_group",
    "description", "instructions",
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

INT_FIELDS = {
    "default_sets", "is_compound", "is_unilateral",
    "recovery_demand", "cns_load",
    "low_energy_suitable", "pre_event_safe", "warmup_compatible",
    "source_year",
}


def split_multi(value: str) -> list[str]:
    if not value:
        return []
    return [v.strip() for v in value.split(";") if v.strip()]


def coerce(field: str, raw: str):
    if raw == "" or raw is None:
        return None
    if field in INT_FIELDS:
        try:
            return int(raw)
        except ValueError:
            raise ValueError(f"field {field!r} expected int, got {raw!r}")
    if field == "cues":
        try:
            parsed = json.loads(raw)
            return parsed if isinstance(parsed, list) else [str(parsed)]
        except json.JSONDecodeError:
            return [raw]
    return raw


def load(name: str):
    with (SOURCE_DIR / f"{name}.json").open() as f:
        return json.load(f)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true",
                        help="validate the additions without writing source files")
    parser.add_argument("--no-build", action="store_true",
                        help="skip the build_db.py invocation at the end")
    args = parser.parse_args()

    if not CSV_PATH.exists():
        sys.exit(f"missing {CSV_PATH}")
    if not ALIASES_PATH.exists():
        sys.exit(f"missing {ALIASES_PATH}")

    # Lookups
    equipment_id_by_slug = {r["slug"]: r["id"] for r in load("equipment")}
    muscle_id_by_slug = {r["slug"]: r["id"] for r in load("muscle_groups")}
    pattern_id_by_slug = {r["slug"]: r["id"] for r in load("movement_patterns")}

    # Existing data
    existing_exercises = load("exercises")
    existing_slugs = {e["slug"] for e in existing_exercises}
    existing_names = {e["name"].lower() for e in existing_exercises}
    next_ex_id = max((e["id"] for e in existing_exercises), default=0) + 1

    eq_rows = load("exercise_equipment")
    muscle_rows = load("exercise_muscles")
    pattern_rows = load("exercise_movement_patterns")
    alias_rows = load("exercise_aliases") if (SOURCE_DIR / "exercise_aliases.json").exists() else []
    existing_aliases = {(a.get("exercise_id"), a.get("alias", "").lower()) for a in alias_rows if isinstance(a, dict)}

    # --- Process new exercises ---
    new_ex_rows: list[dict] = []
    new_eq_rows: list[dict] = []
    new_muscle_rows: list[dict] = []
    new_pattern_rows: list[dict] = []
    slug_to_new_id: dict[str, int] = {}
    errors: list[str] = []

    with CSV_PATH.open() as f:
        reader = csv.DictReader(f)
        for lineno, row in enumerate(reader, start=2):
            name = (row.get("name") or "").strip()
            slug = (row.get("slug") or "").strip()
            if not name or not slug:
                continue
            if slug in existing_slugs:
                errors.append(f"row {lineno} ({name}): slug {slug!r} already in exercises.json")
                continue
            if name.lower() in existing_names:
                errors.append(f"row {lineno} ({name}): name already in exercises.json")
                continue

            ex_id = next_ex_id
            next_ex_id += 1
            slug_to_new_id[slug] = ex_id

            ex_record: dict = {"id": ex_id, "name": name, "slug": slug}
            for field in PASSTHROUGH_FIELDS:
                if field in {"name", "slug"}:
                    continue
                try:
                    ex_record[field] = coerce(field, row.get(field, ""))
                except ValueError as exc:
                    errors.append(f"row {lineno} ({name}): {exc}")

            # cues — special-case JSON list
            if row.get("cues"):
                ex_record["cues"] = coerce("cues", row["cues"])

            new_ex_rows.append(ex_record)

            for eq in split_multi(row.get("equipment", "")):
                eid = equipment_id_by_slug.get(eq)
                if eid is None:
                    errors.append(f"row {lineno} ({name}): unknown equipment {eq!r}")
                    continue
                new_eq_rows.append({"exercise_id": ex_id, "equipment_id": eid, "is_required": 1})

            primary_muscle_ids: set[int] = set()
            for m in split_multi(row.get("muscles_primary", "")):
                mid = muscle_id_by_slug.get(m)
                if mid is None:
                    errors.append(f"row {lineno} ({name}): unknown muscle {m!r}")
                    continue
                primary_muscle_ids.add(mid)
                new_muscle_rows.append({"exercise_id": ex_id, "muscle_group_id": mid, "role": "primary"})
            for m in split_multi(row.get("muscles_secondary", "")):
                mid = muscle_id_by_slug.get(m)
                if mid is None:
                    errors.append(f"row {lineno} ({name}): unknown muscle {m!r}")
                    continue
                # Avoid (exercise, muscle) primary+secondary collision — the
                # schema has a UNIQUE constraint on (exercise_id, muscle_group_id).
                if mid in primary_muscle_ids:
                    continue
                new_muscle_rows.append({"exercise_id": ex_id, "muscle_group_id": mid, "role": "secondary"})

            for p in split_multi(row.get("movement_patterns", "")):
                pid = pattern_id_by_slug.get(p)
                if pid is None:
                    errors.append(f"row {lineno} ({name}): unknown pattern {p!r}")
                    continue
                new_pattern_rows.append({"exercise_id": ex_id, "movement_pattern_id": pid})

    # --- Process proposed_aliases.json ---
    proposed_aliases = json.loads(ALIASES_PATH.read_text())
    new_aliases: list[dict] = []
    for entry in proposed_aliases:
        key = (entry.get("exercise_id"), entry.get("alias", "").lower())
        if key in existing_aliases:
            continue
        new_aliases.append({"exercise_id": entry["exercise_id"], "alias": entry["alias"]})

    if errors:
        print("Validation failed:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Merge plan:")
    print(f"  + {len(new_ex_rows)} new exercises")
    print(f"  + {len(new_eq_rows)} exercise_equipment rows")
    print(f"  + {len(new_muscle_rows)} exercise_muscles rows")
    print(f"  + {len(new_pattern_rows)} exercise_movement_patterns rows")
    print(f"  + {len(new_aliases)} aliases (existing preserved)")

    if args.dry_run:
        print("\n--dry-run: not writing.")
        return

    # Write back to source files (append)
    print(f"\nWriting source files:")

    def write(name: str, data):
        path = SOURCE_DIR / f"{name}.json"
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        print(f"  wrote {path.relative_to(REPO_ROOT)}  ({len(data)} rows)")

    write("exercises", existing_exercises + new_ex_rows)
    write("exercise_equipment", eq_rows + new_eq_rows)
    write("exercise_muscles", muscle_rows + new_muscle_rows)
    write("exercise_movement_patterns", pattern_rows + new_pattern_rows)
    write("exercise_aliases", alias_rows + new_aliases)

    if args.no_build:
        print("\n--no-build: skipped coach.db regen.")
        return

    print("\nRebuilding coach.db:")
    result = subprocess.run([sys.executable, str(BUILD_SCRIPT)], check=False)
    if result.returncode != 0:
        sys.exit(f"build_db.py exited {result.returncode}")


if __name__ == "__main__":
    main()
