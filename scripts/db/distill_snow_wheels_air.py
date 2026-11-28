#!/usr/bin/env python3
"""Distill published S&C programs for the snow, wheels and air sports of bucket C into coach.db routines.

Backlog 2026-11e 4.5: freestyle-skiing, ski-jumping, nordic-combined, roller-skiing, skateboarding,
inline-skating, bmx, paragliding, hang-gliding, keelboat-racing, catamaran-sailing. Sources meet the
Phase 0 #4 standard as applied in 4.1 to 4.4: a named author with credentials or an affiliation, and a
named venue. Each is cited in `source_name` with its URL in `source_url`. Movements and doses are
distilled. The notes are ours.

No source met the standard for freestyle-skiing, ski-jumping, nordic-combined, bmx, paragliding,
hang-gliding or keelboat-racing after one search pass; they move to bucket D (see the 4.5 note in the
backlog). Roller-skiing has one routine and waits on a follow-up item.

Phase follows `AuthoredRoutine.phaseLabels(for:)`. Where the source names no season, the phase is
chosen from what the source says the block is for, and the note says so. Sport tags are the sport
slugs only; family roots and parent mapping are left to 5.1.

Substitutes, where the catalog has no row for the movement the source names, are named in each
movement note. Doses the source does not print are not filled in: the note gives a working rule.
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

STEADY = "steady"
HARD = "hard but controlled"
HEAVY = "heavy, 1 to 2 reps in reserve"
FAST = "fast, full intent"

# ------------------------------------------------------------------ snow
ROLLER_SKIING = (588,)

CARLSSON_2017 = ("Carlsson T, Wedholm L, Nilsson J, Carlsson M (School of Education, Health and Social Studies, "
                 "Dalarna University, Falun). The effects of strength training versus ski-ergometer training on "
                 "double-poling capacity of elite junior cross-country skiers. Eur J Appl Physiol "
                 "2017;117(8):1523-1532 (distilled)")
CARLSSON_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC5506237"

# ------------------------------------------------------------------ wheels
SKATEBOARDING = (581,)
INLINE = (586,)

GLADE = ("Williams B (Men's Health), program of pro skateboarder Heimana Reynolds built with his coach Brandon "
         "Glade (C.S.C.S.). A World Champion Skateboarder's Gnarly Training Routine, Men's Health, syndicated "
         "on Yahoo Lifestyle (distilled)")
GLADE_URL = "https://www.yahoo.com/lifestyle/world-champion-skateboarders-gnarly-training-173000721.html"
BROWN = ("Brown K (Dr., licensed physical therapist who designs rehab and strength routines for pro skateboarders) "
         "and Read S. The Jock's Guide to Skateboarding Workouts, Jenkem Magazine, 30 Aug 2019 (distilled)")
BROWN_URL = "https://www.jenkemmag.com/home/2019/08/30/jocks-guide-skateboarding-gym-exercises/"
HILDEBRAND = ("Hildebrand R (head coach, Team Florida at Skateworld, Tampa; coach of Mantia, Bowe and Swings). "
              "Training article, Inline Planet, 2 Nov 2007 (distilled)")
HILDEBRAND_URL = "https://www.inlineplanet.com/2007-11/training.html"

# ------------------------------------------------------------------ sail
CATAMARAN = (663,)

ROSENDAHL = ("Rosendahl HC and Rosendahl LP (Denmark SailGP Team grinders on the F50 foiling catamaran). The Ultimate "
             "Sailing Training Guide, ROCKWOOL / Denmark SailGP Team presented by ROCKWOOL, 'The Gym Guide' pages "
             "(distilled)")
ROSENDAHL_URL = "https://www.rockwool.com/syssiteassets/rw-group/media/sailgp/sailgp-guides/training-guides/rockwool-interview-final.pdf"

ROUTINES = [

    dict(
        name="Roller-Skiing: Junior Skier Strength Session",
        phase="build", goal="strength", minutes=45, sports=ROLLER_SKIING,
        credit=CARLSSON_2017, url=CARLSSON_URL,
        notes="Source: the strength group session of a 6 week trial in elite junior cross-country skiers, two "
              "sessions a week added to normal endurance training. The paper uses roller skis for testing and "
              "ends each session with 20 minutes of double-poling roller skiing at 75 to 85 percent of max "
              "heart rate (dropped here: on-wheels). It is a cross-country source; roller skiing is the "
              "dry-land form of the same sport, and it is the only sport tag we use. The source names no "
              "season; build is ours because it is an added loaded block. Two sets per lift with 1 minute "
              "rest. The paper alternates snatch, squat and deadlift by day at 5RM, loaded 60 to 85 percent "
              "of body mass: the squat day is written here. Source: seal row and pull-down variants map to Lat "
              "Pulldown (Machine); push-down variants map to Triceps Pushdown; belly-backs map to Back "
              "Extension. The source gives no load for the 8RM and 6RM lifts: use a weight that stops at the "
              "named rep count. The core stability work (5 to 10 minutes, no list printed) and the rope "
              "circuit are left out.",
        movements=[
            (57, "Barbell Back Squat", 2, "5", HEAVY, "5RM, 60 to 85 percent of body mass per source. Source alternates snatch, squat or deadlift by day"),
            (969, "Sit-Up", 2, "8", HARD, "8RM, source gives no load. Source: sit-ups or vertical sit-ups"),
            (1046, "Lat Pulldown (Machine)", 2, "6", HEAVY, "6RM, source gives no load. Source: pull-downs, chin-ups or seal rows"),
            (1108, "Triceps Pushdown (Cable - Straight Bar)", 2, "6", HEAVY, "6RM, source gives no load. Source: pushdowns, bar-dips or narrow bench press"),
            (983, "Back Extension", 2, "6", HARD, "6RM, source gives no load. Source: belly-backs, with or without dumbbells"),
            (973, "Cable Crunch", 2, "90 s", STEADY, "Source: 90 s cable crunches in a circuit, repeated once. Printed as a time, not sets"),
            (50, "Medicine Ball Slam", 3, "45 s", FAST, "3 to 5 kg ball, 15 s rest between sets"),
        ],
    ),

    dict(
        name="Skateboarding: Pro Gym Circuit",
        phase="maintenance", goal="power", minutes=45, sports=SKATEBOARDING,
        credit=GLADE, url=GLADE_URL,
        notes=("Sets and reps are the printed ones for pro skater Heimana Reynolds, trained by a C.S.C.S. coach. The "
               "source gives no loads and no season; use loads you can move with fast, clean reps. The phase is ours. "
               "The source lists a lunge with lateral reach as a warm-up; here it opens the session. The source's "
               "dumbbell snatch with box jump has no catalog row, so the box jump is kept and the snatch is left out. "
               "Source's kneeling push-up med ball toss, single-leg lateral hurdle hop, row chop press and banded "
               "dumbbell row map to the nearest rows below."),
        movements=[
            (227, "Lateral Lunge", 3, "10", STEADY, "Source: lunge with lateral reach (listed as the warm-up)"),
            (49, "Box Jump", 4, "10", FAST, "Source: dumbbell snatch with box jump; snatch omitted, no load given"),
            (431, "Med Ball Chest Pass (Explosive)", 4, "10", FAST, "Source: kneeling push-up med ball toss"),
            (329, "Lateral Bound to Stick", 2, "5 per side", FAST, "Source: single-leg lateral hurdle hop; no hurdle height given"),
            (982, "Assault Bike", 5, "45 seconds with 5-second sprints", HARD, "Source: 5 x 45 seconds with 5-second sprints"),
            (115, "Cable Wood Chop (High-to-Low)", 5, "10", STEADY, "Source: row chop press; the source gives no load"),
            (10, "Dumbbell Single-Arm Row", 4, "10", STEADY, "Source: banded dumbbell row; no load given"),
        ],
    ),
    dict(
        name="Skateboarding: Trick-Pattern Jump and Hip Session",
        phase="base", goal="accessory", minutes=25, sports=SKATEBOARDING, environment="home",
        credit=BROWN, url=BROWN_URL,
        notes=("Distilled from a physical therapist's off-board drills that mimic skate tricks, using a resistance "
               "band, a bed or ledge and a couch pillow. The source gives no band strength and the phase is ours. "
               "Box jump: hips back, knees in line, as high as possible. The source's switch-pop jump 2 to 3 sets of 10 "
               "uses the soft-landing jump. The 10 to 15 lb ball throw from a manual position (3 sets per stance) is "
               "mapped to the rotational throw: throw from a half-squat, no deck balance. The source's frontside and "
               "backside 180 band work (2 to 3 sets of 10, glute focus) is mapped to the banded hip thrust. Its "
               "kickflip band flick (2 sets of 20 or until the hip and outer ankle tire) is mapped to side-lying "
               "hip abduction. Stop if a drill hurts; the source tells readers with injuries to see a physio."),
        movements=[
            (49, "Box Jump", 2, "10", FAST, "Source: pop with band, as high as possible; 2 sets of 10"),
            (616, "Box Jump to Stick (Soft Landing)", 3, "10", FAST, "Source: switch pop 2 to 3 sets of 10, land softly"),
            (114, "Medicine Ball Rotational Throw", 3, "6 per side", STEADY, "Source: manual ball throw, 10 to 15 lb ball, 3 sets per stance; reps not given, ours"),
            (308, "Banded Hip Thrust (Home)", 3, "10", STEADY, "Source: 180 band drill, 2 to 3 sets of 10; nearest glute row"),
            (1200, "Side-Lying Hip Abduction", 2, "20 per side", STEADY, "Source: kickflip band flick, 2 sets of 20 or until the hip tires"),
        ],
    ),
    dict(
        name="Inline Skating: Phase One Strength and Balance",
        phase="base", goal="strength", minutes=35, sports=INLINE, environment="home",
        credit=HILDEBRAND, url=HILDEBRAND_URL,
        notes=("The source names this list as Phase One (from October for her team, after 2 to 4 weeks of active "
               "rest), the block that builds the base for the year. It prints the 12 exercises but no sets, reps or "
               "loads, and mentions dumbbells and medicine balls without weights. Working rule is ours: 2 sets of 10 "
               "with slow, full-depth control in the skating squat position, loads you could lift for 12. Drills are "
               "meant to be slow and exaggerated. Not in the catalog or merged: leg kicks, leg lifts, squat with "
               "legs apart, the stick version of the Heiden, and overhead throw (nearest row used)."),
        movements=[
            (60, "Goblet Squat", 2, "10", STEADY, "Source: squats with dumbbells or medicine ball; the source gives no load"),
            (945, "Forward Lunge (Dumbbell)", 2, "10 per leg", STEADY, "Source: forward lunges with dumbbells; the source gives no load"),
            (227, "Lateral Lunge", 2, "10 per leg", STEADY, "Source: lateral squat (weight shift)"),
            (601, "Single-Leg Skater Squat", 2, "10 per leg", STEADY, "Source: one-leg squats"),
            (329, "Lateral Bound to Stick", 2, "10 per side", STEADY, "Source: Heiden and stick (lateral bound)"),
            (50, "Medicine Ball Slam", 2, "10", STEADY, "Source: overhead throw with medicine ball; nearest row"),
            (431, "Med Ball Chest Pass (Explosive)", 2, "10", STEADY, "Source: chest pass with medicine ball"),
            (968, "Crunch", 2, "10", STEADY, "Source: half crunches"),
            (1055, "Oblique Crunch", 2, "10 per side", STEADY, "Source: oblique crunches"),
        ],
    ),
    dict(
        name="Inline Skating: Power and Technique Jumps",
        phase="build", goal="power", minutes=30, sports=INLINE, environment="home",
        credit=HILDEBRAND, url=HILDEBRAND_URL,
        notes=("The source's power and technique list, done twice a week after a 10 minute warm-up and stretch. "
               "Start with 1 set of 10 per exercise with 30 seconds rest, slow and with perfect form. Add a set when "
               "one set feels good, and aim for 3 sets of 10 by week four. The source gives no loads. It places "
               "the list inside Phase One; the build label is ours because it is the power step after the strength "
               "list. Power skip, crossover bound and low walks have no catalog row and are left out; the "
               "single-leg hop row stands in for the source's one-foot jumps."),
        movements=[
            (1035, "Jumping Jack", 3, "10", FAST, "Source: speed skater jumping jacks"),
            (329, "Lateral Bound to Stick", 3, "10 per side", FAST, "Source: lateral bound (without stick); nearest row"),
            (230, "Squat Jump (Counter-Movement)", 3, "10", FAST, "Source: two-foot jumps"),
            (526, "Single-Leg Hop (Dance Tempo)", 3, "10 per leg", FAST, "Source: one-foot jumps; nearest row"),
            (52, "Broad Jump", 3, "10", FAST, "Source: broad jumps"),
        ],
    ),

    dict(
        name="Catamaran Sailing: F50 Grinder Strength and Conditioning",
        phase="build", goal="strength", minutes=40, sports=CATAMARAN,
        credit=ROSENDAHL, url=ROSENDAHL_URL,
        notes="Source: the strength and conditioning workout of the Rosendahl twins, grinders on the SailGP F50 "
              "(a foiling catamaran class). Two supersets of 4 sets each, then a 12 minute EMOM. The guide says "
              "their regimes change with time of year and gym access but names no season, so the phase is ours. "
              "The source gives no load: heavy bench is a weight near a 5RM, the lighter cable row a weight that "
              "allows 15, and the incline press 7 rep set is a weight close to the slow single. The 1 rep incline "
              "press takes 7 seconds down and 7 seconds up. Source: weighted push-ups, read as Push-Up with added "
              "load. Source: dips map to Dips (Parallel Bar). EMOM alternates minute one push-ups (6 to 8) and "
              "minute two dips (8 to 10) for 12 minutes, 6 rounds of each.",
        movements=[
            (900, "Barbell Bench Press", 4, "5", HEAVY, "Superset with the cable row; heavy weight, source gives no load"),
            (9, "Seated Cable Row", 4, "15", STEADY, "Superset with the bench press; lighter weight. Source: cable rows"),
            (907, "Incline Dumbbell Bench Press", 4, "1 slow rep (7 s down, 7 s up)", HEAVY, "Superset with the 7 rep set below; heavy weight, source gives no load"),
            (907, "Incline Dumbbell Bench Press", 4, "7", HEAVY, "Normal speed, same weight as the slow rep"),
            (13, "Push-Up", 6, "6 to 8", HARD, "EMOM minute one, weighted; rest the rest of the minute. Source: weighted push-ups"),
            (16, "Dips (Parallel Bar)", 6, "8 to 10", HARD, "EMOM minute two; rest the rest of the minute"),
        ],
    ),
    dict(
        name="Catamaran Sailing: F50 Grinder Anywhere Circuit",
        phase="maintenance", goal="endurance", minutes=30, sports=CATAMARAN, environment="anywhere",
        credit=ROSENDAHL, url=ROSENDAHL_URL,
        notes="Source: the 'killer workout' of the Rosendahl twins (SailGP F50 catamaran grinders) that they use "
              "when they have no gym. Five rounds that get harder because an exercise is added each round: "
              "burpees 10 in all 5 rounds, push-ups 25 from round 2 (4 rounds), lunges 50 from round 3 "
              "(3 rounds), sit-ups 100 from round 4 (2 rounds), air squats 150 in round 5 only. The table is "
              "read from the PDF column layout. The source gives no rest or time; the working rule is to move "
              "steadily and finish in about 30 minutes. The phase is ours. Source: air squats map to Squat "
              "(Bodyweight). Source: lunges, read as bodyweight lunges.",
        movements=[
            (216, "Burpee", 5, "10", HARD, "Every round"),
            (13, "Push-Up", 4, "25", STEADY, "Rounds 2 to 5"),
            (1051, "Lunge (Bodyweight)", 3, "50", STEADY, "Rounds 3 to 5. Source: lunges"),
            (969, "Sit-Up", 2, "100", STEADY, "Rounds 4 to 5"),
            (1088, "Squat (Bodyweight)", 1, "150", STEADY, "Round 5 only. Source: air squats"),
        ],
    ),
    dict(
        name="Catamaran Sailing: F50 Grinder AMRAP Blocks",
        phase="base", goal="endurance", minutes=35, sports=CATAMARAN,
        credit=ROSENDAHL, url=ROSENDAHL_URL,
        notes="Source: the AMRAP workout of the Rosendahl twins (SailGP F50 catamaran grinders). Three 5 minute "
              "AMRAPs of walking lunge, sit-up and max calorie row with 2 minutes rest, then a dumbbell finisher "
              "of chin hangs plus curls, 6 sets each, alternating partners. The phase is ours. Set 1 is 60 m "
              "bodyweight walking lunge and 35 sit-ups, set 2 is 30 m with a pair of 22.5 kg dumbbells and 50 "
              "sit-ups, set 3 is 60 m bodyweight and 50 sit-ups. Source: Abmat sit-ups, read as Sit-Up. Finisher: "
              "15 second chin hang with 10 wide-grip dumbbell curls, then twist curls, then close-touch curls, "
              "12.5 kg dumbbells, each done twice. The catalog has no curl variations by name, so all three map "
              "to Dumbbell Curl; vary the grip as the source does.",
        movements=[
            (943, "Walking Lunge", 3, "60 m (30 m with 2 x 22.5 kg in set 2)", HARD, "Inside a 5 minute AMRAP; source: walking lunges"),
            (969, "Sit-Up", 3, "35, 50, 50", HARD, "Inside the same AMRAP; source: Abmat sit-ups"),
            (1068, "Rowing (Machine)", 3, "max calories", HARD, "Inside the same AMRAP; 2 minutes rest between AMRAPs"),
            (380, "Bent-Arm Bar Hang", 6, "15 s", STEADY, "Finisher, paired with a curl each time. Source: chin hangs"),
            (948, "Dumbbell Curl", 6, "10", STEADY, "Finisher, 12.5 kg dumbbells; wide-grip, twist and close-touch variations rotate"),
        ],
    ),
]

CREATED = "2026-11-27 00:00:00"

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
            id=rid, name=spec["name"], slug=slug, goal=spec["goal"],
            difficulty="intermediate", phase=spec["phase"],
            duration_minutes=spec["minutes"], frequency="2-3x/week",
            environment=spec.get("environment", "gym"), time_commitment=f'{spec["minutes"]} min',
            notes=spec["notes"], source_name=spec["credit"], source_url=spec["url"],
            created_at=CREATED, updated_at=CREATED,
        )
        routines.append(row)
        for sport in spec["sports"]:
            routine_sports.append({"routine_id": rid, "sport_id": sport})

        for pos, (ex_id, _name, sets, reps, effort, note) in enumerate(spec["movements"], start=1):
            xrow = {k: None for k in re_keys}
            text = f"Effort: {effort}." + (f" Note: {note}" if note else "")
            xrow.update(id=next_re_id, routine_id=rid, exercise_id=ex_id, position=pos,
                        sets=sets, reps=reps, notes=text)
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
