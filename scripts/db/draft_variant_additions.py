#!/usr/bin/env python3
"""Draft new exercise rows for the equipment-variant gaps surfaced by
`scripts/db/audit_equipment_variants.py`.

Strategy: for each (canonical lift, missing equipment slot) pair, clone
a "template" existing exercise of the same lift (typically the barbell
or dumbbell variant), then override:
  - name        — follow db/NAMING_CONVENTION.md
  - slug        — derived from name
  - equipment   — replaced with the new slot
  - cues + a couple of demand fields where the equipment meaningfully
    changes the movement (unilateral DB vs bilateral BB, etc.)

Outputs the same artifacts the existing PR-11 pipeline expects so
merge_proposed_additions.py can apply them:
  - proposed_new_exercises.csv
  - proposed_new_equipment.json   (equipment-join rows for the new IDs)

Idempotent against repeated runs: regenerated artifacts overwrite.

Run with: uv run scripts/db/draft_variant_additions.py
"""

from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path
from typing import Optional

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "db" / "source"


# Equipment slot → equipment_id in db/source/equipment.json. Looked up
# at runtime by slug; this is the slot→slug map. When a slot maps to a
# specific machine type, we pick the most-canonical equipment row.
SLOT_TO_EQUIPMENT_SLUG = {
    "barbell":     "barbell",
    "dumbbell":    "dumbbells",
    "cable":       "cable-machine",
    "smith":       "smith-machine",
    "machine":     None,         # filled per-lift (different machines)
    "ez-bar":      "ez-bar",
    "trap-bar":    "trap-bar",
    "kettlebell":  "kettlebell",
    "band":        "band-medium",
    "landmine":    "landmine",
    "plate":       "weight-plates",
}

# When a lift uses slot=machine, which specific machine slug to attach
# (machines are slug-specific in the equipment table — not a generic
# "machine" row). Order: prefer the most-named machine for the lift.
MACHINE_SLUG_BY_LIFT = {
    "seated_row":             "iso-lateral-machine",
    "t_bar_row":              "iso-lateral-machine",
    "preacher_curl":          "bicep-curl-machine",
    "tricep_dip":             "iso-lateral-machine",
    "lateral_raise":          "iso-lateral-machine",
    "rear_delt_fly":          "pec-deck",
    "shrug":                  "shrug-machine",
    "back_squat":             "hack-squat",
    "hip_thrust":             "iso-lateral-machine",
    "standing_calf_raise":    "iso-lateral-machine",
    "seated_calf_raise":      "iso-lateral-machine",
}

# Equipment-slot human label for slug derivation
SLOT_TO_DISPLAY = {
    "barbell":     "Barbell",
    "dumbbell":    "Dumbbell",
    "cable":       "Cable",
    "smith":       "Smith Machine",
    "machine":     "Machine",
    "ez-bar":      "EZ-Bar",
    "trap-bar":    "Trap Bar",
    "kettlebell":  "Kettlebell",
    "band":        "Band",
    "landmine":    "Landmine",
    "plate":       "Plate",
}


