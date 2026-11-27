#!/usr/bin/env python3
"""Distill published S&C programs for the combat sports of bucket C into coach.db routines.

Backlog 2026-11e 4.2: muay-thai, kickboxing, karate, taekwondo, krav-maga, aikido, kung-fu,
capoeira, hema, kendo, iaido. Sources meet the Phase 0 #4 standard as applied in 4.1: a named
author with credentials or an affiliation, and a named venue. Each is cited in `source_name`
with its URL in `source_url`. Movements and doses are distilled. The notes are ours.

No source met the standard for krav-maga, aikido or iaido after one search pass; they move to
bucket D (see the 4.2 note in the backlog). Kung-fu is served from a Wushu Sanda paper and says so.

Phase follows `AuthoredRoutine.phaseLabels(for:)`. Where the source names no season, the phase
is chosen from what the source says the block is for, and the note says so. Sport tags are the
sport slugs only; the martial-arts root and parent mapping are left to 5.1.

Substitutes, where the catalog has no row for the movement the source names, are named in each
movement note. Doses the source does not print are not filled in: the note gives a working rule.
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source"

MUAY_THAI = (270,)
KICKBOXING = (271,)
KARATE = (277,)
TAEKWONDO = (281,)

ABELSSON = ("Abelsson A (certified nutrition coach and bodybuilding specialist, about four decades of "
            "training). Strength Training for Muay Thai, StrengthLog (strengthlog.com), 11 week program, "
            "two full-body sessions a week (distilled)")
ABELSSON_URL = "https://www.strengthlog.com/strength-training-for-muay-thai"
DE_LACEY = ("de Lacey J (MSc Sport and Exercise Science, strength and conditioning coach, founder of Sweet "
            "Science of Fighting). Strength Training for Kickboxing, sweetscienceoffighting.com, two phase "
            "twice-weekly program (distilled)")
DE_LACEY_URL = "https://sweetscienceoffighting.com/strength-training-for-kickboxing/"
MARIC = ("Maric F (PT, ISSA Elite Trainer: personal trainer, nutritionist and strength and conditioning "
         "certificates). Best Kickboxing Workout, Fitness Volt (fitnessvolt.com), two session strength "
         "plan (distilled)")
MARIC_URL = "https://fitnessvolt.com/best-kickboxing-workout/"
ANGLOS_KATA = ("Anglos K (MSc, CSCS), written for Karate Canada. Karate-Specific Strength & Conditioning "
               "Program, Junior Kata Athletes, 2022, beginner and intermediate/advanced workouts (distilled)")
ANGLOS_KATA_URL = "https://karatecanada.org/wp-content/uploads/2022/10/Karate-Canada-SC-Program-Junior-Kata35.pdf"
ANGLOS_KUMITE = ("Anglos K (MSc, CSCS), written for Karate Canada. Programme de force et conditionnement "
                 "specifique au karate, Athletes Kumite Junior (French edition), 2022, beginner and "
                 "intermediate/advanced workouts (distilled)")
ANGLOS_KUMITE_URL = "https://karatecanada.org/wp-content/uploads/2022/11/KC_SC-Program-Junior-Kumite_FRC42.pdf"
KHAZAEI = ("Khazaei L, Parnow A (Razi University, Kermanshah), Amani-shalamzari S (Kharazmi University, "
           "Tehran). Traditional resistance training vs functional training in female elite taekwondo "
           "athletes. BMC Sports Sci Med Rehabil 2023;15:139, Table 1 (distilled)")
KHAZAEI_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC10589965"

KUNG_FU = (287,)
CAPOEIRA = (288,)

ESPOSITO_2025 = ("Esposito G, Ceruso R, Tessitore A, Raiola G (University of Pegaso; University of Verona; "
                 "University of Rome Foro Italico). Maximum strength development in martial arts and "
                 "perception and awareness. Front Sports Act Living 2025;7:1676250, Table 2 (distilled)")
ESPOSITO_URL = "https://www.frontiersin.org/journals/sports-and-active-living/articles/10.3389/fspor.2025.1676250/full"

ARAUJO_2015 = ("Araujo S, Cohen D, Hayes L (London Metropolitan University; Universidad de Santander; "
               "University of the West of Scotland). Six weeks of core stability training improves landing "
               "kinetics among female capoeira athletes: a pilot study. J Hum Kinet 2015;45:27-37 (distilled)")
ARAUJO_URL = "https://pmc.ncbi.nlm.nih.gov/articles/PMC4415841"

HEMA = (293,)
KENDO = (294,)

SCOTT_2025 = ("Scott L (MD; MSc Strength and Conditioning, Loughborough; NSCA CSCS; HEMA coach and "
              "competitive longsword fencer, Sprezzatura Sports). Summer of Strength, Beyond the Blade "
              "newsletter, 17 Jul 2025, 8 to 12 week strength cycle (distilled)")
SCOTT_URL = "https://sprezzaturasports.beehiiv.com/p/summer-of-strength"

TAKAHASHI_HOME = ("Takahashi K (PhD Physical Education, Nippon Sport Science University; professor and head "
                  "coach, Kanto Gakuin University kendo club; kendo kyoshi 7th dan; physical training coach "
                  "for All Japan Kendo Federation representative camps since 2006). Kendo Jidai International, "
                  "'The most powerful home training you can do on your own', 20 Jul 2020, beginner circuit (distilled)")
TAKAHASHI_HOME_URL = "https://kendojidai.com/2020/07/20/home-training/"

STEADY = "steady"
HARD = "hard but controlled"
HEAVY = "heavy, 1 to 2 reps in reserve"
FAST = "fast, full intent"

ROUTINES = [
    # ------------------------------------------------------------------ muay thai
    dict(
        name="Muay Thai: Foundational Strength A",
        phase="base", goal="strength", minutes=45, sports=MUAY_THAI,
        credit=ABELSSON, url=ABELSSON_URL,
        notes="Source: workout 1 of block 1 (foundational strength, weeks 1 to 5) of an 11 week program, two "
              "full-body sessions a week with a rest day between. The block is the general strength block "
              "before the power block, so it sits in base. The page prints sets and reps only, no loads: "
              "work each lift at a weight that leaves 1 to 2 reps in reserve and add weight or a rep once "
              "every set hits its target. Rest 2 to 4 minutes after compound lifts. Pull-ups are max reps.",
        movements=[
            (451, "Trap Bar Deadlift", 3, "5", HEAVY, "Rest 2 to 4 min"),
            (922, "Pull-Up", 3, "max", HARD, "Max reps each set"),
            (62, "Bulgarian Split Squat", 3, "8", HARD, "Each leg"),
            (905, "Push Press", 3, "8", HARD, ""),
            (63, "Pallof Press", 3, "12", STEADY, "Each side"),
        ],
    ),
    dict(
        name="Muay Thai: Foundational Strength B",
        phase="base", goal="strength", minutes=45, sports=MUAY_THAI,
        credit=ABELSSON, url=ABELSSON_URL,
        notes="Source: workout 2 of block 1 (foundational strength, weeks 1 to 5) of the same 11 week program. "
              "Sets and reps only; the source gives no load, so use a weight that leaves 1 to 2 reps in "
              "reserve. Alternate with Foundational Strength A.",
        movements=[
            (450, "Front Squat (Barbell)", 3, "5", HEAVY, "Rest 2 to 4 min"),
            (8, "Barbell Bent-Over Row", 3, "8", HARD, ""),
            (900, "Barbell Bench Press", 3, "8", HARD, ""),
            (61, "Kettlebell Swing", 3, "12-15", FAST, ""),
            (376, "Hanging Leg Raise", 3, "12-15", STEADY, ""),
        ],
    ),
    dict(
        name="Muay Thai: Power A",
        phase="build", goal="power", minutes=45, sports=MUAY_THAI,
        credit=ABELSSON, url=ABELSSON_URL,
        notes="Source: workout 1 of block 2 (power and explosiveness, weeks 7 to 11) of the same 11 week "
              "program. Loads up to 75 percent of 1RM, every rep moved explosively. Rest 2 to 4 minutes after "
              "compound lifts and 1 to 2 minutes after the rest. Wood chop is 12 a side; the source does "
              "not say which wood chop, so the high-to-low cable version stands in.",
        movements=[
            (217, "Power Clean", 3, "3", FAST, "Up to 75% of 1RM, explosive"),
            (62, "Bulgarian Split Squat", 3, "5", HARD, "Each leg"),
            (922, "Pull-Up", 3, "5", HARD, ""),
            (900, "Barbell Bench Press", 3, "5", FAST, "Up to 75% of 1RM, explosive"),
            (50, "Medicine Ball Slam", 3, "12", FAST, "Source: ball slam"),
            (115, "Cable Wood Chop (High-to-Low)", 3, "12", FAST, "Source: wood chop. Each side"),
        ],
    ),
    dict(
        name="Muay Thai: Power B",
        phase="build", goal="power", minutes=45, sports=MUAY_THAI,
        credit=ABELSSON, url=ABELSSON_URL,
        notes="Source: workout 2 of block 2 (power and explosiveness, weeks 7 to 11) of the same 11 week "
              "program. Loads up to 75 percent of 1RM, every rep moved explosively. Ab wheel rollout is max "
              "reps. Alternate with Power A.",
        movements=[
            (57, "Barbell Back Squat", 3, "4", FAST, "Source: squat. Up to 75% of 1RM, explosive"),
            (8, "Barbell Bent-Over Row", 3, "6", HARD, "Source: barbell row"),
            (905, "Push Press", 3, "6", FAST, ""),
            (108, "Single-Leg Romanian Deadlift", 3, "6", HARD, "Each leg"),
            (49, "Box Jump", 3, "10", FAST, ""),
            (7, "Ab Wheel Rollout", 3, "max", HARD, "Max reps"),
        ],
    ),
    dict(
        name="Muay Thai: Light Week Strength",
        phase="maintenance", goal="strength", minutes=30, sports=MUAY_THAI,
        credit=ABELSSON, url=ABELSSON_URL,
        notes="Source: the deload week 6 of the same 11 week program, two sessions joined into one. Every "
              "exercise is 2 sets at 50 to 60 percent of the regular weight. The source places it between "
              "the strength and power blocks; the maintenance label is ours, because the load is low enough "
              "to hold strength through a fight camp. The source's wood chop has no dose we can match and is "
              "left out.",
        movements=[
            (57, "Barbell Back Squat", 2, "10", STEADY, "Source: squat. 50 to 60% of regular weight"),
            (58, "Romanian Deadlift (Barbell)", 2, "10", STEADY, "50 to 60% of regular weight"),
            (62, "Bulgarian Split Squat", 2, "10", STEADY, "Each leg"),
            (900, "Barbell Bench Press", 2, "10", STEADY, "50 to 60% of regular weight"),
            (922, "Pull-Up", 2, "10", STEADY, "Assisted if 10 is out of reach"),
            (49, "Box Jump", 2, "10", FAST, ""),
            (376, "Hanging Leg Raise", 2, "12", STEADY, ""),
        ],
    ),
    # ------------------------------------------------------------------ kickboxing
    dict(
        name="Kickboxing: Phase 1 Strength Day 1",
        phase="base", goal="strength", minutes=50, sports=KICKBOXING,
        credit=DE_LACEY, url=DE_LACEY_URL,
        notes="Source: phase 1, day 1 of a twice-weekly program; phase 1 prepares the athlete for the "
              "harder phase 2, so it sits in base. A short bodyweight jump circuit comes first (1 to 2 "
              "sets of 10), then the strength work. Squat at 75 to 88 percent of 1RM; the source gives no "
              "other loads, so work the rest at a weight that leaves 1 to 2 reps in reserve. Calf raise is "
              "paused 3 seconds at the bottom. The source gives no rest periods. Its split-stance medicine "
              "ball anti-rotation rebound has no catalog row and is left out.",
        movements=[
            (230, "Squat Jump (Counter-Movement)", 2, "10", FAST, "Bodyweight jump circuit, 1 to 2 sets"),
            (57, "Barbell Back Squat", 3, "3-5", HEAVY, "Source: squat variation. 75 to 88% of 1RM, 3 to 4 sets"),
            (907, "Incline Dumbbell Bench Press", 3, "5-6", HARD, "Source: low-incline dumbbell bench. 3 to 4 sets"),
            (1122, "Dumbbell Bent-Over Row", 3, "5-6", HARD, "Source: row variation. 3 to 4 sets"),
            (58, "Romanian Deadlift (Barbell)", 3, "4-6", HEAVY, "3 to 4 sets"),
            (112, "Standing Calf Raise", 3, "10-20", STEADY, "3 s pause at the bottom"),
            (976, "Hanging Knee Raise", 3, "10-20", STEADY, ""),
        ],
    ),
    dict(
        name="Kickboxing: Phase 1 Strength Day 2",
        phase="base", goal="strength", minutes=50, sports=KICKBOXING,
        credit=DE_LACEY, url=DE_LACEY_URL,
        notes="Source: phase 1, day 2 of the same twice-weekly program. Single-leg squat at 75 to 88 percent "
              "of 1RM; no other loads are printed, so work the rest at 1 to 2 reps in reserve. No rest "
              "periods are given. The source's one-arm dumbbell press is matched to the two-arm catalog "
              "dumbbell bench press. Alternate with Day 1.",
        movements=[
            (130, "Split Squat Jump", 2, "10", FAST, "Jump circuit, 1 to 2 sets, bodyweight"),
            (62, "Bulgarian Split Squat", 3, "5-6", HEAVY, "Source: single-leg squat variation. 75 to 88% of 1RM, each leg, 3 to 4 sets"),
            (14, "Dumbbell Bench Press", 3, "5-6", HARD, "Source: 1-arm dumbbell press. 3 to 4 sets"),
            (923, "Chin-Up", 3, "5-10", HARD, "3 to 4 sets"),
            (102, "Nordic Hamstring Curl", 3, "3-5", HARD, "Source: assisted Nordic drop. 3 to 4 sets"),
            (112, "Standing Calf Raise", 3, "10-20", STEADY, "3 s pause at the bottom"),
            (127, "Half-Kneeling Cable Rotation", 3, "10", STEADY, "Source: band rotation. Each side"),
        ],
    ),
    dict(
        name="Kickboxing: Phase 2 Power Day 1",
        phase="build", goal="power", minutes=50, sports=KICKBOXING,
        credit=DE_LACEY, url=DE_LACEY_URL,
        notes="Source: phase 2, day 1 of the same program: maximal plyometrics first, then lifts with fewer "
              "sets of heavier, faster work. Power jerk at 70 to 90 percent of 1RM, squat at 75 to 88 "
              "percent. Medicine ball is 3 to 5 kg. The source gives no other loads and no rest. Its "
              "continuous hurdle hop has no catalog row and is left out; the kettlebell clinch pull-up is "
              "done as a plain pull-up.",
        movements=[
            (49, "Box Jump", 3, "3-5", FAST, "Maximal plyometric, 3 to 4 sets"),
            (114, "Medicine Ball Rotational Throw", 3, "3-5", FAST, "Source: explosive rotational throw, 3 to 5 kg. 3 to 4 sets"),
            (906, "Push Jerk", 3, "2-5", FAST, "Source: power jerk. 70 to 90% of 1RM, 3 to 4 sets"),
            (922, "Pull-Up", 3, "5-10", HARD, "Source: kettlebell clinch pull-up, grip a kettlebell for the clinch hold. 3 to 4 sets"),
            (57, "Barbell Back Squat", 2, "2-5", HEAVY, "Source: squat variation. 75 to 88% of 1RM, 2 to 3 sets"),
            (58, "Romanian Deadlift (Barbell)", 2, "4-6", HEAVY, "2 to 3 sets"),
            (112, "Standing Calf Raise", 3, "6-10", HARD, "Source: 2 legs up, 1 leg down, 3 s pause. Each side"),
            (376, "Hanging Leg Raise", 3, "10-20", STEADY, ""),
        ],
    ),
    dict(
        name="Kickboxing: Phase 2 Power Day 2",
        phase="build", goal="power", minutes=50, sports=KICKBOXING,
        credit=DE_LACEY, url=DE_LACEY_URL,
        notes="Source: phase 2, day 2 of the same program. Low-box drop jump and a punch throw lead, then a "
              "loaded squat jump at 30 to 40 kg, then single-leg and upper body lifts at 2 to 3 sets. "
              "Medicine ball for the punch throw is 2 to 3 kg. The source gives no loads for the lifts and "
              "no rest.",
        movements=[
            (232, "Depth Jump", 2, "3-6", FAST, "Source: low box drop jump. 2 to 3 sets"),
            (225, "Med Ball Shot Put", 3, "3-5", FAST, "Source: explosive medicine ball punch throw, 2 to 3 kg. Each side, 3 to 4 sets"),
            (1034, "Jump Squat", 3, "2-5", FAST, "Source: loaded squat jump, 30 to 40 kg. 3 to 4 sets"),
            (62, "Bulgarian Split Squat", 2, "5-6", HEAVY, "Source: single-leg squat variation. Each leg, 2 to 3 sets"),
            (907, "Incline Dumbbell Bench Press", 2, "4-6", HARD, "Source: low-incline dumbbell bench. 2 to 3 sets"),
            (1122, "Dumbbell Bent-Over Row", 2, "5-6", HARD, "Source: row variation. 2 to 3 sets"),
            (102, "Nordic Hamstring Curl", 2, "3-5", HARD, "Source: Nordic drop. 2 to 3 sets"),
            (310, "Landmine Rotation", 3, "5-8", FAST, "Each side"),
        ],
    ),
    dict(
        name="Kickboxing: Two-Day Power Lifts",
        phase="maintenance", goal="power", minutes=45, sports=KICKBOXING,
        credit=MARIC, url=MARIC_URL,
        notes="Source: day 1 (lower-body power) of a two-session week with at least 2 days between sessions. "
              "The article names no phases, so maintenance is our label for a twice-weekly plan. Every lift is "
              "4 sets of 3 to 6, around 70 to 80 percent of 1RM; cable flies and pull-ups are 6 to 12. "
              "Rest is not given; take 2 to 3 minutes on the heavy lifts.",
        movements=[
            (1034, "Jump Squat", 4, "3-6", FAST, "Source: trap-bar jump, light load. Maximum height"),
            (933, "Leg Extension", 4, "3-6", HEAVY, "About 70 to 80% of 1RM"),
            (934, "Lying Leg Curl", 4, "3-6", HEAVY, "Source: leg curl. About 70 to 80% of 1RM"),
            (1070, "Seated Leg Press (Machine)", 4, "3-6", HEAVY, "Source: leg press. About 70 to 80% of 1RM"),
            (900, "Barbell Bench Press", 4, "3-6", HEAVY, "About 70 to 80% of 1RM"),
            (1121, "Incline Cable Fly", 4, "6-12", STEADY, "Source: cable flies"),
            (922, "Pull-Up", 4, "6-12", HARD, ""),
            (983, "Back Extension", 4, "3-6", HARD, "Source: back extensions"),
        ],
    ),
    dict(
        name="Kickboxing: Two-Day Punch Power Lifts",
        phase="maintenance", goal="power", minutes=45, sports=KICKBOXING,
        credit=MARIC, url=MARIC_URL,
        notes="Source: day 2 (punching power through upper-body ballistic work) of the same two-session "
              "week. Every lift is 4 sets; heavy lifts 3 to 6 reps at around 70 to 80 percent of 1RM, with "
              "maximum intent on the way up and a 2 to 3 second lowering. The article names no phases, so "
              "maintenance is our label. No rest is given; take 2 to 3 minutes on heavy lifts. The banded "
              "punches use the cable punch row as the nearest match.",
        movements=[
            (114, "Medicine Ball Rotational Throw", 4, "6-8", FAST, "Source: one-arm medicine ball throw. Each side"),
            (311, "Cable Punch / Chest Press Rotation", 4, "10-15", FAST, "Source: banded punches. Each side"),
            (451, "Trap Bar Deadlift", 4, "3-6", HEAVY, "About 70 to 80% of 1RM"),
            (932, "Hack Squat (Machine)", 4, "3-6", HEAVY, "About 70 to 80% of 1RM"),
            (9, "Seated Cable Row", 4, "3-6", HEAVY, "Source: cable rows"),
            (925, "Lat Pulldown (Wide-Grip)", 4, "6-12", HARD, "Source: lat pulldowns"),
            (16, "Dips (Parallel Bar)", 4, "6-12", HARD, "Source: weighted dips"),
            (101, "Barbell Hip Thrust", 4, "3-6", HEAVY, ""),
        ],
    ),
    # ------------------------------------------------------------------ karate
    dict(
        name="Karate Junior: Beginner Strength Circuit (Kata)",
        phase="base", goal="strength", minutes=30, sports=KARATE,
        credit=ANGLOS_KATA, url=ANGLOS_KATA_URL,
        notes="Source: the beginner workout (0 to 1 years in the gym) of Karate Canada's junior kata program. "
              "The program says 2 to 3 sessions a week before and after the season and 1 to 2 in season; "
              "this block is the off-season slot, so it sits in base (the phase is ours). Every exercise "
              "is 2 sets. Lower body and press lifts at 65 to 75 percent of 1RM; rest 15 to 30 seconds "
              "between exercises. Run the circuit as A1 to C2 straight through or all sets of each exercise "
              "in turn. Warm-up in the source: 5 to 10 minutes cardio, banded crab walks, 10 body squats and "
              "10 jump squats, dropped here. The source is written for kata; kumite has its own program "
              "(Karate Junior: Beginner Strength Circuit (Kumite)).",
        movements=[
            (916, "Sumo Deadlift", 2, "10-15", STEADY, "Source: kettlebell or dumbbell sumo deadlift, 65 to 75% of 1RM (20 to 50 lb), 15 s rest"),
            (60, "Goblet Squat", 2, "10-15", STEADY, "65 to 75% of 1RM (20 to 40 lb), 15 s rest"),
            (943, "Walking Lunge", 2, "10-15", STEADY, "10 to 25 lb each hand, 30 s rest"),
            (13, "Push-Up", 2, "max", HARD, "Bodyweight, full range, no rest into the row"),
            (1122, "Dumbbell Bent-Over Row", 2, "10-15", STEADY, "Source: bent-over row, 10 to 25 lb, 65 to 75% of 1RM. Each side, 30 s rest"),
            (1205, "Dead Bug", 2, "10-15", STEADY, "Each side, 15 s rest"),
            (971, "Bicycle Crunch", 2, "10-15", STEADY, "Each side, feet elevated, 30 s rest"),
        ],
    ),
    dict(
        name="Karate Junior: Intermediate Strength and Power (Kata)",
        phase="build", goal="power", minutes=45, sports=KARATE,
        credit=ANGLOS_KATA, url=ANGLOS_KATA_URL,
        notes="Source: the intermediate and advanced workout (1 to 2 years and over 2 years in the gym) of "
              "Karate Canada's junior kata program. The program names no block; its 2 to 3 sessions a week "
              "suit the preseason, so the build label is ours. Clean and jerk at 85 to 95 percent of 1RM "
              "(dumbbell for intermediate, barbell for advanced), 1 to 2 minutes rest; sumo deadlift and "
              "Bulgarian split squat at 70 to 85 percent; rest 30 s to 1:30 on the rest. The source "
              "says to complete all sets of each lower-body exercise before moving on. Warm-up as in the "
              "beginner workout, dropped here. Written for kata; kumite has its own program.",
        movements=[
            (914, "Clean & Jerk", 3, "3-5", FAST, "85 to 95% of 1RM, 2 to 4 sets, 1 to 2 min rest, technique first"),
            (916, "Sumo Deadlift", 3, "6-10", HEAVY, "Barbell, 70 to 85% of 1RM, 2 to 4 sets, 1 to 2 min rest"),
            (62, "Bulgarian Split Squat", 3, "6-10", HEAVY, "Source: rear-foot-elevated split squat, 20 to 50 lb dumbbells, 70 to 85% of 1RM. Each leg, 2 to 4 sets"),
            (900, "Barbell Bench Press", 2, "6-10", HEAVY, "70 to 85% of 1RM, 2 to 3 sets, 30 s rest"),
            (994, "Cable Row (Single Arm)", 2, "10-15", HARD, "Source: single-arm cable or bent-over row, 60 to 75% of 1RM. Each side, 2 to 3 sets"),
            (114, "Medicine Ball Rotational Throw", 2, "12", FAST, "10 to 20 lb ball. Each side"),
            (115, "Cable Wood Chop (High-to-Low)", 2, "12", FAST, "Source: cable or band woodchop, 60 to 75% of 1RM. Each side"),
        ],
    ),
    dict(
        name="Karate Junior: Beginner Strength Circuit (Kumite)",
        phase="base", goal="strength", minutes=30, sports=KARATE,
        credit=ANGLOS_KUMITE, url=ANGLOS_KUMITE_URL,
        notes="Source: the beginner workout of Karate Canada's junior kumite program, read in the French "
              "edition. Same frequency as the kata program: 2 to 3 sessions a week out of season, 1 to 2 in "
              "season. This one sits in base (the phase is ours). Every exercise is 2 sets; goblet squat at "
              "65 to 75 percent of 1RM (20 to 40 lb), lunges 10 to 25 lb in each hand, rest 10 to 30 s. "
              "The page lists the chest exercise as a dumbbell bench press at bodyweight for max reps, "
              "which reads as a push-up (the English kata program prints push-ups in the same slot). The "
              "source's second upper-body exercise (a 10 to 20 lb dumbbell press, 15 a side) is not clear "
              "enough to match to a catalog row and is left out.",
        movements=[
            (60, "Goblet Squat", 2, "10-15", STEADY, "65 to 75% of 1RM (20 to 40 lb), 10 s rest"),
            (1034, "Jump Squat", 2, "10-15", FAST, "Bodyweight, absorb the landing, 30 s rest"),
            (943, "Walking Lunge", 2, "10-15", STEADY, "10 to 25 lb in each hand, 30 s rest"),
            (13, "Push-Up", 2, "max", HARD, "Source: horizontal press at bodyweight, max reps"),
            (1205, "Dead Bug", 2, "10-15", STEADY, "Each side, 15 s rest"),
            (971, "Bicycle Crunch", 2, "10-15", STEADY, "Each side, feet elevated, 30 s rest"),
        ],
    ),
    dict(
        name="Karate Junior: Intermediate Strength and Power (Kumite)",
        phase="maintenance", goal="power", minutes=45, sports=KARATE,
        credit=ANGLOS_KUMITE, url=ANGLOS_KUMITE_URL,
        notes="Source: the intermediate and advanced workout of Karate Canada's junior kumite program, read in "
              "the French edition. The program names no block and prints 1 to 2 sessions a week in season; "
              "the maintenance label is ours. Clean and jerk at 85 to 95 percent of 1RM (dumbbell for "
              "intermediate, barbell for advanced) with 1 to 2 minutes rest, then barbell squat, Bulgarian "
              "split squat, bench press, landmine press and a rotational medicine ball throw against a wall "
              "or a partner. Rest 30 s to 2 min.",
        movements=[
            (914, "Clean & Jerk", 3, "3-5", FAST, "85 to 95% of 1RM, 2 to 4 sets, 1 to 2 min rest"),
            (57, "Barbell Back Squat", 3, "6-10", HEAVY, "Source: barbell squat. 70 to 85% of 1RM, 2 to 4 sets, 1 to 2 min rest"),
            (62, "Bulgarian Split Squat", 3, "6-10", HEAVY, "Source: rear-foot-elevated split squat, 20 to 50 lb dumbbells, 60 to 75% of 1RM. Each leg, 2 to 4 sets"),
            (900, "Barbell Bench Press", 2, "6-10", HEAVY, "75 to 80% of 1RM, 2 to 3 sets, 30 s rest"),
            (19, "Landmine Press", 2, "10", FAST, "60 to 75% of 1RM. Each side, 2 to 3 sets"),
            (114, "Medicine Ball Rotational Throw", 2, "12", FAST, "10 to 20 lb ball. Each side"),
        ],
    ),
    # ------------------------------------------------------------------ taekwondo
    dict(
        name="Taekwondo: Gym Strength Weeks 1 to 4",
        phase="base", goal="strength", minutes=60, sports=TAEKWONDO,
        credit=KHAZAEI, url=KHAZAEI_URL,
        notes="Source: weeks 1 to 4 of the 8 week traditional resistance protocol in female elite taekwondo "
              "athletes, 3 sessions a week alongside 3 taekwondo sessions. The paper names no season; its "
              "first half builds up from light weights, so base is our label. Table 1 prints one set, rep, "
              "load and rest value per week and does not say it applies to each lift, but it is the only "
              "scheme given, so it is applied to all seven. Week 1: 3 x 14 at 50 percent of 1RM, 60 s. "
              "Week 2: 3 x 12 at 60 percent, 60 s. Week 3: 4 x 10 at 70 percent, 75 s. Week 4: 4 x 10 at 70 "
              "percent, 60 s. 1RM was re-tested at week 4. The source ends each session with a plank, 3 to 4 "
              "holds of 30 to 60 seconds. The source's smith squat is matched to the Smith machine squat.",
        movements=[
            (1091, "Squat (Smith Machine)", 3, "14-10", STEADY, "50 to 70% of 1RM by week, 3 sets in weeks 1 and 2, 4 in weeks 3 and 4"),
            (900, "Barbell Bench Press", 3, "14-10", STEADY, "Source: barbell chest press. Same weekly scheme"),
            (933, "Leg Extension", 3, "14-10", STEADY, "Same weekly scheme"),
            (1045, "Lat Pulldown (Cable)", 3, "14-10", STEADY, "Same weekly scheme"),
            (934, "Lying Leg Curl", 3, "14-10", STEADY, "Same weekly scheme"),
            (1075, "Shoulder Press (Machine)", 3, "14-10", STEADY, "Same weekly scheme"),
            (958, "Cable Lateral Raise", 3, "14-10", STEADY, "Same weekly scheme"),
            (974, "Front Plank", 3, "30-60 s", STEADY, "End of session, 3 to 4 holds"),
        ],
    ),
    dict(
        name="Taekwondo: Gym Strength Weeks 5 to 8",
        phase="build", goal="strength", minutes=60, sports=TAEKWONDO,
        credit=KHAZAEI, url=KHAZAEI_URL,
        notes="Source: weeks 5 to 8 of the same 8 week traditional resistance protocol, 3 sessions a week. "
              "The paper names no season; the heavier second half is the build label, which is ours. The "
              "one set, rep, load and rest scheme per week is applied to all seven lifts (the paper does "
              "not say so). Week 5: 3 x 12 at 60 percent of 1RM, 60 s. Week 6: 4 x 6 at 70 percent, 90 s. "
              "Weeks 7 and 8: 5 x 6 at 80 percent, 120 s. Same session-end plank as weeks 1 to 4. The "
              "paper's functional training arm lists its exercises but no sets or reps, so it is not "
              "distilled.",
        movements=[
            (1091, "Squat (Smith Machine)", 4, "12-6", HEAVY, "60 to 80% of 1RM by week, 3 to 5 sets"),
            (900, "Barbell Bench Press", 4, "12-6", HEAVY, "Source: barbell chest press. Same weekly scheme"),
            (933, "Leg Extension", 4, "12-6", HEAVY, "Same weekly scheme"),
            (1045, "Lat Pulldown (Cable)", 4, "12-6", HEAVY, "Same weekly scheme"),
            (934, "Lying Leg Curl", 4, "12-6", HEAVY, "Same weekly scheme"),
            (1075, "Shoulder Press (Machine)", 4, "12-6", HEAVY, "Same weekly scheme"),
            (958, "Cable Lateral Raise", 4, "12-6", HEAVY, "Same weekly scheme"),
            (974, "Front Plank", 3, "30-60 s", STEADY, "End of session, 3 to 4 holds"),
        ],
    ),
    # --------------------------------------------------------------- kung-fu (Wushu Sanda)
    dict(
        name="Wushu Sanda: Accumulation Strength Block",
        phase="base", goal="strength", minutes=45, sports=KUNG_FU,
        credit=ESPOSITO_2025, url=ESPOSITO_URL,
        notes="Source: weeks 1 to 4 (accumulation) of an 8 week Russian-style strength protocol in 12 male "
              "Wushu Sanda competitors aged 16 to 27 with at least 5 years of training, three sessions a "
              "week. All main sets at 80 percent of 1RM. Heavy sets are 6 x 3 in week 1, 6 x 4 in week 2, "
              "6 x 5 in week 3 and 6 x 6 in week 4. Each session also carries light paired sets of 6 x 2 at "
              "80 percent: bench press alongside the squat, squat alongside the bench press. Deadlift is "
              "trained alone. The paper does not say how lifts are split across the three days, so the "
              "order here is ours. The source names no season; phase is ours (an off-competition "
              "strength block). The study has no sport-specific work and no accessories, only the three lifts. "
              "Rest between heavy sets is given only for week 1 (2 min). The paper's text and table disagree "
              "on a few loads; the table values are used. The source is for Sanda and applies to the "
              "sanda side of kung fu only.",
        movements=[
            (57, "Barbell Back Squat", 6, "3-6", HARD, "80% of 1RM. Reps rise 3, 4, 5, 6 over weeks 1 to 4. "
                                                      "Light 6 x 2 at 80% on bench days"),
            (900, "Barbell Bench Press", 6, "3-6", HARD, "80% of 1RM. Reps rise 3, 4, 5, 6 over weeks 1 to 4. "
                                                       "Light 6 x 2 at 80% on squat days"),
            (59, "Conventional Deadlift", 6, "3-6", HARD, "80% of 1RM, trained alone. Reps rise 3, 4, 5, 6 "
                                                         "over weeks 1 to 4"),
        ],
    ),
    dict(
        name="Wushu Sanda: Intensification Strength Block",
        phase="build", goal="strength", minutes=45, sports=KUNG_FU,
        credit=ESPOSITO_2025, url=ESPOSITO_URL,
        notes="Source: weeks 5 to 8 (intensification) of the same 8 week protocol, three sessions a week. "
              "Heavy sets drop in volume as load climbs: 5 x 5 at 85 percent in week 5, 4 x 4 at 90 percent "
              "in week 6, 3 x 3 at 95 percent in week 7, 2 x 2 at 100 percent in week 8. Light paired "
              "6 x 2 sets at 80 percent continue (bench with squat, squat with bench). Deadlift is trained "
              "alone. Week 5 deadlift is 80 percent in the text and 85 percent in Table 2; the table is "
              "used. The paper adds a week 9 single at 105 percent as a test; it is left out here. Percents "
              "at 95 and above are a test-block choice of the source: cap weeks 7 and 8 at what you "
              "can move with good form. The source names no season; phase is ours. "
              "Applies to the sanda side of kung fu only.",
        movements=[
            (57, "Barbell Back Squat", 4, "5-2", HEAVY, "Weeks 5 to 8: 5x5 at 85%, 4x4 at 90%, 3x3 at 95%, "
                                                       "2x2 at 100% of 1RM. Light 6 x 2 at 80% on bench days"),
            (900, "Barbell Bench Press", 4, "5-2", HEAVY, "Same weekly scheme as the squat. Light 6 x 2 at "
                                                         "80% on squat days"),
            (59, "Conventional Deadlift", 4, "5-2", HEAVY, "Same weekly scheme, trained alone"),
        ],
    ),
    # --------------------------------------------------------------- capoeira
    dict(
        name="Capoeira: Core Stability Block",
        phase="base", goal="accessory", minutes=25, sports=CAPOEIRA,
        credit=ARAUJO_2015, url=ARAUJO_URL,
        notes="Source: a 6 week trunk program in 16 female capoeira athletes (at least 2 years of training), "
              "three sessions a week, done before regular capoeira training. Holds go 3 x 30 s in weeks 1 "
              "and 2, then 3 x 45 s. Rep exercises go 3 x 20, 3 x 30, 3 x 45 across the three two-week blocks. "
              "In weeks 5 and 6 the plank, side plank and bridge become one-arm, one-arm and single-leg "
              "versions, each 3 x 45 s per side, alongside the standard versions. The catalog has no one-arm "
              "plank row: Source: one-arm plank and one-arm side plank are covered by Plank and Side Plank "
              "with the arm lifted. The source gives no load, rest or session length; hold or rep "
              "targets only. Session length of 25 minutes and the phase are ours. The paper tested landing "
              "kinetics, not jump height, and a trunk program like this is an accessory block rather than "
              "a strength block.",
        movements=[
            (1058, "Plank", 3, "30-45 s", STEADY, "Hold. 30 s weeks 1-2, 45 s from week 3. Weeks 5-6 add a "
                                                  "one-arm plank, 3 x 45 s"),
            (132, "Side Plank", 3, "30-45 s", STEADY, "Hold each side. 30 s weeks 1-2, 45 s from week 3. "
                                                        "Weeks 5-6 add a one-arm side plank, 3 x 45 s"),
            (1020, "Glute Bridge", 3, "30-45 s", STEADY, "Source: supine bridge hold. 30 s weeks 1-2, 45 s "
                                                          "from week 3"),
            (103, "Single-Leg Glute Bridge", 3, "45 s", STEADY, "Source: single-leg supine bridge hold, "
                                                                "weeks 5-6 only, each side"),
            (968, "Crunch", 3, "20-45", STEADY, "Source: abdominal crunch. 20 reps weeks 1-2, 30 weeks 3-4, "
                                                 "45 weeks 5-6"),
            (970, "Russian Twist", 3, "20-45", STEADY, "20 reps weeks 1-2, 30 weeks 3-4, 45 weeks 5-6"),
            (1206, "Scissor Kick", 3, "20-45", STEADY, "Source: split leg scissors. 20 reps weeks 1-2, 30 "
                                                        "weeks 3-4, 45 weeks 5-6"),
        ],
    ),
    # ------------------------------------------------------------------ hema
    dict(
        name="HEMA: Base Building Block",
        phase="base", goal="strength", minutes=40, sports=HEMA,
        credit=SCOTT_2025, url=SCOTT_URL,
        notes="Source: block 1 of an 8 to 12 week cycle for a fencer with some lifting experience, 3 to 4 "
              "weeks, 2 to 3 sessions a week overall, focus on volume and technique. 2 to 3 sets of 8 to 12. "
              "The source gives no load; work at a weight that leaves 2 to 3 reps in reserve. The source "
              "names 'core work' without a movement; Dead Bug is our pick. Source: RDL without equipment, "
              "dumbbell version used. Base follows the source's own label.",
        movements=[
            (60, "Goblet Squat", 3, "8-12", STEADY, "2 to 3 sets"),
            (1171, "Dumbbell Romanian Deadlift", 3, "8-12", STEADY, "Source: RDL, equipment not named"),
            (61, "Kettlebell Swing", 3, "8-12", STEADY, "2 to 3 sets"),
            (922, "Pull-Up", 3, "8-12", STEADY, "Use a band or lat pulldown reps if 8 is out of reach"),
            (1205, "Dead Bug", 3, "8-12", STEADY, "Source: core work, movement not named"),
        ],
    ),
    dict(
        name="HEMA: Strength Block",
        phase="build", goal="strength", minutes=40, sports=HEMA,
        credit=SCOTT_2025, url=SCOTT_URL,
        notes="Source: block 2 of the same cycle, 4 to 6 weeks, 2 to 3 sessions a week overall, 3 sets of 6 "
              "to 10 with lower reps and higher weight than block 1. The source gives no load; work near "
              "a 6 to 8RM on the lifts. The source gives no carry distance; 20 to 40 m is our working "
              "rule. Source: split squats, Bulgarian split squat is the nearest catalog row. Phase is ours: "
              "the source calls it the strength phase and names no season.",
        movements=[
            (450, "Front Squat (Barbell)", 3, "6-10", HEAVY, "Lower reps, higher weight than block 1"),
            (451, "Trap Bar Deadlift", 3, "6-10", HEAVY, ""),
            (62, "Bulgarian Split Squat", 3, "6-10", HARD, "Source: split squats"),
            (64, "Farmer's Carry", 3, "20-40 m", HARD, "Source: weighted carries, no distance given"),
        ],
    ),
    dict(
        name="HEMA: Power Block",
        phase="maintenance", goal="power", minutes=35, sports=HEMA,
        credit=SCOTT_2025, url=SCOTT_URL,
        notes="Source: block 3 of the same cycle, 2 to 3 weeks, 2 to 3 sessions a week overall, 3 to 4 sets of "
              "6 to 10 at high intensity, focus on speed and explosiveness. The source gives no load or "
              "ground contacts per set; keep every rep fast and stop a set when speed drops. Source: "
              "plyometric lunges, Split Squat Jump is the nearest row. Source: agility ladder work, no "
              "pattern named; the count is passes. Phase is ours: a short closing block, so maintenance.",
        movements=[
            (130, "Split Squat Jump", 3, "6-10", FAST, "Source: plyometric lunges. 3 to 4 sets"),
            (50, "Medicine Ball Slam", 3, "6-10", FAST, "3 to 4 sets"),
            (61, "Kettlebell Swing", 3, "6-10", FAST, "3 to 4 sets"),
            (49, "Box Jump", 3, "6-10", FAST, "Step down, do not jump down. 3 to 4 sets"),
            (464, "Agility Ladder In-Out", 3, "6-10", FAST, "Source: agility ladder work. Passes"),
        ],
    ),
    # ------------------------------------------------------------------ kendo
    dict(
        name="Kendo: Takahashi Beginner Circuit",
        phase="base", goal="endurance", minutes=30, sports=KENDO,
        credit=TAKAHASHI_HOME, url=TAKAHASHI_HOME_URL,
        notes="Source: the beginner bodyweight circuit that the All Japan camp coach prints for home training: "
              "ten movements at 10 reps each, run as a round, about ten rounds without breaks. The article "
              "suggests a different focus by day and short daily strength work. The two arm movements (arms "
              "forward then back, arms out to the side then up to the ears) have no catalog row and stay "
              "in this note; the three knee raises (hands at shoulder height, alternating knee to opposite "
              "hand) are listed once. The source prints no seconds or rest. The rest of the article, the "
              "six or seven menus and the shinai work, is behind the Kendo Jidai paywall and is not "
              "distilled. Phase is ours: the source names no season.",
        movements=[
            (1088, "Squat (Bodyweight)", 10, "10", STEADY, "One pass per round"),
            (1018, "Flat Knee Raise", 10, "10", STEADY, "Source: knee raise to opposite hand, three per round"),
            (1051, "Lunge (Bodyweight)", 10, "10", STEADY, ""),
            (112, "Standing Calf Raise", 10, "10", STEADY, "Bodyweight"),
            (216, "Burpee", 10, "10", HARD, "Last movement of the round"),
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
