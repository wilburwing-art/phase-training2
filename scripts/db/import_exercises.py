#!/usr/bin/env python3
"""Import an edited exercises CSV back into db/source/*.json + rebuild coach.db.

Round-trip partner for `export_exercises.py`. Reads a CSV produced by that
exporter (or one the user has hand-edited / extended with new rows), validates
each row, and rewrites the canonical source files:

  - db/source/exercises.json
  - db/source/exercise_aliases.json
  - db/source/exercise_equipment.json
  - db/source/exercise_muscles.json
  - db/source/exercise_movement_patterns.json

Then invokes `build_db.py` to regenerate coach.db.

New-row workflow: leave `id` blank in the CSV. The script assigns the next
available id and derives a kebab-case slug from `name`. Existing rows keep
their id stable so foreign-key references in routines / substitutions / etc.
stay intact.

Multi-value columns (equipment, muscles_primary, muscles_secondary,
movement_patterns, aliases) must use ';' as the separator. Empty = none.

Run:
    python3 scripts/db/import_exercises.py exercises.csv
    python3 scripts/db/import_exercises.py exercises.csv --dry-run   # validate only
    python3 scripts/db/import_exercises.py exercises.csv --no-rebuild # skip build_db.py
"""

import argparse
import csv
import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = REPO_ROOT / "db" / "source"
BUILD_SCRIPT = REPO_ROOT / "scripts" / "db" / "build_db.py"


# Fields we copy verbatim from the CSV into exercises.json. Keep ids OUT of
# this list — id handling is special. cues is also special (it's JSON-encoded).
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


def slugify(name: str) -> str:
    s = name.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s


def split_multi(value: str) -> list[str]:
    if not value:
        return []
    return [v.strip() for v in value.split(";") if v.strip()]


