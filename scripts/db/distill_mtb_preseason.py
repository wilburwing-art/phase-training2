#!/usr/bin/env python3
"""Distill MTB pre-season strength into coach.db (fills the build-phase gap).

Source: MTI "Mountain Bike Pre-Season Training Plan V2" (7 weeks, 6 days/week)
from ~/repos/mti-archive/mti.db — objectives: pedaling power, bike-specific leg
strength, core strength, upper body strength. Mountain biking had off_season
(#20/#25) and maintenance (#24) routines but NO `build` routine, so pre-season
fell back to off-season content.

We distil the two STARTABLE strength days — week 1 Session 2 and the progressed
week 5 Session 30 — so MTB's lift days rotate instead of repeating. The plan's
other days (FTP assessment, threshold intervals, easy/moderate spins) are rides:
read-and-log sport sessions, not set/rep routines, so they're not distilled here.

Adds 5 signature MTI movements (Scotty Bobs, DB Squat Thrust, Leg Blaster,
Kneeling Curl to Press, Mr. Spectacular) so the sessions read like the source.
Idempotent: re-running skips routines whose slug already exists.

Run:  python3 scripts/db/distill_mtb_preseason.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"
MOUNTAIN_BIKING_SPORT_ID = 2  # sport_categories: Mountain Biking

SIGNATURE = [
    dict(name="Scotty Bobs", modality="strength", movement_plane="multi_plane",
         is_compound=1, environment="home", default_sets=4, default_reps="4",
         default_rest="30 sec",
         description="MTI's dumbbell chain — push-up, row each side, then stand into a clean and press. One rep is the whole sequence; brutal full-body conditioning strength.",
         instructions="Start in push-up position gripping a pair of dumbbells. Push-up, row right, row left, hop the feet in, clean the dumbbells to the shoulders and press overhead. Lower and return to the plank for the next rep.",
         cues=["flat back in the plank", "don't pike the hips on the row", "clean with the legs, not the arms"],
         source_name="Mountain Tactical Institute", tags=["mtb", "full-body", "strength-endurance", "dumbbell"]),
    dict(name="Dumbbell Squat Thrust", modality="strength", movement_plane="sagittal",
         is_compound=1, environment="home", default_sets=3, default_reps="5",
         default_rest="45 sec",
         description="Loaded squat thrust — a burpee without the push-up or jump, holding dumbbells. Cheap, repeatable leg + trunk conditioning.",
         instructions="Standing with dumbbells at the sides, drop to a squat and place them down, kick the feet back to a plank, snap the feet back in, and stand tall.",
         cues=["keep the dumbbells under the shoulders", "flat back on the kick-back", "stand all the way up"],
         source_name="Mountain Tactical Institute", tags=["mtb", "conditioning", "legs", "dumbbell"]),
    dict(name="Leg Blaster", modality="strength", movement_plane="sagittal",
         is_compound=1, environment="home", default_sets=4, default_reps="1 round",
         default_rest="30-45 sec",
         description="MTI's full-size leg-endurance round: 20 air squats, 20 in-place lunges, 20 jumping lunges, 10 squat jumps. The big sibling of the Mini Leg Blaster.",
         instructions="Per round: 20 air squats, 20 in-place lunges (10/leg), 20 jumping lunges (10/leg), 10 squat jumps. Land soft and quiet throughout. Rest 30-45s between rounds.",
         cues=["land soft and quiet", "full depth on the squats", "quality over speed"],
         source_name="Mountain Tactical Institute", tags=["mtb", "legs", "eccentric", "durability"]),
    dict(name="Kneeling Curl to Press", modality="strength", movement_plane="sagittal",
         is_compound=1, environment="home", default_sets=4, default_reps="8",
         default_rest="30 sec",
         description="Tall-kneeling dumbbell curl straight into an overhead press — upper-body pulling and pressing strength without loading a standing spine.",
         instructions="Tall-kneeling with dumbbells at the sides, curl to the shoulders, then press overhead. Reverse under control. Keep the ribs down and glutes engaged throughout.",
         cues=["ribs down, glutes on", "no leaning back on the press", "control the lower"],
         source_name="Mountain Tactical Institute", tags=["mtb", "upper-body", "shoulders", "dumbbell"]),
    dict(name="Mr. Spectacular", modality="strength", movement_plane="multi_plane",
         is_compound=1, environment="home", default_sets=4, default_reps="5",
         default_rest="60 sec",
         description="MTI single-dumbbell complex — burpee into a clean, into a front squat, into a push press. One rep is the whole chain.",
         instructions="With one dumbbell: burpee down and back up, clean the dumbbell to the shoulder, drop into a front squat, then push press overhead. Switch hands each rep or each set.",
         cues=["one continuous chain", "drive the press with the legs", "switch sides evenly"],
         source_name="Mountain Tactical Institute", tags=["mtb", "full-body", "power", "dumbbell"]),
]

ROUTINES = [
    dict(
        name="MTB Pre-Season Strength — Leg Blasters + Grind",
        goal="strength", difficulty="intermediate", phase="build", duration_minutes=45,
        frequency="1-2x/week", environment="home", time_commitment="45 min",
        notes="Pre-season bike-specific leg strength + trunk. Leg blasters paired with Scotty Bobs, "
              "then a 15-minute grind — work steadily through the circuit, not frantically.",
        source_name="MTI Mountain Bike Pre-Season V2 (distilled)",
        tags=["mountain-biking", "mtb", "pre-season", "strength", "legs", "grind"],
        exercises=[
            ("Mini Leg Blaster", 8, "1 round", "30 sec", 1, "8 rounds, paired with Scotty Bobs"),
            ("Scotty Bobs", 8, "4", "30 sec", 1, "@ 15/25# dumbbells"),
            ("Dumbbell Squat Thrust", 3, "5", None, 2, "15-min grind @ 15/25# — steady, not frantic"),
            ("Standing Founder", 3, "15/15 sec", None, 2, None),
            ("Kneeling Slasher", 3, "10", None, 2, "@ 15/25#"),
            ("Back Extension", 3, "10", None, 2, "Face down"),
            ("Standing Calf Raise", 4, "20 sec", "10 sec", None, "4 rounds, 20s on / 10s off"),
        ],
    ),
    dict(
        name="MTB Pre-Season Strength — Power Grind",
        goal="power", difficulty="advanced", phase="build", duration_minutes=55,
        frequency="1-2x/week", environment="home", time_commitment="55 min",
        notes="Progressed pre-season session (plan week 5): full leg blasters, then a 20-minute grind. "
              "Upper-body work stays kneeling to spare the spine after the leg volume.",
        source_name="MTI Mountain Bike Pre-Season V2, week 5 (distilled)",
        tags=["mountain-biking", "mtb", "pre-season", "power", "strength", "grind"],
        exercises=[
            ("Leg Blaster", 4, "1 round", "30 sec", 1, "Full leg blaster"),
            ("Kneeling Curl to Press", 4, "8", "30 sec", 1, "@ 15/25#"),
            ("Mini Leg Blaster", 4, "1 round", "30 sec", 2, "Second block"),
            ("Mr. Spectacular", 4, "5", None, 3, "20-min grind @ 15/25#"),
            ("Dumbbell Romanian Deadlift", 4, "15", None, 3, "DB hinge lift @ 15/25#"),
            ("Kneeling Slasher", 4, "5", None, 3, "Slasher to halo @ 15/25#"),
            ("Standing Founder", 4, "15/15 sec", None, 3, None),
            ("Standing Calf Raise", 8, "20 sec", "10 sec", None, "8 rounds, 20s on / 10s off"),
        ],
    ),
]


def slugify(name):
    out = []
    for ch in name.lower():
        if ch.isalnum():
            out.append(ch)
        elif ch in " -—–/&+'.":
            out.append("-")
    s = "".join(out)
    while "--" in s:
        s = s.replace("--", "-")
    return s.strip("-")


def load(n):
    return json.load((SOURCE / f"{n}.json").open())


def save(n, rows):
    with (SOURCE / f"{n}.json").open("w") as f:
        json.dump(rows, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main():
    exercises = load("exercises")
    routines = load("routines")
    routine_exercises = load("routine_exercises")
    routine_sports = load("routine_sports")

    ex_keys = list(exercises[0].keys())
    rt_keys = list(routines[0].keys())
    re_keys = list(routine_exercises[0].keys())
    name_to_id = {e["name"].lower(): e["id"] for e in exercises}

    def blank(keys):
        return {k: None for k in keys}

    next_ex_id = max(e["id"] for e in exercises) + 1
    added_sig = []
    for sig in SIGNATURE:
        if sig["name"].lower() in name_to_id:
            continue
        row = blank(ex_keys)
        row.update(
            id=next_ex_id, name=sig["name"], slug=slugify(sig["name"]),
            description=sig["description"], instructions=sig["instructions"],
            cues=sig["cues"], difficulty="intermediate", modality=sig["modality"],
            movement_plane=sig["movement_plane"], is_unilateral=0,
            is_compound=sig["is_compound"], environment=sig["environment"],
            default_sets=sig["default_sets"], default_reps=sig["default_reps"],
            default_rest=sig["default_rest"], source_name=sig["source_name"],
            source_type="coaching", tags=json.dumps(sig["tags"]),
        )
        exercises.append(row)
        name_to_id[sig["name"].lower()] = next_ex_id
        added_sig.append((next_ex_id, sig["name"]))
        next_ex_id += 1

    existing_slugs = {r["slug"] for r in routines}
    next_rt_id = max(r["id"] for r in routines) + 1
    next_re_id = max((r["id"] for r in routine_exercises), default=0) + 1
    unresolved, added = [], []

    for spec in ROUTINES:
        slug = slugify(spec["name"])
        if slug in existing_slugs:
            print(f"  skip (exists): {slug}")
            continue
        rid = next_rt_id
        next_rt_id += 1
        rrow = blank(rt_keys)
        rrow.update(
            id=rid, name=spec["name"], slug=slug, description=spec["notes"],
            goal=spec["goal"], difficulty=spec["difficulty"], phase=spec["phase"],
            duration_minutes=spec["duration_minutes"], frequency=spec["frequency"],
            environment=spec["environment"], time_commitment=spec["time_commitment"],
            notes=spec["notes"], source_name=spec["source_name"],
            tags=json.dumps(spec["tags"]),
            created_at="2026-07-18 00:00:00", updated_at="2026-07-18 00:00:00",
        )
        routines.append(rrow)
        routine_sports.append({"routine_id": rid, "sport_id": MOUNTAIN_BIKING_SPORT_ID})

        for pos, (mv, sets, reps, rest, ss, notes) in enumerate(spec["exercises"], start=1):
            ex_id = name_to_id.get(mv.lower())
            if ex_id is None:
                unresolved.append((spec["name"], mv))
                continue
            xrow = blank(re_keys)
            xrow.update(id=next_re_id, routine_id=rid, exercise_id=ex_id, position=pos,
                        superset_group=ss, sets=sets, reps=reps, rest=rest, notes=notes)
            routine_exercises.append(xrow)
            next_re_id += 1
        added.append((rid, spec["name"]))

    save("exercises", exercises)
    save("routines", routines)
    save("routine_exercises", routine_exercises)
    save("routine_sports", routine_sports)

    print("Signature movements added:")
    for i, n in added_sig:
        print(f"  {i}  {n}")
    print("Routines added:")
    for i, n in added:
        print(f"  {i}  {n}")
    if unresolved:
        print("\nUNRESOLVED:")
        for r, m in unresolved:
            print(f"  [{r}] {m}")
    else:
        print("\nAll movements resolved to catalog exercise ids.")


if __name__ == "__main__":
    main()
