#!/usr/bin/env python3
"""Distill snowboarding/splitboard strength routines into db/source/*.json.

Phase 3 pilot. Source: the owner's shralpinism splitboard program (which itself
credits MTI Backcountry Ski Pre-Season V6, MTI In-Season Ski Maintenance V2, and
Uphill Athlete freeride/skimo plans). We distil the STARTABLE dryland strength
sessions (Strength A, Strength B, In-Season Maintenance) into coach.db routines
tagged to Snowboarding (sport_categories.id 221) — filling the gap where
snowboarding pre-season + in-season previously had zero full-session routines,
so the Phase 2 selector now serves them.

Endurance days (uphill ME, Z1-2) are intentionally NOT distilled here: they are
read-and-log sport sessions, not set/rep strength work.

Movements resolve to existing catalog exercises where possible; a small curated
SIGNATURE shortlist (Tibialis Raise, Kneeling Slasher, Mini Leg Blaster,
Standing Founder, Poor Man's Leg Curl) is added so the sessions read like the
source. Idempotent: re-running skips routines whose slug already exists.

Run:  uv run scripts/db/distill_snowboard.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

SNOWBOARDING_SPORT_ID = 221  # sport_categories: Snowboarding

# --- Curated signature movements (added only if not already in the catalog) ---
# Minimal-but-real records; build_db re-encodes `cues` (a JSON-array column).
SIGNATURE = [
    dict(name="Tibialis Raise", modality="strength", movement_plane="sagittal",
         is_compound=0, environment="home", default_sets=3, default_reps="15",
         default_rest="45 sec",
         description="Loaded dorsiflexion for the tibialis anterior — shin and ankle durability for edge control and absorbing landings.",
         instructions="Stand heels against a wall, feet out a few inches. Keeping heels down, pull the toes/forefoot up toward the shins against a band or tib-bar, then lower slowly.",
         cues=["heels stay down", "pull toes to shins", "slow lower"],
         source_name="Knees Over Toes (distilled)", tags=["snowboarding", "durability", "lower-leg"]),
    dict(name="Kneeling Slasher", modality="strength", movement_plane="transverse",
         is_compound=1, environment="home", default_sets=4, default_reps="10",
         default_rest="60 sec",
         description="Tall-kneeling rotational DB chop — builds the rotational trunk power that splitboard riding demands without loading the spine in flexion.",
         instructions="Tall-kneeling, hold a DB at one hip. Drive it diagonally up and across to the opposite shoulder ('slash'), rotating through the trunk, then return under control. Complete reps, switch sides.",
         cues=["rotate through the trunk, not the low back", "hips stay square", "control the return"],
         source_name="Mountain Tactical Institute", tags=["snowboarding", "rotational", "chassis", "core"]),
    dict(name="Mini Leg Blaster", modality="strength", movement_plane="sagittal",
         is_compound=1, environment="home", default_sets=8, default_reps="1 round",
         default_rest="30-45 sec",
         description="One round = squats + in-place lunges + jumping lunges + squat jumps. MTI's eccentric leg-strength + durability builder for controlled descents.",
         instructions="Per round: 5 air squats, 5 in-place lunges (each leg), 5 jumping lunges (each leg), 5 squat jumps. Land soft and quiet. Rest 30-45s between rounds.",
         cues=["land soft and quiet", "quality over speed", "full depth on the squats"],
         source_name="Mountain Tactical Institute", tags=["snowboarding", "eccentric", "leg", "durability"]),
    dict(name="Standing Founder", modality="strength", movement_plane="sagittal",
         is_compound=1, environment="home", default_sets=3, default_reps="15-30 sec",
         default_rest="45 sec",
         description="Standing hip-hinge isometric (Foundation Training) that decompresses and strengthens the posterior chain under tension — resilience for pack-carry hinging.",
         instructions="Hinge at the hips with a long spine, weight in the heels, arms reaching back then forward-up. Hold the tension, breathing into the posterior chain.",
         cues=["long spine", "weight in the heels", "reach through the fingertips"],
         source_name="Foundation Training", tags=["snowboarding", "posterior-chain", "hinge", "mobility"]),
    dict(name="Poor Man's Leg Curl", modality="strength", movement_plane="sagittal",
         is_compound=1, environment="home", default_sets=4, default_reps="15",
         default_rest="60 sec",
         description="Partner-free eccentric hamstring curl (nordic-style, sliders or heels-on-floor) — knee-flexor strength and ACL resilience for landings.",
         instructions="From a glute bridge, dig heels in and drag them out to extend the knees while holding the hips high, then pull back in. Sliders or a towel on a smooth floor.",
         cues=["keep the hips high", "resist on the way out", "no low-back arch"],
         source_name="Mountain Tactical Institute", tags=["snowboarding", "hamstring", "acl", "durability"]),
]

# --- Curated routines (grounded in the shralpinism rendered week sheets) ---
# Each exercise: (movement_name, sets, reps, rest, superset_group, notes)
ROUTINES = [
    dict(
        name="Splitboard Pre-Season Strength A — Squat + Eccentric + Rotation",
        goal="power", difficulty="advanced", phase="build", duration_minutes=50,
        frequency="1x/week", environment="gym", time_commitment="50 min",
        notes="Pre-season max strength + eccentric leg + rotational chassis. Squat at ~72.5% TM, 3s eccentric on the leg blasters.",
        source_name="shralpinism (MTI Backcountry Ski Pre-Season V6, distilled)",
        tags=["snowboarding", "splitboard", "pre-season", "strength", "eccentric", "rotational"],
        exercises=[
            ("Barbell Back Squat", 3, "5", "2-3 min", None, "~72.5% TM · 3s eccentric"),
            ("Mini Leg Blaster", 8, "1 round", "30-45 sec", None, "Eccentric leg — land soft"),
            ("Kneeling Slasher", 4, "10/side", "60 sec", 1, "Rotational chassis · ~25# DB"),
            ("Landmine Rotation", 4, "8/side", "60 sec", 1, None),
            ("Side Plank", 4, "30s/side", "45 sec", 1, None),
            ("Poor Man's Leg Curl", 4, "15", "60 sec", 1, None),
        ],
    ),
    dict(
        name="Splitboard Pre-Season Strength B — Hinge + Power + Upper",
        goal="power", difficulty="advanced", phase="build", duration_minutes=50,
        frequency="1x/week", environment="gym", time_commitment="50 min",
        notes="Pre-season hinge strength + jump power + upper pull/press. Deadlift ~72.5% TM, box jumps for maximal pop (not conditioning).",
        source_name="shralpinism (MTI Backcountry Ski Pre-Season V6, distilled)",
        tags=["snowboarding", "splitboard", "pre-season", "strength", "power", "upper"],
        exercises=[
            ("Trap Bar Deadlift", 3, "5", "2-3 min", None, "~72.5% TM"),
            ("Box Jump", 5, "5", "full recovery", None, "Power — maximal pop, 20in"),
            ("Barbell Overhead Press (Strict)", 3, "5", "2 min", None, "~70% TM"),
            ("Weighted Pull-Up", 3, "5", "2 min", 2, None),
            ("Standing Founder", 3, "15-30 sec", "45 sec", 2, None),
        ],
    ),
    dict(
        name="Splitboard In-Season Maintenance",
        goal="strength", difficulty="intermediate", phase="maintenance", duration_minutes=35,
        frequency="2x/week", environment="gym", time_commitment="35 min",
        notes="In-season 2x/week maintenance that defers to riding days. Keep RPE 6-7, leave reps in the tank — this protects strength, it doesn't build it.",
        source_name="shralpinism (MTI In-Season Ski Maintenance V2, distilled)",
        tags=["snowboarding", "splitboard", "in-season", "maintenance", "strength"],
        exercises=[
            ("Goblet Squat", 3, "8", "90 sec", None, "RPE 6-7"),
            ("Step-Up with Pack (High Box)", 3, "10/side", "90 sec", None, "Board-carry stimulus"),
            ("Weighted Pull-Up", 3, "6", "90 sec", None, None),
            ("Standing Calf Raise", 3, "15", "60 sec", None, None),
            ("Side Plank", 3, "30s/side", "45 sec", None, None),
        ],
    ),
]


def slugify(name: str) -> str:
    out = []
    for ch in name.lower():
        if ch.isalnum():
            out.append(ch)
        elif ch in " -—–/&+":
            out.append("-")
    s = "".join(out)
    while "--" in s:
        s = s.replace("--", "-")
    return s.strip("-")


def load(name):
    return json.load((SOURCE / f"{name}.json").open())


def save(name, rows):
    with (SOURCE / f"{name}.json").open("w") as f:
        json.dump(rows, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main():
    exercises = load("exercises")
    routines = load("routines")
    routine_exercises = load("routine_exercises")
    routine_sports = load("routine_sports")

    ex_template_keys = list(exercises[0].keys())
    rt_template_keys = list(routines[0].keys())
    re_template_keys = list(routine_exercises[0].keys())

    # name -> id resolver over the existing catalog
    name_to_id = {e["name"].lower(): e["id"] for e in exercises}

    def blank(keys):
        return {k: None for k in keys}

    # 1. Add signature movements not already present.
    next_ex_id = max(e["id"] for e in exercises) + 1
    added_sig = []
    for sig in SIGNATURE:
        if sig["name"].lower() in name_to_id:
            continue
        row = blank(ex_template_keys)
        row.update(
            id=next_ex_id, name=sig["name"], slug=slugify(sig["name"]),
            description=sig.get("description"), instructions=sig.get("instructions"),
            cues=sig.get("cues", []), difficulty="intermediate",
            modality=sig.get("modality", "strength"),
            movement_plane=sig.get("movement_plane"), is_unilateral=0,
            is_compound=sig.get("is_compound", 1), environment=sig.get("environment", "home"),
            default_sets=sig.get("default_sets"), default_reps=sig.get("default_reps"),
            default_rest=sig.get("default_rest"),
            source_name=sig.get("source_name"), source_type="coaching",
            tags=json.dumps(sig.get("tags", [])),  # exercises.tags is a JSON string
        )
        exercises.append(row)
        name_to_id[sig["name"].lower()] = next_ex_id
        added_sig.append((next_ex_id, sig["name"]))
        next_ex_id += 1

    def resolve(movement: str):
        key = movement.lower()
        if key in name_to_id:
            return name_to_id[key]
        # loose contains match as a fallback
        for n, i in name_to_id.items():
            if all(w in n for w in key.split()):
                return i
        return None

    # 2. Add routines (skip any whose slug already exists — idempotent).
    existing_slugs = {r["slug"] for r in routines}
    next_rt_id = max(r["id"] for r in routines) + 1
    next_re_id = max((r["id"] for r in routine_exercises), default=0) + 1
    unresolved = []
    added_routines = []

    for spec in ROUTINES:
        slug = slugify(spec["name"])
        if slug in existing_slugs:
            print(f"  skip (exists): {slug}")
            continue
        rid = next_rt_id
        next_rt_id += 1
        rrow = blank(rt_template_keys)
        rrow.update(
            id=rid, name=spec["name"], slug=slug, description=spec.get("notes"),
            goal=spec["goal"], difficulty=spec["difficulty"], phase=spec["phase"],
            duration_minutes=spec["duration_minutes"], frequency=spec.get("frequency"),
            environment=spec.get("environment", "gym"),
            time_commitment=spec.get("time_commitment"), notes=spec.get("notes"),
            source_name=spec.get("source_name"),
            tags=json.dumps(spec.get("tags", [])),  # routines.tags is a JSON string
            created_at="2026-07-17 00:00:00", updated_at="2026-07-17 00:00:00",
        )
        routines.append(rrow)
        routine_sports.append({"routine_id": rid, "sport_id": SNOWBOARDING_SPORT_ID})

        for pos, (mv, sets, reps, rest, ss, notes) in enumerate(spec["exercises"], start=1):
            ex_id = resolve(mv)
            if ex_id is None:
                unresolved.append((spec["name"], mv))
                continue
            xrow = blank(re_template_keys)
            xrow.update(
                id=next_re_id, routine_id=rid, exercise_id=ex_id, position=pos,
                superset_group=ss, sets=sets, reps=reps, rest=rest, notes=notes,
            )
            routine_exercises.append(xrow)
            next_re_id += 1
        added_routines.append((rid, spec["name"]))

    save("exercises", exercises)
    save("routines", routines)
    save("routine_exercises", routine_exercises)
    save("routine_sports", routine_sports)

    print("\nSignature movements added:")
    for i, n in added_sig:
        print(f"  {i}  {n}")
    print("Routines added:")
    for i, n in added_routines:
        print(f"  {i}  {n}")
    if unresolved:
        print("\nUNRESOLVED movements (fix the name or add a signature entry):")
        for r, m in unresolved:
            print(f"  [{r}] {m}")
    else:
        print("\nAll movements resolved to catalog exercise ids.")


if __name__ == "__main__":
    main()
