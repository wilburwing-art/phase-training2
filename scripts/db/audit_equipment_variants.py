#!/usr/bin/env python3
"""Audit equipment-variant coverage across the exercise catalog.

For each of ~50 canonical lifts users actually care about, report which
equipment variants exist and which are missing.

Design notes
------------
The DB uses three naming conventions for equipment:
  - Prefix:    "Barbell Curl"
  - Embedded:  "Incline Barbell Bench Press"  ← regex on lift-name fails here
  - Suffix:    "Bench Press (Cable)"

Per-row equipment extraction therefore scans the name for ANY known
equipment token, anywhere — prefix, middle, or in a trailing paren.
Combined with the exercise_equipment join table as a secondary signal
(but the join sometimes has wrong/missing tags like Pec Deck Fly being
tagged `cable-crossover`, so name tokens win when they conflict).

Canonical-lift matching uses a `match_anywhere` substring list rather
than tight regex, because the lift name itself is sometimes split by
the embedded equipment word. We check that ALL required name tokens
appear in the row name, and NONE of the exclude tokens do.

Run with: uv run scripts/db/audit_equipment_variants.py
"""

from __future__ import annotations

import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "db" / "source"


# Equipment slot vocab.
EQUIPMENT_LABEL = {
    "barbell": "Barbell",
    "dumbbell": "Dumbbell",
    "cable": "Cable",
    "smith": "Smith Machine",
    "machine": "Machine",
    "ez-bar": "EZ-Bar",
    "trap-bar": "Trap Bar",
    "kettlebell": "Kettlebell",
    "band": "Band",
    "bodyweight": "Bodyweight",
    "rings": "Rings",
    "landmine": "Landmine",
    "plate": "Plate",
}

# Name tokens that indicate equipment. Lowercased substring match — the
# token must appear anywhere in the lowercased name. Longer phrases first
# so "smith machine" is checked before "smith" and "machine".
NAME_EQUIPMENT_TOKENS = [
    ("smith machine", "smith"),
    ("smith", "smith"),
    ("trap bar", "trap-bar"),
    ("trap-bar", "trap-bar"),
    ("hex bar", "trap-bar"),
    ("ez-bar", "ez-bar"),
    ("ez bar", "ez-bar"),
    ("barbell", "barbell"),
    ("dumbbell", "dumbbell"),
    ("kettlebell", "kettlebell"),
    ("cable", "cable"),
    ("machine", "machine"),
    ("landmine", "landmine"),
    ("(rings)", "rings"),
    ("(band)", "band"),
    ("(bodyweight)", "bodyweight"),
    ("(plate)", "plate"),
]

# Equipment SLUG (from equipment.json) → slot. Authoritative mapping.
# Filled in from equipment.json at load time, plus these explicit overrides
# for slugs that don't follow the heuristic.
SLUG_TO_SLOT_OVERRIDES = {
    "leg-extension":           "machine",
    "leg-extension-machine":   "machine",
    "leg-curl-machine":        "machine",
    "leg-press":               "machine",
    "leg-press-machine":       "machine",
    "hack-squat-machine":      "machine",
    "hack-squat":              "machine",
    "lat-pulldown":            "cable",
    "lat-pulldown-machine":    "machine",
    "seated-row-machine":      "machine",
    "chest-press-machine":     "machine",
    "shoulder-press-machine":  "machine",
    "pec-deck":                "machine",
    "cable-crossover":         "cable",
    "cable-machine":           "cable",
    "cable-column":            "cable",
    "smith-machine":           "smith",
    "olympic-barbell":         "barbell",
    "trap-bar":                "trap-bar",
    "hex-bar":                 "trap-bar",
    "ez-bar":                  "ez-bar",
    "ez-curl-bar":             "ez-bar",
    "kettlebell":              "kettlebell",
    "barbell":                 "barbell",
    "dumbbell":                "dumbbell",
    "dumbbells":               "dumbbell",
    "resistance-band":         "band",
    "resistance-bands":        "band",
    "elastic-band":            "band",
    "rings":                   "rings",
    "gymnastic-rings":         "rings",
    "landmine":                "landmine",
    "weight-plate":            "plate",
    "plate":                   "plate",
}


