#!/usr/bin/env python3
"""Generate db/source/sport_movements.json — the season-aware generator's
curated movement pools (skiing SPEC §3.3, climbing SPEC §4.3).

EDITABLE SOURCE OF TRUTH for the pools: tune here (add/drop a movement, change a
demand tag or fatigue cost), then run to emit the JSON that build_db.py bakes
into coach.db.

Design: a thin SEASON-TAGGING LAYER over the existing catalog, not a duplicate.
Each row references a real `exercises.id`; name/equipment/scheme join from the
catalog at query time. The only new per-movement field is `fatigue_cost`
(1 low .. 5 high), the in-season volume-cap currency.

A movement may appear under multiple sports (e.g. Pallof Press for both ski core
and climb core) — dedup is per (sport, exercise_id); row `id` is globally unique.
"""
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BY_ID = {e["id"]: e for e in json.load(open(REPO / "db/source/exercises.json"))}

OFF, PRE, IN, EVT, MNT = "off_season", "pre_season", "in_season", "event_prep", "maintenance"
ALL = [OFF, PRE, IN, EVT, MNT]

# (exercise_id, [demands primary-first], [allowed_phases], variants|None,
#  fatigue_cost, min_experience|None, injury_caution|None)
SKI_POOL = [
    # maxStrength
    (57,  ["maxStrength"],                  [OFF, PRE, IN],      None, 4, None, None),
    (450, ["maxStrength"],                  [OFF, PRE],          None, 4, None, None),
    (451, ["maxStrength"],                  [OFF, PRE],          None, 4, None, "low back"),
    (58,  ["maxStrength"],                  [OFF, PRE, MNT],     None, 3, None, "low back"),
    (62,  ["maxStrength", "kneeStability"], [OFF, PRE, IN],      None, 3, None, None),
    (931, ["maxStrength", "eccentricLeg"],  [OFF, PRE],          None, 3, None, None),
    # eccentricLeg (signature)
    (129, ["eccentricLeg", "maxStrength"],  [OFF, PRE, IN, EVT], None, 4, None, None),
    (603, ["eccentricLeg"],                 [PRE, IN, EVT, MNT], None, 2, None, None),
    (623, ["eccentricLeg"],                 [PRE, IN, MNT],      None, 2, None, None),
    (420, ["eccentricLeg"],                 [OFF, PRE],          None, 3, "intermediate", "quad / knee — start shallow"),
    (102, ["eccentricLeg"],                 [OFF, PRE],          None, 4, "intermediate", "high DOMS — assist eccentric first"),
    (242, ["eccentricLeg", "prehab"],       [OFF, PRE, IN],      None, 2, None, None),
    # legEndurance
    (943, ["legEndurance"],                 [OFF, PRE],          None, 4, None, None),
    (600, ["legEndurance"],                 [PRE, IN, EVT],      None, 3, None, None),
    (238, ["legEndurance"],                 [OFF, PRE],          None, 3, None, None),
    (622, ["legEndurance", "aerobicUphill"],[OFF, PRE],          None, 3, None, None),
    (636, ["legEndurance"],                 [PRE, IN, MNT, EVT], None, 2, None, None),
    (130, ["legEndurance", "power"],        [OFF, PRE],          None, 4, None, "never in-season — high fatigue"),
    # power / reactive
    (49,  ["power"],                        [PRE, IN, EVT],      None, 2, None, "land soft — requires base"),
    (616, ["power"],                        [PRE, IN, EVT],      None, 2, None, None),
    (232, ["power"],                        [PRE],               None, 3, "advanced", "strength base required"),
    (329, ["power", "hipLateral"],          [PRE, IN, EVT],      None, 2, None, None),
    (52,  ["power"],                        [OFF, PRE],          None, 2, None, None),
    (602, ["power", "kneeStability"],       [PRE, EVT],          ["park"], 3, "intermediate", None),
    # kneeStability
    (108, ["kneeStability"],                ALL,                 None, 2, None, None),
    (226, ["kneeStability", "hipLateral"],  ALL,                 None, 2, None, "hip / knee mobility"),
    (361, ["kneeStability"],                [PRE, IN, EVT, MNT], None, 2, None, None),
    (477, ["kneeStability", "hipLateral"],  [PRE, IN, EVT],      None, 2, None, None),
    (601, ["kneeStability"],                [PRE, IN, EVT],      None, 2, None, None),
    (237, ["kneeStability", "core"],        ALL,                 None, 2, None, "groin — regress to short lever"),
    # hipLateral
    (227, ["hipLateral", "kneeStability"],  ALL,                 None, 2, None, None),
    # core / chassis
    (63,  ["core"],                         ALL,                 None, 1, None, None),
    (64,  ["core"],                         ALL,                 None, 2, None, None),
    (630, ["core"],                         ALL,                 None, 2, None, None),
    (132, ["core"],                         ALL,                 None, 1, None, None),
    (939, ["core"],                         [OFF, MNT],          None, 2, None, "low back"),
    # aerobicUphill (backcountry / skimo)
    (241, ["aerobicUphill"],                [OFF, PRE, IN],      ["backcountry", "skimo"], 3, None, None),
    (692, ["aerobicUphill"],                [OFF, PRE],          ["backcountry", "skimo"], 4, None, None),
    (1092,["aerobicUphill"],                [OFF, PRE, IN],      ["backcountry", "skimo"], 2, None, None),
    (325, ["aerobicUphill", "legEndurance"],[OFF, PRE],          ["backcountry", "skimo"], 4, None, None),
    # prehab
    (613, ["prehab"],                       [OFF, MNT],          None, 1, None, None),
    (704, ["prehab"],                       [OFF, MNT],          None, 1, None, None),
    (103, ["prehab"],                       [OFF, MNT],          None, 1, None, None),
    (308, ["prehab"],                       [OFF, MNT],          None, 1, None, None),
]

