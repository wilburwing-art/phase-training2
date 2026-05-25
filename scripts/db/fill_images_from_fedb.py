#!/usr/bin/env python3
"""Fill image_url + thumbnail_url + attribution fields on the proposed
new-exercises CSV by matching against yuhonas/free-exercise-db.

Mirrors the matching logic in sync_free_exercise_db.py but operates on the
CSV produced by draft_new_exercises.py — so we can fill images BEFORE the
new rows are merged into the canonical exercises.json.

Idempotent: never overwrites an existing image_url. Re-runnable.

Run:
    python3 scripts/db/fill_images_from_fedb.py [--csv path]
"""
from __future__ import annotations
import argparse
import csv
import json
import re
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CSV = REPO_ROOT / "proposed_new_exercises.csv"
FEDB_URL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
IMAGE_BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"

# Manual overrides where source-app and free-exercise-db names diverge enough
# that fuzzy match misses but we KNOW the intent. Maps our source name → FEDB id.
MANUAL_OVERRIDES: dict[str, str] = {
    "Bent Over One Arm Row (Dumbbell)": "Bent_Over_Two-Dumbbell_Row",  # closest
    "Chest Press (Machine)":            "Hammer_Grip_Incline_DB_Bench_Press",  # weak; manual review
    "Chest Fly (Dumbbell)":             "Dumbbell_Flyes",
    "Chest Fly":                        "Cable_Crossover",
    "Cable Row (Single Arm)":           "Seated_Cable_Rows",
    "Calf Press on Seated Leg Press":   "Calf_Press",
    "Chest Dip (Assisted)":             "Dips_-_Chest_Version",
    "Cross Body Crunch":                "Cross-Body_Crunch",
    "Deadlift High Pull (Barbell)":     "Clean_Pull",
    "Flat Knee Raise":                  "Lying_Leg_Raise",
    "Handstand Push Up":                "Handstand_Push-Ups",
    "Incline Chest Fly (Dumbbell)":     "Incline_Dumbbell_Flyes",
    "Hip Adductor (Machine)":           "Thigh_Adductor",
    "Jump Shrug (Barbell)":             "Barbell_Shrug",
    "Knee Raise (Captain's Chair)":     "Air_Bike",  # captain's chair knee raise
    "Kneeling Pulldown (Band)":         "Wide-Grip_Lat_Pulldown",
    "L-Sit":                            "L-Sit",
    "Lat Pulldown - Underhand (Cable)": "Close-Grip_Front_Lat_Pulldown",
    "Lat Pulldown - Underhand (Band)":  "Wide-Grip_Lat_Pulldown",
    "Lat Pulldown (Single Arm)":        "One-Arm_High-Pulley_Cable_Side_Bends",  # weak
    "Lateral Box Jump":                 "Side_To_Side_Box_Shuffle",
    "Lunge (Barbell)":                  "Barbell_Walking_Lunge",
    "Lunge (Bodyweight)":               "Bodyweight_Walking_Lunge",
    "Lunge (Dumbbell)":                 "Dumbbell_Lunges",
    "Medicine Ball Slam":               "Slam_Ball",
    "Muscle Up":                        "Muscle_Up",
    "Overhead Press (Smith Machine)":   "Smith_Machine_Overhead_Shoulder_Press",
    "Pistol Squat":                     "Pistol_Squat",
    "Plyo Push-Up":                     "Clap_Push_Up",
    "Press Under (Barbell)":            "Snatch_Pulls",
    "Reverse Grip Concentration Curl (Dumbbell)": "Concentration_Curls",
    "Reverse Plank":                    "Reverse_Plank",
    "Rowing (Machine)":                 "Rowing_Stationary",
    "Running (Treadmill)":              "Walking_Treadmill",
    "Seated Wide-Grip Row (Cable)":     "Wide-Grip_Seated_Cable_Row",
    "Shoulder Press (Machine)":         "Smith_Machine_Overhead_Shoulder_Press",  # weak
    "Single Leg Bridge":                "Glute_Bridge",
    "Single Leg Romanian Deadlift":     "Single_Leg_Hip_Extension_With_Bench",
    "Sit Up":                           "Sit-Up",
    "Skullcrusher (Barbell)":           "Lying_Triceps_Press",
    "Skullcrusher (Dumbbell)":          "Lying_Dumbbell_Tricep_Extension",
    "Snatch (Barbell)":                 "Power_Snatch",  # closest
    "Sumo Deadlift High Pull (Barbell)":"Sumo_Deadlift",  # weak
    "Toes To Bar":                      "Toes-To-Bars",
    "Torso Rotation (Machine)":         "Standing_Cable_Wood_Chop",
    "Trap Bar Deadlift":                "Trap_Bar_Deadlift",
    "Tricep Rope Pushdown":             "Tricep_Dumbbell_Kickback",
    "Triceps Dip":                      "Dips_-_Triceps_Version",
    "Triceps Dip (Assisted)":           "Dips_-_Triceps_Version",
    "Upright Row (Cable)":              "Cable_Rope_Rear-Delt_Rows",
    "Upright Row (Dumbbell)":           "Upright_Row_-_With_Bands",
    "V Up":                             "Sit-Up",  # closest
}

