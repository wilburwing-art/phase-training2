#!/usr/bin/env python3
"""Distill running child-sport strength routines into coach.db.

Backlog 2026-11e 3.5. Sources are eight Mountain Tactical Institute plans:
Mountain Marathon (248), Alpine Running (247), 100K Ultra (305), 100 Mile Ultra
(252), Obstacle Race Short, Medium and Long Distance V2 (394, 393, 392) and
Cross Country Pre-Season Peak (408).

Every plan is a pre-season build toward one race, so every routine here is
`build`. Each distinct strength day is distilled once and tagged to every child
sport it serves:

- mountain-running (65), fell-running (66): the Mountain Marathon vertical
  fitness gym option, early (mini leg blaster and push-ups) and late (full leg
  blaster), and the Alpine Running hinge day and squat day.
- trail-ultra-100k (61), trail-ultra-100mi (62): the two ultra plans share one
  strength spine session for session (a 5 round grind of a press, a pull and a
  leg blaster or hinge), so one pair of routines serves both.
- obstacle-course-racing (68): the Short V2 lunge, pull-up and burpee grind,
  the Medium V2 leg blaster and sandbag clean and press EMOM, and the Long V2
  60 minute work capacity AMRAP.
- orienteering-foot (71): the Cross Country Pre-Season Peak strength days
  (mini leg blaster, push-ups and pull-ups, then a dumbbell chassis circuit).

Not distilled: run sessions, assessments, mini-events, the steep hill option,
the Gi grip days (Medium V2), the Quadzilla and Scotty Bob grind (Long V2), and
the late Cross Country core circuit (EOs, seated keg lifts, heel taps,
founders), which has too few catalog matches.

Catalog exercises only. Each movement is checked against the expected catalog
name, so a stale id fails the run instead of linking the wrong exercise.
Source movements with no catalog match are left out and named in the routine
notes. Source loads written "40/60#" and reps written "3/5x" are MTI's
women/men scale.
Idempotent: a routine whose slug already exists is skipped.

Run:  python3 scripts/db/distill_running.py   (then scripts/db/build_db.py)
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

ULTRA_100K = 61
ULTRA_100MI = 62
MOUNTAIN_RUNNING = 65
FELL_RUNNING = 66
OCR = 68
ORIENTEERING = 71

MOUNTAIN_MARATHON = "MTI Mountain Marathon Training Plan (distilled)"
ALPINE = "MTI Alpine Running Training Plan (distilled)"
ULTRA = "MTI 100K Ultra and 100 Mile Ultra Training Plans (distilled)"
OCR_SHORT = "MTI Obstacle Race Training Plan - Short Distance V2 (distilled)"
OCR_MEDIUM = "MTI Obstacle Race Training Plan - Medium Distance V2 (distilled)"
OCR_LONG = "MTI Obstacle Race Training Plan - Long Distance V2 (distilled)"
CROSS_COUNTRY = "MTI Cross Country Pre-Season Peak Training Plan (distilled)"

GRIND = "work steadily, not frantically, through the circuit"
STEADY = "steady"
MODERATE = "moderate, comfortable but not easy"
HARD = "increase load each round until the reps are hard but doable"
HAND_RELEASE = "Hand-release: chest to the floor and hands lifted each rep"
MINI = "Mini leg blaster round, done as its parts: 10 squats, 10 in-place lunges, 10 jumping lunges, 5 squat jumps"
FULL = "Full leg blaster round, done as its parts: 20 squats, 20 in-place lunges, 20 jumping lunges, 10 squat jumps"
GETUP = ("Substitute for Sandbag Getup, 40/60 lb in the source: lie down with the bag on one shoulder, stand up, "
         "alternate shoulders each rep")
STEP_UP = "Bodyweight in the source, 16 to 20 inch box or bench, each step is a rep. Run 400 m after each block"


def blaster(rounds, size):
    """The leg blaster as its catalog parts, one row per part. `size` is
    "mini", "full" or "mixed" (full rounds first, then mini rounds)."""
    big, small = {"mini": ("10", "5"), "full": ("20", "10"), "mixed": ("10-20", "5-10")}[size]
    return [
        (1088, "Squat (Bodyweight)", rounds, big, STEADY, "Leg blaster, part 1"),
        (1051, "Lunge (Bodyweight)", rounds, big, STEADY, "Leg blaster, part 2. In place, alternate legs, each step is a rep"),
        (130, "Split Squat Jump", rounds, big, STEADY, "Leg blaster, part 3: jumping lunges"),
        (1034, "Jump Squat", rounds, small, STEADY, "Leg blaster, part 4. Rest 30 seconds after each round"),
    ]


ROUTINES = [
    dict(
        name="Mountain Running Vertical: Mini Leg Blaster, Push-Up, Step-Ups",
        sports=[MOUNTAIN_RUNNING, FELL_RUNNING], credit=MOUNTAIN_MARATHON,
        minutes=60, environment="home", goal="endurance",
        notes="Source: Mountain Marathon sessions 2, 4, 9, 11, 16 and 18 (vertical fitness, gym option). "
              "8 to 10 rounds of the mini leg blaster with 4/8 hand-release push-ups and 30 seconds rest "
              "(sessions 16 and 18 open with 3 rounds of the full leg blaster and EOs, then 4 mini rounds), "
              "then 2 rounds at a moderate pace of 250 to 450 step-ups and a 400 m run. "
              f"Leg blaster rows: {MINI}. Warm-up is 5 squats, 5 push-ups and 5 walking lunges with hip flexor and instep stretches. "
              "Not included, no catalog match: EOs, stretches. Not distilled: the steep hill option (700 vertical feet up and down in session 2, rising from there).",
        movements=blaster(10, "mini") + [
            (13, "Push-Up", 10, "4-8", STEADY, HAND_RELEASE + ". 4 (women) / 8 (men) in the source, inside each blaster round"),
            (238, "Loaded Step-Up", 2, "250-450", MODERATE, STEP_UP),
        ],
    ),
    dict(
        name="Mountain Running Vertical: Leg Blaster, Step-Ups",
        sports=[MOUNTAIN_RUNNING, FELL_RUNNING], credit=MOUNTAIN_MARATHON,
        minutes=60, environment="home", goal="endurance",
        notes="Source: Mountain Marathon sessions 23, 25, 30, 32, 37, 39, 44, 46, 51, 53 and 58 (vertical fitness, gym option). "
              "3 to 8 rounds of the full leg blaster, each with 10 EOs (weeks 4 and 5) or a 30/5/30 Sean Special (week 6 on), "
              "30 seconds rest, then 2 to 3 rounds at a moderate pace of 300 to 500 step-ups and a 400 m run. "
              f"Leg blaster rows: {FULL}. Warm-up is 5 squats, 5 push-ups and 5 walking lunges with hip flexor and instep stretches. "
              "Not included, no catalog match: EOs, 30/5/30 Sean Special. Not distilled: the steep hill option (up to 2,000 vertical feet).",
        movements=blaster(8, "full") + [
            (238, "Loaded Step-Up", 3, "300-500", MODERATE, STEP_UP),
        ],
    ),
    dict(
        name="Alpine Running Strength: Hinge, Press, Pull-Up, Sandbag Grind",
        sports=[MOUNTAIN_RUNNING, FELL_RUNNING], credit=ALPINE,
        minutes=60, environment="gym", goal="strength",
        notes="Source: Alpine Running sessions 7, 19 and 31 (strength, chassis integrity). "
              "6 rounds of 3 hinge lifts with a 3/3/3 toe touch complex (session 31 uses the 1-leg hinge), "
              "6 rounds of a press (kneeling curl to press, kettlebell floor press, or standing 1-arm dumbbell military press) "
              "with a rope climb or 3 Tarzan pull-ups and 5 shoulder dislocates, "
              "then a 15 to 20 minute sandbag grind (getups, toss and chase, keg lifts, cleans, pick-up and carry at 40/60 to 60/80 lb). "
              "Warm-up is 3 rounds of 8 hinges at 65/95 lb and 4 Scotty Bobs. "
              "Not included, no catalog match: toe touch complex, Scotty Bobs, shoulder dislocates, cauldrons, kneeling slashers, "
              "toss and chase, keg lifts, plate halfmoons, rope climb.",
        movements=[
            (59, "Conventional Deadlift", 6, "3", HARD, "Hinge lift. Session 19 holds rounds 4 to 6 at the first session's finishing load; session 31 is the 1-leg version"),
            (15, "Dumbbell Overhead Press", 6, "5", HARD, "Stands in for the kneeling curl to press (7), kettlebell floor press (19) and 1-arm dumbbell military press (31)"),
            (922, "Pull-Up", 6, "3", STEADY, "Tarzan pull-ups in the source, or a rope climb"),
            (786, "Sandbag Stone-to-Shoulder", 1, "15-20 min", GRIND, GETUP + ". 3 per round in session 19's grind"),
            (328, "Sandbag Bear Hug Carry", 1, "15 min", GRIND, "Sandbag pick-up and carry at 60/80 lb, inside session 7's grind"),
        ],
    ),
    dict(
        name="Alpine Running Strength: Eccentric Squat, Bench, Chin-Up",
        sports=[MOUNTAIN_RUNNING, FELL_RUNNING], credit=ALPINE,
        minutes=55, environment="gym", goal="strength",
        notes="Source: Alpine Running sessions 9, 21 and 33 (strength, chassis integrity). "
              "6 rounds of 3 eccentric back squats with a 5 second drop at 65 to 75% 1RM and a pigeon stretch "
              "(session 33 uses 2 eccentric split squats), 6 rounds of 5 bench press (session 21 incline, session 33 1-arm dumbbell) "
              "paired with 5/8 chin-ups (session 21 2/5 weighted pull-ups, session 33 1-arm dumbbell rows), "
              "then a 10 to 12 minute low back grind (kettlebell swings, back extensions, good mornings). "
              "Warm-up is 3 rounds of 5 back squats at 40 to 70% 1RM and 4 Scotty Bobs. "
              "Not included, no catalog match: low back lunges, standing and kneeling founders, Scotty Bobs, stretches.",
        movements=[
            (129, "Eccentric-Focused Back Squat (Skier Prep)", 6, "3", "65-75% 1RM", "5 second drop. Session 33 is the eccentric split squat at 2 reps"),
            (900, "Barbell Bench Press", 6, "5", HARD, "Session 21 is incline, session 33 is 1-arm dumbbell"),
            (923, "Chin-Up", 6, "5-8", STEADY, "5 (women) / 8 (men). Session 21 is 2/5 weighted pull-ups, session 33 is 1-arm dumbbell rows"),
            (61, "Kettlebell Swing", 1, "15", GRIND, "10 minute grind at 12/20 kg in session 9, with back extensions and founders"),
            (921, "Barbell Good Morning", 1, "8-10", GRIND, "45/65 lb, inside the 12 minute grind of sessions 21 and 33"),
            (220, "Superman Hold", 1, "10", GRIND, "Face-down back extension: lift chest and legs off the floor and lower. Session 9 uses a GHD"),
        ],
    ),
    dict(
        name="Ultra Strength: Dumbbell Bench, Pull-Up, Leg Blaster",
        sports=[ULTRA_100K, ULTRA_100MI], credit=ULTRA,
        minutes=45, environment="gym", goal="strength",
        notes="Source: 100K Ultra sessions 2, 17, 38, 52 and 108 and 100 Mile Ultra sessions 2, 17, 38, 52, 73, 87 and 108 (strength). "
              "A 5 round grind of 5 dumbbell bench press (or kneeling curl to press), 3/5 pull-ups (or 3/6 mixed grip pull-ups) "
              "and a leg blaster, mini in the first weeks and full later. The plan caps the session at 45 minutes. "
              f"Leg blaster rows: {MINI}. {FULL}. "
              "Warm-up is 3 rounds of a 45/65 lb barbell complex and 6 hand-release push-ups with instep and lat/pec stretches. "
              "Not included, no catalog match: barbell complex, kneeling curl to press, stretches.",
        movements=[
            (13, "Push-Up", 3, "6", "warm-up", HAND_RELEASE + ". Warm-up, after the barbell complex"),
            (14, "Dumbbell Bench Press", 5, "5", HARD, "Grind. Sessions 17, 52 and 87 swap in the kneeling curl to press"),
            (922, "Pull-Up", 5, "3-5", GRIND, "3 (women) / 5 (men). Mixed grip, 3/6, on curl to press days"),
        ] + blaster(5, "mixed"),
    ),
    dict(
        name="Ultra Strength: Floor Press, Hinge, Row",
        sports=[ULTRA_100K, ULTRA_100MI], credit=ULTRA,
        minutes=45, environment="gym", goal="strength",
        notes="Source: 100K Ultra sessions 10, 24, 45 and 59 and 100 Mile Ultra sessions 10, 24, 45, 59, 80 and 94 (strength). "
              "A 5 round grind of 5 kettlebell floor press (or 5 Scotty Bobs), 8 hinge lifts and 4/8 horizontal pull-ups "
              "(or 3/6 chin-ups). Sessions 10 and 24 run a leg blaster where later sessions run the hinge. "
              "The plan caps the session at 45 minutes. "
              "Warm-up is 3 rounds of a 45/65 lb barbell complex and 6 hand-release push-ups with instep and lat/pec stretches. "
              "Not included, no catalog match: barbell complex, Scotty Bobs, stretches.",
        movements=[
            (13, "Push-Up", 3, "6", "warm-up", HAND_RELEASE + ". Warm-up, after the barbell complex"),
            (313, "Dumbbell Floor Press", 5, "5", HARD, "Kettlebell floor press in the source"),
            (59, "Conventional Deadlift", 5, "8", HARD, "Hinge lift. Sessions 10 and 24 run a leg blaster here instead"),
            (135, "Inverted Row", 5, "4-8", GRIND, "Horizontal pull-ups, 4 (women) / 8 (men)"),
            (923, "Chin-Up", 5, "3-6", GRIND, "Sessions 10 and 45 use 3/6 chin-ups in place of the row"),
        ],
    ),
    dict(
        name="Obstacle Race Strength: Lunge, Pull-Up, Burpee Grind, Sandbag AMRAP",
        sports=[OCR], credit=OCR_SHORT,
        minutes=45, environment="home", goal="strength",
        notes="Source: Obstacle Race Short Distance V2 sessions 3, 6, 8, 11, 13, 18, 21, 23, 26 and 28 (strength, work capacity). "
              "A 5 round grind at 30 to 40% of the assessed max reps (sessions 1 and 16) of in-place lunges, pull-ups "
              "(sessions 3, 8, 13, 18 and 23 use a max dead hang instead) and burpees, then a 20 minute AMRAP: "
              "3 sandbag getups at 40/60 lb, 6 40-foot sandbag shuttles and 6 sit-ups; other weeks use renegade man makers at 15/25 lb "
              "with a 100 m dumbbell run and 5 EOs, or sandbag toss and chase with a backwards drag and a 100 m sandbag run. "
              "Warm-up is 3 rounds of 5 in-place lunges, 1 pull-up and 5 burpees. "
              "Not included, no catalog match: dead hang from a bar, sandbag shuttle, toss and chase, drag, EOs, man makers.",
        movements=[
            (1051, "Lunge (Bodyweight)", 5, "30-40% of max", GRIND, "In place, alternate legs. Reps from the session 1 or 16 assessment, rounded up"),
            (922, "Pull-Up", 5, "30-40% of max", GRIND, "Sessions 3, 8, 13, 18 and 23 swap in a max dead hang from the bar (grip work)"),
            (216, "Burpee", 5, "30-40% of max", GRIND, "Reps from the assessment, rounded up"),
            (786, "Sandbag Stone-to-Shoulder", 1, "20 min AMRAP", GRIND, GETUP + ". 3 per round with 6 shuttles and 6 sit-ups"),
            (969, "Sit-Up", 1, "6 per round", GRIND, "Inside the 20 minute AMRAP"),
            (373, "Renegade Row", 1, "3 per round", GRIND, "Stands in for the renegade man maker at 15/25 lb (session 3 AMRAP)"),
        ],
    ),
    dict(
        name="Obstacle Race Strength: Leg Blaster, Pull-Up, Sandbag Clean EMOM",
        sports=[OCR], credit=OCR_MEDIUM,
        minutes=45, environment="gym", goal="strength",
        notes="Source: Obstacle Race Medium Distance V2 sessions 1, 7, 13, 25, 31, 37 and 43 (strength, work capacity). "
              "10 rounds of the mini leg blaster with 3/5 mixed grip pull-ups and 30 seconds rest, moving to 5 to 6 full rounds "
              "with 6/8 pull-ups by the end, then 17 rounds every minute on the minute of 3 to 6 sandbag clean and press at 40/60 lb, "
              "the same number of 20 inch box jumps and burpees, resting rounds 6 and 12 (11 rounds in session 43). "
              f"Leg blaster rows: {MINI}. {FULL}. "
              "Warm-up is 3 rounds of 5 in-place lunges, 5 hand-release push-ups and 10 squats. "
              "Not included, no catalog match: sandbag clean and press. Not distilled: the Gi grip days (4, 10, 16, 22, 28, 34, 40, 45).",
        movements=blaster(8, "mixed") + [
            (922, "Pull-Up", 8, "3-8", STEADY, "Mixed grip, inside each blaster round. 3/5 at the start, 6/8 by session 31"),
            (786, "Sandbag Stone-to-Shoulder", 17, "3-6", "every minute on the minute",
             "Substitute for the sandbag clean and press, 40/60 lb: clean the bag to the shoulder, then press it overhead. Rest rounds 6 and 12"),
            (49, "Box Jump", 17, "3-6", "every minute on the minute", "20 inch box, after the cleans"),
            (216, "Burpee", 17, "3-6", "every minute on the minute", "Last in each minute; what is left of the minute is rest"),
        ],
    ),
    dict(
        name="Obstacle Race Work Capacity: Sandbag, Burpee, Pull-Up AMRAP",
        sports=[OCR], credit=OCR_LONG,
        minutes=60, environment="gym", goal="endurance",
        notes="Source: Obstacle Race Long Distance V2 sessions 4, 10, 28, 34, 40 and 45 (60-minute work capacity). "
              "A 60 minute AMRAP (40 in session 45) of 2 sandbag getups and run at 40/60 lb (sessions 28 and 34: 3 sandbag cleans and run; "
              "sessions 40 and 45: 5 sandbag clean and press with 10 box jumps), 10 burpees, 2/5 pull-ups or a rope climb "
              "(sessions 40 and 45: a 60 second dead hang) and a 400 m run. "
              "Not included, no catalog match: the run with the sandbag, rope climb, dead hang. "
              "Not distilled: the 400 m and 200 m runs, the Quadzilla and Scotty Bob grind days, the Gi grip work, "
              "and the renegade man maker AMRAP (sessions 16 and 22).",
        movements=[
            (786, "Sandbag Stone-to-Shoulder", 1, "60 min AMRAP", GRIND, GETUP + ", then run a few steps with it. 2 per round"),
            (216, "Burpee", 1, "10 per round", GRIND, "Inside the AMRAP"),
            (922, "Pull-Up", 1, "2-5 per round", GRIND, "2 (women) / 5 (men), or a rope climb. Then run 400 m"),
            (49, "Box Jump", 1, "10 per round", GRIND, "Sessions 40 and 45 only, with sandbag clean and press"),
        ],
    ),
    dict(
        name="Cross Country Strength: Mini Leg Blaster, Pull-Up, Get-Up and Hinge",
        sports=[ORIENTEERING], credit=CROSS_COUNTRY,
        minutes=40, environment="gym", goal="strength",
        notes="Source: Cross Country Pre-Season Peak sessions 2, 8, 14 and 20 (strength). "
              "8 to 10 rounds of the mini leg blaster with 5 hand-release push-ups, 2/4 pull-ups and 30 seconds rest "
              "(session 20 runs 2 full and 6 mini rounds with 3 Scotty Bobs), then 2 to 5 rounds of 5 kneeling plate half moons "
              "and 5 kneeling slasher to halos with a 15/25 lb dumbbell, 3 Turkish get-ups (alternate hands each round) "
              f"and 10 dumbbell hinge lifts. Leg blaster rows: {MINI}. "
              "Not included, no catalog match: kneeling plate half moon, slasher to halo, Scotty Bobs.",
        movements=blaster(9, "mini") + [
            (13, "Push-Up", 9, "5", STEADY, HAND_RELEASE + ". Inside each blaster round"),
            (922, "Pull-Up", 9, "2-4", STEADY, "2 (women) / 4 (men), inside each blaster round"),
            (119, "Turkish Get-Up", 2, "3", STEADY, "15/25 lb dumbbell, alternate hands each round"),
            (1171, "Dumbbell Romanian Deadlift", 2, "10", STEADY, "Dumbbell hinge lift at 15/25 lb"),
        ],
    ),
    dict(
        name="Cross Country Strength: Mini Leg Blaster, Pull-Up, Crawl and Renegade",
        sports=[ORIENTEERING], credit=CROSS_COUNTRY,
        minutes=40, environment="home", goal="strength",
        notes="Source: Cross Country Pre-Season Peak sessions 4, 10, 16 and 22 (strength). "
              "8 to 10 rounds of the mini leg blaster with 5 hand-release push-ups, 2/4 pull-ups and 30 seconds rest "
              "(session 22 runs 2 full and 6 mini rounds with 3 Scotty Bobs), then 2 to 5 rounds of 5 dumbbell crawls, "
              "5 slasher to halos and 5 renegade man makers at 15/25 lb, and 15/15 standing founders. "
              f"Leg blaster rows: {MINI}. "
              "Not included, no catalog match: slasher to halo, man maker, standing founder, Scotty Bobs.",
        movements=blaster(9, "mini") + [
            (13, "Push-Up", 9, "5", STEADY, HAND_RELEASE + ". Inside each blaster round"),
            (922, "Pull-Up", 9, "2-4", STEADY, "2 (women) / 4 (men), inside each blaster round"),
            (120, "Bear Crawl", 2, "5", STEADY, "Substitute for the dumbbell crawl at 15/25 lb"),
            (373, "Renegade Row", 2, "5", STEADY, "Stands in for the renegade man maker at 15/25 lb"),
        ],
    ),
]

CREATED = "2026-11-26 00:00:00"


def slugify(name):
    out = []
    for ch in name.lower():
        if ch.isalnum():
            out.append(ch)
        elif ch in " -/&+'.":
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
            difficulty="intermediate", phase="build",
            duration_minutes=spec["minutes"], frequency="1-2x/week",
            environment=spec["environment"], time_commitment=f'{spec["minutes"]} min',
            notes=spec["notes"], source_name=spec["credit"],
            created_at=CREATED, updated_at=CREATED,
        )
        routines.append(row)
        routine_sports.extend({"routine_id": rid, "sport_id": sp} for sp in spec["sports"])

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