# Canonical lifts — each entry:
#   key:     short id (internal)
#   name:    display name in the report
#   require: list of substrings that MUST all appear in the lowercased name
#   exclude: substrings whose presence disqualifies a row
#   slots:   equipment slots the lift sensibly takes
CANONICAL_LIFTS = [
    # --- PUSH ---
    {"key": "bench_press", "name": "Bench Press (flat)",
     "require": [["bench press"]],
     "exclude": ["incline", "decline", "close-grip", "close grip", "wide-grip",
                 "wide grip", "reverse-grip", "reverse grip", "floor press",
                 "paused", "spoto", "one-arm", "one arm", "single-arm",
                 "single arm", "guillotine", "neutral grip", "neutral-grip"],
     "slots": ["barbell", "dumbbell", "smith", "machine"]},

    {"key": "incline_bench_press", "name": "Incline Bench Press",
     "require": [["incline", "press"]],
     "exclude": ["close-grip", "close grip", "fly", "single-arm", "one-arm",
                 "shoulder press", "reverse", "lateral"],
     "slots": ["barbell", "dumbbell", "smith", "machine"]},

    {"key": "decline_bench_press", "name": "Decline Bench Press",
     "require": [["decline", "press"]],
     "exclude": ["fly", "single-arm"],
     "slots": ["barbell", "dumbbell", "smith", "machine"]},

    {"key": "close_grip_bench", "name": "Close-Grip Bench Press",
     "require": [["close", "bench"]],
     "exclude": ["incline", "decline", "row"],
     "slots": ["barbell", "smith", "dumbbell"]},

    {"key": "shoulder_press", "name": "Shoulder Press / Overhead Press",
     "require": [["shoulder press"], ["overhead press"], ["military press"]],
     "exclude": ["arnold", "z press", "z-press", "push press", "behind",
                 "single-arm", "one-arm", "landmine", "kneeling"],
     "slots": ["barbell", "dumbbell", "smith", "machine", "cable"]},

    {"key": "arnold_press", "name": "Arnold Press",
     "require": [["arnold press"]],
     "exclude": [],
     "slots": ["dumbbell", "kettlebell"]},

    {"key": "chest_fly", "name": "Chest Fly (flat)",
     "require": [["fly"]],
     "exclude": ["incline", "decline", "rear", "reverse", "bent-over",
                 "bent over", "casting", "fishing", "superman", "leg",
                 "deck", "high", "low"],
     "slots": ["dumbbell", "cable", "machine"]},

    {"key": "incline_fly", "name": "Incline Chest Fly",
     "require": [["incline", "fly"]],
     "exclude": ["rear", "reverse"],
     "slots": ["dumbbell", "cable"]},

    {"key": "pec_deck", "name": "Pec Deck (Machine Chest Fly)",
     "require": [["pec deck"]],
     "exclude": ["rear"],
     "slots": ["machine"]},

    {"key": "cable_crossover", "name": "Cable Crossover (High-to-Low / Low-to-High)",
     "require": [["crossover"]],
     "exclude": ["rear", "reverse"],
     "slots": ["cable"]},

    # --- PULL ---
    {"key": "bent_over_row", "name": "Bent-Over Row",
     "require": [["bent", "row"], ["pendlay row"], ["yates row"]],
     "exclude": ["one-arm", "one arm", "single-arm", "single arm",
                 "underhand", "reverse-grip", "reverse grip",
                 "chest-supported", "chest supported", "t-bar", "t bar",
                 "meadows", "incline", "rear delt", "high-pull"],
     "slots": ["barbell", "dumbbell", "smith", "landmine"]},

    {"key": "seated_row", "name": "Seated Row",
     "require": [["seated row"], ["seated cable row"]],
     "exclude": ["one-arm", "single-arm"],
     "slots": ["cable", "machine"]},

    {"key": "single_arm_row", "name": "Single-Arm Row",
     "require": [["one-arm", "row"], ["one arm", "row"],
                 ["single-arm", "row"], ["single arm", "row"]],
     "exclude": ["seated", "chest-supported", "pulldown"],
     "slots": ["dumbbell", "cable", "kettlebell"]},

    {"key": "chest_sup_row", "name": "Chest-Supported Row",
     "require": [["chest-supported", "row"], ["chest supported", "row"]],
     "exclude": [],
     "slots": ["dumbbell", "machine", "barbell"]},

    {"key": "t_bar_row", "name": "T-Bar / Landmine Row",
     "require": [["t-bar row"], ["t bar row"], ["landmine row"]],
     "exclude": [],
     "slots": ["barbell", "landmine", "machine"]},

    {"key": "lat_pulldown", "name": "Lat Pulldown",
     "require": [["lat pulldown"], ["pulldown"]],
     "exclude": ["tricep", "triceps", "straight-arm", "straight arm",
                 "banded", "face", "adductor"],
     "slots": ["cable", "machine"]},

    {"key": "straight_arm_pulldown", "name": "Straight-Arm Pulldown",
     "require": [["straight-arm pulldown"], ["straight arm pulldown"]],
     "exclude": [],
     "slots": ["cable"]},

    {"key": "face_pull", "name": "Face Pull",
     "require": [["face pull"]],
     "exclude": [],
     "slots": ["cable", "band"]},

    {"key": "shrug", "name": "Shrug",
     "require": [["shrug"]],
     "exclude": ["walking", "carry"],
     "slots": ["barbell", "dumbbell", "cable", "smith", "trap-bar", "machine"]},

    # --- ARMS — BICEPS ---
    {"key": "bicep_curl", "name": "Bicep Curl (standing)",
     "require": [["curl"]],
     "exclude": ["leg curl", "wrist curl", "jefferson", "nordic", "reverse",
                 "hammer", "preacher", "concentration", "drag", "spider",
                 "zottman", "incline", "bayesian", "21s", "cheat",
                 "negative", "paused", "isometric", "myo-rep", "myo rep",
                 "eccentric", "calf", "jm", "deep", "partial", "isolation",
                 "scott", "pinwheel", "21-method", "ankle",
                 "(band)", "neck", "supination", "supinating"],
     "slots": ["barbell", "dumbbell", "cable", "ez-bar", "machine"]},

    {"key": "hammer_curl", "name": "Hammer Curl",
     "require": [["hammer curl"]],
     "exclude": [],
     "slots": ["dumbbell", "cable", "kettlebell"]},

    {"key": "preacher_curl", "name": "Preacher Curl",
     "require": [["preacher curl"], ["spider curl"], ["scott curl"]],
     "exclude": [],
     "slots": ["barbell", "dumbbell", "cable", "ez-bar", "machine"]},

    {"key": "incline_curl", "name": "Incline Curl",
     "require": [["incline", "curl"], ["bayesian curl"]],
     "exclude": ["jefferson", "leg"],
     "slots": ["dumbbell", "cable"]},

    {"key": "concentration_curl", "name": "Concentration Curl",
     "require": [["concentration curl"]],
     "exclude": [],
     "slots": ["dumbbell", "cable"]},

    {"key": "reverse_curl", "name": "Reverse Curl (forearm)",
     "require": [["reverse curl"]],
     "exclude": ["nordic", "wrist"],
     "slots": ["barbell", "dumbbell", "cable", "ez-bar"]},

    {"key": "wrist_curl", "name": "Wrist Curl",
     "require": [["wrist curl"]],
     "exclude": ["reverse", "eccentric"],
     "slots": ["barbell", "dumbbell", "cable"]},

    # --- ARMS — TRICEPS ---
    {"key": "tricep_pushdown", "name": "Tricep Pushdown",
     "require": [["tricep pushdown"], ["triceps pushdown"], ["pushdown"]],
     "exclude": ["leg", "squat", "adductor"],
     "slots": ["cable", "band"]},

    {"key": "overhead_tricep_ext", "name": "Overhead Tricep Extension",
     "require": [["overhead", "extension"], ["french press"]],
     "exclude": ["leg", "back extension", "knee", "neck"],
     "slots": ["dumbbell", "cable", "ez-bar", "barbell"]},

    {"key": "skullcrusher", "name": "Skullcrusher / Lying Tricep Extension",
     "require": [["skull"], ["lying", "tricep"], ["lying triceps"],
                 ["lying tricep press"]],
     "exclude": [],
     "slots": ["barbell", "dumbbell", "ez-bar", "cable"]},

    {"key": "tricep_kickback", "name": "Tricep Kickback",
     "require": [["kickback"]],
     "exclude": ["glute", "donkey", "hip"],
     "slots": ["dumbbell", "cable"]},

    {"key": "tricep_dip", "name": "Tricep Dip / Bench Dip / Parallel Bar Dip",
     "require": [["tricep dip"], ["bench dip"], ["triceps dip"],
                 ["dips"], ["dip ("], ["ring dip"], ["chest dip"]],
     "exclude": ["nose dip", "shoulder dip"],
     "slots": ["bodyweight", "machine"]},

    # --- DELTS ---
    {"key": "lateral_raise", "name": "Lateral Raise (Side Delt)",
     "require": [["lateral raise"], ["side raise"], ["side lateral"]],
     "exclude": ["rear", "bent-over", "bent over", "myo-rep", "myo rep",
                 "leg", "cossack", "lunge"],
     "slots": ["dumbbell", "cable", "machine"]},

    {"key": "front_raise", "name": "Front Raise",
     "require": [["front raise"]],
     "exclude": ["lateral", "rear", "leg"],
     "slots": ["dumbbell", "cable", "barbell", "plate"]},

    {"key": "rear_delt_fly", "name": "Rear Delt Fly / Reverse Fly",
     "require": [["rear delt"], ["reverse fly"], ["bent-over fly"],
                 ["bent over fly"], ["rear lateral"]],
     "exclude": ["row"],
     "slots": ["dumbbell", "cable", "machine"]},

    {"key": "upright_row", "name": "Upright Row",
     "require": [["upright row"]],
     "exclude": [],
     "slots": ["barbell", "dumbbell", "cable", "smith", "ez-bar"]},

    # --- LEGS ---
    {"key": "back_squat", "name": "Back Squat",
     "require": [["back squat"], ["high-bar squat"], ["low-bar squat"]],
     "exclude": ["box", "pause", "tempo", "pin", "partial", "bulgarian",
                 "single-leg", "single leg", "good morning", "front"],
     "slots": ["barbell", "smith", "machine"]},

    {"key": "front_squat", "name": "Front Squat",
     "require": [["front squat"]],
     "exclude": ["goblet"],
     "slots": ["barbell", "smith", "dumbbell"]},

    {"key": "goblet_squat", "name": "Goblet Squat",
     "require": [["goblet squat"]],
     "exclude": [],
     "slots": ["dumbbell", "kettlebell"]},

    {"key": "bulgarian_split_squat", "name": "Bulgarian Split Squat",
     "require": [["bulgarian"], ["rear-foot-elevated split"]],
     "exclude": [],
     "slots": ["dumbbell", "barbell", "smith", "kettlebell"]},

    {"key": "walking_lunge", "name": "Walking Lunge",
     "require": [["walking lunge"]],
     "exclude": ["bosu", "beach", "cossack"],
     "slots": ["dumbbell", "barbell", "kettlebell"]},

    {"key": "reverse_lunge", "name": "Reverse Lunge",
     "require": [["reverse lunge"]],
     "exclude": ["bosu"],
     "slots": ["dumbbell", "barbell", "smith", "kettlebell"]},

    {"key": "step_up", "name": "Step-Up",
     "require": [["step-up"], ["step up"]],
     "exclude": [],
     "slots": ["dumbbell", "barbell", "kettlebell"]},

    {"key": "deadlift_conventional", "name": "Conventional Deadlift",
     "require": [["deadlift"]],
     "exclude": ["romanian", "stiff", "stiff-leg", "sumo", "deficit", "block",
                 "single-leg", "single leg", "b-stance", "snatch", "jefferson",
                 "high-pull", "high pull", "rdl"],
     "slots": ["barbell", "dumbbell", "trap-bar"]},

    {"key": "rdl", "name": "Romanian Deadlift",
     "require": [["romanian deadlift"], ["rdl"], ["stiff-leg deadlift"],
                 ["stiff leg deadlift"]],
     "exclude": ["single-leg", "single leg", "b-stance"],
     "slots": ["barbell", "dumbbell", "cable", "smith"]},

    {"key": "sl_rdl", "name": "Single-Leg RDL",
     "require": [["single-leg", "romanian"], ["single-leg rdl"],
                 ["single leg rdl"], ["b-stance rdl"]],
     "exclude": [],
     "slots": ["dumbbell", "kettlebell", "barbell"]},

    {"key": "sumo_deadlift", "name": "Sumo Deadlift",
     "require": [["sumo deadlift"]],
     "exclude": [],
     "slots": ["barbell", "trap-bar"]},

    {"key": "hip_thrust", "name": "Hip Thrust",
     "require": [["hip thrust"]],
     "exclude": ["single-leg", "single leg", "b-stance"],
     "slots": ["barbell", "dumbbell", "machine", "smith"]},

    {"key": "glute_bridge", "name": "Glute Bridge",
     "require": [["glute bridge"]],
     "exclude": ["single-leg", "single leg"],
     "slots": ["barbell", "dumbbell"]},

    {"key": "good_morning", "name": "Good Morning",
     "require": [["good morning"]],
     "exclude": [],
     "slots": ["barbell", "smith"]},

    {"key": "leg_extension", "name": "Leg Extension",
     "require": [["leg extension"]],
     "exclude": ["terminal knee"],
     "slots": ["machine"]},

    {"key": "leg_curl_lying", "name": "Lying Leg Curl (Hamstring)",
     "require": [["lying leg curl"], ["prone leg curl"]],
     "exclude": [],
     "slots": ["machine", "cable"]},

    {"key": "leg_curl_seated", "name": "Seated Leg Curl (Hamstring)",
     "require": [["seated leg curl"]],
     "exclude": [],
     "slots": ["machine"]},

    {"key": "leg_press", "name": "Leg Press / Hack Squat",
     "require": [["leg press"], ["hack squat"]],
     "exclude": [],
     "slots": ["machine"]},

    {"key": "standing_calf_raise", "name": "Standing Calf Raise",
     "require": [["standing calf raise"], ["calf raise"]],
     "exclude": ["seated", "donkey", "single-leg", "single leg", "deficit",
                 "eccentric", "endurance", "relevé", "knee"],
     "slots": ["barbell", "dumbbell", "smith", "machine"]},

    {"key": "seated_calf_raise", "name": "Seated Calf Raise",
     "require": [["seated calf raise"]],
     "exclude": [],
     "slots": ["machine", "dumbbell"]},
]