_PLURAL_STRIP = re.compile(r"(?<=[a-z])s\b")


def normalize(name: str) -> str:
    s = name.lower().replace("-", "")
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    s = _PLURAL_STRIP.sub("", s)
    return s


def token_set(s: str) -> frozenset[str]:
    return frozenset(normalize(s).split())


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--csv", default=str(DEFAULT_CSV))
    args = p.parse_args()
    csv_path = Path(args.csv)

    print(f"Fetching {FEDB_URL}...")
    with urllib.request.urlopen(FEDB_URL) as resp:
        theirs = json.load(resp)
    print(f"  catalog: {len(theirs)} entries")

    by_norm = {}
    by_tokens = {}
    by_id = {}
    for ex in theirs:
        by_norm.setdefault(normalize(ex["name"]), ex)
        by_tokens.setdefault(token_set(ex["name"]), ex)
        by_id[ex["id"]] = ex

    with csv_path.open() as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        rows = list(reader)

    manual = 0
    exact = 0
    fuzzy = 0
    no_match = []
    no_image_in_match = []

    for r in rows:
        if r.get("image_url"):
            continue  # never overwrite

        name = r["name"]
        match = None

        if name in MANUAL_OVERRIDES:
            match = by_id.get(MANUAL_OVERRIDES[name])
            if match:
                manual += 1

        if not match:
            match = by_norm.get(normalize(name))
            if match:
                exact += 1

        if not match:
            ours = token_set(name)
            if len(ours) >= 2:
                best = None
                for tt, te in by_tokens.items():
                    if len(tt) < 2:
                        continue
                    ix = len(ours & tt)
                    un = len(ours | tt)
                    if ix < 2 or un == 0:
                        continue
                    sim = ix / un
                    if sim < 0.6:
                        continue
                    score = (sim, -len(te["name"]))
                    if best is None or score > (best[0], best[1]):
                        best = (sim, -len(te["name"]), te)
                if best:
                    match = best[2]
                    fuzzy += 1

        if not match:
            no_match.append(name)
            continue

        images = match.get("images") or []
        if not images:
            no_image_in_match.append(name)
            continue

        # Prefer the second image (end position — usually clearer than 0/start).
        idx = 1 if len(images) > 1 else 0
        url = IMAGE_BASE + images[idx]
        r["image_url"] = url
        r["thumbnail_url"] = url
        r["image_source"] = "free-exercise-db"
        r["image_license"] = "MIT"
        r["image_attribution"] = "free-exercise-db (yuhonas), MIT"
        r["source_video_attribution"] = "yuhonas/free-exercise-db (Unlicense)"

    filled = sum(1 for r in rows if r.get("image_url"))
    print()
    print(f"Match summary:")
    print(f"  manual overrides:   {manual}")
    print(f"  exact name matches: {exact}")
    print(f"  fuzzy matches:      {fuzzy}")
    print(f"  no match found:     {len(no_match)}")
    print(f"  match-but-no-image: {len(no_image_in_match)}")
    print(f"\n  image_url coverage now: {filled}/{len(rows)}")

    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    print(f"\nWrote {csv_path}")

    if no_match:
        print(f"\nUnmatched ({len(no_match)} — would need other sources):")
        for n in no_match:
            print(f"  - {n}")


if __name__ == "__main__":
    main()
