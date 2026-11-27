#!/usr/bin/env python3
"""Distill published S&C programs for the racquet and team sports of bucket C into coach.db routines.

Backlog 2026-11e 4.3: padel, badminton, racquetball, disc-golf, softball, ultimate-frisbee, hockey,
lacrosse, cricket, team-handball. Sources meet the Phase 0 #4 standard as applied in 4.1 and 4.2: a
named author with credentials or an affiliation, and a named venue. Each is cited in `source_name`
with its URL in `source_url`. Movements and doses are distilled. The notes are ours.

No source met the standard for racquetball, disc-golf or ultimate-frisbee after one search pass;
they move to bucket D (see the 4.3 note in the backlog).

Phase follows `AuthoredRoutine.phaseLabels(for:)`. Where the source names no season, the phase
is chosen from what the source says the block is for, and the note says so. Sport tags are the
sport slugs only; family roots and parent mapping are left to 5.1.

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

# ------------------------------------------------------------------ racquet
PADEL = (349,)
BADMINTON = (350,)
SAEZ_2023 = ("Saez de Villarreal E, Ramos-Garcia D (Universidad Pablo de Olavide), Calleja-Gonzalez J "
             "(University of the Basque Country; University of Zagreb), Alcaraz PE (UCAM Catholic University "
             "of Murcia), Ramirez-Campillo R (Universidad Andres Bello). Comparison of two 8-week training "
             "interventions on the athletic performance of padel players. Kinesiology 2023;55(1):38-48, "
             "Table 2 (distilled)")
SAEZ_URL = "https://ojs.srce.hr/index.php/kinesiology/article/view/22623"
XIE_2025 = ("Xie Z, Wu X, Liang H, Li W, Li R, Wang Z, Wen T, Huang Z (Guangzhou Sport University; Ersha Sports "
            "Training Center of Guangdong Province). Effects of eight-week resistance and complex training on "
            "the biomechanical characteristics of lower limbs during badminton backhand forward lunge. Front "
            "Sports Act Living 2025;7:1615558, Table 1 (distilled)")
XIE_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC12170538/"
HUANG_2025 = ("Huang R, Gao Y, Yang K, Mo Y, Lu Y, Gao Z (Guangzhou Sport University; Guangdong Provincial Sports "
              "Bureau; Capital University of Physical Education and Sports). Comparative effects of French "
              "Contrast Method vs. Complex Training on explosive power and its endurance in youth badminton "
              "athletes. PLoS One 2025;20(12):e0338383, Table 1 (distilled)")
HUANG_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC12680223"

# ------------------------------------------------------------------ field
SOFTBALL = (541,)
CRICKET = (554,)
PORCHIAZZO = ("Porchiazzo L (MS, CSCS, SCCC; assistant strength and conditioning coach for Olympic sports, "
              "University of Michigan, works with softball). Poised for Power, Training & Conditioning, "
              "Sep 2015, Michigan softball 34 week offseason plan (distilled)")
PORCHIAZZO_URL = "https://training-conditioning.com/article/poised-for-power/"
HISLEN = ("Hislen S, Ferrier B, English C (Edinburgh Napier University), Kavaliauskas M (University of the West "
          "of Scotland). The Effects of a 14-Week Physical Preparation Programme on Developing Adolescent Seam "
          "Bowlers in Cricket. Int J Strength Cond 2023;3(1), Appendix C (distilled)")
HISLEN_URL = "https://doi.org/10.47206/ijsc.v3i1.273"

# ------------------------------------------------------------------ stick
HOCKEY = (549,)
LACROSSE = (553,)
TEAM_HANDBALL = (556,)
ABELSSON_HOCKEY = ("Abelsson A (certified nutrition coach and bodybuilding specialist, about four decades of "
                   "training). Strength Training for Hockey, StrengthLog (strengthlog.com), 11 week off-season "
                   "program, four sessions a week (distilled)")
ABELSSON_HOCKEY_URL = "https://www.strengthlog.com/strength-training-for-hockey/"
ABELSSON_LAX = ("Abelsson A (certified nutrition coach and bodybuilding specialist, about four decades of "
                "training). Strength Training for Lacrosse, StrengthLog (strengthlog.com), 12 week off-season "
                "program (distilled)")
ABELSSON_LAX_URL = "https://www.strengthlog.com/strength-training-for-lacrosse/"
HERMASSI = ("Hermassi S, Ghaith A, Schwesig R, Shephard RJ, Chelly MS (Qatar University; University of La Manouba, "
            "Tunis; Martin-Luther-University Halle-Wittenberg; University of Toronto). Effects of short-term "
            "resistance training and tapering on maximal strength, peak power, throwing ball velocity, and sprint "
            "performance in handball players. PLoS One 2019;14(7):e0214827 (distilled)")
HERMASSI_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC6611564"
SPIESZNY = ("Spieszny M, Zubik M (University of Physical Education, Cracow; AGH University of Science and "
            "Technology, Krakow). Modification of strength training programs in handball players and its "
            "influence on power during the competitive period. J Hum Kinet 2018;63:149-160 (distilled)")
SPIESZNY_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC6162982"

ROUTINES = [

    # ------------------------------------------------------------------ padel
    dict(
        name="Padel: Court Power Weeks 1 to 4",
        phase="maintenance", goal="power", minutes=45, sports=PADEL,
        credit=SAEZ_2023, url=SAEZ_URL,
        notes="Source: weeks 1 to 4 (sessions 1 to 8) of an 8 week in-season program in 24 male padel players, "
              "two sessions a week 48 to 72 hours apart, done before normal padel training; 45 of the 60 "
              "session minutes are this block. Rest 90 s between all sets. The paper is in season, so the "
              "maintenance label follows it. The integrated arm paired each jump or sprint with a padel stroke "
              "(smash, volley, lob); strokes are left out here and the movements are the physical work. "
              "Doses by week: counter-movement jump 3 x 15; burpee 3 x 5 to 8 for the forehand volley pairing "
              "and 3 x 5 to 8 for the backhand pairing (6 sets listed); jump lunge 3 x 5 to 8; 5 m sprint, "
              "turn, 5 m sprint at 90 degrees left, 90 degrees right and 180 degrees (3 sets of 10 each in "
              "weeks 1 and 2, 12 in weeks 3 and 4, 9 sets listed); medicine ball one-hand overhead throw 3 x 10 "
              "with 1 kg (2 kg in week 4); chest throw 3 x 10 with 5 kg (7 kg in week 4); bird-dog 3 x 10 "
              "(12 from week 3); front and side bridge 3 x 30 s (45 s in week 4). The source gives no load "
              "for the jumps beyond bodyweight. Source: shuttle sprints, the 5-10-5 shuttle is the nearest "
              "catalog row. Source: one-hand overhead medicine ball throw, the one-hand shot put throw is the "
              "nearest row.",
        movements=[
            (230, "Squat Jump (Counter-Movement)", 3, "15", FAST, "Source: CMJ, bodyweight"),
            (216, "Burpee", 6, "5-8", HARD, "Source: burpee pairings, 3 sets forehand volley and 3 backhand volley"),
            (130, "Split Squat Jump", 3, "5-8", FAST, "Source: jump lunge. Each leg"),
            (359, "5-10-5 Pro Agility Shuttle", 9, "10-12", FAST, "Source: 5+5 m sprint-turn-sprint, 3 sets each of 90 degrees left, 90 degrees right, 180 degrees"),
            (225, "Med Ball Shot Put", 3, "10", FAST, "Source: one-hand overhead throw, 1 kg (2 kg in week 4)"),
            (431, "Med Ball Chest Pass (Explosive)", 3, "10", FAST, "Source: chest throw, 5 kg (7 kg in week 4)"),
            (1201, "Bird Dog", 3, "10-12", STEADY, "Each side"),
            (974, "Front Plank", 3, "30-45 s", STEADY, "Source: front bridge"),
            (132, "Side Plank", 3, "30-45 s", STEADY, "Source: side bridge. Each side"),
        ],
    ),
    dict(
        name="Padel: Court Power Weeks 5 to 8",
        phase="maintenance", goal="power", minutes=45, sports=PADEL,
        credit=SAEZ_2023, url=SAEZ_URL,
        notes="Source: weeks 5 to 8 (sessions 9 to 16) of the same 8 week in-season program, two sessions a week, "
              "rest 90 s between all sets. Volume steps up from weeks 1 to 4. The paper is in season, so the "
              "maintenance label follows it. Doses by week: counter-movement jump 3 x 20; burpee 3 x 9 to 10 "
              "per pairing (forehand volley, backhand volley; 6 sets listed); jump lunge 3 x 9 to 10; 5 m "
              "sprint, turn, 5 m sprint at 90 degrees left, 90 degrees right and 180 degrees, 3 sets of 12 "
              "each in week 5 (15 in weeks 6 to 8, 9 sets listed); medicine ball one-hand overhead throw "
              "3 x 10 with 2 kg (3 kg in weeks 7 and 8); chest throw 3 x 10 with 7 kg (10 kg in weeks 7 and "
              "8); bird-dog 3 x 12 (15 from week 6); front and side bridge 3 x 45 s (60 s in weeks 7 and 8). "
              "Padel strokes paired with the movements in the source are left out. Substitutions as in weeks "
              "1 to 4: the 5-10-5 shuttle stands in for the 5 m sprint-turn-sprint and the one-hand shot put "
              "throw for the overhead throw.",
        movements=[
            (230, "Squat Jump (Counter-Movement)", 3, "20", FAST, "Source: CMJ, bodyweight"),
            (216, "Burpee", 6, "9-10", HARD, "Source: burpee pairings, 3 sets forehand volley and 3 backhand volley"),
            (130, "Split Squat Jump", 3, "9-10", FAST, "Source: jump lunge. Each leg"),
            (359, "5-10-5 Pro Agility Shuttle", 9, "12-15", FAST, "Source: 5+5 m sprint-turn-sprint, 3 sets each of 90 degrees left, 90 degrees right, 180 degrees"),
            (225, "Med Ball Shot Put", 3, "10", FAST, "Source: one-hand overhead throw, 2 kg (3 kg in weeks 7 and 8)"),
            (431, "Med Ball Chest Pass (Explosive)", 3, "10", FAST, "Source: chest throw, 7 kg (10 kg in weeks 7 and 8)"),
            (1201, "Bird Dog", 3, "12-15", STEADY, "Each side"),
            (974, "Front Plank", 3, "45-60 s", STEADY, "Source: front bridge"),
            (132, "Side Plank", 3, "45-60 s", STEADY, "Source: side bridge. Each side"),
        ],
    ),
    # ------------------------------------------------------------------ badminton
    dict(
        name="Badminton: Lower-Body Resistance Block",
        phase="base", goal="strength", minutes=30, sports=BADMINTON,
        credit=XIE_2025, url=XIE_URL,
        notes="Source: the resistance training arm of an 8 week study in 20 male amateur badminton players (at "
              "least 2 years of play, at least 6 hours a week), two sessions a week 72 hours apart, 3 sets of "
              "6 per exercise, 3 minutes rest between sets. Loads step up every 2 weeks: squat 75, 80, 85, 90 "
              "percent of back squat 1RM; calf raise 50, 55, 60, 65 percent of the same 1RM; split squat 20, "
              "25, 30, 35 kg. The paper names no season; the strength block label is ours, so it sits in base. "
              "Session length is not printed; 30 minutes is our estimate for 9 sets with 3 minute rests. "
              "Source: split squat, the Bulgarian split squat is the nearest catalog row (the paper does not "
              "say rear foot elevated). The sample is amateur and male, so treat the percentages as a ceiling "
              "and stop at 1 to 2 reps in reserve.",
        movements=[
            (57, "Barbell Back Squat", 3, "6", HEAVY, "75% of 1RM in weeks 1 and 2, rising to 90% in weeks 7 and 8. Rest 3 min"),
            (112, "Standing Calf Raise", 3, "6", HEAVY, "Loaded at 50% of the back squat 1RM in weeks 1 and 2, rising to 65%. Rest 3 min"),
            (62, "Bulgarian Split Squat", 3, "6", HEAVY, "Source: split squat. 20 kg in weeks 1 and 2, rising 5 kg every 2 weeks to 35 kg. Each leg"),
        ],
    ),
    dict(
        name="Badminton: Complex Pair Power Block",
        phase="build", goal="power", minutes=35, sports=BADMINTON,
        credit=XIE_2025, url=XIE_URL,
        notes="Source: the complex training arm of the same 8 week study, two sessions a week. Each of three "
              "pairs is a heavy lift followed by a jump, 3 sets per pair, 4 reps of the lift then 8 jumps, 30 "
              "seconds between the two, 3 minutes between sets. Lift loads are the same as in the "
              "resistance block: squat 75 to 90 percent of back squat 1RM, calf raise 50 to 65 percent, split "
              "squat 20 to 35 kg, stepping up every 2 weeks. The paper names no season; the power label and "
              "the build phase are ours. Session length is not printed; 35 minutes is our estimate. Source: "
              "vertical jump, the counter-movement jump is the nearest row. Source: hurdle jump, the box "
              "jump over is the nearest row. Source: jumping lunge, the split squat jump. Source: split "
              "squat, the Bulgarian split squat.",
        movements=[
            (57, "Barbell Back Squat", 3, "4", HEAVY, "Pair 1 lift. 75% of 1RM in weeks 1 and 2, rising to 90%. Then 30 s rest"),
            (230, "Squat Jump (Counter-Movement)", 3, "8", FAST, "Pair 1 jump. Source: vertical jump. 3 min rest after the pair"),
            (112, "Standing Calf Raise", 3, "4", HEAVY, "Pair 2 lift. 50% of back squat 1RM in weeks 1 and 2, rising to 65%. Then 30 s rest"),
            (214, "Box Jump Over", 3, "8", FAST, "Pair 2 jump. Source: hurdle jump. 3 min rest after the pair"),
            (62, "Bulgarian Split Squat", 3, "4", HEAVY, "Pair 3 lift. Source: split squat. 20 kg rising to 35 kg. Each leg. Then 30 s rest"),
            (130, "Split Squat Jump", 3, "8", FAST, "Pair 3 jump. Source: jumping lunge. 3 min rest after the pair"),
        ],
    ),
    dict(
        name="Badminton: French Contrast Power Session",
        phase="build", goal="power", minutes=35, sports=BADMINTON,
        credit=HUANG_2025, url=HUANG_URL,
        notes="Source: the French Contrast Method arm of an 8 week study in 20 male adolescent badminton "
              "athletes, two supervised sessions a week at least 72 hours apart, 4 sets per session, a 20 "
              "minute warm-up and 10 minute stretch around the main work. One contrast set is four moves in "
              "a row with 20 seconds between them and 3 to 4 minutes after the last: isometric back squat at "
              "85 percent of 1RM for 4, 50 cm drop jump for 4, back squat jump at 50 percent of bodyweight "
              "for 8, band-assisted jump for 8. Loads were held fixed for all 8 weeks. The paper recommends "
              "the method for the pre-competition phase, so build is the label. Youth sample; adult "
              "players should treat 85 percent as a ceiling. Source: isometric back squat, the pause squat "
              "is the nearest row (hold the pause in the bottom). Source: back squat jump, the jump squat. "
              "Source: band-assisted jump, the counter-movement jump is the nearest row (the band is left "
              "out of the catalog).",
        movements=[
            (919, "Pause Squat", 4, "4", HEAVY, "Source: isometric back squat, 85% of 1RM. 20 s rest"),
            (232, "Depth Jump", 4, "4", FAST, "Source: drop jump, 50 cm box. 20 s rest"),
            (1034, "Jump Squat", 4, "8", FAST, "Source: back squat jump, load 50% of bodyweight. 20 s rest"),
            (230, "Squat Jump (Counter-Movement)", 4, "8", FAST, "Source: band-assisted jump. 3 to 4 min rest after the set"),
        ],
    ),

    # ------------------------------------------------------------------ softball
    dict(
        name="Softball: Offseason GPP Day",
        phase="off_season", goal="strength", minutes=55, sports=SOFTBALL,
        credit=PORCHIAZZO, url=PORCHIAZZO_URL,
        notes="Source: the sample general physical preparation (GPP) workout from the University of Michigan "
              "softball offseason plan. GPP opens the plan (weeks 1 to 7 and again at weeks 13 to 17 and 25 to "
              "27) at 3 to 5 sets of 8 to 12 at 55 to 75 percent of 1RM, so it sits in off_season. Strength "
              "list first, then the circuit: 3 rounds, 40 seconds of as many reps as possible per station, "
              "20 seconds to rotate, 1 minute rest between rounds. Warm-up sets in the source (2 x 5 at 50 to "
              "65 percent on the clean pull, front squat and bench press) are dropped. The lat pulldown is "
              "loaded at 70 percent of a 1RM estimated from chin-ups. The source's suitcase sit-up has no "
              "catalog row and is left out of the circuit.",
        movements=[
            (911, "Clean Pull", 3, "5", FAST, "Source: clean pull from the knee. 75% of 1RM"),
            (450, "Front Squat (Barbell)", 4, "6", HARD, "70% of 1RM"),
            (900, "Barbell Bench Press", 3, "10", HARD, "65% of 1RM"),
            (941, "Glute-Ham Raise (GHR)", 3, "8", HARD, ""),
            (1049, "Lat Pulldown - Underhand (Cable)", 4, "8", HARD, "Source: supinated-grip lat pulldown. 70% of 1RM"),
            (63, "Pallof Press", 3, "10", STEADY, "Each side"),
            (974, "Front Plank", 3, "60 s", STEADY, "Source: plank, 3 x 1 minute"),
            (61, "Kettlebell Swing", 3, "40 s", HARD, "Circuit station 1, as many reps as possible, 20 s to rotate"),
            (50, "Medicine Ball Slam", 3, "40 s", HARD, "Circuit station 2, 3 rounds"),
            (21, "Band Pull-Apart", 3, "40 s", STEADY, "Circuit station 4, 3 rounds"),
            (1165, "Dumbbell Reverse Lunge", 3, "40 s", HARD, "Circuit station 5, 3 rounds"),
        ],
    ),
    dict(
        name="Softball: Offseason Power Day",
        phase="build", goal="power", minutes=40, sports=SOFTBALL,
        credit=PORCHIAZZO, url=PORCHIAZZO_URL,
        notes="Source: the Power cycle (weeks 31 to 34, the last block before the season) is 3 to 5 sets of 1 to "
              "5, with power clean at 70 to 85 percent of 1RM and back squat, front squat and bench press at 40 "
              "to 60 percent of 1RM, moved fast. The source prints the four lifts and their loads and no "
              "session layout, so the order and set counts inside the ranges are ours. Alternate back squat "
              "and front squat between sessions. Plyometrics and change-of-direction work rise in this "
              "cycle but the source gives no doses and they are left out. Rest 2 to 3 minutes (our rule).",
        movements=[
            (217, "Power Clean", 4, "3", FAST, "70 to 85% of 1RM"),
            (57, "Barbell Back Squat", 4, "3", FAST, "40 to 60% of 1RM, move the bar fast. Front squat on alternate days"),
            (900, "Barbell Bench Press", 4, "3", FAST, "40 to 60% of 1RM, move the bar fast"),
        ],
    ),
    # ------------------------------------------------------------------ cricket
    dict(
        name="Cricket: Seam Bowler Block 1 Foundation",
        phase="base", goal="strength", minutes=50, sports=CRICKET,
        credit=HISLEN, url=HISLEN_URL,
        notes="Source: block 1 (4 weeks, 2 gym sessions a week) of a 14 week pre-season programme for six academy "
              "seam bowlers aged 18, November to March, with a conditioning session a week on top. Every lift is "
              "3 x 10, planks 3 x 60 s. Loads were set from each player's rep max; the source gives no "
              "percent, so work each lift at a weight that leaves 2 to 3 reps in reserve. The source's "
              "isometric side-hold plate press (3 x 10) has no catalog row and is left out. Movement prep "
              "before lifting (10 each of squats, press-ups, walking lunges, thoracic rotations, hip openers, "
              "box jumps at 30 cm and drop jumps at 30 cm) is not in the movement list. The phase is ours "
              "(the first block of a pre-season build).",
        movements=[
            (57, "Barbell Back Squat", 3, "10", STEADY, ""),
            (8, "Barbell Bent-Over Row", 3, "10", STEADY, "Source: barbell row"),
            (58, "Romanian Deadlift (Barbell)", 3, "10", STEADY, ""),
            (451, "Trap Bar Deadlift", 3, "10", STEADY, ""),
            (1095, "Strict Military Press (Barbell)", 3, "10", STEADY, "Source: military press"),
            (135, "Inverted Row", 3, "10", STEADY, "Source: inverted row, straight legs"),
            (974, "Front Plank", 3, "60 s", STEADY, "Hold"),
            (132, "Side Plank", 3, "60 s", STEADY, "Hold each side"),
        ],
    ),
    dict(
        name="Cricket: Seam Bowler Block 2 Strength",
        phase="build", goal="strength", minutes=50, sports=CRICKET,
        credit=HISLEN, url=HISLEN_URL,
        notes="Source: block 2 (4 weeks, 2 gym sessions a week) of the same 14 week seam-bowler programme. 3 x 8 "
              "on the main lifts, 3 x 6 on chin-ups, 3 x 10 on the hamstring slider and 3 x 12 on the cable "
              "rotations. The source gives no load, so work the 8s near an 8RM less 2 reps. Substitutes: "
              "the source's barbell split squat is the Barbell Bulgarian Split Squat row, the hamstring "
              "slider is the lying leg curl (Source: hamstring slider), and the wide stance cable "
              "rotation is the cable punch rotation row and the kneeling cable rotation is the half-kneeling "
              "cable rotation row. "
              "Phase is ours: the middle of a pre-season build.",
        movements=[
            (57, "Barbell Back Squat", 3, "8", HARD, ""),
            (900, "Barbell Bench Press", 3, "8", HARD, ""),
            (1160, "Barbell Bulgarian Split Squat", 3, "8", HARD, "Source: barbell split squat. Each leg"),
            (15, "Dumbbell Overhead Press", 3, "8", HARD, "Source: dumbbell shoulder press"),
            (10, "Dumbbell Single-Arm Row", 3, "8", HARD, "Source: single arm row. Each side"),
            (923, "Chin-Up", 3, "6", HARD, ""),
            (311, "Cable Punch / Chest Press Rotation", 3, "12", STEADY, "Source: wide stance cable rotation. Each side"),
            (934, "Lying Leg Curl", 3, "10", STEADY, "Source: hamstring slider"),
            (127, "Half-Kneeling Cable Rotation", 3, "12", STEADY, "Source: kneeling cable rotation. Each side"),
        ],
    ),
    dict(
        name="Cricket: Seam Bowler Block 3 Heavy and Explosive",
        phase="build", goal="power", minutes=45, sports=CRICKET,
        credit=HISLEN, url=HISLEN_URL,
        notes="Source: block 3 (4 weeks, 2 gym sessions a week) of the same 14 week seam-bowler programme. 3 x 6 "
              "on the lifts, 3 x 10 on the medicine ball rotational slam and the wide stance cable rotation. "
              "The source gives no load; work the 6s near a 6RM less 1 to 2 reps and move the slam and "
              "rotation fast. The source's single-leg RDL was done in a Smith machine; the catalog row is "
              "free-weight. The wide stance cable rotation is matched to the cable punch rotation row. "
              "Phase is ours: the heaviest block before the closing taper.",
        movements=[
            (57, "Barbell Back Squat", 3, "6", HEAVY, ""),
            (108, "Single-Leg Romanian Deadlift", 3, "6", HARD, "Source: single leg RDL in a Smith machine. Each leg"),
            (451, "Trap Bar Deadlift", 3, "6", HEAVY, ""),
            (904, "Barbell Overhead Press (Strict)", 3, "6", HARD, "Source: barbell shoulder press"),
            (10, "Dumbbell Single-Arm Row", 3, "6", HARD, "Source: single arm row. Each side"),
            (50, "Medicine Ball Slam", 3, "10", FAST, "Source: medicine ball rotational slam. Each side"),
            (311, "Cable Punch / Chest Press Rotation", 3, "10", FAST, "Source: wide stance cable rotation. Each side"),
        ],
    ),
    dict(
        name="Cricket: Seam Bowler Block 4 Low-Volume Heavy",
        phase="maintenance", goal="strength", minutes=35, sports=CRICKET,
        credit=HISLEN, url=HISLEN_URL,
        notes="Source: block 4 (2 weeks, 2 gym sessions a week), the last block of the same 14 week seam-bowler "
              "programme, with fewer exercises and 4 sets of 4 on most lifts (trap bar deadlift 3 x 5). The "
              "source gives no load; work each set near a 4RM less 1 rep. The source ends with a 10 minute "
              "trunk circuit and names no movements, so it is not included. The programme ends with a "
              "one-week deload. The source's single-leg RDL was in a Smith machine and its dumbbell step-up "
              "is matched to the loaded step-up row. The maintenance label is ours: a short low-volume block "
              "that holds strength into the season.",
        movements=[
            (108, "Single-Leg Romanian Deadlift", 4, "4", HEAVY, "Source: single leg RDL in a Smith machine. Each leg"),
            (451, "Trap Bar Deadlift", 3, "5", HEAVY, ""),
            (8, "Barbell Bent-Over Row", 4, "4", HEAVY, ""),
            (900, "Barbell Bench Press", 4, "4", HEAVY, ""),
            (238, "Loaded Step-Up", 4, "4", HARD, "Source: dumbbell step up. Each leg"),
        ],
    ),

    # ------------------------------------------------------------------ hockey
    dict(
        name="Hockey: Phase 1 Lower Body Strength",
        phase="base", goal="strength", minutes=45, sports=HOCKEY,
        credit=ABELSSON_HOCKEY, url=ABELSSON_HOCKEY_URL,
        notes="Source: workout 1 (lower body strength) of phase 1, weeks 1 to 4, of an 11 week off-season "
              "program for intermediate lifters, four sessions a week. Phase 1 is the first block and builds toward "
              "heavier work, so it sits in base. Squat is 4 to 5 sets; the source gives no load (the percentages "
              "sit behind its paid app): work each lift near a 6 to 8RM and add 5 to 10 lb on lower body lifts "
              "once every rep is clean. Rest 90 to 120 s on the 5 to 8 rep lifts, about 60 s on the rest. "
              "Phases 2 and 3 of the source swap the calf raise for a hip thrust, 3 x 6 to 8; not distilled "
              "as a separate session.",
        movements=[
            (57, "Barbell Back Squat", 4, "5-8", HEAVY, "Source: squat. 4 to 5 sets, rest 90 to 120 s"),
            (58, "Romanian Deadlift (Barbell)", 3, "5-8", HEAVY, "Rest 90 to 120 s"),
            (62, "Bulgarian Split Squat", 3, "5-8", HARD, "Each leg"),
            (112, "Standing Calf Raise", 3, "20", STEADY, "About 60 s rest"),
            (63, "Pallof Press", 3, "10", STEADY, "Each side"),
        ],
    ),
    dict(
        name="Hockey: Phase 1 Upper Body Pull",
        phase="base", goal="strength", minutes=40, sports=HOCKEY,
        credit=ABELSSON_HOCKEY, url=ABELSSON_HOCKEY_URL,
        notes="Source: workout 4 (upper body pull) of phase 1 of the same 11 week program. The source gives "
              "no load; work at a weight that leaves 1 to 2 reps in reserve and add 2.5 to 5 lb on upper body "
              "lifts once every rep is clean. Pull-ups are bodyweight; use a band if 5 is out of reach. Base "
              "matches the source's phase 1.",
        movements=[
            (922, "Pull-Up", 4, "5-10", HARD, "Rest 90 to 120 s"),
            (8, "Barbell Bent-Over Row", 3, "6-8", HARD, "Source: barbell row"),
            (24, "Face Pull (Cable or Band)", 3, "10", STEADY, ""),
            (950, "Hammer Curl", 3, "6-10", STEADY, ""),
            (376, "Hanging Leg Raise", 3, "12-15", STEADY, ""),
        ],
    ),
    dict(
        name="Hockey: Lower Body Power",
        phase="build", goal="power", minutes=40, sports=HOCKEY,
        credit=ABELSSON_HOCKEY, url=ABELSSON_HOCKEY_URL,
        notes="Source: workout 3 (lower body power) of the same program, with the phase 3 swap of box jump for "
              "depth jump (weeks 8 to 10). Every power rep is fast; rest 2 to 3 minutes on the power lifts. "
              "The source gives no load: use a clean weight you can move fast for 2 to 3 reps, and a speed "
              "squat near 60 percent of a 5RM weight. The source says 'squat (speed focus)'. Phase is ours: "
              "the source calls the block power, so build.",
        movements=[
            (217, "Power Clean", 4, "2-3", FAST, "4 to 5 sets, rest 2 to 3 min"),
            (232, "Depth Jump", 3, "5", FAST, "Source: depth jump (phase 3 swap for box jump)"),
            (57, "Barbell Back Squat", 3, "3-5", FAST, "Source: squat, speed focus. 3 to 4 sets"),
            (103, "Single-Leg Glute Bridge", 3, "8", STEADY, "Each side"),
            (237, "Copenhagen Adductor Lift (Dynamic)", 3, "12-15", STEADY, "Source: dynamic Copenhagen plank"),
        ],
    ),
    dict(
        name="Hockey: Deload Week Strength",
        phase="maintenance", goal="strength", minutes=30, sports=HOCKEY,
        credit=ABELSSON_HOCKEY, url=ABELSSON_HOCKEY_URL,
        notes="Source: week 11 (deload) of the same program: lifts at about 60 to 70 percent of week 10 loads, "
              "3 x 5, accessory volume cut by half. The source's upper pull and push sessions are joined here "
              "into one. The source gives no week 10 loads, so use a weight you could lift 8 times. "
              "Maintenance is ours: the load is low enough to hold strength through a rec league season.",
        movements=[
            (57, "Barbell Back Squat", 3, "5", STEADY, "About 60 to 70% of week 10 load"),
            (900, "Barbell Bench Press", 3, "5", STEADY, "About 60 to 70% of week 10 load"),
            (904, "Barbell Overhead Press (Strict)", 3, "5", STEADY, "About 60 to 70% of week 10 load"),
            (922, "Pull-Up", 3, "5", STEADY, "Bodyweight"),
            (8, "Barbell Bent-Over Row", 3, "5", STEADY, "About 60 to 70% of week 10 load"),
        ],
    ),
    # ------------------------------------------------------------------ lacrosse
    dict(
        name="Lacrosse: Phase 1 Lower Body",
        phase="base", goal="strength", minutes=45, sports=LACROSSE,
        credit=ABELSSON_LAX, url=ABELSSON_LAX_URL,
        notes="Source: workout 1 (lower body) of phase 1, weeks 1 to 4 (hypertrophy and work capacity) of a 12 "
              "week off-season program, three sessions a week. The page prints sets only and no reps or loads "
              "(they sit behind its paid app). Our rule: 8 to 10 reps a set at a weight that leaves 2 reps in "
              "reserve, rest about 60 s on the accessory work and 90 to 120 s on squat. Add 5 to 10 lb "
              "on lower body lifts once every rep is clean. Base follows the source's first block.",
        movements=[
            (57, "Barbell Back Squat", 4, "8-10", HARD, "Source: squat. Rep range is ours"),
            (58, "Romanian Deadlift (Barbell)", 3, "8-10", HARD, "Rep range is ours"),
            (62, "Bulgarian Split Squat", 3, "8-10", HARD, "Each leg. Rep range is ours"),
            (103, "Single-Leg Glute Bridge", 3, "8-10", STEADY, "Each side. Rep range is ours"),
            (112, "Standing Calf Raise", 3, "12-15", STEADY, "Rep range is ours"),
        ],
    ),
    dict(
        name="Lacrosse: Phase 2 Max Strength Lower",
        phase="build", goal="strength", minutes=50, sports=LACROSSE,
        credit=ABELSSON_LAX, url=ABELSSON_LAX_URL,
        notes="Source: workout 1 (lower body) of phase 2, weeks 5 to 8 (maximum strength) of the same 12 week "
              "program. Sets only are printed; the source gives its heavier lifts 5 to 6 reps with 90 to 120 s "
              "rest in its rest guidance. Our rule: 5 reps on squat and trap bar deadlift at 1 to 2 reps in "
              "reserve, 6 to 8 on the rest. Phase is ours: max strength after a hypertrophy block, so build.",
        movements=[
            (57, "Barbell Back Squat", 5, "5", HEAVY, "Source: squat. Rest 90 to 120 s. Rep count is ours"),
            (451, "Trap Bar Deadlift", 4, "5", HEAVY, "Rest 90 to 120 s. Rep count is ours"),
            (62, "Bulgarian Split Squat", 3, "6-8", HARD, "Each leg. Rep range is ours"),
            (102, "Nordic Hamstring Curl", 3, "5-6", HARD, "Source: Nordic hamstring eccentric. Rep range is ours"),
            (112, "Standing Calf Raise", 3, "8-12", STEADY, "Rep range is ours"),
        ],
    ),
    dict(
        name="Lacrosse: Phase 3 Explosive Lower",
        phase="build", goal="power", minutes=40, sports=LACROSSE,
        credit=ABELSSON_LAX, url=ABELSSON_LAX_URL,
        notes="Source: workout 1 (explosive lower, squat-based) of phase 3, weeks 9 to 12 (power and speed) of "
              "the same program. Sets only are printed; the source rests power lifts 2 to 3 minutes. Our rule: "
              "3 reps a set on the clean and jump squat, 5 on the jumps, every rep fast. The source's "
              "'horizontal and vertical jump' is matched to the broad jump; add a vertical jump if you like. "
              "The source is inconsistent on the phase 3 weeks (9 to 11 in some places). Phase is ours: "
              "build.",
        movements=[
            (910, "Hang Clean", 5, "3", FAST, "Source: hang clean. Rep count is ours. Rest 2 to 3 min"),
            (1034, "Jump Squat", 4, "3-5", FAST, "Rep count is ours"),
            (62, "Bulgarian Split Squat", 3, "6-8", HARD, "Each leg. Rep range is ours"),
            (52, "Broad Jump", 3, "5", FAST, "Source: horizontal and vertical jump. Rep count is ours"),
            (376, "Hanging Leg Raise", 3, "10-12", STEADY, "Rep range is ours"),
        ],
    ),
    # ------------------------------------------------------------------ team handball
    dict(
        name="Team Handball: Resistance Weeks 1 to 5",
        phase="base", goal="strength", minutes=45, sports=TEAM_HANDBALL,
        credit=HERMASSI, url=HERMASSI_URL,
        notes="Source: phases 1 and 2 (weeks 1 to 5) of a 10 week resistance program plus a 2 week taper in "
              "male handball players, twice a week from January to April, replacing part of technical training. "
              "Four lifts, same dose each. Weeks 1 and 2 are 60 percent of 1RM (3 x 6, then 4 x 8); weeks 3 "
              "to 5 are 70 percent (3 x 6, 3 x 8, then 3 x 10). Rest 3 minutes in the first 2 weeks; the "
              "paper gives no rest after that, so keep 2 to 3 minutes. The paper does not say whether "
              "these are pre-season or in-season, so base is our label (the first, lower-load block). "
              "Source: squat from a squatting position is a squat snatch, matched to the snatch "
              "row; half-squat is matched to the back squat, so keep depth to about 90 degrees at the knee.",
        movements=[
            (915, "Snatch", 3, "6-10", STEADY, "Source: snatch from a squatting position. 60 to 70% of 1RM"),
            (900, "Barbell Bench Press", 3, "6-10", STEADY, "60 to 70% of 1RM"),
            (57, "Barbell Back Squat", 3, "6-10", STEADY, "Source: half-squat. 60 to 70% of 1RM"),
            (914, "Clean & Jerk", 3, "6-10", STEADY, "60 to 70% of 1RM"),
        ],
    ),
    dict(
        name="Team Handball: Resistance Weeks 6 to 10",
        phase="build", goal="strength", minutes=45, sports=TEAM_HANDBALL,
        credit=HERMASSI, url=HERMASSI_URL,
        notes="Source: phase 3 (weeks 6 to 10) of the same 10 week program, twice a week. Same four lifts. "
              "Week 6 is 75 percent of 1RM (3 x 8, then 3 x 10), weeks 7 to 9 are 80 percent (3 x 6, then "
              "3 x 7), and the last two sessions are 85 percent for 3 x 5. The paper gives no rest here; "
              "keep 2 to 3 minutes. Phase is ours: the heaviest block of the paper, so build.",
        movements=[
            (915, "Snatch", 3, "5-8", HEAVY, "Source: snatch from a squatting position. 75 to 85% of 1RM"),
            (900, "Barbell Bench Press", 3, "5-8", HEAVY, "75 to 85% of 1RM"),
            (57, "Barbell Back Squat", 3, "5-8", HEAVY, "Source: half-squat. 75 to 85% of 1RM"),
            (914, "Clean & Jerk", 3, "5-8", HEAVY, "75 to 85% of 1RM"),
        ],
    ),
    dict(
        name="Team Handball: Taper Week Strength",
        phase="maintenance", goal="strength", minutes=30, sports=TEAM_HANDBALL,
        credit=HERMASSI, url=HERMASSI_URL,
        notes="Source: the 2 week taper (weeks 11 and 12) of the same program: 2 x 12 at 50 percent of 1RM, "
              "volume cut by about two thirds and frequency halved, so one session a week. Maintenance is "
              "ours: the load is low enough to hold strength through a competition week.",
        movements=[
            (915, "Snatch", 2, "12", STEADY, "Source: snatch from a squatting position. 50% of 1RM"),
            (900, "Barbell Bench Press", 2, "12", STEADY, "50% of 1RM"),
            (57, "Barbell Back Squat", 2, "12", STEADY, "Source: half-squat. 50% of 1RM"),
            (914, "Clean & Jerk", 2, "12", STEADY, "50% of 1RM"),
        ],
    ),
    dict(
        name="Team Handball: Competition Period Max Strength Day",
        phase="maintenance", goal="strength", minutes=45, sports=TEAM_HANDBALL,
        credit=SPIESZNY, url=SPIESZNY_URL,
        notes="Source: the maximal strength session of the paper's undulating pair, added twice a week to "
              "club training during the competitive period in male handball players, about 45 minutes. "
              "3 to 4 sets of 3 to 6 reps, load set so each athlete can just finish the reps. The paper "
              "gives no percentages and no rest: work near a 4 to 6RM and rest 2 to 3 minutes. "
              "Loads rose across the paper through volume and intensity changes it does not detail. The "
              "paper names the period as competitive, so maintenance is the nearest label.",
        movements=[
            (57, "Barbell Back Squat", 4, "3-6", HEAVY, "Source: barbell squat. 3 to 4 sets"),
            (59, "Conventional Deadlift", 4, "3-6", HEAVY, "Source: deadlift. 3 to 4 sets"),
            (900, "Barbell Bench Press", 4, "3-6", HEAVY, "Source: bench press. 3 to 4 sets"),
        ],
    ),
    dict(
        name="Team Handball: Competition Period Power Day",
        phase="maintenance", goal="power", minutes=45, sports=TEAM_HANDBALL,
        credit=SPIESZNY, url=SPIESZNY_URL,
        notes="Source: the power session of the same undulating pair, twice a week in the competitive period. "
              "3 to 4 sets of 3 to 6 reps of jump squat, clean and jerk and dynamic bench press, load chosen "
              "so each athlete finishes the reps. The paper gives no percentages and no rest: use a load you "
              "can move fast and stop a set when speed drops, rest 2 to 3 minutes. Source: dynamic bench press "
              "is matched to the barbell bench press moved fast. Alternate with the max strength day. "
              "Maintenance is our nearest label for a competitive-period block.",
        movements=[
            (1034, "Jump Squat", 4, "3-6", FAST, "Source: barbell jump squat. 3 to 4 sets"),
            (914, "Clean & Jerk", 4, "3-6", FAST, "Source: clean and jerk. 3 to 4 sets"),
            (900, "Barbell Bench Press", 4, "3-6", FAST, "Source: dynamic bench press. 3 to 4 sets"),
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