def build_slug_to_slot(equipment: list[dict]) -> dict[str, str]:
    out = dict(SLUG_TO_SLOT_OVERRIDES)
    for e in equipment:
        slug = e["slug"]
        if slug in out:
            continue
        # Heuristic for slugs not explicitly mapped
        if "smith" in slug:
            out[slug] = "smith"
        elif slug == "kettlebell":
            out[slug] = "kettlebell"
        elif "ez" in slug and "bar" in slug:
            out[slug] = "ez-bar"
        elif "trap-bar" in slug or "hex-bar" in slug:
            out[slug] = "trap-bar"
        elif "landmine" in slug:
            out[slug] = "landmine"
        elif "cable" in slug:
            out[slug] = "cable"
        elif "band" in slug:
            out[slug] = "band"
        elif "ring" in slug:
            out[slug] = "rings"
        elif slug == "bodyweight":
            out[slug] = "bodyweight"
        elif "machine" in slug:
            out[slug] = "machine"
    return out


def slots_from_name(name: str) -> set[str]:
    n = name.lower()
    out = set()
    for tok, slot in NAME_EQUIPMENT_TOKENS:
        if tok in n:
            out.add(slot)
            # First match per token category is enough; longer-first ordering
            # protects "smith machine" from also matching "machine".
            # But we want both barbell AND machine if "Barbell Bench Press
            # (Machine)" — so we just accumulate.
    return out