# The additions. Hand-curated based on the audit output + spec in
# db/NAMING_CONVENTION.md. Each entry:
#   key:            internal id (matches audit canonical key when possible)
#   new_name:       exact display name (per NAMING_CONVENTION.md)
#   template_id:    existing exercise to clone (kept stable in the CSV
#                   so reviewers can diff template vs draft)
#   slot:           equipment slot for the join
#   unilateral:     None = inherit from template, otherwise override
#   notes_cues:     optional extra cue appended verbatim ("" = none)
ADDITIONS = [
    # --- BENCH PRESS family ---
    {"key": "bench_press_dumbbell", "new_name": "Dumbbell Bench Press",
     "template_id": 900, "slot": "dumbbell", "unilateral": False,
     "notes_cues": "DBs travel independently — control the path."},
    {"key": "bench_press_smith", "new_name": "Smith Machine Bench Press",
     "template_id": 900, "slot": "smith", "unilateral": False,
     "notes_cues": "Bar travels on a fixed vertical track — no balance cost."},
    {"key": "bench_press_machine", "new_name": "Machine Chest Press",
     "template_id": 1004, "slot": "machine", "machine_slug": "chest-press-machine",
     "unilateral": False, "notes_cues": ""},

    # --- INCLINE BENCH PRESS family ---
    {"key": "incline_bench_smith", "new_name": "Incline Smith Machine Bench Press",
     "template_id": 901, "slot": "smith", "unilateral": False,
     "notes_cues": "Bar travels on a fixed vertical track — no balance cost."},

    # --- CLOSE-GRIP BENCH ---
    {"key": "close_grip_dumbbell", "new_name": "Close-Grip Dumbbell Bench Press",
     "template_id": 902, "slot": "dumbbell", "unilateral": False,
     "notes_cues": "Keep DBs touching through the press for tricep emphasis."},
    {"key": "close_grip_smith", "new_name": "Close-Grip Smith Machine Bench Press",
     "template_id": 902, "slot": "smith", "unilateral": False, "notes_cues": ""},

    # --- SHOULDER PRESS ---
    {"key": "ohp_smith", "new_name": "Smith Machine Shoulder Press",
     "template_id": 1071, "slot": "smith", "unilateral": False,
     "notes_cues": "Bar path is fixed — no need to track behind the head."},
    {"key": "ohp_cable", "new_name": "Cable Shoulder Press",
     "template_id": 1071, "slot": "cable", "unilateral": False,
     "notes_cues": "Constant tension through lockout."},

    # --- ARNOLD PRESS ---
    {"key": "arnold_kb", "new_name": "Kettlebell Arnold Press",
     "template_id": 909, "slot": "kettlebell", "unilateral": False, "notes_cues": ""},

    # --- CHEST FLY ---
    {"key": "chest_fly_cable", "new_name": "Cable Chest Fly",
     "template_id": 1002, "slot": "cable", "unilateral": False,
     "notes_cues": "Constant tension at peak contraction."},

    # --- INCLINE FLY ---
    {"key": "incline_fly_cable", "new_name": "Incline Cable Fly",
     "template_id": 1026, "slot": "cable", "unilateral": False, "notes_cues": ""},

    # --- BENT-OVER ROW ---
    {"key": "bent_row_db", "new_name": "Dumbbell Bent-Over Row",
     "template_id": 992, "slot": "dumbbell", "unilateral": False,
     "notes_cues": "Both DBs row simultaneously — squeeze shoulder blades together at the top."},
    {"key": "bent_row_smith", "new_name": "Smith Machine Bent-Over Row",
     "template_id": 992, "slot": "smith", "unilateral": False,
     "notes_cues": "Use lower pins — bar travels in a fixed plane."},
    {"key": "landmine_row", "new_name": "Landmine Row",
     "template_id": 992, "slot": "landmine", "unilateral": False,
     "notes_cues": "Anchor one end of barbell — row the loaded end toward the chest."},

    # --- SEATED ROW ---
    {"key": "seated_row_machine", "new_name": "Machine Seated Row",
     "template_id": 1074, "slot": "machine", "unilateral": False, "notes_cues": ""},

    # --- SINGLE-ARM ROW ---
    {"key": "single_arm_row_kb", "new_name": "Kettlebell Single-Arm Row",
     "template_id": 991, "slot": "kettlebell", "unilateral": True, "notes_cues": ""},

    # --- CHEST-SUPPORTED ROW ---
    {"key": "csr_barbell", "new_name": "Barbell Chest-Supported Row",
     "template_id": 930, "slot": "barbell", "unilateral": False,
     "notes_cues": "Lie chest-down on a high-incline bench, row the bar to the chest."},

    # --- T-BAR ROW ---
    {"key": "tbar_machine", "new_name": "Machine T-Bar Row",
     "template_id": 1030, "slot": "machine", "unilateral": False, "notes_cues": ""},

    # --- STRAIGHT-ARM PULLDOWN ---
    {"key": "sa_pulldown_cable", "new_name": "Cable Straight-Arm Pulldown",
     "template_id": 1045, "slot": "cable", "unilateral": False,
     "notes_cues": "Slight elbow bend, drive the bar down to the thighs by pulling with the lats."},

    # --- SHRUG ---
    {"key": "shrug_cable", "new_name": "Cable Shrug",
     "template_id": 963, "slot": "cable", "unilateral": False,
     "notes_cues": "Constant tension top + bottom of the lift."},
    {"key": "shrug_smith", "new_name": "Smith Machine Shrug",
     "template_id": 963, "slot": "smith", "unilateral": False, "notes_cues": ""},
    {"key": "shrug_trap_bar", "new_name": "Trap Bar Shrug",
     "template_id": 963, "slot": "trap-bar", "unilateral": False,
     "notes_cues": "Neutral grip puts less stress on the wrists and shoulders."},
    {"key": "shrug_machine", "new_name": "Machine Shrug",
     "template_id": 963, "slot": "machine", "unilateral": False, "notes_cues": ""},

    # --- HAMMER CURL ---
    {"key": "hammer_cable", "new_name": "Cable Hammer Curl",
     "template_id": 950, "slot": "cable", "unilateral": False,
     "notes_cues": "Use a rope attachment for the neutral grip."},

    # --- PREACHER CURL ---
    {"key": "preacher_cable", "new_name": "Cable Preacher Curl",
     "template_id": 543, "slot": "cable", "unilateral": False,
     "notes_cues": "Constant tension at peak contraction."},
    {"key": "preacher_ezbar", "new_name": "EZ-Bar Preacher Curl",
     "template_id": 543, "slot": "ez-bar", "unilateral": False,
     "notes_cues": "Angled grip lowers wrist strain vs a straight bar."},
    {"key": "preacher_machine", "new_name": "Machine Preacher Curl",
     "template_id": 543, "slot": "machine", "unilateral": False, "notes_cues": ""},

    # --- INCLINE CURL ---
    {"key": "incline_curl_cable", "new_name": "Incline Cable Curl",
     "template_id": 949, "slot": "cable", "unilateral": False,
     "notes_cues": "Lean back on an incline bench, cable column behind — long-head bias."},

    # --- CONCENTRATION CURL ---
    {"key": "concentration_cable", "new_name": "Cable Concentration Curl",
     "template_id": 951, "slot": "cable", "unilateral": True,
     "notes_cues": "Use a single-handle attachment, low pulley."},

    # --- REVERSE CURL (forearm) ---
    {"key": "reverse_curl_cable", "new_name": "Cable Reverse Curl",
     "template_id": 1064, "slot": "cable", "unilateral": False, "notes_cues": ""},
    {"key": "reverse_curl_ezbar", "new_name": "EZ-Bar Reverse Curl",
     "template_id": 1064, "slot": "ez-bar", "unilateral": False,
     "notes_cues": "Pronated grip on the angled bar — easier on the wrists."},

    # --- WRIST CURL ---
    {"key": "wrist_curl_barbell", "new_name": "Barbell Wrist Curl",
     "template_id": 979, "slot": "barbell", "unilateral": False,
     "notes_cues": "Forearms on a bench, palms up — let the bar roll to the fingertips, then curl up."},

    # --- TRICEP PUSHDOWN ---
    {"key": "tricep_pushdown_band", "new_name": "Band Tricep Pushdown",
     "template_id": 1108, "slot": "band", "unilateral": False,
     "notes_cues": "Anchor band overhead — keep elbows pinned at sides."},

    # --- OVERHEAD TRICEP EXTENSION ---
    {"key": "overhead_tri_ezbar", "new_name": "EZ-Bar Overhead Tricep Extension",
     "template_id": 23, "slot": "ez-bar", "unilateral": False,
     "notes_cues": "Angled grip is easier on the wrists than a straight bar."},
    {"key": "overhead_tri_barbell", "new_name": "Barbell Overhead Tricep Extension",
     "template_id": 23, "slot": "barbell", "unilateral": False, "notes_cues": ""},

    # --- SKULLCRUSHER ---
    {"key": "skull_ezbar", "new_name": "EZ-Bar Skullcrusher",
     "template_id": 1082, "slot": "ez-bar", "unilateral": False,
     "notes_cues": "Angled grip puts less strain on the wrists at the bottom."},
    {"key": "skull_cable", "new_name": "Cable Skullcrusher",
     "template_id": 1082, "slot": "cable", "unilateral": False,
     "notes_cues": "Low pulley, EZ-bar or rope attachment — constant tension through the rep."},

    # --- TRICEP KICKBACK ---
    {"key": "kickback_cable", "new_name": "Cable Tricep Kickback",
     "template_id": 956, "slot": "cable", "unilateral": True,
     "notes_cues": "Single-handle low pulley — constant tension through the lockout."},

    # --- LATERAL RAISE ---
    {"key": "lat_raise_machine", "new_name": "Machine Lateral Raise",
     "template_id": 546, "slot": "machine", "unilateral": False,
     "notes_cues": "Strength curve matches the move — heavier at lockout."},

    # --- FRONT RAISE ---
    {"key": "front_raise_cable", "new_name": "Cable Front Raise",
     "template_id": 959, "slot": "cable", "unilateral": False,
     "notes_cues": "Low pulley behind, raise to forehead height with elbows mostly locked."},
    {"key": "front_raise_barbell", "new_name": "Barbell Front Raise",
     "template_id": 959, "slot": "barbell", "unilateral": False,
     "notes_cues": "Pronated grip, raise to forehead height."},
    {"key": "front_raise_plate", "new_name": "Plate Front Raise",
     "template_id": 959, "slot": "plate", "unilateral": False,
     "notes_cues": "Hold a single plate at 3-and-9 o'clock with both hands."},

    # --- UPRIGHT ROW ---
    {"key": "upright_row_dumbbell", "new_name": "Dumbbell Upright Row",
     "template_id": 962, "slot": "dumbbell", "unilateral": False,
     "notes_cues": "Lead with the elbows — don't let the wrists pass the elbow height."},
    {"key": "upright_row_cable", "new_name": "Cable Upright Row",
     "template_id": 962, "slot": "cable", "unilateral": False, "notes_cues": ""},
    {"key": "upright_row_smith", "new_name": "Smith Machine Upright Row",
     "template_id": 962, "slot": "smith", "unilateral": False, "notes_cues": ""},
    {"key": "upright_row_ezbar", "new_name": "EZ-Bar Upright Row",
     "template_id": 962, "slot": "ez-bar", "unilateral": False,
     "notes_cues": "Angled grip is easier on the wrists than a straight bar."},

    # --- BACK SQUAT ---
    {"key": "back_squat_smith", "new_name": "Smith Machine Back Squat",
     "template_id": 1087, "slot": "smith", "unilateral": False,
     "notes_cues": "Bar travels on a fixed track — load can be heavier than free squat."},
    {"key": "back_squat_machine", "new_name": "Machine Hack Squat",
     "template_id": 932, "slot": "machine", "unilateral": False, "notes_cues": ""},

    # --- FRONT SQUAT ---
    {"key": "front_squat_smith", "new_name": "Smith Machine Front Squat",
     "template_id": 450, "slot": "smith", "unilateral": False, "notes_cues": ""},
    {"key": "front_squat_db", "new_name": "Dumbbell Front Squat",
     "template_id": 450, "slot": "dumbbell", "unilateral": False,
     "notes_cues": "Hold DBs at shoulders — elbows up."},

    # --- BULGARIAN SPLIT SQUAT ---
    {"key": "bss_barbell", "new_name": "Barbell Bulgarian Split Squat",
     "template_id": 60, "slot": "barbell", "unilateral": True, "notes_cues": ""},
    {"key": "bss_smith", "new_name": "Smith Machine Bulgarian Split Squat",
     "template_id": 60, "slot": "smith", "unilateral": True, "notes_cues": ""},
    {"key": "bss_kb", "new_name": "Kettlebell Bulgarian Split Squat",
     "template_id": 60, "slot": "kettlebell", "unilateral": True,
     "notes_cues": "Hold one KB goblet-style or two at the shoulders."},

    # --- WALKING LUNGE ---
    {"key": "walk_lunge_barbell", "new_name": "Barbell Walking Lunge",
     "template_id": 1052, "slot": "barbell", "unilateral": True,
     "notes_cues": "Bar on the back — short stride for quad bias, long stride for glute bias."},
    {"key": "walk_lunge_kb", "new_name": "Kettlebell Walking Lunge",
     "template_id": 1052, "slot": "kettlebell", "unilateral": True,
     "notes_cues": "Hold KBs at the shoulders (rack position) or by the sides."},

    # --- REVERSE LUNGE ---
    {"key": "rev_lunge_db", "new_name": "Dumbbell Reverse Lunge",
     "template_id": 944, "slot": "dumbbell", "unilateral": True, "notes_cues": ""},
    {"key": "rev_lunge_smith", "new_name": "Smith Machine Reverse Lunge",
     "template_id": 944, "slot": "smith", "unilateral": True, "notes_cues": ""},
    {"key": "rev_lunge_kb", "new_name": "Kettlebell Reverse Lunge",
     "template_id": 944, "slot": "kettlebell", "unilateral": True, "notes_cues": ""},

    # --- STEP-UP ---
    {"key": "step_up_barbell", "new_name": "Barbell Step-Up",
     "template_id": 238, "slot": "barbell", "unilateral": True,
     "notes_cues": "Bar on the back; drive through the heel of the elevated foot."},
    {"key": "step_up_kb", "new_name": "Kettlebell Step-Up",
     "template_id": 238, "slot": "kettlebell", "unilateral": True, "notes_cues": ""},

    # --- DEADLIFT ---
    {"key": "deadlift_dumbbell", "new_name": "Dumbbell Deadlift",
     "template_id": 59, "slot": "dumbbell", "unilateral": False,
     "notes_cues": "DBs on the floor outside the feet, hinge at the hips, drive the floor away."},

    # --- ROMANIAN DEADLIFT ---
    {"key": "rdl_dumbbell", "new_name": "Dumbbell Romanian Deadlift",
     "template_id": 58, "slot": "dumbbell", "unilateral": False,
     "notes_cues": "DBs slide along the front of the legs — feel the hamstring stretch."},
    {"key": "rdl_cable", "new_name": "Cable Romanian Deadlift",
     "template_id": 58, "slot": "cable", "unilateral": False,
     "notes_cues": "Low pulley with a straight bar attachment — constant tension."},
    {"key": "rdl_smith", "new_name": "Smith Machine Romanian Deadlift",
     "template_id": 58, "slot": "smith", "unilateral": False, "notes_cues": ""},

    # --- HIP THRUST ---
    {"key": "hip_thrust_db", "new_name": "Dumbbell Hip Thrust",
     "template_id": 101, "slot": "dumbbell", "unilateral": False,
     "notes_cues": "DB across the hips with a pad — easier setup than the barbell version."},
    {"key": "hip_thrust_machine", "new_name": "Machine Hip Thrust",
     "template_id": 101, "slot": "machine", "unilateral": False, "notes_cues": ""},
    {"key": "hip_thrust_smith", "new_name": "Smith Machine Hip Thrust",
     "template_id": 101, "slot": "smith", "unilateral": False,
     "notes_cues": "Bar travels on a fixed track — easier to set up than barbell hip thrust."},

    # --- GLUTE BRIDGE ---
    {"key": "glute_bridge_barbell", "new_name": "Barbell Glute Bridge",
     "template_id": 1020, "slot": "barbell", "unilateral": False,
     "notes_cues": "Bar across the hips with a pad — squeeze glutes at the top."},
    {"key": "glute_bridge_db", "new_name": "Dumbbell Glute Bridge",
     "template_id": 1020, "slot": "dumbbell", "unilateral": False,
     "notes_cues": "Hold a single DB vertically across the hips."},

    # --- GOOD MORNING ---
    {"key": "good_morning_smith", "new_name": "Smith Machine Good Morning",
     "template_id": 921, "slot": "smith", "unilateral": False, "notes_cues": ""},

    # --- CALF RAISE ---
    {"key": "calf_db_standing", "new_name": "Dumbbell Standing Calf Raise",
     "template_id": 112, "slot": "dumbbell", "unilateral": False,
     "notes_cues": "Hold DBs at sides — toes on a small block for stretch."},
    {"key": "calf_smith_standing", "new_name": "Smith Machine Calf Raise",
     "template_id": 112, "slot": "smith", "unilateral": False, "notes_cues": ""},
    {"key": "calf_machine_standing", "new_name": "Machine Standing Calf Raise",
     "template_id": 112, "slot": "machine", "unilateral": False, "notes_cues": ""},
    {"key": "calf_db_seated", "new_name": "Dumbbell Seated Calf Raise",
     "template_id": 942, "slot": "dumbbell", "unilateral": False,
     "notes_cues": "DBs on the knees — toes on a block for stretch."},
]


