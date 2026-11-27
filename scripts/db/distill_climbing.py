#!/usr/bin/env python3
"""Distill the Mountain Tactical Institute climbing plans into coach.db routines.

Backlog 2026-11e 3.12. Sources are three MTI plans: Alpine Rock Climb (219, 30 sessions), AMGA
Rock Guide Course Training Plan (229, 36) and Big Wall Climbing (230, 40).

Phase follows `AuthoredRoutine.phaseLabels(for:)`: all three plans prepare for an objective (an
alpine rock day, the 10 day AMGA course, a big wall of up to 40 pitches) and none carries a
season label, so every routine is `build`.

Sport tags: 219 and 229 routines are tagged multi-pitch (108). 230 routines are tagged
aid-climbing (118) and multi-pitch (108). The family root climbing (100) is not tagged.

Shapes that repeat across weeks are one routine, written from a mid-cycle session, with the
progression in its notes. Each routine is credited to the plan it comes from.

Not distilled:
- Climbing days: the V-Sums, 4x4 bouldering groups, route laps and stamina laps on a rope, the
  15 minute top rope intervals, the traverse wall work capacity blocks and the technical work at
  the crag (219 sessions 3, 5, 8, 10, 13, 15, 18, 20, 23, 25, 28 and 30, 229 sessions 2, 5, 7, 10,
  12, 15, 17, 20, 22, 25, 27 and 30, 230 Mondays and Fridays). The campus board and strength
  blocks inside the 229 and 230 strength days are kept.
- 219 Wednesday sessions 3, 8, 13, 18, 23 and 28: the Quadzilla complex and leg curl block
  repeats the Monday routine, and the rest is route climbing. 219 Monday sessions are one
  routine, the V-Sum around the leg and core block is dropped.
- 219 step-up sessions 17, 22, 27, 19, 24 and 29, which are step-ups plus the first core block
  only, and 229 Thursday sessions 4, 9, 14, 19, 24 and 29 (step-ups, sandbag get-ups and a run):
  fewer than three catalog exercises once the run is dropped.
- Every stretch, wrist stretch, instep stretch, pigeon, glute leg raise and shoulder scarecrow
  block, and the rope coil.
- Movements with no catalog row are named in each routine note: Quadzilla complex, Scotty Bob,
  Hamstring Hell, EOs, standing and kneeling founders, low back lunge, curl to press, hello
  dollies and 3 limb bridge. Lock and reach, the campus dyno, touch jump touch and alligator
  push-ups are catalog substitutes named in the row notes.

Idempotent: a routine whose slug already exists is skipped.
Run:  python3 scripts/db/distill_climbing.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

MULTI_PITCH = (108,)
BIG_WALL = (118, 108)

ALPINE = "MTI Alpine Rock Climb (distilled)"
AMGA = "MTI AMGA Rock Guide Course Training Plan (distilled)"
WALL = "MTI Big Wall Climbing (distilled)"

STEADY = "steady"
HARD = "hard but controlled"
BW = "bodyweight"
HARD_SETS = "go hard, rest only as long as the next round needs"


ROUTINES = [
    # Alpine Rock Climb (219)
    dict(
        name="Alpine Rock Climb: Leg Curl, Push-Up and Sit-Up Strength",
        phase="build", credit=ALPINE, sports=MULTI_PITCH, minutes=30,
        notes="Source: Alpine Rock Climb Monday strength and climb sessions 1, 6, 11, 16, 21 and 26 (week 4 shown). Six rounds of a leg "
              "curl on the floor, then three rounds of push-ups and sit-ups. The leg curl rises from 15 reps and the leg complex "
              "adds one rep each week. The source also has a 15 move wall traverse each round and a 45 to 50 minute V-Sum "
              "boulder test, both dropped. Not included, no catalog match: the Quadzilla complex and the traverse.",
        movements=[
            (934, "Lying Leg Curl", 6, "15", HARD, "Substitute for the 2-leg poor man's leg curl, done on slides or a towel in the source"),
            (13, "Push-Up", 3, "5", STEADY, "Paired with sit-ups and a wall traverse each round"),
            (969, "Sit-Up", 3, "10", STEADY, BW),
        ],
    ),
    dict(
        name="Alpine Rock Climb: Step-Ups, Pull-Ups and Calves",
        phase="build", credit=ALPINE, sports=MULTI_PITCH, minutes=60,
        notes="Source: Alpine Rock Climb Tuesday step-up sessions 2, 7 and 12 (500 to 700 step-ups in a 30 lb pack, shown at 600). "
              "Do the step-ups for time first, then 4 rounds of weighted sit-ups, a front bridge and a one-leg hip bridge, then 5 "
              "rounds of calf raises and pull-ups. The step-up count rises by 100 each cycle while rounds and reps shift week to "
              "week. Sessions 17, 22 and 27 repeat the step-ups with the core block only. Not included, no catalog match: Scotty "
              "Bobs, Hamstring Hell, EOs, glute leg raises and the shoulder scarecrow.",
        movements=[
            (238, "Loaded Step-Up", 1, "600 total", "for time", "30 lb pack, 15 to 18 inch box, count total steps not per leg"),
            (969, "Sit-Up", 4, "9", STEADY, "Hold a 25 lb plate"),
            (1058, "Plank", 4, "50 sec", STEADY, "Front bridge"),
            (1080, "Single Leg Bridge", 4, "9", STEADY, "One-leg hip bridge"),
            (112, "Standing Calf Raise", 5, "25", STEADY, "Hold 25 lb"),
            (923, "Chin-Up", 5, "4-8", STEADY, "Chin-ups in session 7, pull-ups in session 2, mixed grip pull-ups in session 12"),
        ],
    ),
    dict(
        name="Alpine Rock Climb: Step-Ups, Hinge and Back Extension",
        phase="build", credit=ALPINE, sports=MULTI_PITCH, minutes=60,
        notes="Source: Alpine Rock Climb Thursday step-up sessions 4, 9 and 14 (550 to 750 step-ups in a 30 lb pack, shown at 650). "
              "Step-ups for time, then 4 rounds of timed lunge holds and a back extension, then 5 rounds of calf raises, "
              "pull-ups and a dumbbell hinge. Rounds drop and hold times rise from 15 to 20 seconds as the step-up count climbs. "
              "Sessions 19, 24 and 29 are step-ups and the first block only. Not included, no catalog match: standing and kneeling "
              "founders, low back lunge, curl to press and the lat, pec and instep stretches.",
        movements=[
            (238, "Loaded Step-Up", 1, "650 total", "for time", "30 lb pack, 15 to 18 inch box, count total steps not per leg"),
            (983, "Back Extension", 4, "10", STEADY, "Face down on the floor or a bench"),
            (112, "Standing Calf Raise", 5, "10", STEADY, "Substitute for the one-leg calf raise with 15 to 25 lb"),
            (922, "Pull-Up", 5, "3-5", STEADY, "Three for women and five for men in the source"),
            (1171, "Dumbbell Romanian Deadlift", 5, "10", STEADY, "Substitute for the dumbbell hinge, 15 to 25 lb"),
        ],
    ),
    # AMGA Rock Guide Course Training Plan (229)
    dict(
        name="AMGA Guide Course: Campus Board Strength and Back Extension",
        phase="build", credit=AMGA, sports=MULTI_PITCH, minutes=60,
        notes="Source: AMGA plan Monday climb strength sessions 1, 6, 11, 16, 21 and 26 (week 4 shown). Warm up with 3 rounds of campus "
              "pull-ups and sit-ups. Then 6 rounds of lock and reach drills, 6 rounds of two-hand campus dynos, and 4 rounds of "
              "20 second timed lunge holds with 10 back extensions. Lock and reach moves from one rung at a time to skipping as many "
              "as possible, and dynos go from skipping one rung to hitting every rung. Women may put the feet on to dyno. Air squats follow each lock and reach and dyno round. Not "
              "included, no catalog match: the traverse wall, standing and kneeling founders, low back lunge and wrist stretch.",
        movements=[
            (922, "Pull-Up", 3, "2", STEADY, "Substitute for the offset campus pull-ups in the warm-up"),
            (969, "Sit-Up", 3, "8", STEADY, "Warm-up"),
            (51, "Dynamic Lock-Off (Campus-Lite)", 6, "2 per arm", HARD, "Substitute for the campus lock and reach, ending in a hold with the other arm"),
            (47, "Campus Board Ladder (1-3-5)", 6, "up the board", HARD, "Substitute for the two-hand dyno, feet on to come down"),
            (1088, "Squat (Bodyweight)", 6, "10", STEADY, "Air squats between campus rounds"),
            (983, "Back Extension", 4, "10", STEADY, "Face down, after the timed lunge holds"),
        ],
    ),
    dict(
        name="AMGA Guide Course: Push-Ups, Pull-Ups and Climber Core A",
        phase="build", credit=AMGA, sports=MULTI_PITCH, minutes=60,
        notes="Source: AMGA plan Wednesday general fitness sessions 3, 13 and 23 (week 3 shown). Warm up 4 rounds of 5 burpees, 5 lunges and "
              "10 sit-ups. Then 7 rounds of push-ups and pull-ups, 6 rounds of a bridge, leg curls and ankle to bar, and 3 rounds of wrist "
              "eccentrics with 5 to 10 lb. Each round rises one rep a cycle: push-ups 3 for women and 5 for men, pull-ups 5 and 8. Not "
              "included, no catalog match: EOs, the 3 limb bridge, hello dollies, and the lat, pec and wrist stretches.",
        movements=[
            (216, "Burpee", 4, "5", STEADY, "Warm-up"),
            (1051, "Lunge (Bodyweight)", 4, "5", STEADY, "Warm-up"),
            (13, "Push-Up", 7, "3-5", STEADY, "Paired with pull-ups each round"),
            (922, "Pull-Up", 7, "5-8", STEADY, "Paired with push-ups each round"),
            (934, "Lying Leg Curl", 6, "15", STEADY, "Substitute for the one-leg poor man's leg curl"),
            (1099, "Toes To Bar", 6, "7", STEADY, "Source calls it ankle to bar"),
            (979, "Wrist Curl (Dumbbell)", 3, "10", "slow lowering", "Substitute for the wrist eccentrics, 5 to 10 lb"),
        ],
    ),
    dict(
        name="AMGA Guide Course: Push-Ups, Pull-Ups and Climber Core B",
        phase="build", credit=AMGA, sports=MULTI_PITCH, minutes=60,
        notes="Source: AMGA plan Wednesday general fitness sessions 8, 18 and 28 (week 4 shown). Warm up 4 rounds of 5 burpees, 5 lunges and "
              "10 sit-ups. Then 8 rounds of push-ups and pull-ups, 6 rounds of an elevated front bridge, back extensions, flutter kicks "
              "and sit-ups, and 3 rounds of wrist eccentrics. Back extensions and flutter kicks rise from 10 to 20 reps and sit-ups "
              "from 20 to 30 across the cycle. Not included, no catalog match: EOs and the lat, pec and wrist stretches.",
        movements=[
            (216, "Burpee", 4, "5", STEADY, "Warm-up"),
            (1051, "Lunge (Bodyweight)", 4, "5", STEADY, "Warm-up"),
            (13, "Push-Up", 8, "3-5", STEADY, "Paired with pull-ups each round"),
            (922, "Pull-Up", 8, "5-8", STEADY, "Paired with push-ups each round"),
            (1058, "Plank", 6, "20 sec", STEADY, "Substitute for the elevated front bridge, feet on a bench"),
            (983, "Back Extension", 6, "15", STEADY, "Face down"),
            (221, "Flutter Kick (Hollow)", 6, "15", STEADY, BW),
            (969, "Sit-Up", 6, "25", STEADY, BW),
            (979, "Wrist Curl (Dumbbell)", 3, "10", "slow lowering", "Substitute for the wrist eccentrics, 5 to 10 lb"),
        ],
    ),
    # Big Wall Climbing (230)
    dict(
        name="Big Wall Prep: Campus Board Strength and Burpee Intervals",
        phase="build", credit=WALL, sports=BIG_WALL, minutes=60,
        notes="Source: Big Wall Climbing Tuesday climb strength sessions, one per week (week 4 shown). Warm up with 3 rounds of two campus "
              "laps with the feet on, two offset campus pull-ups, sit-ups and a wrist stretch. Then 6 rounds of lock and reach on each arm, "
              "6 rounds of campus dynos using the sixteen step progression table (move down it after two clean rounds in a row), and "
              "10 rounds of 20 seconds touch jump touch, 20 seconds burpees and 20 seconds rest. Air squats follow each lock and reach and dyno round. Later weeks swap the burpees for "
              "alligator push-ups and the jumps for air squats. If pull-ups are out of reach, do 5 shoulder holds of 5 seconds. Not "
              "included, no catalog match: the rope coil and the wrist stretch.",
        movements=[
            (922, "Pull-Up", 3, "2", STEADY, "Substitute for the offset campus pull-ups in the warm-up"),
            (969, "Sit-Up", 3, "8", STEADY, "Warm-up"),
            (51, "Dynamic Lock-Off (Campus-Lite)", 6, "2 per arm", HARD, "Substitute for the campus lock and reach"),
            (47, "Campus Board Ladder (1-3-5)", 6, "up the board", HARD, "Substitute for the campus dyno, feet on to come down"),
            (1088, "Squat (Bodyweight)", 6, "10", STEADY, "Air squats between campus rounds"),
            (216, "Burpee", 10, "20 sec", HARD_SETS, "20 seconds on, 20 seconds of jumps, 20 seconds of rest"),
            (230, "Squat Jump (Counter-Movement)", 10, "20 sec", HARD_SETS, "Substitute for touch jump touch"),
            (1059, "Plyo Push-Up", 10, "20 sec", HARD_SETS, "Substitute for alligator push-ups, which replace the burpees in later weeks"),
        ],
    ),
    dict(
        name="Big Wall Prep: Man Makers, Step-Ups and Core",
        phase="build", credit=WALL, sports=BIG_WALL, minutes=60,
        notes="Source: Big Wall Climbing Wednesday work capacity sessions, one per week (week 4 shown). Warm up 3 rounds of 8 front squats at "
              "45 to 65 lb, 8 push-ups and 8 sit-ups. Then 8 rounds of 5 renegade man makers at 15 to 25 lb and 25 step-ups on a 20 inch "
              "box, sprinting to the 30 second rest. Then 4 rounds of 15 second bridge, 12 Russian twists, 12 ab wheel rollouts and 4 "
              "offset pull-ups, and 2 rounds of 20 wrist eccentrics at 5 to 10 lb. Later weeks swap man makers for burpees and sit-ups and "
              "raise the bridge to 20 seconds. Not included, no catalog match: the 3 limb bridge and the wrist stretch.",
        movements=[
            (450, "Front Squat (Barbell)", 3, "8", STEADY, "Warm-up, 45 to 65 lb"),
            (13, "Push-Up", 3, "8", STEADY, "Warm-up"),
            (969, "Sit-Up", 3, "8", STEADY, "Warm-up"),
            (373, "Renegade Row", 8, "5", HARD, "Substitute for the renegade man maker, 15 to 25 lb"),
            (238, "Loaded Step-Up", 8, "25", HARD, "Unloaded or light, 20 inch box, sprint then 30 seconds rest"),
            (970, "Russian Twist", 4, "12", STEADY, "Bar or bar plus 15 lb"),
            (7, "Ab Wheel Rollout", 4, "12", STEADY, BW),
            (922, "Pull-Up", 4, "4", STEADY, "Substitute for the campus offset pull-up"),
            (979, "Wrist Curl (Dumbbell)", 2, "20", "slow lowering", "Substitute for the wrist eccentrics, 5 to 10 lb"),
        ],
    ),
    dict(
        name="Big Wall Prep: Burpee and Goblet Squat Intervals with Core",
        phase="build", credit=WALL, sports=BIG_WALL, minutes=45,
        notes="Source: Big Wall Climbing Thursday climb work capacity sessions (week 4 shown). Warm up 4 rounds of 2 easy boulder problems, "
              "8 push-ups and 8 sit-ups. The wall work is 3 rounds of 2 minutes moving constantly and 2 rounds of 2 minutes with shaking, "
              "twice, which is dropped here. Then 10 rounds of 20 seconds burpees, 20 seconds goblet squats at 15 to 25 lb and 20 "
              "seconds rest, and 4 rounds of 30 seconds flutter kicks, Russian twists at 15 to 25 lb and a front bridge. Not included, no "
              "catalog match: the traverse wall rounds, easy boulder problems and wrist rotations.",
        movements=[
            (13, "Push-Up", 4, "8", STEADY, "Warm-up"),
            (969, "Sit-Up", 4, "8", STEADY, "Warm-up"),
            (216, "Burpee", 10, "20 sec", HARD_SETS, "Paired with goblet squats, 20 seconds rest"),
            (60, "Goblet Squat", 10, "20 sec", HARD_SETS, "15 to 25 lb"),
            (221, "Flutter Kick (Hollow)", 4, "30 sec", STEADY, BW),
            (970, "Russian Twist", 4, "30 sec", STEADY, "15 to 25 lb"),
            (974, "Front Plank", 4, "30 sec", STEADY, "Front bridge"),
        ],
    ),
]
CREATED = "2026-11-26 00:00:00"


def slugify(name):
    out = []
    for ch in name.lower():
        if ch.isalnum():
            out.append(ch)
        elif ch in " -/&+'.:,":
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

    names_by_id = {e["id"]: e["name"] for e in exercises}
    rt_keys = list(routines[0].keys())
    re_keys = list(routine_exercises[0].keys())

    existing_slugs = {r["slug"] for r in routines}
    next_rt_id = max(r["id"] for r in routines) + 1
    next_re_id = max(r["id"] for r in routine_exercises) + 1

    mismatches = []
    for spec in ROUTINES:
        for ex_id, expected, *_ in spec["movements"]:
            actual = names_by_id.get(ex_id)
            if actual != expected:
                mismatches.append((spec["name"], ex_id, expected, actual))
    if mismatches:
        print("CATALOG MISMATCH, nothing written:")
        for r, ex_id, expected, actual in mismatches:
            print(f"  [{r}] id {ex_id}: expected {expected!r}, catalog has {actual!r}")
        raise SystemExit(1)

    added = []
    for spec in ROUTINES:
        slug = slugify(spec["name"])
        if slug in existing_slugs:
            print(f"  skip (exists): {slug}")
            continue
        rid = next_rt_id
        next_rt_id += 1
        row = {k: None for k in rt_keys}
        row.update(
            id=rid, name=spec["name"], slug=slug, goal="strength",
            difficulty="intermediate", phase=spec["phase"],
            duration_minutes=spec["minutes"], frequency="1-2x/week",
            environment="gym", time_commitment=f'{spec["minutes"]} min',
            notes=spec["notes"], source_name=spec["credit"],
            created_at=CREATED, updated_at=CREATED,
        )
        routines.append(row)
        for sport in spec["sports"]:
            routine_sports.append({"routine_id": rid, "sport_id": sport})

        for pos, (ex_id, _name, sets, reps, effort, note) in enumerate(spec["movements"], start=1):
            xrow = {k: None for k in re_keys}
            xrow.update(id=next_re_id, routine_id=rid, exercise_id=ex_id, position=pos,
                        sets=sets, reps=reps, notes=f"Effort: {effort}. Note: {note}")
            routine_exercises.append(xrow)
            next_re_id += 1
        added.append((rid, spec["phase"], spec["name"]))

    save("routines", routines)
    save("routine_exercises", routine_exercises)
    save("routine_sports", routine_sports)

    print("Routines added:")
    for i, ph, n in added:
        print(f"  {i}  {ph:12s} {n}")
    if not added:
        print("  none (all slugs already exist)")


if __name__ == "__main__":
    main()