def slots_from_join(ex_id: int, eq_join: dict[int, set[str]],
                    slug_to_slot: dict[str, str]) -> set[str]:
    out = set()
    for slug in eq_join.get(ex_id, set()):
        if slug in slug_to_slot:
            out.add(slug_to_slot[slug])
    return out


def load():
    exercises = json.loads((SRC / "exercises.json").read_text())
    eq = json.loads((SRC / "equipment.json").read_text())
    eq_by_id = {e["id"]: e["slug"] for e in eq}
    join_rows = json.loads((SRC / "exercise_equipment.json").read_text())
    aliases = json.loads((SRC / "exercise_aliases.json").read_text())

    # exercise_id → set of equipment slugs
    eq_join: dict[int, set[str]] = defaultdict(set)
    for r in join_rows:
        slug = eq_by_id.get(r["equipment_id"])
        if slug:
            eq_join[r["exercise_id"]].add(slug)

    slug_to_slot = build_slug_to_slot(eq)
    return exercises, dict(eq_join), slug_to_slot, aliases


def lift_matches(name: str, lift: dict) -> bool:
    n = name.lower()
    # require: list of token-tuples, ANY tuple matches if ALL its tokens appear
    if not any(all(tok in n for tok in toks) for toks in lift["require"]):
        return False
    if any(tok in n for tok in lift["exclude"]):
        return False
    return True