CLIMB_POOL = [
    # fingerStrength (signature, injury-gated). Note: NONE in transition (tendon rest).
    (2,   ["fingerStrength"],                [PRE, IN, OFF],      None, 3, "intermediate", "warm up; no acute finger injury"),
    (3,   ["fingerStrength"],                [OFF, PRE],          None, 3, "intermediate", None),
    (302, ["fingerStrength"],                [OFF, PRE, IN],      None, 2, None, None),   # pinch — novice-safe entry
    (303, ["fingerStrength"],                [OFF, PRE],          None, 2, None, None),   # fat-grip hang — entry
    # pullStrength
    (1,   ["pullStrength"],                  [OFF, PRE, IN],      None, 3, None, None),
    (4,   ["pullStrength"],                  [PRE, IN, EVT],      None, 2, None, None),   # lock-off
    (8,   ["pullStrength"],                  [OFF, MNT],          None, 2, None, "scapular health"),
    (10,  ["pullStrength"],                  [OFF, MNT],          None, 2, None, None),
    (11,  ["pullStrength"],                  [PRE],               None, 3, "advanced", None),  # one-arm progression
    # bodyTension
    (6,   ["bodyTension"],                   [OFF, PRE],          None, 3, "intermediate", "advanced regressions"),
    (1099,["bodyTension"],                   [OFF, PRE, IN, EVT, MNT], None, 2, None, None),  # toes-to-bar
    (7,   ["bodyTension"],                   [OFF, PRE, IN],      None, 2, None, "low back"),  # ab wheel
    (486, ["bodyTension", "core"],           [OFF, PRE, IN],      None, 2, None, None),        # hollow
    # contactStrength (advanced, pre-season-led)
    (47,  ["contactStrength"],               [PRE],               None, 4, "advanced", "finger/elbow risk; pre-season only"),
    (48,  ["contactStrength", "pullStrength"],[PRE, IN, EVT],     None, 3, "intermediate", None),  # explosive pull-up
    (50,  ["contactStrength"],               [PRE],               None, 2, None, None),        # med-ball slam
    # antagonist (scales UP in-season — the climbing inversion)
    (16,  ["antagonist"],                    ALL,                 None, 2, None, None),        # dips
    (491, ["antagonist"],                    [OFF, PRE, IN, EVT], None, 2, None, None),        # ring dip
    (15,  ["antagonist"],                    [OFF, IN, EVT, MNT], None, 2, None, None),        # overhead press
    (13,  ["antagonist"],                    ALL,                 None, 1, None, None),        # push-up
    (427, ["antagonist"],                    ALL,                 None, 1, None, None),        # Y-T-W-L complex
    # prehab (elbow / finger-tendon / shoulder — scales up in transition)
    (17,  ["prehab"],                        ALL,                 None, 1, None, "elbow (epicondylitis)"),  # reverse wrist curl
    (24,  ["prehab", "antagonist"],          ALL,                 None, 1, None, None),        # face pull
    # core
    (63,  ["core"],                          ALL,                 None, 1, None, None),        # pallof
    (974, ["core"],                          ALL,                 None, 1, None, None),        # front plank
]

POOLS = [("alpine-skiing", "ski", SKI_POOL), ("climbing", "climb", CLIMB_POOL)]

VALID_DEMANDS = {"maxStrength","power","core","prehab","aerobicUphill","eccentricLeg",
                 "legEndurance","kneeStability","hipLateral","fingerStrength","pullStrength",
                 "bodyTension","contactStrength","pullEndurance","antagonist"}
VALID_PHASES = set(ALL)

def slugify(n): return n.lower().replace("(","").replace(")","").replace("'","").replace("/"," ").replace("  "," ").strip().replace(" ","-")

rows, errors, seen = [], [], set()
gid = 0
for sport, prefix, pool in POOLS:
    for (eid, demands, phases, variants, fc, min_exp, caution) in pool:
        gid += 1
        if eid not in BY_ID: errors.append(f"{sport}: exercise_id {eid} not in catalog"); continue
        if (sport, eid) in seen: errors.append(f"{sport}: duplicate exercise_id {eid}"); continue
        seen.add((sport, eid))
        if any(d not in VALID_DEMANDS for d in demands): errors.append(f"{sport}/{eid}: bad demand {demands}")
        if any(p not in VALID_PHASES for p in phases): errors.append(f"{sport}/{eid}: bad phase {phases}")
        name = BY_ID[eid]["name"]
        rows.append({
            "id": gid, "slug": f"{prefix}-{slugify(name)}", "name": name, "sport": sport,
            "exercise_id": eid, "demands": demands, "allowed_phases": phases,
            "allowed_variants": variants, "fatigue_cost": fc,
            "min_experience": min_exp, "injury_caution": caution,
        })

if errors:
    raise SystemExit("SEED ERRORS:\n  " + "\n  ".join(errors))

(REPO / "db/source/sport_movements.json").write_text(json.dumps(rows, indent=2) + "\n")
from collections import Counter
print(f"wrote {len(rows)} movements ({len(SKI_POOL)} ski + {len(CLIMB_POOL)} climb)")
for sport, _, _ in POOLS:
    cov = Counter(d for r in rows if r["sport"] == sport for d in r["demands"])
    print(f"  {sport}: {dict(sorted(cov.items(), key=lambda x: -x[1]))}")