def coerce(field: str, raw: str):
    """CSV stores everything as strings; widen to int / None where the schema wants it."""
    if raw == "" or raw is None:
        return None
    if field in INT_FIELDS:
        try:
            return int(raw)
        except ValueError:
            raise ValueError(f"field {field!r} expected int, got {raw!r}")
    if field == "cues":
        # cues round-trips as a JSON-encoded array string in the CSV.
        try:
            parsed = json.loads(raw)
            return parsed if isinstance(parsed, list) else [str(parsed)]
        except json.JSONDecodeError:
            return [raw]
    return raw


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("csv_path")
    parser.add_argument("--dry-run", action="store_true",
                        help="validate the CSV without writing any files")
    parser.add_argument("--no-rebuild", action="store_true",
                        help="skip the build_db.py invocation at the end")
    args = parser.parse_args()

    csv_path = Path(args.csv_path).resolve()
    if not csv_path.exists():
        sys.exit(f"missing CSV: {csv_path}")

    # Load lookups — we resolve slugs back to ids when writing the join tables.
    equipment_rows = json.loads((SOURCE_DIR / "equipment.json").read_text())
    muscles_rows = json.loads((SOURCE_DIR / "muscle_groups.json").read_text())
    patterns_rows = json.loads((SOURCE_DIR / "movement_patterns.json").read_text())

    equipment_id_by_slug = {r["slug"]: r["id"] for r in equipment_rows}
    muscle_id_by_slug = {r["slug"]: r["id"] for r in muscles_rows}
    pattern_id_by_slug = {r["slug"]: r["id"] for r in patterns_rows}

    # Existing exercises — used to assign new ids and preserve unchanged data
    # that doesn't appear in the CSV (we don't strictly need this since the
    # exporter writes all fields, but it's a safety net).
    existing_exercises = json.loads((SOURCE_DIR / "exercises.json").read_text())
    existing_by_slug = {row["slug"]: row for row in existing_exercises}
    next_id = max((row["id"] for row in existing_exercises), default=0) + 1

    out_exercises: list[dict] = []
    out_equipment: list[dict] = []
    out_muscles: list[dict] = []
    out_patterns: list[dict] = []
    out_aliases: list[dict] = []

    errors: list[str] = []

    with csv_path.open() as f:
        reader = csv.DictReader(f)
        for lineno, row in enumerate(reader, start=2):
            name = (row.get("name") or "").strip()
            if not name:
                continue

            slug = (row.get("slug") or "").strip() or slugify(name)
            id_raw = (row.get("id") or "").strip()
            if id_raw:
                try:
                    ex_id = int(id_raw)
                except ValueError:
                    errors.append(f"row {lineno}: bad id {id_raw!r}")
                    continue
            else:
                ex_id = next_id
                next_id += 1

            # Build the exercise record. Start from the existing row (so any
            # fields the CSV didn't surface keep their values) and overlay CSV
            # data on top.
            ex_record = dict(existing_by_slug.get(slug, {}))
            ex_record["id"] = ex_id
            ex_record["name"] = name
            ex_record["slug"] = slug
            for field in PASSTHROUGH_FIELDS:
                if field in {"name", "slug"}:
                    continue
                if field in row:
                    try:
                        ex_record[field] = coerce(field, row[field])
                    except ValueError as exc:
                        errors.append(f"row {lineno} ({name}): {exc}")

            # cues lives in PASSTHROUGH but needs JSON-list coercion (handled
            # by coerce()).
            if "cues" in row and row.get("cues"):
                ex_record["cues"] = coerce("cues", row["cues"])

            out_exercises.append(ex_record)

            # Join tables
            for slug_val in split_multi(row.get("equipment", "")):
                eq_id = equipment_id_by_slug.get(slug_val)
                if eq_id is None:
                    errors.append(f"row {lineno} ({name}): unknown equipment slug {slug_val!r}")
                    continue
                out_equipment.append({"exercise_id": ex_id, "equipment_id": eq_id, "is_required": 1})

            for slug_val in split_multi(row.get("muscles_primary", "")):
                m_id = muscle_id_by_slug.get(slug_val)
                if m_id is None:
                    errors.append(f"row {lineno} ({name}): unknown muscle slug {slug_val!r}")
                    continue
                out_muscles.append({"exercise_id": ex_id, "muscle_group_id": m_id, "role": "primary"})
            for slug_val in split_multi(row.get("muscles_secondary", "")):
                m_id = muscle_id_by_slug.get(slug_val)
                if m_id is None:
                    errors.append(f"row {lineno} ({name}): unknown muscle slug {slug_val!r}")
                    continue
                out_muscles.append({"exercise_id": ex_id, "muscle_group_id": m_id, "role": "secondary"})

            for slug_val in split_multi(row.get("movement_patterns", "")):
                p_id = pattern_id_by_slug.get(slug_val)
                if p_id is None:
                    errors.append(f"row {lineno} ({name}): unknown movement_pattern slug {slug_val!r}")
                    continue
                out_patterns.append({"exercise_id": ex_id, "movement_pattern_id": p_id})

            for alias in split_multi(row.get("aliases", "")):
                out_aliases.append({"exercise_id": ex_id, "alias": alias})

    if errors:
        print("Validation failed:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        sys.exit(1)

    if args.dry_run:
        print(f"OK: {len(out_exercises)} exercises validated. (--dry-run; no writes)")
        return

    # Write files. Preserve unsorted order by id so diffs stay clean.
    def write(path: Path, data):
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        print(f"  wrote {path.relative_to(REPO_ROOT)}  ({len(data)} rows)")

    print("Writing source files:")
    write(SOURCE_DIR / "exercises.json", sorted(out_exercises, key=lambda r: r["id"]))
    write(SOURCE_DIR / "exercise_equipment.json", out_equipment)
    write(SOURCE_DIR / "exercise_muscles.json", out_muscles)
    write(SOURCE_DIR / "exercise_movement_patterns.json", out_patterns)
    write(SOURCE_DIR / "exercise_aliases.json", out_aliases)

    if args.no_rebuild:
        print("Skipped coach.db rebuild (--no-rebuild).")
        return

    print("\nRebuilding coach.db:")
    result = subprocess.run([sys.executable, str(BUILD_SCRIPT)], check=False)
    if result.returncode != 0:
        sys.exit(f"build_db.py exited {result.returncode}")


if __name__ == "__main__":
    main()