# ---------------------------------------------------------------------------
# Implementation


def slugify(name: str) -> str:
    s = name.lower()
    s = re.sub(r"[°'’]", "", s)
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")


def derive_equipment_slug(spec: dict) -> str:
    slot = spec["slot"]
    if slot == "machine":
        # Explicit override on the spec wins
        if spec.get("machine_slug"):
            return spec["machine_slug"]
        slug = MACHINE_SLUG_BY_LIFT.get(_lift_key_from_spec(spec))
        if slug:
            return slug
    slug = SLOT_TO_EQUIPMENT_SLUG.get(slot)
    if not slug:
        raise ValueError(f"No equipment slug for slot {slot} (entry {spec['key']})")
    return slug


def _lift_key_from_spec(spec: dict) -> str:
    """Map a spec key back to a lift_key for the MACHINE_SLUG_BY_LIFT lookup."""
    key = spec["key"]
    if key.startswith("seated_row"):       return "seated_row"
    if key.startswith("tbar"):             return "t_bar_row"
    if key.startswith("preacher"):         return "preacher_curl"
    if key.startswith("kickback"):         return "tricep_kickback"
    if key.startswith("tricep_dip"):       return "tricep_dip"
    if key.startswith("lat_raise"):        return "lateral_raise"
    if key.startswith("rear_delt"):        return "rear_delt_fly"
    if key.startswith("shrug"):            return "shrug"
    if key.startswith("back_squat"):       return "back_squat"
    if key.startswith("hip_thrust"):       return "hip_thrust"
    if key.startswith("calf_") and "standing" in key:  return "standing_calf_raise"
    if key.startswith("calf_") and "seated"   in key:  return "seated_calf_raise"
    return key


