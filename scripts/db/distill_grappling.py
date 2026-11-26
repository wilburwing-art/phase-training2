#!/usr/bin/env python3
"""Distill the Tactical BJJ "Action Heroes" packet into grappling routines in coach.db.

Backlog 2026-11e 3.7. Sources are five Mountain Tactical Institute plans written for
tactical athletes who also train BJJ or other grappling: Casey Ryback (579), Dutch (580),
John Creassy (581), John Wick (582) and Riggs (583). Each runs 20 sessions of 30 to 45
minutes in a five session rotation: chassis and work capacity, chassis and grip with
strength, tactical endurance, chassis grip and work capacity, chassis grip and strength.

Phase is `build` for every routine. The plans run alongside sport training and carry no
season label, and `build` is the phase none of the six grappling slugs had a routine for.

Every routine is tagged to bjj (261), bjj-gi (262), bjj-nogi (263), judo (265),
wrestling (266) and sambo (285), because the packet is written for "BJJ or other
grappling based athletics". The family root (martial-arts, 260) is not tagged, matching
3.5 and 3.6.

Not distilled:
- Session 3 of every plan (tactical endurance: rucks, runs, step-ups, gorilla complex and
  curl and extension work by job), which is read-and-log endurance, not a strength day.
- Run, bike and row interval days and the Riggs kettlebell snatch work capacity days
  (assessment-driven interval pace), the shuttle and sprint conditioning days.
- Variants that repeat a shape already distilled: later weeks of the same session
  (a round or two more, a swapped carry), noted inside the routine they match.
- Casey Ryback sessions 1 and 4 (sandbag good morning, founder and sprawl sprint rounds,
  and the tarzan pull-up, sandbag drag and broad jump grind), session 5 (close grip bench,
  Craig special, lunge).
- Dutch sessions 5 and 10 (corrective get-up, one-arm clean and thruster, ankle to bar)
  and its hinge work capacity day.
- John Wick sessions 4, 6, 9 (push press and clean, thruster and weighted pull-up, power
  clean and front squat days with sandbag burpee finishers).
- Foam roll, shoulder sweep, pigeon, hip flexor and Hug hip mobility drills.

Catalog exercises only. Each movement is checked against the expected catalog name, so a
stale id fails the run instead of linking the wrong exercise. Source movements with no
catalog match are left out and named in the routine notes. Loads written "25/35#" are
MTI's women/men scale.
Idempotent: a routine whose slug already exists is skipped.

Run:  python3 scripts/db/distill_grappling.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

GRAPPLING = [261, 262, 263, 265, 266, 285]

CASEY = "MTI Tactical BJJ - Casey Ryback (distilled)"
DUTCH = "MTI Tactical BJJ - Dutch (distilled)"
CREASSY = "MTI Tactical BJJ - John Creassy (distilled)"
WICK = "MTI Tactical BJJ - John Wick (distilled)"
RIGGS = "MTI Tactical BJJ - Riggs (distilled)"

GRIND = "work steadily through the rounds"
STEADY = "steady"
BUILD = "increase load rapidly each round until the last set is hard but doable"
TOWEL = "Throw a towel or old gi top over the bar and grip it like a climbing rope"
BAG = "60 to 80 lb sandbag in the source"
HOLD = "Substitute for the gi or towel grip hold: hang from the bar, or from a towel or gi top over it"

ROUTINES = [
    dict(
        name="Casey Ryback: Hang Power Clean, Back Squat, Weighted Chin-Up",
        credit=CASEY, minutes=40,
        notes="Source: Casey Ryback chassis integrity, grip and strength days (sessions 2 and 12). "
              "Focus is grip strength and chassis integrity. 3 rounds of 5 hang power cleans adding load each round with a 30 second "
              "plate pinch hold, then 5 rounds of 2 hang power cleans building to a hard double, then 6 rounds of 5 back squats "
              "followed straight away by 4 to 8 weighted chin-ups, adding load each round. Aim for hip extension, bar speed and clean reps. "
              "Not included, no catalog match: kneeling slasher to halo, shoulder dislocate, foam roll, hip flexor stretch.",
        movements=[
            (540, "Hang Power Clean", 8, "5 then 2", BUILD, "3 rounds of 5 adding load, then 5 rounds of 2 building to a hard double"),
            (302, "Plate Pinch Hold", 3, "30 s", "hard but doable load", "Substitute for the 30 second plate pinch carry"),
            (57, "Barbell Back Squat", 6, "5", BUILD, "Each set is followed straight away by the chin-ups"),
            (923, "Chin-Up", 6, "4-8", BUILD, "4 (women) / 8 (men), weighted"),
        ],
    ),
    dict(
        name="Casey Ryback: Power Clean and Push Press, Box Squat, Renegade Row",
        credit=CASEY, minutes=40,
        notes="Source: Casey Ryback chassis integrity, grip and strength days (sessions 10 and 20). "
              "A 12 minute grind of band rotations, a 30 second plate pinch carry, a barbell complex at 45/65 lb and shoulder dislocates, "
              "then 5 rounds of 2 power clean and push press combos building to a hard double, 6 rounds of 5 box squats building to a hard triple "
              "and 6 rounds of 8 renegade rows building to a hard 8. "
              "Not included, no catalog match: band rotation, barbell complex, shoulder dislocate, foam roll.",
        movements=[
            (302, "Plate Pinch Hold", 1, "30 s", GRIND, "Substitute for the plate pinch carry, hard but doable load, inside the 12 minute grind"),
            (217, "Power Clean", 5, "2", BUILD, "Followed by a push press each rep"),
            (905, "Push Press", 5, "2", BUILD, "Paired with the power clean"),
            (920, "Box Squat", 6, "5", BUILD, "The last sets are hard triples"),
            (373, "Renegade Row", 6, "8", BUILD, "Build to a hard 8"),
        ],
    ),
    dict(
        name="Casey Ryback: Single-Leg Deadlift, Sandbag Burpee, Step-Up Work Capacity",
        credit=CASEY, minutes=35,
        notes="Source: Casey Ryback chassis integrity and work capacity days (sessions 6 and 16). "
              "A 12 minute grind of 20/20 standing founders, 8 single-leg deadlifts and 5 waiter's carry lunges at 12/16 kg, "
              "then a 10 minute AMRAP of 5 sandbag burpees (60 to 80 lb) and 6 forty-foot shuttles, then 5 rounds for time "
              "of 30 step-ups on a 16 to 18 inch box, a 30 second wall sit, a 30 second front bridge and a 200 m run. "
              "Not included, no catalog match: standing founder, shuttle, run, foam roll.",
        movements=[
            (108, "Single-Leg Romanian Deadlift", 4, "8", GRIND, "12/16 kg kettlebell or dumbbell, 12 minute grind"),
            (1164, "Kettlebell Walking Lunge", 4, "5", GRIND, "Stands in for the waiter's carry lunge at 12/16 kg"),
            (216, "Burpee", 4, "5", "10 minute AMRAP", "Sandbag burpee in the source, 60 to 80 lb. Bodyweight burpee if no bag"),
            (238, "Loaded Step-Up", 5, "30", "for time", "16 to 18 inch box, each step is a rep"),
            (125, "Wall Sit", 5, "30 s", "for time", "Inside the 5 round finisher"),
            (974, "Front Plank", 5, "30 s", "for time", "Substitute for the 30 second front bridge"),
        ],
    ),
    dict(
        name="Dutch: Kettlebell Snatch, Bulgarian Split Squat, Floor Press, Row Grind",
        credit=DUTCH, minutes=40,
        notes="Source: Dutch chassis integrity and strength days (sessions 2 and 12). The plan trains lower body, push, pull "
              "and total body movements one side at a time. 4 rounds of 8 kneeling slasher to halo (16/20 kg), 8 one-arm sit-ups "
              "each side at 15/25 lb, 8 band press-outs each side and 6 four-way band neck holds, then a 4 to 5 round grind of 3 "
              "kettlebell snatches, 5 Bulgarian split squats, 5 kettlebell floor presses and 5 kettlebell rows, loading up fast to hard but doable. "
              "Not included, no catalog match: kneeling slasher to halo, four-way quasi-isometric band neck work, foam roll, stretches.",
        movements=[
            (969, "Sit-Up", 4, "8 each side", "warm-up", "One-arm sit-up at 15/25 lb: hold the weight on the working side"),
            (63, "Pallof Press", 4, "8 each side", "warm-up", "Stands in for the band press-out"),
            (785, "Kettlebell Snatch Sets", 5, "3", BUILD, "Dumbbell or kettlebell snatch, 4 rounds early in the plan and 5 later"),
            (62, "Bulgarian Split Squat", 5, "5 each leg", BUILD, "Add load fast to a hard 5"),
            (313, "Dumbbell Floor Press", 5, "5", BUILD, "Kettlebell floor press in the source, one arm at a time"),
            (1125, "Kettlebell Single-Arm Row", 5, "5 each arm", BUILD, "Horizontal row"),
        ],
    ),
    dict(
        name="Dutch: One-Arm Swing, Lunge, Push Press, Ring Row Grind",
        credit=DUTCH, minutes=40,
        notes="Source: Dutch chassis integrity and strength days (sessions 7 and 17). "
              "4 rounds of a 30 second dead hang and 8 kneeling dumbbell half moons at 25/35 lb, then a 4 to 5 round grind of "
              "6 one-arm swings, 5 walking lunges, 5 one-arm push presses and 8 to 12 ring rows, loading up fast to hard but doable. "
              "Not included, no catalog match: kneeling dumbbell half moon, foam roll, stretches.",
        movements=[
            (303, "Fat-Grip Dead Hang", 4, "30 s", "warm-up", "Substitute for the plain dead hang from a pull-up bar"),
            (61, "Kettlebell Swing", 5, "6 each arm", BUILD, "One arm at a time"),
            (943, "Walking Lunge", 5, "5", BUILD, "Add load fast to a hard 5"),
            (905, "Push Press", 5, "5 each arm", BUILD, "One arm at a time, dumbbell"),
            (499, "Body Row (Rings or Bar)", 5, "8-12", BUILD, "8 (women) / 12 (men), ring rows"),
        ],
    ),
    dict(
        name="John Creassy: Towel Pull-Up Hold and Bodyweight Grind",
        credit=CREASSY, minutes=40,
        notes="Source: John Creassy chassis integrity, grip and strength days (sessions 2, 12, 7 and 17). The plan builds back to back "
              "hard efforts that grow from 5 to 7 minutes. 4 rounds of 30/5/30 Sean Special, 10 one-arm sit-ups each side at 15/25 lb "
              "and a 20 second towel or gi pull-up hold, then a 20 minute grind of 1/2 towel pull-ups, 1/2 chin-ups, 1/2 pull-ups, "
              "6 squats, 6 squat jumps and a 30 second wall sit. A 25 lb weight vest is optional. Later weeks swap the pull-up variants "
              "(tarzan, negative) and the leg work (in place and jumping lunges, leg blaster, 4-square drill) and add towel and horizontal rows. "
              "Not included, no catalog match: 30/5/30 Sean Special, drill hug, 4-square drill, explosive horizontal pull-up.",
        movements=[
            (969, "Sit-Up", 4, "10 each side", "warm-up", "One-arm sit-up at 15/25 lb"),
            (303, "Fat-Grip Dead Hang", 4, "20 s", "warm-up", HOLD),
            (922, "Pull-Up", 4, "1-2", GRIND, f"1 (women) / 2 (men). {TOWEL}, or a plain pull-up"),
            (923, "Chin-Up", 4, "1-2", GRIND, "1 (women) / 2 (men)"),
            (1088, "Squat (Bodyweight)", 4, "6", GRIND, "Inside the 20 minute grind"),
            (1034, "Jump Squat", 4, "6", GRIND, "Inside the 20 minute grind"),
            (125, "Wall Sit", 4, "20-30 s", GRIND, "30 seconds early in the plan, 20 seconds later"),
        ],
    ),
    dict(
        name="John Creassy: Handstand Push-Up, Hand-Release Push-Up and Lunge Grind",
        credit=CREASSY, minutes=40,
        notes="Source: John Creassy chassis integrity, grip and strength days (sessions 5 and 15). "
              "4 rounds of 15 reverse crunches, 10 toes to sky and a 20 second towel or gi pull-up hold, then a 20 minute grind of "
              "1/3 handstand push-ups, 3/6 hand-release push-ups, 3/6 plyo push-ups, 6 walking lunges, 6 bodyweight Bulgarian split squats "
              "and 6 jumping lunges. A 25 lb weight vest is optional, but not for the handstand push-ups. "
              "Not included, no catalog match: toes to sky, drill hug.",
        movements=[
            (975, "Reverse Crunch", 4, "15", "warm-up", "Pre-grind block"),
            (303, "Fat-Grip Dead Hang", 4, "20 s", "warm-up", HOLD),
            (1022, "Handstand Push Up", 4, "1-3", GRIND, "1 (women) / 3 (men)"),
            (13, "Push-Up", 4, "3-6", GRIND, "Hand-release: chest to the floor and hands lifted each rep"),
            (1059, "Plyo Push-Up", 4, "3-6", GRIND, "3 (women) / 6 (men)"),
            (943, "Walking Lunge", 4, "6", GRIND, "Bodyweight"),
            (62, "Bulgarian Split Squat", 4, "6", GRIND, "Bodyweight"),
            (130, "Split Squat Jump", 4, "6", GRIND, "Jumping lunges"),
        ],
    ),
    dict(
        name="John Wick: Hang Power Clean, Back Squat, Wall Slam and Burpee Work Capacity",
        credit=WICK, minutes=45,
        notes="Source: John Wick chassis integrity, strength and work capacity days (sessions 1 and 11), the plan's most strength focused. "
              "Warm-up of 4 rounds of 5 hang power cleans building load and 8 ab wheels with an instep complex. "
              "Then 5 rounds of 2 hang power cleans building to a hard double with 1 explosive burpee, 5 rounds of 5 back squats building "
              "to a hard 5 with 2 squat jumps, then 5 rounds every 60 seconds of 4 medicine ball wall slams at 16/20 lb, 4 burpees and 2 forty-foot shuttles. "
              "Not included, no catalog match: instep complex, shuttle, drill hug, shoulder sweep.",
        movements=[
            (7, "Ab Wheel Rollout", 4, "8", "warm-up", "With the hang power clean warm-up rounds"),
            (540, "Hang Power Clean", 5, "2", BUILD, "Followed by 1 explosive burpee"),
            (57, "Barbell Back Squat", 5, "5", BUILD, "Build to a hard 5"),
            (1034, "Jump Squat", 5, "2", "explosive", "After each back squat set"),
            (50, "Medicine Ball Slam", 5, "4", "every 60 seconds", "16/20 lb ball, 5 rounds every 60 seconds"),
            (216, "Burpee", 5, "4", "every 60 seconds", "With the slams, then 2 forty-foot shuttles each round"),
        ],
    ),
    dict(
        name="John Wick: Front Squat, Incline Bench, Renegade Row, Gi Grip Hang",
        credit=WICK, minutes=45,
        notes="Source: John Wick chassis integrity, strength and grip days (session 2). Warm-up of a 4 round grind of 8 dumbbell good mornings "
              "at 25/35 lb and 5 front squats building load. Then 5 rounds of 3 front squats building to a hard double with 1 box jump at 24/30 inches, "
              "5 rounds of 5 incline bench presses with 5 renegade rows, and a gi grip assessment: a gi top hung over a ring or rack, "
              "hang from the sleeves for as long as you can with a bodyweight row every 10 seconds. Later sessions repeat the grip block at "
              "20 to 25% of the assessed time for 5 rounds with 45 seconds rest. "
              "Not included, no catalog match: the gi grip assessment itself, drill hug.",
        movements=[
            (450, "Front Squat (Barbell)", 5, "3", BUILD, "Build to a hard double"),
            (49, "Box Jump", 5, "1", "explosive", "24/30 inch box, after each front squat set"),
            (901, "Incline Barbell Bench Press", 5, "5", BUILD, "Build to a hard 5"),
            (373, "Renegade Row", 5, "5", BUILD, "Paired with the incline bench"),
            (303, "Fat-Grip Dead Hang", 5, "20-25% of max", "45 seconds rest", HOLD + ". Sleeves of a gi top over a ring or rack in the source"),
            (499, "Body Row (Rings or Bar)", 5, "1 every 10 s", "during the hang", "A bodyweight row every 10 seconds of the hang"),
        ],
    ),
    dict(
        name="John Wick: Lunge, Bulgarian Split Squat, Dumbbell Bench, Gi Grip Hang",
        credit=WICK, minutes=45,
        notes="Source: John Wick chassis integrity, strength and grip days (sessions 5 and 10). Warm-up of kneeling slashers at 16/20 kg "
              "and walking lunges building load, or standing Russian twists and an instep complex. "
              "Then 5 rounds of 3 walking lunges building to a hard double with 2 jumping lunges, or 3 Bulgarian split squats each leg with 2 "
              "jumping lunges, then 5 rounds of 3 Craig specials with 2 squat jumps, or 5 dumbbell bench presses building to a hard 5 with 3 alligator push-ups, "
              "then the gi grip hang at 20 to 25% of the assessed time with a bodyweight row every 10 seconds. "
              "Not included, no catalog match: Craig special, alligator push-up, toe touch complex, instep complex.",
        movements=[
            (943, "Walking Lunge", 5, "3", BUILD, "Build to a hard double"),
            (130, "Split Squat Jump", 5, "2", "explosive", "Jumping lunges"),
            (62, "Bulgarian Split Squat", 5, "3 each leg", BUILD, "Session 10 swaps this in for the walking lunge"),
            (14, "Dumbbell Bench Press", 5, "5", BUILD, "Build to a hard 5"),
            (303, "Fat-Grip Dead Hang", 5, "20-25% of max", "45 seconds rest", HOLD),
            (499, "Body Row (Rings or Bar)", 5, "1 every 10 s", "during the hang", "A bodyweight row every 10 seconds of the hang"),
        ],
    ),
    dict(
        name="Riggs: Sandbag Clean, Bear Hug Carry and Squat Ladder",
        credit=RIGGS, minutes=30,
        notes="Source: Riggs brute strength and chassis integrity days (sessions 2 and 7). A 10 to 1 ladder at grind pace: "
              "sandbag clean and press, bear hug squats and kneeling keg lifts (session 7: getup, side to side push press and bear hug lunges), "
              "10 reps of each, then 9, down to 1, with a 30 second bear hug carry once per round. Sandbag is 60 to 80 lb. "
              "Not included, no catalog match: keg lift (the stone-to-shoulder stands in), side to side push press.",
        movements=[
            (786, "Sandbag Stone-to-Shoulder", 10, "10 down to 1", GRIND, "Substitute for the sandbag clean and press, getup and keg lift, 60 to 80 lb"),
            (60, "Goblet Squat", 10, "10 down to 1", GRIND, "Stands in for the sandbag bear hug squat, hold the bag at the chest"),
            (943, "Walking Lunge", 10, "10 down to 1", GRIND, "Stands in for the sandbag bear hug lunge"),
            (328, "Sandbag Bear Hug Carry", 10, "30 s", GRIND, "Once per round, 60 to 80 lb"),
        ],
    ),
    dict(
        name="Riggs: Sandbag Good Morning, Cross Clean and Step-Up Grind",
        credit=RIGGS, minutes=35,
        notes="Source: Riggs brute strength and chassis integrity days (sessions 5, 10 and 15), a 30 to 35 minute grind with a 60 to 80 lb sandbag. "
              "Session 5 and 15: 4 sandbag cross cleans, 8 good mornings, 4 kneeling plate half moons at 25/45 lb and 10 toss and chases. "
              "Session 10: a 40 foot drag, 3 clean, squat and runs, 4 overhead walking lunges and 20 step-ups on a 15 to 18 inch box. "
              "Not included, no catalog match: kneeling plate half moon, sandbag toss and chase, sandbag drag, run.",
        movements=[
            (786, "Sandbag Stone-to-Shoulder", 1, "3-4 per round", GRIND, "Substitute for the sandbag cross clean and the clean, squat and run"),
            (921, "Barbell Good Morning", 1, "8 per round", GRIND, "Substitute for the sandbag good morning"),
            (943, "Walking Lunge", 1, "4 per round", GRIND, "Stands in for the sandbag overhead walking lunge"),
            (238, "Loaded Step-Up", 1, "20 per round", GRIND, "Sandbag step-ups on a 15 to 18 inch box, session 10"),
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
            difficulty="intermediate", phase="build",
            duration_minutes=spec["minutes"], frequency="1-2x/week",
            environment="gym", time_commitment=f'{spec["minutes"]} min',
            notes=spec["notes"], source_name=spec["credit"],
            created_at=CREATED, updated_at=CREATED,
        )
        routines.append(row)
        routine_sports.extend({"routine_id": rid, "sport_id": sp} for sp in GRAPPLING)

        for pos, (ex_id, _name, sets, reps, effort, note) in enumerate(spec["movements"], start=1):
            xrow = {k: None for k in re_keys}
            xrow.update(id=next_re_id, routine_id=rid, exercise_id=ex_id, position=pos,
                        sets=sets, reps=reps, notes=f"Effort: {effort}. Note: {note}")
            routine_exercises.append(xrow)
            next_re_id += 1
        added.append((rid, spec["name"]))

    save("routines", routines)
    save("routine_exercises", routine_exercises)
    save("routine_sports", routine_sports)

    print("Routines added:")
    for i, n in added:
        print(f"  {i}  {n}")
    if not added:
        print("  none (all slugs already exist)")


if __name__ == "__main__":
    main()
