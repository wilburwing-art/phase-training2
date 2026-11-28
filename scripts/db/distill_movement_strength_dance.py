#!/usr/bin/env python3
"""Distill published S&C programs for the movement, strength and dance sports of bucket C into coach.db routines.

Backlog 2026-11e 4.6: tai-chi-qigong, movement-culture, pole-fitness, crossfit, olympic-weightlifting,
highland-games, dance-fitness, ballroom-latin, swing-dance, salsa-bachata, contemporary-dance, hip-hop-dance,
irish-dance. Sources meet the Phase 0 #4 standard as applied in 4.1 to 4.5: a named author with credentials or
an affiliation, and a named venue. Each is cited in `source_name` with its URL in `source_url`. Movements and
doses are distilled. The notes are ours.

No source met the standard for highland-games, ballroom-latin, swing-dance, salsa-bachata or irish-dance after
one search pass; they move to bucket D (see the 4.6 note in the backlog). The StrengthLog dancer program names
street and club styles, so it is tagged dance-fitness and hip-hop-dance.

Phase follows `AuthoredRoutine.phaseLabels(for:)`. Where the source names no season, the phase is chosen from
what the source says the block is for, and the note says so. Sport tags are the sport slugs only; family roots
other than dance-fitness (a listed sport here) and parent mapping are left to 5.1.

Substitutes, where the catalog has no row for the movement the source names, are named in each movement note.
Doses the source does not print are not filled in: the note gives a working rule.
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

STEADY = "steady"
HARD = "hard but controlled"
HEAVY = "heavy, 1 to 2 reps in reserve"
FAST = "fast, full intent"

# ------------------------------------------------------------------ strength
CROSSFIT = (631,)
OLY = (635,)

MARTIN_WHITE = ("Martin J (coach and co-owner, CrossFit Brand X, CrossFit Kids program) and White DE (M.D., CrossFit Level 1 "
                "instructor). Strong Medicine: CrossFit with a Strength Bias (CFSB), CrossFit Journal, Feb 2009 (distilled)")
MARTIN_WHITE_URL = "https://library.crossfit.com/premium/pdf/CFJ_MartinWhite_StrengthBias.pdf"


EVERETT = ("Everett G (USA Weightlifting International Coach, 2021 Danish Coach of the Year, author of Olympic Weightlifting: "
           "A Complete Guide for Athletes & Coaches; coach of 40+ national and international lifters). ")
BASIC_STRENGTH = (EVERETT + "Basic Strength Cycle, week 1 sample, Catalyst Athletics (distilled)")
BASIC_STRENGTH_URL = "https://www.catalystathletics.com/olympic-weightlifting-training-program/27/Basic-Strength-Cycle/"
GENERAL_CYCLE = (EVERETT + "General Cycle, week 1 sample, Catalyst Athletics (distilled)")
GENERAL_CYCLE_URL = "https://www.catalystathletics.com/olympic-weightlifting-training-program/34/General-Cycle/"
OPEN_CYCLE = (EVERETT + "Greg Everett 2014 American Open Cycle, week 1 sample, Catalyst Athletics (distilled)")
OPEN_CYCLE_URL = "https://catalystathletics.com/olympic-weightlifting-training-program/55/Greg-Everett-2014-American-Open-Cycle/"

# ------------------------------------------------------------------ movement
TAI_CHI_QIGONG = (611,)
MOVEMENT_CULTURE = (612,)
POLE_FITNESS = (616,)

ZHUANG_2014 = ("Zhuang J, Huang L, Wu Y, Zhang Y (School of Kinesiology, Shanghai University of Sport; Dept of Sport and "
               "Exercise Science, University of Auckland). The effectiveness of a combined exercise intervention on "
               "physical fitness factors related to falls in community-dwelling older adults. Clin Interv Aging "
               "2014;9 (distilled)")
ZHUANG_URL = "https://www.dovepress.com/article/download/15474"

JIA_2018 = ("Jia X, Jiang C, Tao J, Li Y, Zhou Y, Chen L (Fujian University of Traditional Chinese Medicine; Fujian "
            "Provincial Hospital). Effects of core strength training combined with Tai Chi Chuan for the "
            "musculoskeletal system and cardiopulmonary function in older adults: a study protocol for a randomized "
            "controlled trial. Medicine (Baltimore) 2018;97(35):e12024 (distilled)")
JIA_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC6392686/"

BUXTON_2020 = ("Buxton JD, Prins PJ, Miller MG, Moreno A, Welton GL, Atwell AD, Talampas TR, Elsey GE (Dept of Exercise "
               "Science, Grove City College; Rocky Mountain University of Health Professions; Western and Eastern "
               "Michigan Universities). The effects of a novel quadrupedal movement training program on functional "
               "movement, range of motion, muscular strength, and endurance (Animal Flow). J Strength Cond Res 2020 "
               "(distilled)")
BUXTON_URL = "https://animalflow.com/wp-content/uploads/2020/11/The_Effects_of_a_Novel_Quadrupedal_Movement.94204.pdf"

MUNSON = ("Munson H (PoleFreaks founder and pole instructor, Level 4 advanced personal trainer, 2017 Miss Pole Dance UK "
          "semi-pro instructor 1st place, 2015 Pole2Pole Professional Cup 1st place). Strength Exercises for Pole "
          "Dancers, PoleFreaks (distilled)")
MUNSON_URL = "https://www.polefreaks.com/?p=10104"

MUSCAT = ("Muscat S (The Pole Physio; listed on the practice's team page as owner and founder, APA sports and exercise "
          "physiotherapist, ASCA strength and conditioning coach). Cross Train for Success, The Pole Physio blog "
          "(distilled)")
MUSCAT_URL = "https://www.thepolephysio.com/post/cross-train-for-success"

# ------------------------------------------------------------------ dance
DANCE_STREET = (730, 735)
CONTEMPORARY_DANCE = (734,)

LONG_2021 = ("Long KL, Milidonis MK, Wildermuth VL, Kruse AN, Parham UT (physical therapists, Cleveland State "
             "University, with The MetroHealth System). The impact of dance-specific neuromuscular conditioning and "
             "injury prevention training on motor control, stability, balance, function and injury in professional "
             "ballet dancers. Int J Sports Phys Ther 2021;16(2):404-417 (distilled)")
LONG_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC8016435"

SKOPAL_2020 = ("Skopal L, Netto K, Aisbett B, Takla A, Castricum T (Deakin University School of Exercise and Nutrition "
               "Sciences, Curtin University, Australian Sports Physiotherapy). The effect of a rhythmic "
               "gymnastics-based power-flexibility program on the lower limb flexibility and power of contemporary "
               "dancers. Int J Sports Phys Ther 2020;15(3):343-364 (distilled)")
SKOPAL_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC7297002"
ABELSSON = ("Abelsson A (certified nutrition coach and bodybuilding specialist, four decades of training). Strength Training "
            "for Dancers: Complete Guide and Training Program, StrengthLog, strengthlog.com (distilled)")
ABELSSON_URL = "https://www.strengthlog.com/strength-training-for-dancers/"

ROUTINES = [
    # -------------------------------------------------------------- crossfit
    dict(
        name="CrossFit: Strength Bias Lifts",
        phase="build", goal="strength", minutes=50, sports=CROSSFIT,
        credit=MARTIN_WHITE, url=MARTIN_WHITE_URL,
        notes=("Source: the CrossFit Strength Bias (CFSB) week for intermediate and advanced CrossFitters, six weeks, "
               "run on top of normal CrossFit met-cons. The source spreads these four lifts over three days (back squat, "
               "deadlift, then front squat with shoulder press); one or two lifts a day is under the app's floor, so "
               "they are joined here, as in 4.1 for fencing. Split them back over the week if you can. Each lift is a "
               "choice between 3 x 5 and 5 x 3 (weeks 3 to 5 lean to sets of 3), done as ascending sets that end on "
               "one PR set, 1 minute rest, aiming at a small PR every week. Start about 15 to 20 percent under your "
               "current PR; the source prints no other loads. The source also allows one set of 15 to 20 near failure "
               "in place of the sets on a day. The source names no season; build is ours. Met-con and skill work are "
               "left out."),
        movements=[
            (57, "Barbell Back Squat", 3, "5 or 3 (choose 3 x 5 or 5 x 3)", HEAVY, "Ascending sets to one PR set; 1 min rest"),
            (59, "Conventional Deadlift", 3, "5 or 3 (choose 3 x 5 or 5 x 3)", HEAVY, "Ascending sets to one PR set; 1 min rest. Source: its own day, after the squat day"),
            (450, "Front Squat (Barbell)", 3, "5 or 3 (choose 3 x 5 or 5 x 3)", HEAVY, "Ascending sets to one PR set; 1 min rest"),
            (904, "Barbell Overhead Press (Strict)", 3, "5 or 3 (choose 3 x 5 or 5 x 3)", HEAVY, "Ascending sets to one PR set; 1 min rest. Source: shoulder press, same day as the front squat"),
        ],
    ),

    # -------------------------------------------------------------- olympic-weightlifting
    dict(
        name="Olympic Weightlifting: Basic Strength Cycle Squat, Press and Pull Day",
        phase="base", goal="strength", minutes=45, sports=OLY,
        credit=BASIC_STRENGTH, url=BASIC_STRENGTH_URL,
        notes=("Source: day 1 of week 1 of Catalyst's 6 week strength phase for squat, pull and press, moderate volume and "
               "intensity, ending in a snatch and clean and jerk test. Only week 1 is public; the rest of the cycle needs a "
               "login and is not distilled. Percentages are of the lifter's max for that lift (snatch pull is 90 percent of "
               "the snatch). The same week has classic-lift days that are left out."),
        movements=[
            (57, "Barbell Back Squat", 4, "5", HEAVY, "75 percent of max"),
            (905, "Push Press", 5, "5", HEAVY, "70 percent of max"),
            (913, "Snatch Pull", 5, "5", HEAVY, "90 percent of the snatch"),
            (969, "Sit-Up", 3, "10", HARD, "Weighted, per source; the source gives no load"),
        ],
    ),
    dict(
        name="Olympic Weightlifting: Basic Strength Cycle Front Squat and Clean Pull Day",
        phase="base", goal="strength", minutes=45, sports=OLY,
        credit=BASIC_STRENGTH, url=BASIC_STRENGTH_URL,
        notes=("Source: day 3 of week 1 of Catalyst's 6 week Basic Strength Cycle (see the day 1 routine). Percentages are "
               "of the lifter's max for the lift; clean pull is 93 percent of the clean. Source: snatch push press, read "
               "as Push Press with a snatch grip (the catalog has no snatch push press row)."),
        movements=[
            (450, "Front Squat (Barbell)", 3, "5", HEAVY, "75 percent of max; source prints 3 x 5"),
            (905, "Push Press", 5, "5", HEAVY, "73 percent of max. Source: snatch push press, snatch grip"),
            (911, "Clean Pull", 5, "5", HEAVY, "93 percent of the clean"),
            (376, "Hanging Leg Raise", 3, "15", HARD, "Source: hanging leg raise"),
            (983, "Back Extension", 3, "15", HARD, "Source: back extension"),
        ],
    ),
    dict(
        name="Olympic Weightlifting: General Cycle Strength Day",
        phase="maintenance", goal="strength", minutes=40, sports=OLY,
        credit=GENERAL_CYCLE, url=GENERAL_CYCLE_URL,
        notes=("Source: the strength work from week 1 of Catalyst's 8 week General Cycle, which the page describes as low to "
               "moderate volume for lifters with limited recovery or time, or who combine lifting with other sports. That "
               "is why the phase is maintenance (ours). Week 1 is a light transition week and only it is public. Back squat "
               "ramps 55 percent x 10, 60 x 8, 65 x 8, 70 x 5. Press and rows are 3 x 8 with no load printed: use a weight "
               "that leaves 2 reps in reserve. Front squat and the light good morning are from the Saturday session of the "
               "same week. The half-moon drill and the snatch and clean complexes are left out."),
        movements=[
            (57, "Barbell Back Squat", 4, "10, 8, 8, 5", STEADY, "Ramp 55, 60, 65, 70 percent of max"),
            (904, "Barbell Overhead Press (Strict)", 3, "8", STEADY, "Source: press; the source gives no load"),
            (8, "Barbell Bent-Over Row", 3, "8", STEADY, "Source: bent row; the source gives no load"),
            (120, "Bear Crawl", 3, "20 m", STEADY, "Source: 20 m bear crawl, 3 sets with no rest, paired with half-moons (not in catalog)"),
            (450, "Front Squat (Barbell)", 3, "5, 5, 3", STEADY, "60, 65, 70 percent of max, Saturday session"),
            (921, "Barbell Good Morning", 3, "8", STEADY, "Light, per source; the source gives no load"),
        ],
    ),
    dict(
        name="Olympic Weightlifting: Open Cycle Push Press and Squat Day",
        phase="build", goal="strength", minutes=45, sports=OLY,
        credit=OPEN_CYCLE, url=OPEN_CYCLE_URL,
        notes=("Source: day 1 of week 1 of a 12 week cycle close to what Everett trained for the 2014 American Open, "
               "ending in a 4 week competition block. Only week 1 is public. Each RM lift is a top set at 95 percent of the "
               "day's rep max and a second set at 90 percent, found by feel in week 1 (do not go to a true max; weights "
               "go up in weeks 2 and 3). The push press set is a (5+1) complex, 5 push presses then 1 pause jerk, the "
               "jerk left out here. The back squat jump is 20 percent of the back squat. The phase is ours, a heavy "
               "strength block inside a peaking cycle."),
        movements=[
            (905, "Push Press", 2, "5 (+1 pause jerk)", HEAVY, "95 percent then 90 percent of the day's RM; source: push press plus pause jerk"),
            (57, "Barbell Back Squat", 2, "5", HEAVY, "95 percent then 90 percent of the day's 5RM"),
            (1050, "Lunge (Barbell)", 3, "5 per leg", HARD, "Source: weighted lunge; the source gives no load"),
            (1034, "Jump Squat", 3, "5", FAST, "20 percent of the back squat. Source: back squat jump"),
        ],
    ),
    dict(
        name="Olympic Weightlifting: Open Cycle Pause Squat and Press Day",
        phase="build", goal="strength", minutes=50, sports=OLY,
        credit=OPEN_CYCLE, url=OPEN_CYCLE_URL,
        notes=("Source: day 3 of week 1 of the 12 week Open cycle (see the push press and squat routine for how the RM "
               "percentages work). Only week 1 is public. Top set at 95 percent of the day's 5RM, then 90 percent. The "
               "jumping quarter squat is 50 percent of the back squat. The source's snatch push press with overhead squat "
               "is shown as the overhead squat; read the push press as a snatch grip push press first. The phase is ours."),
        movements=[
            (905, "Push Press", 2, "5 (+1 overhead squat)", HEAVY, "95 then 90 percent of the day's RM. Source: snatch push press plus overhead squat, snatch grip"),
            (1056, "Overhead Squat (Barbell)", 2, "1", HEAVY, "The single that follows each push press set"),
            (919, "Pause Squat", 2, "5", HEAVY, "95 percent then 90 percent of the day's 5RM. Source: pause back squat"),
            (1034, "Jump Squat", 3, "5", FAST, "50 percent of the back squat. Source: jumping quarter squat"),
            (904, "Barbell Overhead Press (Strict)", 2, "5", HEAVY, "95 then 90 percent of the day's 5RM. Source: press"),
        ],
    ),

    # -------------------------------------------------------------- movement
    dict(
        name="Tai Chi: Lower-Body Strength and Balance Class",
        phase="base", goal="strength", minutes=30, sports=TAI_CHI_QIGONG, environment="home",
        credit=ZHUANG_2014, url=ZHUANG_URL,
        notes="Source: the 12 week class for community-dwelling adults aged 60 to 80 (three 60 minute classes a week). "
              "Each class was 5 min warm-up, 15 min balance work, 15 min bodyweight strength work, 15 min of 8-form Yang "
              "tai chi and 10 min stretching. The tai chi forms and stretching are dropped here (forms practice and "
              "mobility). The paper names the movements and the block lengths but prints no sets, reps or holds, and "
              "names no season, so the phase is ours. Working rule, ours: 2 sets of 10 to 12 slow reps for the strength "
              "moves and 20 to 30 seconds a side for the balance move, with a chair within reach. The source is written "
              "for older adults; a tai chi practitioner of any age can use it as the stance-strength companion to forms "
              "practice. Source: standing on toes maps to Standing Calf Raise; side leg raise maps to Side-Lying Hip "
              "Abduction; hip flexion lying maps to Flat Leg Raise; abdominal leg raise and hip bend maps to Reverse "
              "Crunch; back extension lying on the stomach maps to Superman Hold. Source: single-limb stance, staggered "
              "stance, heel-to-toe walking, knee marching and star excursion balance work are covered by one row "
              "(Single-Leg Relevé with Balance). Standing up from a chair and the shank lift have no catalog row and "
              "are left out.",
        movements=[
            (1088, "Squat (Bodyweight)", 2, "10 to 12", STEADY, "Source: bodyweight squat; no sets or reps printed"),
            (112, "Standing Calf Raise", 2, "10 to 12", STEADY, "Source: standing on toes, bodyweight; no sets or reps printed"),
            (1200, "Side-Lying Hip Abduction", 2, "10 to 12 per side", STEADY, "Source: side leg raise; nearest row"),
            (1019, "Flat Leg Raise", 2, "10 to 12", STEADY, "Source: hip flexion, raising one leg while lying on the back"),
            (975, "Reverse Crunch", 2, "10 to 12", STEADY, "Source: raising legs and bending hip while lying on the back"),
            (220, "Superman Hold", 2, "10 to 12", STEADY, "Source: raising the upper body while lying on the stomach"),
            (511, "Single-Leg Relevé with Balance", 2, "20 to 30 s per side", STEADY, "Source: single-limb stance and the other balance drills; hold a chair if needed"),
        ],
    ),

    dict(
        name="Tai Chi: Core Strength Session",
        phase="maintenance", goal="accessory", minutes=30, sports=TAI_CHI_QIGONG, environment="home",
        credit=JIA_2018, url=JIA_URL,
        notes="Source: the five-movement core strength arm of a randomized trial protocol in older adults, run next to "
              "a 24-form Yang tai chi arm and a combined arm (30 min core strength plus 30 min tai chi). The protocol "
              "gives 60 minute sessions five days a week for 12 weeks including warm-up and cool-down, led by "
              "physiotherapists, and prints no sets, reps, holds or progression. It is a published protocol, not "
              "results. The phase is ours. Working rule, ours: 2 sets of 8 to 10 slow reps per side, or 20 to 30 s "
              "holds, stopping before the low back sags. The source says each single-leg bridge alternates twice per "
              "side. Source: double leg bypass is a two-leg hip lift; single leg bypass lifts one straight leg with "
              "both hips kept up; supine step is an alternating foot step with the knees bent and the hips balanced "
              "(Dead Bug is the nearest row); four-point support is a prone elbows-and-toes bridge (Front Plank); "
              "kneeling diagonal support is the opposite arm and leg extension (Bird Dog).",
        movements=[
            (1020, "Glute Bridge", 2, "10", STEADY, "Source: double leg bypass; hold the hip extension at the top"),
            (103, "Single-Leg Glute Bridge", 2, "2 per side, alternating", STEADY, "Source: single leg bypass, alternating sides twice on each side"),
            (1205, "Dead Bug", 2, "10", STEADY, "Source: supine step, alternating feet with knees bent; nearest row"),
            (974, "Front Plank", 2, "20 to 30 s", STEADY, "Source: four-point support (abdominal bridge) on elbows and toes; hold time is ours"),
            (1201, "Bird Dog", 2, "8 per side", STEADY, "Source: kneeling diagonal support, opposite arm and leg extended, alternating"),
        ],
    ),

    dict(
        name="Movement Culture: Quadrupedal Movement Base Session",
        phase="base", goal="accessory", minutes=40, sports=MOVEMENT_CULTURE, environment="anywhere",
        credit=BUXTON_2020, url=BUXTON_URL,
        notes="Source: weeks 1 to 4 of an 8 week randomized trial of a commercial ground-based movement system "
              "(Animal Flow), two 60 minute sessions a week with at least 48 hours between, taught by a certified "
              "instructor, on top of the subjects' normal training. Animal Flow is one movement-culture system "
              "(ground movement, animal positions and transitions); the paper does not name other systems. The "
              "wrist mobility block (30 s each of six drills), form stretches and the choreographed flow at the end are "
              "dropped as mobility or skill. Progression in the paper is more reps and sets and shorter rest over the "
              "block; the phase label is ours. Source: Beast is a hovering four-point hold and Crab is the reverse "
              "tabletop hold. Neither has a catalog row; Bear Crawl is used for the Beast hold and Glute Bridge for "
              "the Crab hold. Loaded beast unload, loaded beast wave, ape reach and traveling Ape have no row and are "
              "left out except for the squat-position row. Source: underswitch and side kick through map to Mountain "
              "Climber.",
        movements=[
            (120, "Bear Crawl", 2, "10 to 15 s hold", HARD, "Source: Beast (hover) and Beast 2 activations, 2 sets each, 30 to 60 s rest; nearest row"),
            (1020, "Glute Bridge", 2, "10 to 15 s hold", HARD, "Source: Crab and Crab 2 activations, 2 sets each, 30 to 60 s rest; nearest row"),
            (1088, "Squat (Bodyweight)", 1, "3 to 5", STEADY, "Source: ape reach form stretch, 1 set; nearest row, hands low in a deep squat"),
            (120, "Bear Crawl", 2, "10 yds forward and back", HARD, "Source: forward and reverse Beast traveling form, 1 to 3 sets, 30 to 60 s rest"),
            (1053, "Mountain Climber", 2, "10 to 20", HARD, "Source: underswitch and side kick through, 10 to 20 each, 1 to 3 sets; nearest row"),
        ],
    ),

    dict(
        name="Movement Culture: Quadrupedal Movement Circuits",
        phase="build", goal="endurance", minutes=40, sports=MOVEMENT_CULTURE, environment="anywhere",
        credit=BUXTON_2020, url=BUXTON_URL,
        notes="Source: weeks 5 to 8 of the same 8 week Animal Flow trial (see the base routine). The session is two "
              "mini circuits, each an activation, a mobilizing move and a traveling form for 3 sets with 15 s rest "
              "(30 to 60 s between circuits), then two switch-and-transition combos of 2 to 3 sets of 5 to 10 per side "
              "with 60 s rest, then a Beast flow for 2 to 4 rounds with 60 s rest. The wrist mobility, the form "
              "stretch flow and the flow itself are dropped. The table in the paper reads the Beast activation as '10' "
              "with no unit; the note treats it as seconds. Source: Beast is a hovering four-point hold and Crab a "
              "reverse tabletop hold; nearest catalog rows are used. Lateral Ape maps to the Cossack Squat. Scorpion "
              "reach, side kick through to full scorpion, and front step through to front kick through have no catalog "
              "row; the kick-through combos are covered by the mountain climber row.",
        movements=[
            (120, "Bear Crawl", 3, "10 s hold", HARD, "Source: circuit 1 Beast activation, 15 s rest; nearest row"),
            (1020, "Glute Bridge", 3, "10", HARD, "Source: circuit 1 Crab reach, 15 s rest; nearest row"),
            (226, "Cossack Squat", 3, "10", HARD, "Source: circuit 1 Lateral Ape, 15 s rest; nearest row"),
            (120, "Bear Crawl", 3, "20 (10 forward, 10 back)", HARD, "Source: circuit 2 forward and reverse Beast traveling form; 15 s rest"),
            (1053, "Mountain Climber", 3, "5 to 10 per side", HARD, "Source: the two switch and transition combos, 2 to 3 sets, 60 s rest; nearest row"),
        ],
    ),

    dict(
        name="Pole Fitness: Inversion Pulling Strength",
        phase="build", goal="strength", minutes=35, sports=POLE_FITNESS,
        credit=MUSCAT, url=MUSCAT_URL,
        notes="Source: the cross-training advice of a pole physiotherapy practice, which names off-pole gym work for "
              "inverts (horizontal pulling, vertical pulling, eccentric biceps loading). The only dose the post prints "
              "is 3 to 5 sets of 6 to 12 reps with a load matched to the trick; it gives no load, rest or weekly "
              "frequency and names no season, so the phase is ours. Working rule, ours: a weight that stops the set "
              "at the top of the rep range, 90 s rest, and 3 sets when starting. The post names the exercises without "
              "a list for each, so the four rows are the movements it names: bent-over row, inverted row, lat "
              "pulldown, and biceps loading with a slow lowering. The sets figure here is the middle of the range.",
        movements=[
            (8, "Barbell Bent-Over Row", 4, "6 to 12", HEAVY, "Source: bent-over row (horizontal pull for inverts); the source gives no load"),
            (135, "Inverted Row", 4, "6 to 12", HARD, "Source: inverted row; the source gives no load"),
            (1046, "Lat Pulldown (Machine)", 4, "6 to 12", HEAVY, "Source: lat pulldown (vertical pull for inverts); the source gives no load"),
            (948, "Dumbbell Curl", 4, "6 to 12", STEADY, "Source: eccentric bicep loading at the gym; lower slowly, load not given"),
        ],
    ),

    dict(
        name="Pole Fitness: Conditioning Circuit",
        phase="maintenance", goal="endurance", minutes=25, sports=POLE_FITNESS, environment="home",
        credit=MUNSON, url=MUNSON_URL,
        notes="Source: a pole champion and Level 4 personal trainer's conditioning circuit of four sections, each "
              "section done once with 30 s rest between sections. Reps are per side or timed 30 s efforts, drop to 3 "
              "reps per side if 5 is too much. The page gives no weekly frequency and no season, so the phase is ours. "
              "It prints one pass; the working rule, ours, is to repeat the circuit about 3 times to reach 25 minutes. "
              "The source also prints a 4 kg ball for the Russian twist and a 6 kg ball for the squat to press. Shoulder "
              "mount and climb overs are pole skills with no catalog row and are left out. Source: aerial V invert is "
              "an on-pole move, nearest row is Hanging Knee Raise (the source lists floor V inverts or knee tucks as "
              "the alternative); seated pull up is an on-pole pull, nearest row is Inverted Row; kneeling press ups map "
              "to Push-Up from the knees.",
        movements=[
            (976, "Hanging Knee Raise", 1, "5 per side", HARD, "Source: aerial V invert; nearest row"),
            (970, "Russian Twist", 1, "30 s", STEADY, "Source: 4 kg medicine ball, or none"),
            (60, "Goblet Squat", 1, "30 s", STEADY, "Source: squat to press with a 6 kg ball; nearest row"),
            (221, "Flutter Kick (Hollow)", 1, "30 s", STEADY, "Source: flutter kicks"),
            (135, "Inverted Row", 1, "5 per side", HARD, "Source: seated pull ups; nearest row"),
            (13, "Push-Up", 1, "30 s", STEADY, "Source: kneeling press ups; drop to the knees"),
        ],
    ),

    # -------------------------------------------------------------- contemporary-dance
    dict(
        name="Contemporary Dance: Neuromuscular Strength, Weeks 1 and 2",
        phase="base", goal="strength", minutes=30, sports=CONTEMPORARY_DANCE, environment="gym",
        credit=LONG_2021, url=LONG_URL,
        notes="Source: the strength block of a 5 week, twice-weekly, 30 minute conditioning class run by physical "
              "therapists for a professional company the paper describes as a contemporary company (the abstract "
              "says classical and contemporary ballet dancers). The class also has a jog warm-up, plyometrics and "
              "ladder agility hops, all left out here. The source prints exercises but no sets, reps or loads. "
              "Working rule is ours: 2 sets of 8 to 10 per exercise (8 to 10 per side for single-leg work), "
              "holds of 20 to 30 seconds, loads you could lift for 3 more reps. The source names no season; "
              "base is ours because week 1 and 2 are the entry block. Source: squat with TheraBand biceps curl "
              "and the lunge with overhead press are read as the dumbbell lunge; TheraBand rows are read as "
              "the inverted row; prone gluteal set and straight leg raises are left out.",
        movements=[
            (1058, "Plank", 2, "30 s", STEADY, "Source: high plank. Dose is ours"),
            (132, "Side Plank", 2, "20 s per side", STEADY, "Source: side plank each side. Dose is ours"),
            (1020, "Glute Bridge", 2, "10", STEADY, "Source: bridges, progressing to bridges with marching"),
            (1052, "Lunge (Dumbbell)", 2, "8 per leg", STEADY, "Source: lunge with overhead shoulder press; source gives no load"),
            (108, "Single-Leg Romanian Deadlift", 2, "8 per leg", STEADY, "Source: single-leg Romanian deadlift, arms forward in week 2; no load given"),
            (13, "Push-Up", 2, "8", STEADY, "Source: push-up; week 2 holds and adds an opposite shoulder tap"),
            (135, "Inverted Row", 2, "8", STEADY, "Source: inverted rows at a bar (week 1); week 2 uses TheraBand rows"),
        ],
    ),

    dict(
        name="Contemporary Dance: Single-Leg Strength and Balance, Weeks 3 to 5",
        phase="build", goal="strength", minutes=30, sports=CONTEMPORARY_DANCE, environment="home",
        credit=LONG_2021, url=LONG_URL,
        notes="Source: weeks 3 to 5 of the same twice-weekly, 30 minute class for a professional contemporary "
              "company (see the other routine from this paper). The strength list moves to single-leg, reaching "
              "and balance work. The source prints no sets, reps or loads: 2 to 3 sets of 6 to 8 per side with "
              "slow control, bodyweight only. The source names no season; build is ours because it is the "
              "harder half of the block. Source: Y-balance single-leg squat (reaching the free leg forward, "
              "back-inside and back-outside) is read as the pistol squat to a box, or a shallow single-leg "
              "squat if you cannot reach a box. Source: relevé lunge-hold into forward, side, back and side "
              "lunges is read as the bodyweight lunge; relevé plié and reaching rond de jambe are left out. "
              "Source: reverse crunches and plank bird dog map to the same rows.",
        movements=[
            (1057, "Pistol Squat", 3, "6 per leg", STEADY, "Source: single-leg squat reaching in several directions; box assist allowed"),
            (108, "Single-Leg Romanian Deadlift", 3, "8 per leg", STEADY, "Source: single-leg stiff-leg deadlift with arms overhead; week 4 adds a calf raise at the top"),
            (1051, "Lunge (Bodyweight)", 2, "6 per direction", STEADY, "Source: relevé lunge-hold into four directions; hold each lunge a beat"),
            (1080, "Single Leg Bridge", 2, "8 per leg", STEADY, "Source: bridges, week 4 with a band around the thighs and alternating hip flexion"),
            (1201, "Bird Dog", 2, "8 per side", STEADY, "Source: plank bird dog, week 4"),
            (975, "Reverse Crunch", 2, "10", STEADY, "Source: reverse crunches, week 3"),
            (13, "Push-Up", 2, "8", STEADY, "Source: push-up with contralateral hand taps, week 4"),
        ],
    ),

    dict(
        name="Contemporary Dance: Jump and Leap Power Session",
        phase="build", goal="power", minutes=25, sports=CONTEMPORARY_DANCE, environment="gym",
        credit=SKOPAL_2020, url=SKOPAL_URL,
        notes="Source: the plyometric day of an 8 week trial in 11 intermediate female contemporary dancers, "
              "two one-hour sessions a week added to usual dance training (the source alternates this day with a "
              "weighted barre kicking day, and has a 30 minute stretch and flexibility block, all left out). "
              "Continuous double-leg box jumps used a 450 mm box: weeks 1 to 4 one box up and down, weeks 5 to 8 "
              "three boxes in a row, 2 sets of 10, 60 s rest. The source's text and its table disagree on foot "
              "contacts for this lift (120 or 100 versus 80). Split leaps: 2 sets of 4 with 30 s rest, from "
              "weeks 3 to 4 with 0.5 kg ankle weights. The source's travelling kicks to jetes have no catalog "
              "row and are left out. The source names no season; build is ours. Source: alternating split "
              "leaps map to Split Squat Jump; vertical and tuck jumps (the 5 minute jump warm-up) map to Tuck Jump. "
              "Keep the 5 minute run or skip before it, as in the source.",
        movements=[
            (233, "Tuck Jump", 2, "8", FAST, "Source: vertical and tuck jumps in the jump warm-up; dose is ours"),
            (49, "Box Jump", 2, "10", FAST, "Source: continuous double-leg box jumps, 450 mm box, 60 s rest between sets"),
            (130, "Split Squat Jump", 2, "4 per leg", FAST, "Source: alternating split leaps, 30 s rest; leaps travel, jumps here are in place"),
        ],
    ),

    # -------------------------------------------------------------- dance-fitness and hip-hop-dance
    dict(
        name="Dance Fitness: Lower Body and Core Strength",
        phase="base", goal="strength", minutes=45, sports=DANCE_STREET,
        credit=ABELSSON, url=ABELSSON_URL,
        notes=("Source: workout A of an 8 week dancer program for street and club styles (hip hop, house, popping, "
               "locking, breaking and similar), two sessions a week in weeks 1 to 4, rest 60 to 120 seconds. The author "
               "is a nutrition coach and bodybuilding specialist, not a dance clinician; the exact program lives in the "
               "app and only the free page was read. The source names no styles of ballroom, salsa or swing. Load rule "
               "printed: the last rep slows but you stop short of failure, and 3 or more reps left in reserve means the "
               "weight is too light. Source gives 2 to 3 sets, shown as 3. Source: Romanian deadlift maps to Dumbbell "
               "Romanian Deadlift. The week 5 swaps are barbell squat for goblet squat, seated for standing calf "
               "raise, Copenhagen plank for side plank. Phase is ours."),
        movements=[
            (60, "Goblet Squat", 3, "10", HARD, "Source: 2 to 3 sets of 10"),
            (1171, "Dumbbell Romanian Deadlift", 3, "10", HARD, "Source: Romanian deadlift, 2 to 3 sets of 10"),
            (62, "Bulgarian Split Squat", 3, "8 per leg", HARD, "Source: 2 to 3 sets of 8"),
            (112, "Standing Calf Raise", 3, "20", STEADY, "Source: 2 to 3 sets of 20"),
            (132, "Side Plank", 3, "30 s per side", STEADY, "Source: 2 to 3 sets of 30 s"),
            (1205, "Dead Bug", 3, "12", STEADY, "Source: 2 to 3 sets of 12"),
        ],
    ),
    dict(
        name="Dance Fitness: Upper Body and Lateral Power",
        phase="build", goal="power", minutes=45, sports=DANCE_STREET,
        credit=ABELSSON, url=ABELSSON_URL,
        notes=("Source: workout B of the same 8 week street and club dancer program (author a nutrition coach and "
               "bodybuilding specialist; only the free page was read; no ballroom, salsa or swing named). Rest 60 to "
               "120 seconds. Source gives 2 to 3 sets, shown as 3. Source: hip thrust maps to Dumbbell Hip Thrust, "
               "side lunge to Lateral Lunge, Pallof press as printed. Phase is ours."),
        movements=[
            (329, "Lateral Bound to Stick", 3, "4 per side", FAST, "Source: lateral bound, 2 to 3 sets of 4"),
            (1174, "Dumbbell Hip Thrust", 3, "12", HARD, "Source: hip thrust, 2 to 3 sets of 12"),
            (227, "Lateral Lunge", 3, "8 per side", HARD, "Source: side lunge, 2 to 3 sets of 8"),
            (13, "Push-Up", 3, "12", STEADY, "Source: 2 to 3 sets of 12"),
            (10, "Dumbbell Single-Arm Row", 3, "12 per arm", STEADY, "Source: dumbbell row, 2 to 3 sets of 12"),
            (63, "Pallof Press", 3, "12 per side", STEADY, "Source: 2 to 3 sets of 12"),
        ],
    ),
    dict(
        name="Dance Fitness: Full-Body Strength and Jumps",
        phase="maintenance", goal="strength", minutes=45, sports=DANCE_STREET,
        credit=ABELSSON, url=ABELSSON_URL,
        notes=("Source: workout C of the same 8 week street and club dancer program, added from week 5 as a third "
               "session (author a nutrition coach and bodybuilding specialist; only the free page was read; no "
               "ballroom, salsa or swing named). Rest 60 to 120 seconds. Source gives 2 to 3 sets, shown as 3. Source: "
               "jump squat maps to Squat Jump (Counter-Movement), assisted pull-up to Pull-Up (use a band or machine "
               "assist), plank with shoulder taps to Plank (add the taps). The tibialis raise paired with the calf "
               "raise has no catalog row and is left out. Phase is ours."),
        movements=[
            (230, "Squat Jump (Counter-Movement)", 3, "5", FAST, "Source: jump squat, 2 to 3 sets of 5"),
            (108, "Single-Leg Romanian Deadlift", 3, "8 per leg", HARD, "Source: 2 to 3 sets of 8"),
            (61, "Kettlebell Swing", 3, "10", FAST, "Source: 2 to 3 sets of 10"),
            (13, "Push-Up", 3, "12", STEADY, "Source: 2 to 3 sets of 12"),
            (922, "Pull-Up", 3, "8", HARD, "Source: assisted pull-up"),
            (1058, "Plank", 3, "15 shoulder taps", STEADY, "Source: plank with shoulder taps"),
            (112, "Standing Calf Raise", 3, "15", STEADY, "Source: standing calf raise superset with a tibialis raise (left out)"),
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