def main() -> int:
    exercises, eq_join, slug_to_slot, aliases = load()

    rows = []
    for lift in CANONICAL_LIFTS:
        slots_present: dict[str, list[tuple[int, str]]] = defaultdict(list)
        unspecced: list[tuple[int, str]] = []

        for ex in exercises:
            if not lift_matches(ex["name"], lift):
                continue
            # Equipment slots: union of name-token and join-table signals
            slots = slots_from_name(ex["name"]) | slots_from_join(
                ex["id"], eq_join, slug_to_slot
            )
            # Bodyweight inference: if a lift sensibly takes "bodyweight"
            # AND the row has no equipment signal at all, treat it as
            # bodyweight. Catches "Dips (Parallel Bar)" / "Chest Dip" /
            # "Ring Dip" etc. where the row is just unstamped.
            if not slots and "bodyweight" in lift["slots"]:
                slots.add("bodyweight")
            # Filter to slots this lift cares about
            relevant = slots & set(lift["slots"])
            if not relevant:
                unspecced.append((ex["id"], ex["name"]))
                continue
            for s in relevant:
                slots_present[s].append((ex["id"], ex["name"]))

        existing = sorted(slots_present.keys())
        missing = [s for s in lift["slots"] if s not in slots_present]

        rows.append({
            "lift_key": lift["key"],
            "canonical_name": lift["name"],
            "expected_slots": ", ".join(EQUIPMENT_LABEL[s] for s in lift["slots"]),
            "existing_slots": ", ".join(EQUIPMENT_LABEL[s] for s in existing) or "—",
            "missing_slots": ", ".join(EQUIPMENT_LABEL[s] for s in missing) or "—",
            "existing_example_ids": ", ".join(
                str(slots_present[s][0][0]) for s in existing if slots_present[s]
            ),
            "existing_example_names": " | ".join(
                f"{s}={slots_present[s][0][1]}" for s in existing if slots_present[s]
            ),
            "unspecced_matches_first3": " | ".join(f"{i}:{n}" for i, n in unspecced[:3]),
        })

    out = REPO / "equipment_audit_report.csv"
    with out.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    # Console summary
    print(f"Wrote {out.relative_to(REPO)} — {len(rows)} canonical lifts audited")
    print()
    print("Lifts with missing equipment variants:")
    gap_count = 0
    by_slot = defaultdict(int)
    for r in rows:
        if r["missing_slots"] != "—":
            gap_count += 1
            for m in r["missing_slots"].split(", "):
                by_slot[m] += 1
            print(f"  {r['canonical_name']:42s} missing: {r['missing_slots']}")
    print()
    print(f"Total canonical lifts with at least one gap: {gap_count}/{len(rows)}")
    print()
    print("Gap totals by equipment slot:")
    for slot, n in sorted(by_slot.items(), key=lambda x: -x[1]):
        print(f"  {slot:15s} {n}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
