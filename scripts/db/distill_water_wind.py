#!/usr/bin/env python3
"""Distill published S&C programs for the water and wind sports of bucket C into coach.db routines.

Backlog 2026-11e 4.4: windsurfing, kitesurfing, wing-foiling, wakeboarding, wakesurfing, hydrofoiling,
freediving, spearfishing, water-polo, artistic-swimming, swimrun. Sources meet the Phase 0 #4 standard
as applied in 4.1 to 4.3: a named author with credentials or an affiliation, and a named venue. Each is
cited in `source_name` with its URL in `source_url`. Movements and doses are distilled. The notes are ours.

No source met the standard for wing-foiling, hydrofoiling, spearfishing or swimrun after one search
pass; they move to bucket D (see the 4.4 note in the backlog). Wakeboarding, water polo and artistic
swimming have one routine each and wait on 4.11.

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

# ------------------------------------------------------------------ wind
WINDSURF = (429,)
KITESURF = (432,)

BEYER = ("Beyer H (author, Health & Fitness for Windsurfing). Strength training program for beginner "
         "windsurfers, Windsurfing News / surfertoday.com, reposted at windsurf.me.uk 2014 (distilled)")
BEYER_URL = "https://windsurf.me.uk/latest/25571-the-strength-training-program-for-beginner-windsurfers.html"
DUOTONE = ("Borgatti N (personal trainer and kitesurfer), Duotone Academy App workouts with Rita Arnaus and Stefan "
           "Spiessberger, Duotone Kiteboarding stories pages 'Fit like a champion' and '19 new workouts' (distilled)")
DUOTONE_URL = "https://www.duotonesports.com/en/uk/kiteboarding/stories/stories/19-new-workouts"
DUOTONE_URL2 = "https://www.duotonesports.com/es/kiteboarding/stories/stories/fit-like-a-champion"

# ------------------------------------------------------------------ tow
WAKEBOARDING = (438,)
WAKESURFING = (439,)

MURRAY = ("Murray S (professional wakeboarder). Top 10 Wakeboarding Exercises. Discover Boating, "
          "National Marine Manufacturers Association (undated; distilled)")
MURRAY_URL = "https://www.discoverboating.com/resources/article.aspx?id=681"
BANK_MALIBU = ("Bank S (physical therapist and Malibu pro wakesurfer). Off-season wakesurfing circuit, "
               "Malibu Boats blog, 1 Oct 2021 (distilled)")
BANK_MALIBU_URL = "https://www.malibuboats.com/blog/season-wakesurfing-training-tips-pro-rider-stacia-bank"
BANK_BOARDERS = ("Bank S (physical therapist and wakesurfer). Wakesurfing Training Tips, "
                 "Boarders Magazine, 28 Jan 2016 (distilled)")
BANK_BOARDERS_URL = "https://www.boardersmag.com/articles/wakesurfing-training-tips-with-stacia-bank"

# ------------------------------------------------------------------ aquatic
FREEDIVING = (460,)
WATER_POLO = (463,)
ARTISTIC_SWIMMING = (464,)

JAMES_2024 = ("Pelios N (freediver and creator), presenting the program of Brad James (experienced freediving "
              "instructor and competitive freediver). Alchemy, 18 Sep 2024, Strength Exercises For Freediving (distilled)")
JAMES_URL = "https://alchemy.gr/post/914/strength-exercises-for-freediving"
ADAMS_2017 = ("Adams JB (PhD) and Adams JB (MS). Weight Training for Better Diving. Alert Diver (Divers Alert "
              "Network), Q2 2017 (distilled)")
ADAMS_URL = "https://dan.org/?p=14598"
MALLIAROS_2025 = ("Malliaros I, Arsoniadis GG, Botonis PG, Terzis G, Platanou T, Toubekis AG (Division of Aquatic "
                  "Sports, National and Kapodistrian University of Athens). Sports (Basel) 2025;13(11):378, "
                  "Table 1 dryland maximum strength session (distilled)")
MALLIAROS_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC12656560/"
FAN_2024 = ("Fan Y, Duan Y, Gao Z, Liu Y (Beijing Research Institute of Sports Science). Front Sports Act Living "
            "2024;6:1476344, Table 2 specialized strength regimen for 14 female artistic swimmers (distilled)")
FAN_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC11652129"

ROUTINES = [
    dict(
        name="Windsurfing: Beginner Strength, Weeks 1 to 4",
        phase="base", goal="strength", minutes=40, sports=WINDSURF,
        credit=BEYER, url=BEYER_URL,
        notes="Source: a 10 lift full-body program for beginner windsurfers, two strength sessions a week in "
              "weeks 1 to 4 with two light 30 minute cardio days (dropped here). The source names no season; "
              "the phase is ours because it is an entry block. All lifts 2 sets of 15 at 70 percent. The page "
              "does not say what the percentage refers to; read it as 70 percent of a 1RM. Source: straight "
              "triceps press and standing calf raise are abbreviated on the page, read as triceps pushdown "
              "and standing calf raise. Leg curls map to Lying Leg Curl. Reverse-grip chins map to Chin-Up. "
              "Bent-over lateral raises map to Bent-Over Reverse Fly.",
        movements=[
            (57, "Barbell Back Squat", 2, "15", STEADY, "70 percent, source calls it squats"),
            (934, "Lying Leg Curl", 2, "15", STEADY, "70 percent. Source: leg curls"),
            (900, "Barbell Bench Press", 2, "15", STEADY, "70 percent"),
            (1095, "Strict Military Press (Barbell)", 2, "15", STEADY, "70 percent. Source: military press"),
            (344, "Bent-Over Reverse Fly", 2, "15", STEADY, "70 percent. Source: bent-over lateral raises"),
            (923, "Chin-Up", 2, "15", STEADY, "Reverse grip. Source gives 70 percent, read as an assisted or loaded variation that allows 15"),
            (1108, "Triceps Pushdown (Cable - Straight Bar)", 2, "15", STEADY, "70 percent. Source: straight triceps press"),
            (112, "Standing Calf Raise", 2, "15", STEADY, "70 percent"),
            (983, "Back Extension", 2, "15", STEADY, "70 percent"),
            (969, "Sit-Up", 2, "15", STEADY, "Source loads it at 70 percent; body weight is the plain working rule"),
        ],
    ),
    dict(
        name="Windsurfing: Beginner Strength, Weeks 5 to 6",
        phase="build", goal="strength", minutes=45, sports=WINDSURF,
        credit=BEYER, url=BEYER_URL,
        notes="Source: the weeks 5 to 6 column of the same beginner program: the same 10 lifts at 3 sets of 12 "
              "at 75 percent. The source names no season; build is ours because it is the loaded step of the "
              "same block. It says to drop to one strength and one cardio session a week from week 4, "
              "which the page words ambiguously. The percentage has no stated reference; read it as 1RM.",
        movements=[
            (57, "Barbell Back Squat", 3, "12", HARD, "75 percent"),
            (934, "Lying Leg Curl", 3, "12", HARD, "75 percent. Source: leg curls"),
            (900, "Barbell Bench Press", 3, "12", HARD, "75 percent"),
            (1095, "Strict Military Press (Barbell)", 3, "12", HARD, "75 percent. Source: military press"),
            (344, "Bent-Over Reverse Fly", 3, "12", HARD, "75 percent. Source: bent-over lateral raises"),
            (923, "Chin-Up", 3, "12", HARD, "Reverse grip, 75 percent read as a loaded variation that allows 12"),
            (1108, "Triceps Pushdown (Cable - Straight Bar)", 3, "12", HARD, "75 percent. Source: straight triceps press"),
            (112, "Standing Calf Raise", 3, "12", HARD, "75 percent"),
            (983, "Back Extension", 3, "12", HARD, "75 percent"),
            (969, "Sit-Up", 3, "12", HARD, "Body weight or light plate"),
        ],
    ),
    dict(
        name="Kitesurfing: TRX Leg Power Circuit",
        phase="build", goal="power", minutes=25, sports=KITESURF,
        credit=DUOTONE, url=DUOTONE_URL2,
        notes="Source: the 'Burn your legs' TRX workout from Duotone Academy, designed for kiteboarders for "
              "stamina, stability and explosive leg strength, to handle big airs and heavy landings. Each "
              "exercise is 45 s of work and 15 s of recovery. The page gives no round count; three rounds is "
              "our working rule, which with the warm-up and cool-down the source includes in every session "
              "reaches 25 minutes. The page names no season; build is ours. Source: squat and twist and park "
              "leg spreaders have no catalog row and are left out. Supermen is mapped to Superman Hold. "
              "The source lists pistol squats twice. The author credential is a trainer named on a "
              "manufacturer page, which is the weakest part of this source.",
        movements=[
            (60, "Goblet Squat", 3, "45 s", HARD, "Source: squats on the TRX, body weight or a light bell. 15 s rest"),
            (220, "Superman Hold", 3, "45 s", STEADY, "Source: supermen"),
            (1057, "Pistol Squat", 3, "45 s", HARD, "Source lists it twice. Use TRX support as needed"),
            (1053, "Mountain Climber", 3, "45 s", HARD, "Source: mountain climbers"),
            (1034, "Jump Squat", 3, "45 s", FAST, "Source: jumping squats"),
        ],
    ),
    dict(
        name="Kitesurfing: TRX Full Body Rounds",
        phase="base", goal="endurance", minutes=25, sports=KITESURF,
        credit=DUOTONE, url=DUOTONE_URL,
        notes="Source: the 'Full Body' workout with tools from Duotone Academy, a three exercise TRX circuit "
              "for strength, power and endurance across long sessions and hard landings. 45 s of work and 15 s "
              "of rest, three rounds. That is 9 minutes of work; the minutes figure includes the warm-up "
              "and cool-down the source attaches to each session. The page names no season; base is ours. "
              "Source: squat with TRX maps to Goblet Squat, supine row with TRX to Inverted Row, push-ups "
              "side to side to Push-Up. Trainer credential on a manufacturer page.",
        movements=[
            (135, "Inverted Row", 3, "45 s", STEADY, "Source: supine row with TRX. 15 s break"),
            (60, "Goblet Squat", 3, "45 s", STEADY, "Source: squat with TRX"),
            (13, "Push-Up", 3, "45 s", STEADY, "Source: push-ups side to side"),
        ],
    ),
    dict(
        name="Kitesurfing: Chest and Shoulder Protection",
        phase="maintenance", goal="accessory", minutes=25, sports=KITESURF,
        credit=DUOTONE, url=DUOTONE_URL,
        notes="Source: the 'Chest and Shoulders' workout from Duotone Academy, meant to strengthen the upper "
              "body against big air and crash loads. 25 s of work, 20 s rest between exercises and one 60 s "
              "break; the page gives no round count, so three rounds is our working rule and the minutes "
              "figure includes the warm-up and cool-down the source attaches. Season is ours: light enough to "
              "run in season. Source: monkey walks, low legs and the inchworm have no catalog "
              "row and are left out; Indo push-ups map to Scapular Push-Up as the nearest row. Up and down plank maps to Plank, shoulder press to Dumbbell Overhead Press, "
              "pattern push-up to Push-Up. Trainer credential on a manufacturer page.",
        movements=[
            (1058, "Plank", 3, "25 s", STEADY, "Source: up and down plank. 20 s rest"),
            (15, "Dumbbell Overhead Press", 3, "25 s", STEADY, "Source: shoulder press, light load"),
            (13, "Push-Up", 3, "25 s", STEADY, "Source: pattern push-up"),
            (28, "Scapular Push-Up", 3, "25 s", STEADY, "Source: Indo push-ups for shoulder control, nearest row"),
        ],
    ),
    dict(
        name="Wakeboarding: Jump and Grip Circuit",
        phase="build", goal="power", minutes=30, sports=WAKEBOARDING,
        credit=MURRAY, url=MURRAY_URL,
        notes="Source: a ten-move plyometric, grip and core plan by a pro wakeboarder, trained four to five "
              "days a week with a rest day. The source names no season; build is ours. It gives no set "
              "counts, so 3 sets is ours, rest 1 to 2 minutes. Source moves with no close catalog row: rope "
              "or pole climb (legs-free climbing, a grip move). Frog hops are done from a full squat for "
              "10 straight jumps then 10 at 45 degrees; here a jump squat and a broad jump stand in. The "
              "source also opens with a jump rope sequence (50 two-footed, 25 per foot, 10 double-unders), "
              "left as a warm-up.",
        movements=[
            (922, "Pull-Up", 3, "10", HARD, "Alternate wide and narrow grips; source says at least 10, "
                                             "then a few past the burn"),
            (1034, "Jump Squat", 3, "10", FAST, "Source: frog hop, 10 straight from a full squat"),
            (52, "Broad Jump", 3, "10", FAST, "Source: frog hop at 45 degrees, 10 reps"),
            (49, "Box Jump", 3, "5", FAST, "Source: two-footed step jumps up and down 4 steps, and "
                                           "single-leg box jumps (5 to 10 per leg); stable landing before "
                                           "the next rep"),
            (376, "Hanging Leg Raise", 3, "8-10", STEADY, "Straight legs to 90 degrees, about 3 seconds "
                                                          "per rep, a few past burn"),
            (923, "Chin-Up", 3, "6-10", HARD, "Full range of motion; source gives no reps"),
        ],
    ),
    dict(
        name="Wakesurfing: Off-Season Jump and Balance Circuit",
        phase="off_season", goal="power", minutes=35, sports=WAKESURFING,
        credit=BANK_MALIBU, url=BANK_MALIBU_URL,
        notes="Source: a six-move off-season circuit by a pro wakesurfer who is a physical therapist, framed "
              "for winter and spring readiness. Do 3 rounds of each circuit, each move 1 minute, 1 minute "
              "rest between circuits; circuit one is the first three rows and circuit two the next three. "
              "Finish with Russian twists, then a hip flexor stretch. Substitutes: squat with curl uses "
              "the goblet squat, the balance-ball shoulder press uses the dumbbell overhead press done on "
              "one leg, plank with row uses a plain plank (add a row if you have a light dumbbell). The "
              "source gives no load.",
        movements=[
            (49, "Box Jump", 3, "60 s", FAST, "Circuit one. Sturdy step is fine; simulates surf air"),
            (60, "Goblet Squat", 3, "60 s", STEADY, "Circuit one. Source: squat with curl, light weights"),
            (15, "Dumbbell Overhead Press", 3, "60 s", STEADY, "Circuit one. Source: single-leg stance "
                                                               "on a balance ball with shoulder press"),
            (1034, "Jump Squat", 3, "60 s", FAST, "Circuit two. Source: squat 180 jumps, repeat in the "
                                                  "opposite direction"),
            (108, "Single-Leg Romanian Deadlift", 3, "60 s", STEADY, "Circuit two. Source: single-leg "
                                                                      "deadlift, weight optional"),
            (1058, "Plank", 3, "60 s", STEADY, "Circuit two. Source: plank with a row"),
            (970, "Russian Twist", 1, "60 s", STEADY, "Finisher, after the rounds"),
        ],
    ),
    dict(
        name="Wakesurfing: Balance Lunge and Tuck Jump Circuit",
        phase="off_season", goal="power", minutes=25, sports=WAKESURFING,
        credit=BANK_BOARDERS, url=BANK_BOARDERS_URL,
        notes="Source: a three-move off-season circuit from a pro wakesurfer who is a physical therapist, "
              "aimed at strength, balance and recovering flexibility lost in-season. Run the three moves "
              "in order, continuously, 2 to 3 rounds, then a hip flexor stretch from a lunge. The source "
              "gives no load. Substitutes: the balance-board lunge with overhead press uses a dumbbell "
              "lunge (press a light weight overhead; a balance board is the source's tool), and the "
              "single-leg balance with an overhead weight and side knee rotation uses the dumbbell "
              "overhead press done on one leg.",
        movements=[
            (1052, "Lunge (Dumbbell)", 3, "20 per side", STEADY, "Source: balance-board lunge with "
                                                                  "overhead press, about 20 per side or "
                                                                  "as many as clean form allows"),
            (233, "Tuck Jump", 3, "AMRAP 60 s", FAST, "Source: explosive jump with knees tucked, land in "
                                                     "a deep squat; as many as possible in 60 seconds"),
            (15, "Dumbbell Overhead Press", 3, "10 per side", STEADY, "Source: single-leg balance with "
                                                                       "weight overhead and knee rotation, "
                                                                       "10 per side, slow"),
        ],
    ),
    # ---------------------------------------------------------------- freediving
    dict(
        name="Freediving: 5x5 Strength A",
        phase="build", goal="strength", minutes=45, sports=FREEDIVING,
        credit=JAMES_2024, url=JAMES_URL,
        notes="Source: workout A of a 3 day a week five-by-five program written for freedivers (A and B "
              "alternate, a rest day between). Every lift is 5 sets of 5. The source gives no load: start "
              "light, add 2.5 kg per session when all sets are made, repeat the weight after a missed set, "
              "cut 10 percent after three misses. Rest 1.5 min rising to 3 min as the weights get heavy. The "
              "source names no season, so the phase is ours. Keep heavy days away from max depth attempts.",
        movements=[
            (57, "Barbell Back Squat", 5, "5", HEAVY, "Add 2.5 kg a session once all sets are made"),
            (900, "Barbell Bench Press", 5, "5", HEAVY, "Rest 1.5 to 3 min"),
            (8, "Barbell Bent-Over Row", 5, "5", HEAVY, "Source: barbell rows"),
        ],
    ),
    dict(
        name="Freediving: 5x5 Strength B",
        phase="build", goal="strength", minutes=45, sports=FREEDIVING,
        credit=JAMES_2024, url=JAMES_URL,
        notes="Source: workout B of the same five-by-five freediving program. 5 sets of 5, no load printed "
              "(same progression as A). The deadlift starts with a single set of 5 in the first session and "
              "builds from there. The phase is ours.",
        movements=[
            (57, "Barbell Back Squat", 5, "5", HEAVY, "Same weight rule as workout A"),
            (904, "Barbell Overhead Press (Strict)", 5, "5", HEAVY, "Source: shoulder press"),
            (59, "Conventional Deadlift", 5, "5", HEAVY, "First session: 1 set of 5, then build to 5 sets"),
        ],
    ),
    dict(
        name="Freediving: Foundation Lifts 3x10",
        phase="off_season", goal="strength", minutes=40, sports=FREEDIVING,
        credit=ADAMS_2017, url=ADAMS_URL,
        notes="Source: five foundational lifts for divers, 3 sets of 10 each, three days a week. The source "
              "gives no load: work near a 12RM and keep form first. It suggests heavier loads and more "
              "explosive intent later to recruit fast-twitch fibres. Written for scuba and breath-hold "
              "divers generally; the source says to avoid hard training for 24 hours after a dive. The "
              "phase is ours. Start squats at a quarter depth (about 45 degrees of knee bend) and work "
              "toward 90 degrees.",
        movements=[
            (57, "Barbell Back Squat", 3, "10", STEADY, "Quarter squat first, progress depth"),
            (900, "Barbell Bench Press", 3, "10", STEADY, "Vary grip for a challenge"),
            (59, "Conventional Deadlift", 3, "10", STEADY, "Lighter and with more rest while learning form"),
            (904, "Barbell Overhead Press (Strict)", 3, "10", STEADY, "Source: military front press"),
            (8, "Barbell Bent-Over Row", 3, "10", STEADY, "Source: bent-over barbell rows"),
        ],
    ),
    # ---------------------------------------------------------------- water polo
    dict(
        name="Water Polo: Maximum Strength Session",
        phase="build", goal="strength", minutes=45, sports=WATER_POLO,
        credit=MALLIAROS_2025, url=MALLIAROS_URL,
        notes="Source: the dryland maximum strength session used on female water polo players (45 min). 3 "
              "sets of 5 to 6 at 80 percent of 1RM on each of three lifts, 5 min rest between sets. The "
              "study found this session did not impair in-water sprint and shot tests afterward, so it can "
              "sit before a pool session. The source prints one session, not a season; the phase and its "
              "weekly frequency are ours. Familiarization in the study was 2 to 3 sets of 15 to 20 at a "
              "self-chosen load, a fair entry point for a new lifter.",
        movements=[
            (900, "Barbell Bench Press", 3, "5-6", HEAVY, "80% of 1RM, rest 5 min"),
            (9, "Seated Cable Row", 3, "5-6", HEAVY, "Source: seated pull row, 80% of 1RM"),
            (931, "Leg Press", 3, "5-6", HEAVY, "80% of 1RM"),
        ],
    ),
    # ---------------------------------------------------------------- artistic swimming
    dict(
        name="Artistic Swimming: Specialized Strength Circuit",
        phase="base", goal="strength", minutes=35, sports=ARTISTIC_SWIMMING,
        credit=FAN_2024, url=FAN_URL,
        notes="Source: the specialized strength regimen given to 14 female artistic swimmers of the Beijing "
              "team over 5 weeks, 3 sets per exercise with 60 s rest. The paper's frequency wording is "
              "unclear (twice a week appears) and its text says 6 to 8 reps where the table shows 15 for "
              "some lines, so the table doses are used. Left out for lack of a catalog row: one-arm kneeling "
              "lift with 7.5 kg, alternating leg lifts on a BOSU ball with 1 kg. The phase is ours.",
        movements=[
            (57, "Barbell Back Squat", 3, "6", HARD, "Source: squats, 40 kg"),
            (922, "Pull-Up", 3, "6", HARD, "Source: 10 kg added"),
            (108, "Single-Leg Romanian Deadlift", 3, "8 per leg", STEADY, "Source: single-leg deadlift on a BOSU ball, 6 kg"),
            (13, "Push-Up", 3, "15", STEADY, "Source: inverted water push-up replica with elastic bands"),
            (127, "Half-Kneeling Cable Rotation", 3, "8 per side", STEADY, "Source: kneeling rotation, 6 kg"),
            (983, "Back Extension", 3, "15", STEADY, "Source: weighted prone back extension, 6 kg"),
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