def load_sources():
    exercises = json.loads((SRC / "exercises.json").read_text())
    equipment = json.loads((SRC / "equipment.json").read_text())
    eq_join = json.loads((SRC / "exercise_equipment.json").read_text())
    muscles_join = json.loads((SRC / "exercise_muscles.json").read_text())
    patterns_join = json.loads((SRC / "exercise_movement_patterns.json").read_text())
    muscle_groups = json.loads((SRC / "muscle_groups.json").read_text())
    movement_patterns = json.loads((SRC / "movement_patterns.json").read_text())
    return (exercises, equipment, eq_join, muscles_join, patterns_join,
            muscle_groups, movement_patterns)


def slugs_for_exercise(ex_id: int, eq_join: list, equipment: list) -> list[str]:
    eq_by_id = {e["id"]: e["slug"] for e in equipment}
    return [eq_by_id[r["equipment_id"]] for r in eq_join
            if r["exercise_id"] == ex_id and r["equipment_id"] in eq_by_id]


def main() -> int:
    (exercises, equipment, eq_join, muscles_join, patterns_join,
     muscle_groups, movement_patterns) = load_sources()
    by_id = {e["id"]: e for e in exercises}
    eq_id_by_slug = {e["slug"]: e["id"] for e in equipment}
    existing_slugs = {e["slug"] for e in exercises}
    muscle_slug_by_id = {m["id"]: m["slug"] for m in muscle_groups}
    pattern_slug_by_id = {p["id"]: p["slug"] for p in movement_patterns}

    # Validate every addition resolves before generating anything
    for spec in ADDITIONS:
        if spec["template_id"] not in by_id:
            print(f"ERROR: template id {spec['template_id']} not found "
                  f"(for {spec['key']})", file=sys.stderr)
            return 1
        derive_equipment_slug(spec)  # raises if slot unknown

    out_rows: list[dict] = []
    out_eq_join: list[dict] = []
    used_slugs: set[str] = set(existing_slugs)
    duplicate_names: list[str] = []
    existing_names = {e["name"].lower() for e in exercises}

    for spec in ADDITIONS:
        template = by_id[spec["template_id"]]
        new_eq_slug = derive_equipment_slug(spec)
        new_eq_id = eq_id_by_slug.get(new_eq_slug)
        if new_eq_id is None:
            print(f"ERROR: equipment slug '{new_eq_slug}' not in equipment.json "
                  f"(entry {spec['key']})", file=sys.stderr)
            return 1

        new_name = spec["new_name"]
        if new_name.lower() in existing_names:
            duplicate_names.append(new_name)
            continue

        new_slug = slugify(new_name)
        if new_slug in used_slugs:
            # Disambiguate with a -v2 suffix as fallback (should be rare)
            n = 2
            while f"{new_slug}-v{n}" in used_slugs:
                n += 1
            new_slug = f"{new_slug}-v{n}"
        used_slugs.add(new_slug)

        # Inherit other equipment join slugs from template (e.g. flat-bench,
        # so a Dumbbell Bench Press still tags 'flat-bench' alongside the
        # dumbbells). Replace the original primary-equipment slug with the
        # new one; keep accessories like 'flat-bench', 'cable-pulley'.
        template_eq_slugs = slugs_for_exercise(template["id"], eq_join, equipment)
        primary_swap_targets = {
            "barbell", "dumbbells", "cable-machine", "cable-crossover",
            "smith-machine", "ez-bar", "trap-bar", "kettlebell",
            "band-light", "band-medium", "band-heavy", "mini-band",
            "landmine", "weight-plates", "rowing-erg", "bodyweight",
            "bicep-curl-machine", "tricep-extension-machine",
            "iso-lateral-machine", "pec-deck", "shrug-machine",
            "hack-squat", "leg-extension", "leg-curl-machine",
            "leg-press", "lat-pulldown", "chest-press-machine",
            "shoulder-press-machine", "back-extension-machine",
        }
        new_equipment_slugs: list[str] = []
        for slug in template_eq_slugs:
            if slug in primary_swap_targets:
                continue  # drop the template's primary, we add the new one below
            new_equipment_slugs.append(slug)
        new_equipment_slugs.insert(0, new_eq_slug)

        # Build CSV row by cloning template fields + overriding name/slug/equip.
        row = {col: template.get(col, "") for col in CSV_COLUMNS}
        row["id"] = ""  # assigned at merge time
        row["name"] = new_name
        row["slug"] = new_slug
        row["equipment"] = ";".join(new_equipment_slugs)
        if spec["unilateral"] is not None:
            row["is_unilateral"] = 1 if spec["unilateral"] else 0

        # If the template's cues field is JSON-encoded, append the spec's
        # custom cue (when set) as another array entry. Otherwise leave as-is.
        if spec.get("notes_cues"):
            try:
                cues = json.loads(row.get("cues", "[]") or "[]")
                if isinstance(cues, list):
                    cues.append(spec["notes_cues"])
                    row["cues"] = json.dumps(cues, ensure_ascii=False)
            except (json.JSONDecodeError, TypeError):
                pass  # leave cues unchanged

        # Swap the equipment word in description / instructions / regression /
        # progression so they read sensibly for the new variant. Best-effort:
        # we map slot-to-display words ("Barbell" → "Smith Machine" etc.) and
        # run a case-insensitive replace. Generic placeholders that don't
        # mention equipment are left untouched.
        target_word = SLOT_TO_DISPLAY[spec["slot"]]
        for k in ("description", "instructions", "regression", "progression"):
            text = row.get(k) or ""
            if not text:
                continue
            for src_word in ("Barbell", "barbell", "Dumbbell", "dumbbell",
                             "DBs", "DB ", "Cable", "cable", "EZ-bar",
                             "EZ-Bar", "Smith Machine", "smith machine"):
                if src_word in text and src_word.lower() != target_word.lower():
                    text = text.replace(src_word, target_word)
                    break  # only one substitution per field
            row[k] = text

        # Strip any image fields — equipment-variant rows shouldn't reuse
        # the original variant's image (it's the wrong equipment).
        for k in ("image_url", "thumbnail_url", "video_url", "image_source",
                  "image_license", "image_attribution",
                  "source_video_attribution"):
            row[k] = ""

        # Stamp source attribution for the audit-derived additions.
        # source_type must be one of the schema CHECK enum:
        # ('peer_reviewed','clinical','governing_body','coaching','expert_consensus').
        row["source_name"] = "phase-training equipment-variant audit"
        row["source_type"] = "expert_consensus"
        row["created_at"] = TODAY
        row["updated_at"] = TODAY

        # Always derive muscle/pattern slugs from the template's join rows —
        # exercises.json rows don't carry those columns directly.
        row["muscles_primary"] = _join_muscles(
            template["id"], muscles_join, muscle_slug_by_id, role="primary")
        row["muscles_secondary"] = _join_muscles(
            template["id"], muscles_join, muscle_slug_by_id, role="secondary")
        row["movement_patterns"] = _join_patterns(
            template["id"], patterns_join, pattern_slug_by_id)

        out_rows.append(row)
        out_eq_join.append({
            "_slug": new_slug,
            "equipment_id": new_eq_id,
            "is_required": 1,
        })

    csv_path = REPO / "proposed_new_exercises.csv"
    with csv_path.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=CSV_COLUMNS)
        w.writeheader()
        for r in out_rows:
            w.writerow(r)

    eq_path = REPO / "proposed_new_equipment.json"
    eq_path.write_text(json.dumps(out_eq_join, indent=2))

    print(f"Wrote {csv_path.relative_to(REPO)}  ({len(out_rows)} rows)")
    print(f"Wrote {eq_path.relative_to(REPO)}  ({len(out_eq_join)} join entries)")
    if duplicate_names:
        print()
        print(f"SKIPPED {len(duplicate_names)} entries — name already in DB:")
        for n in duplicate_names:
            print(f"  {n}")
    return 0


def _join_muscles(ex_id: int, muscles_join: list,
                  muscle_slug_by_id: dict[int, str], role: str) -> str:
    out: list[str] = []
    for r in muscles_join:
        if r["exercise_id"] == ex_id and r.get("role") == role:
            slug = muscle_slug_by_id.get(r["muscle_group_id"])
            if slug and slug not in out:
                out.append(slug)
    return ";".join(out)


def _join_patterns(ex_id: int, patterns_join: list,
                   pattern_slug_by_id: dict[int, str]) -> str:
    out: list[str] = []
    for r in patterns_join:
        if r["exercise_id"] == ex_id:
            slug = pattern_slug_by_id.get(r["movement_pattern_id"])
            if slug and slug not in out:
                out.append(slug)
    return ";".join(out)


# CSV columns (copied from scripts/db/export_exercises.py / PR-11 pipeline)
CSV_COLUMNS = [
    "id", "name", "slug",
    "category", "equipment", "muscles_primary", "muscles_secondary",
    "movement_patterns", "aliases",
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

TODAY = "2026-05-26 00:00:00"


if __name__ == "__main__":
    sys.exit(main())
