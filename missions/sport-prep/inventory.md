# Sport prep inventory: MTI Mountain archive vs coach.db

Compiled 2026-11-15. Read-only inventory. No routines, source JSON or db files were changed.

## How to read this

Sources: the 81 plans under "## Mountain" in `~/repos/mtntactical-plans/INDEX.md`, and `~/repos/uphillathlete-archive`. The Uphill Athlete archive holds 30 plan description pages (1 to 5 KB each, methodology and prerequisites only, no week-by-week sessions) and 2 program pages. Its executable workouts live in TrainingPeaks and only a 12-week General Fitness Base plan, Chamonix Mountain Fit and Yoga for Recovery are captured. Uphill Athlete therefore supplies design ideas but no distillable sessions. Every row below that recommends a source points at an MTI plan.

Phase mapping (`AuthoredRoutine.phaseLabels`): off-season reads `off_season` and `base`; pre-season reads `build`; in-season reads `maintenance`; event prep reads `build` and `maintenance`. The coach.db phase values present are off_season (18), base (14), build (29), maintenance (67) and recovery (2), 130 routines in all. The grid uses these three buckets.

Strength codes in the plan table: G means gym strength sessions with barbell, dumbbell or kettlebell work. L means limited-equipment strength (bodyweight, sandbag, pull-up bar, a light dumbbell pair). E means endurance or read-and-log sessions only. A value marked "est" was judged from keyword counts and the overview because the plan's equipment line or overview was blank.

Already distilled, so skipped as sources: snowboard (ids 295 to 297, 301), MTB pre-season (299, 300), in-season outdoor (310 to 317), Easy Strength (298). Ids 302 to 304 (mountaineering descent, hiking trail strength, thru-hike durability) came from earlier MTI and Uphill Athlete material.

## 1. Sport by phase grid

Phase vocabulary is the coach.db one: pre-season = `build`, in-season = `maintenance`, off-season = `off_season` or `base`.

Counts are servable routines only, counted by script from `routines.json` and `routine_sports.json`: directly tagged to that slug, `goal` outside prehab, mobility, warm_up, pt_rehab and recovery, and `duration_minutes` of 25 or more. This replaces the earlier raw tag counts, which included warm-ups and prehab. I did not verify whether the selector rolls parent or child sport tags up, so a child slug with zero direct tags may still receive parent routines. `xc-skiing` is absent from the SportProfile table in `SportProfile.swift`; I assumed it is authored-served and did not test it.

Sports marked "db only" exist in `sport_categories.json` but are absent from the 36-entry onboarding catalog (`Sport.catalog`). Rule used for ski: `SportProfile` routes `alpine-skiing`, `ski-mountaineering` and `snow-sports` to the season engine, so those rows are engine-served and skipped.

| Sport slug | Off-season (off_season, base) | Pre-season (build) | In-season (maintenance) | Best MTI candidate for empty or thin cells |
|---|---|---|---|---|
| climbing | 4 | 4 | 2 | none needed |
| trail-running | 2 | 2 | 1 | 50K Ultra Training Plan (second pre-season voice, barbell) |
| running | 2 | 2 | 1 | pre-season done 2026-11-15 (ids 320-321, 25K Ultra weeks 3 and 6) |
| cycling | 2 | 2 | 1 | pre-season done 2026-11-15 (ids 318-319, 30-Mile MTB weeks 1/5 and 4); in-season Off/In-Season Training for Endurance Athletes |
| mountain-biking | 3 | 2 | 1 | Enduro MTB Training Plan (variety only) |
| snowboarding | 3 | 2 | 1 | none needed |
| kayaking | 1 | 0 | 0 | Kayak/Paddling Pre-Season (pre-season, in-season) |
| paddle-sports | 1 | 1 | 0 | Kayak/Paddling Pre-Season |
| sup | 1 | 0 | 0 | Kayak/Paddling Pre-Season (shoulder and trunk content transfers) |
| swimming | 1 | 0 | 0 | no MTI swim plan; In-Season and Off-Season Training for Endurance Athletes are the nearest generic |
| mountaineering | 3 | 1 | 2 | Everest Training Plan, Build cycle (pre-season, barbell) |
| hiking-trekking | 3 | 1 | 2 | Backpack Pre-Season V2 (pre-season) |
| thru-hiking | 3 | 1 | 2 | Thru Hike Training Plan (partly used) |
| backcountry-hunting | 1 | 1 | 0 | Backcountry Big Game Hunting Preseason V5 (pre-season); Hunting Build 1; in-season cell has no MTI source, hunting plans are all pre-trip |
| xc-skiing | 0 | 0 | 0 | 20K Nordic Ski Race Training Plan (one strength template across five plans) |
| ice-climbing | 0 | 0 | 0 | Ice/Mixed Climbing Pre-Season |
| alpine-climbing | 0 | 0 | 0 | Alpine Rock Climb |
| adventure-racing | 0 | 0 | 0 | 6-Hour Adventure Race Training Plan (mostly multisport endurance, weak) |
| day-hiking | 0 | 0 | 0 | Half Dome Day Hike Training Plan (limited equipment) |
| ski-mountaineering | engine-served, skip | engine-served, skip | engine-served, skip | the season engine handles these; routines tagged only to them are never served |
| alpine-skiing | engine-served, skip | engine-served, skip | engine-served, skip | the season engine handles these; routines tagged only to them are never served |
| snow-sports | engine-served, skip | engine-served, skip | engine-served, skip | the season engine handles these; routines tagged only to them are never served |
| backcountry-touring | engine-served, skip | engine-served, skip | engine-served, skip | the season engine handles these; routines tagged only to them are never served |
| snowmobiling | needs app change | needs app change | needs app change | Mountain Sledding Training Plan; no sport_categories row or catalog entry yet |

## 2. Ranked gaps to distill first

Ranking rules: engine-served sports are skipped; plans with gym strength sessions (G) outrank plans that are mostly endurance or read-and-log (E); existing-sport gaps rank before NEW sports, which are labelled "needs app change" and are out of scope until the owner approves Swift catalog work.

1. **cycling pre-season** (DONE 2026-11-15, ids 318-319; SportProfile row added). Source: 30-Mile Mountain Bike Race Training Plan (G, 7 weeks, barbell and kettlebell strength). Zero-work alternative: add the cycling tag to routines 299 and 300, which are tagged only to mountain-biking.
2. **running pre-season** (DONE 2026-11-15, ids 320-321; SportProfile row added). Source: 25K Ultra Training Plan (L, 7 weeks, one dumbbell pair). Zero-work alternative: add the running tag to routines 316 and 317.
3. **kayaking and sup pre-season and in-season** (servable routines only in off-season, 1 each; paddle-sports has 1 `build`). Source: Kayak/Paddling Pre-Season (G, 6 weeks, dumbbell press, pull and trunk work). It is the only MTI paddling plan and it is gym-heavy.
4. **running and cycling in-season** (1 servable `maintenance` each). Source: In-Season Strength Training For Endurance Athletes (G, 24 sessions, serves both). Off-Season Training for Endurance Athletes (G) is the matching off-season voice for swimming, which has no `build` or `maintenance` routine and no MTI swim plan.
5. **mountaineering pre-season** (1 `build` routine, a shared pack-prep one). Source: Everest Training Plan, Build cycle (G, 7 weeks, barbell). Denali and Rainier are E/L with pull-ups only.
6. **backcountry-hunting in-season** (0) and a second pre-season voice (1). Source: Backcountry Big Game Hunting Preseason V5 (G, dumbbells and bench). Every hunting plan is written for the weeks before a trip, so none feeds `maintenance`. The slug is db only.
7. **xc-skiing, ice-climbing, alpine-climbing** (db only, all 0). Sources: 20K Nordic Ski Race Training Plan (L; one distill covers the five Nordic plans), Ice/Mixed Climbing Pre-Season (L, grip endurance), Alpine Rock Climb (L, rock gym).
8. **hiking-trekking pre-season depth** (1). Source: Backpack Pre-Season V2 (L).
9. **adventure-racing** (db only, 0). Source: 6-Hour Adventure Race Training Plan (L; the 12-hour and 24-hour plans are mostly multisport endurance, so they rank lowest here).
10. **NEW, needs app change:** snowmobiling (Mountain Sledding Training Plan, G, 6 weeks) and mountain-guiding (Mountain Guide Pre-Season, G). Each needs a `sport_categories` row and a catalog entry first.

Skipped as engine-served: ski-mountaineering (Backcountry Ski Pre-Season V6, In Season Ski Maintenance V2, Randonee Race, Colorado Grand Traverse Ski Mountaineering), alpine-skiing (Dryland Ski V6, 30 Minutes/Day Dryland Ski, Heliski, Monster Factory) and snow-sports. The earlier suggestion to tag splitboard routines 295 to 297 to ski-mountaineering would not be served either and is withdrawn.

Not ranked: climbing and snowboarding (full grids), and the trail and ultra plans beyond those already used (Speedgoat, Rut, Teton Crest and Mountain Marathon are volume progressions with minimal gym work).

## 3. The 81 Mountain plans

Length is plan weeks, then days per week from the overview ("not stated" where the overview omits it). Sessions were not read in full; each plan's overview and equipment line were read and its keyword mix was checked.

| # | Plan | File | Sub-category | Target sport | Phase | Length | Equipment | Strength | Status |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Mountain Athlete In-Season Flex | mountain-athlete-in-season-flex.md | Base Programming | general-fitness / mountain multi-sport | in-season | 8 wk, 2-3 (24 sessions) d/wk | commercial gym, barbell, rack, DB, bench, box | G | distilled (4 routines, ids 310-315) |
| 2 | Mountain Base Artemis | mountain-base-artemis.md | Base Programming | general-fitness | off-season | 7 wk, 5 d/wk | gym with sandbags, box, 25 lb pack, boulder wall optional | L | open, not sport prep |
| 3 | Mountain Base Atalanta | mountain-base-atalanta.md | Base Programming | general-fitness | off-season | 7 wk, 5 d/wk | DB, KB, box, pack | G | open, not sport prep |
| 4 | Mountain Base Danae V3 | mountain-base-danae-v3.md | Base Programming | general-fitness | off-season | 7 wk, 5 d/wk | full functional gym, sandbag, pack | G | open, not sport prep |
| 5 | Mountain Base Helen V3 | mountain-base-helen-v3.md | Base Programming | general-fitness | off-season | 7 wk, 5 d/wk | full gym, barbell, rack, sandbag, pack | G | open, not sport prep |
| 6 | Backcountry Big Game Hunting Preseason V5 | backcountry-big-game-hunting-preseason-v5.md | Hunting | backcountry-hunting (db only) | pre-season (event prep) | 8 wk, 6 d/wk | DB, bench, pack, sandbag (est, equipment line blank) | G | open |
| 7 | Backcountry Hunting Base | backcountry-hunting-base.md | Hunting | backcountry-hunting (db only) | off-season | 7 wk, 5 d/wk | sandbag, step, pack 20-55 lb, pull-up bar | L | open |
| 8 | Backcountry Hunting Build 1 | backcountry-hunting-build-1.md | Hunting | backcountry-hunting (db only) | pre-season | 7 wk, 5 d/wk | full gym, barbell, rack, bench, DB/KB, sandbag, pack | G | open |
| 9 | Backcountry Hunting Build 2 | backcountry-hunting-build-2.md | Hunting | backcountry-hunting (db only) | pre-season | 7 wk, 5 d/wk | full gym, barbell, DB/KB, sandbag, pack | G | open |
| 10 | Backcountry Hunting Fitness Assessment Training Plan | backcountry-hunting-fitness-assessment-training-plan.md | Hunting | backcountry-hunting (db only) | pre-season | 5 wk, not stated (25 sessions) d/wk | gym, barbell, bench, pull-up bar, KB/DB, 75 lb pack, sandbag | G | open |
| 11 | Whitetail Deer Hunting Preseason Training Plan | whitetail-deer-hunting-preseason-training-plan.md | Hunting | fishing-hunting (db only, parent of backcountry-hunting) | pre-season (event prep) | 5 wk, 6 d/wk | sandbag, pull-up bar, box, DB, sled or tire | L | open |
| 12 | Mountain Base Alpha | mountain-base-alpha.md | Daily Training | general-fitness | off-season | 5 wk, not stated d/wk | rock gym with a general fitness area | L | open, not sport prep |
| 13 | Backpack Pre-Season V2 | backpack-pre-season-v2.md | Hiking/Back Packing | hiking-trekking / backpacking | pre-season (event prep) | 7 wk, 6 d/wk | 25 lb DB pair, sandbag, box, pack | L | open (hiking prep partly covered by ids 302-304) |
| 14 | Grand Canyon Rim to Rim to Rim | grand-canyon-rim-to-rim-to-rim.md | Hiking/Back Packing | hiking-trekking (day-hiking) | pre-season (event prep) | 8 wk, 6 d/wk | sandbag, box, pack | L | open |
| 15 | Grand Canyon Rim to Rim Training Plan | grand-canyon-rim-to-rim-training-plan.md | Hiking/Back Packing | hiking-trekking (day-hiking) | pre-season (event prep) | 8 wk, 6 d/wk | sandbag, box, pack | L | open |
| 16 | Jackson Hole Everest 29029 Training Plan | jackson-hole-everest-29029-training-plan.md | Hiking/Back Packing | hiking-trekking | pre-season (event prep) | 9 wk, 6 d/wk | 12 in box, barbell, rack, DB weekly, trekking poles | G | open |
| 17 | Kilimanjaro Training Plan | kilimanjaro-training-plan.md | Hiking/Back Packing | hiking-trekking (international-trekking) | pre-season (event prep) | 5 wk, 6 d/wk | 25 lb DB pair, sandbag, box, pack | L | open |
| 18 | Mountaineering & Hiking Prep Training Plan | mountaineering-hiking-prep-training-plan.md | Hiking/Back Packing | mountaineering / hiking-trekking | off-season (base) | 4 wk, 5 d/wk | box, 25 lb pack, sandbag | L | distilled (ids 311, 314) |
| 19 | Peak Bagger V5 | peak-bagger-v5.md | Hiking/Back Packing | mountaineering (non-tech-mountaineering) | pre-season (event prep) | 7 wk, 6 d/wk | 25 lb DB pair, sandbag, box, pack | L | open |
| 20 | Thru Hike Training Plan | thru-hike-training-plan.md | Hiking/Back Packing | thru-hiking | pre-season | 11 wk, 6-7 d/wk | sandbag, 25 lb pack, box, foam roller | L | partly distilled (id 304, ids 312-313 from other sources) |
| 21 | Kayak/Paddling Pre-Season | kayak-paddling-pre-season.md | Kayak/Paddling | kayaking | pre-season | 6 wk, 4 d/wk | DB, bench, barbell optional, boat for intervals | G | open |
| 22 | Alpine Rock Climb | alpine-rock-climb.md | Climbing Plans | alpine-climbing (db only) | pre-season | 6 wk, 5 d/wk | rock gym, DB, 25 lb plate, step | L | open |
| 23 | Alpinist Fitness Assessment Training Plan | alpinist-fitness-assessment-training-plan.md | Climbing Plans | alpine-climbing (db only) | pre-season | 5 wk, 6 (31 sessions) d/wk | pull-up bar, dip station, box, 40 lb pack, 25 m course | L | open |
| 24 | AMGA Alpine Guide Course Training Plan | amga-alpine-guide-course-training-plan.md | Climbing Plans | NEW: mountain-guiding | pre-season (event prep) | 6 wk, 5-6 d/wk | rock gym, DB, sandbag, 35 lb pack, ice tools | L | open |
| 25 | Half Dome Day Hike Training Plan | half-dome-day-hike-training-plan.md | Climbing Plans | hiking-trekking (day-hiking) | pre-season (event prep) | 7 wk, 6 d/wk | box, 20 lb pack | L | open |
| 26 | Teton Grand Traverse Training Plan | teton-grand-traverse-training-plan.md | Climbing Plans | alpine-climbing / scrambling (db only) | pre-season (event prep) | 8 wk, 6 d/wk | hill or step, 25 lb pack, pull-up bar | L (bodyweight) | open |
| 27 | Wasach Ultimate Ridge Link Up (WURL) Training Plan | wasach-ultimate-ridge-link-up-wurl-training-plan.md | Climbing Plans | alpine-climbing / scrambling (db only) | pre-season (event prep) | 10 wk, 6 d/wk | box, 20 lb pack, boulder gym, GPS | L | open |
| 28 | Big Mountain V3 | big-mountain-v3.md | Climbing Plans | mountaineering (expedition-mountaineering) | pre-season (event prep) | 10 wk, 6 d/wk | box, 35 lb pack, 25 lb DB pair, GPS | L | open |
| 29 | Denali Training Plan | denali-training-plan.md | Climbing Plans | mountaineering (expedition-mountaineering) | pre-season (event prep) | 9 wk, 6 d/wk | sandbag, box, pack 35-60 lb, tire drag rig, pull-up bar | E/L (pull-ups only) | open |
| 30 | Everest Training Plan | everest-training-plan.md | Climbing Plans | mountaineering (expedition-mountaineering) | off-season (Base 7 wk), pre-season (Build 7 wk), event prep (Peak 9 wk) | 7+7+9 wk, 5 d/wk | full weight room, barbell, box, pack, sandbag | G | open |
| 31 | Rainier Training Plan | rainier-training-plan.md | Climbing Plans | mountaineering (non-tech-mountaineering) | pre-season (event prep) | 7 wk, 6 d/wk | sandbag, box, pack 25-35 lb, pull-up bar | E/L (pull-ups only) | open |
| 32 | AMGA Rock Guide Course Training Plan | amga-rock-guide-course-training-plan.md | Climbing Plans | NEW: mountain-guiding | pre-season (event prep) | 6 wk, 5 d/wk | rock gym with campus board | L | open |
| 33 | Big Wall Climbing | big-wall-climbing.md | Climbing Plans | climbing (aid-climbing, db only) | pre-season (event prep) | 8 wk, 5 d/wk | rock gym, 20 in box, DB, rope | L | open |
| 34 | Rock Climb Pre-Season V3 | rock-climb-pre-season-v3.md | Climbing Plans | climbing / sport-climbing | pre-season | 6 wk, 6 d/wk | campus board, boulder gym or Moon Board, sandbag, DB, pull-up bar | L | open (climbing build=4 already, see grid) |
| 35 | Expedition Ice/Mixed | expedition-ice-mixed.md | Climbing Plans | ice-climbing (db only) | pre-season | 8 wk, 5 d/wk | barbell, KB, DB, ice tools (est) | G | open |
| 36 | Ice/Mixed Climbing Pre-Season | ice-mixed-climbing-pre-season.md | Climbing Plans | ice-climbing (db only) | pre-season | 6 wk, 4 d/wk | sandbag, DB, pull-up bar, ice tools or hangs | L | open |
| 37 | 100-Mile Mountain Bike Race Training Plan | 100-mile-mountain-bike-race-training-plan.md | Mountain Bike | mountain-biking | pre-season (event prep) | 10 wk, 6 d/wk | weight room, barbell, rack, bench, DB/KB, bike, HR monitor | G | open |
| 38 | 30-Mile Mountain Bike Race Training Plan | 30-mile-mountain-bike-race-training-plan.md | Mountain Bike | mountain-biking | pre-season (event prep) | 7 wk, 6 d/wk | weight room, barbell, DB/KB, bike, HR monitor | G | open |
| 39 | Colorado Grand Traverse MTB Training Plan | colorado-grand-traverse-mtb-training-plan.md | Mountain Bike | mountain-biking | pre-season (event prep) | 6 wk, 6 d/wk | weight room, barbell, DB/KB, bike, HR monitor | G | open |
| 40 | Colorado Grand Traverse Ultra Run + MTB Race Training Plan | colorado-grand-traverse-ultra-run-plus-mtb-race-training-plan.md | Mountain Bike | trail-running + mountain-biking (multisport) | pre-season (event prep) | 8 wk, 7 (56 sessions over 8 wk) d/wk | trail shoes, MTB, box (est, overview blank) | E (read and log, est) | open |
| 41 | Downhill Mountain Bike Training Plan | downhill-mountain-bike-training-plan.md | Mountain Bike | mountain-biking (downhill, no sub-slug) | pre-season | 5 wk, 6 d/wk | spin or MTB, gym, barbell, DB, KB, sandbag, 20 in box | G | open |
| 42 | Enduro Mountain Bike Training Plan | enduro-mountain-bike-training-plan.md | Mountain Bike | mountain-biking (enduro, no sub-slug) | pre-season | 6 wk, 6 d/wk | power-meter bike or trainer, gym, barbell, DB, KB, sandbag, box | G | open |
| 43 | Mountain Bike Pre-Season Training Plan V2 | mountain-bike-pre-season-training-plan-v2.md | Mountain Bike | mountain-biking | pre-season | 7 wk, 6 d/wk | spin bike or trainer, DB, gym | G | distilled (ids 299-300) |
| 44 | Wilderness Professional Training Packet | wilderness-professional-training-packet.md | Mountain Fitness Packet | NEW: wilderness-professional (game warden, ranger, SAR) | off-season / year-round | 4 plans wk, 5 (4 plans, 5-7 wk each) d/wk | packet: bodyweight, then barbell gym, then DB/KB | G (3 of 4 plans) | open, overview only (no sessions in file) |
| 45 | 12-Hour Adventure Race Training Plan | 12-hour-adventure-race-training-plan.md | Mountain Running/ultra plans | adventure-racing (db only) | pre-season (event prep) | 7 wk, 7 (49 sessions over 7 wk) d/wk | MTB, paddle craft, DB, KB, gym (est, overview blank) | L/G (est) | open |
| 46 | 24-Hour Adventure Race Training Plan | 24-hour-adventure-race-training-plan.md | Mountain Running/ultra plans | adventure-racing (db only) | pre-season (event prep) | 11 wk, 7 (78 sessions over 11 wk) d/wk | MTB, paddle craft, DB, KB, gym (est, overview blank) | L/G (est) | open |
| 47 | 50 Mile Ultra Running V2 | 50-mile-ultra-running-v2.md | Mountain Running/ultra plans | trail-running (trail-ultra-100k) | pre-season (event prep) | 10 wk, 6 d/wk | weight room, barbell, DB, sandbag | G | open |
| 48 | 6-Hour Adventure Race Training Plan | 6-hour-adventure-race-training-plan.md | Mountain Running/ultra plans | adventure-racing (db only) | pre-season (event prep) | 5 wk, 6 d/wk | DB pair, sandbag, MTB, paddle craft | L | open |
| 49 | Colorado Grand Traverse Ultra Run Training Plan | colorado-grand-traverse-ultra-run-training-plan.md | Mountain Running/ultra plans | trail-running | pre-season (event prep) | 8 wk, 6 d/wk | box, foam roller | L | open |
| 50 | Alpine Running Training Plan | alpine-running-training-plan.md | Mountain Running/ultra plans | trail-running (mountain-running) | pre-season (event prep) | 8 wk, 6 d/wk | gym, steep hill or step, 9 water jugs as pack load | G | open |
| 51 | Mountain Marathon Training Plan | mountain-marathon-training-plan.md | Mountain Running/ultra plans | trail-running (mountain-running) | pre-season (event prep) | 9 wk, 6 d/wk | box, foam roller | L | open |
| 52 | Teton Crest Run Training Plan | teton-crest-run-training-plan.md | Mountain Running/ultra plans | trail-running (mountain-running) | pre-season (event prep) | 10 wk, 6 d/wk | box, GPS | L | open |
| 53 | In-Season Strength Training For Endurance Athletes | in-season-strength-training-for-endurance-athletes.md | Mountain Running/ultra plans | running / cycling / trail-running / swimming (endurance generic) | in-season | 12 wk, 2 (24 sessions) d/wk | full gym, barbell, rack, DB/KB, sandbag | G | open (closest existing: ids 34, 24) |
| 54 | Off-Season Training for Endurance Athletes | off-season-training-for-endurance-athletes.md | Mountain Running/ultra plans | running / cycling / trail-running / swimming (endurance generic) | off-season | 6 wk, 6 d/wk | barbell, DB, KB, sandbag | G | open |
| 55 | 100 Mile Ultra Training Plan | 100-mile-ultra-training-plan.md | Mountain Running/ultra plans | trail-running (trail-ultra-100mi) | pre-season (event prep) | 17 wk, 7 d/wk | weight room, barbell, DB, sandbag | G | open |
| 56 | 100-Mile Ultra Stage Race Training Plan | 100-mile-ultra-stage-race-training-plan.md | Mountain Running/ultra plans | trail-running (trail-ultra-100mi) | pre-season (event prep) | 15 wk, 6 d/wk | weight room, barbell, DB, sandbag | G | open |
| 57 | 25K Ultra Training Plan | 25k-ultra-training-plan.md | Mountain Running/ultra plans | trail-running | pre-season | 7 wk, 6 d/wk | 25 lb DB pair, foam roller | L | open |
| 58 | 50K Ultra Training Plan | 50k-ultra-training-plan.md | Mountain Running/ultra plans | trail-running (trail-ultra-100k) | pre-season (event prep) | 12 wk, 6 d/wk | weight room, barbell, DB/KB, sandbag | G | open |
| 59 | Cape Wrath Stage Stop Ultra Training Plan | cape-wrath-stage-stop-ultra-training-plan.md | Mountain Running/ultra plans | trail-running (trail-ultra-100mi) | pre-season (event prep) | 16 wk, 6 d/wk | weight room, barbell, DB, sandbag | G | open |
| 60 | Speedgoat 30K | speedgoat-30k.md | Mountain Running/ultra plans | trail-running | pre-season (event prep) | 8 wk, 6 d/wk | box, GPS, foam roller | L | open |
| 61 | Speedgoat 50K Ultra | speedgoat-50k-ultra.md | Mountain Running/ultra plans | trail-running (trail-ultra-100k) | pre-season (event prep) | 10 wk, 6 d/wk | box, GPS, foam roller | L | open |
| 62 | The Rut 50k Training Plan | the-rut-50k-training-plan.md | Mountain Running/ultra plans | trail-running (trail-ultra-100k) | pre-season (event prep) | 10 wk, 6 d/wk | box, GPS, foam roller | L | open |
| 63 | Ultra Running Pre-Season Training Plan | ultra-running-pre-season-training-plan.md | Mountain Running/ultra plans | trail-running | pre-season | 9 wk, 6 d/wk | weight room, barbell, DB/KB, sandbag | G | distilled (ids 316-317) |
| 64 | Mountain/Wilderness SAR Fitness Assessment Training Plan | mountain-wilderness-sar-fitness-assessment-training-plan.md | Mountain/Wilderness Professional | NEW: wilderness-professional (SAR) | pre-season | 5 wk, 5 d/wk | sandbag, box, pull-up bar, 40 lb pack | L | open |
| 65 | AMGA Ski Guide Course Training Plan | amga-ski-guide-course-training-plan.md | Mountain/Wilderness Professional | NEW: mountain-guiding (ski) | pre-season (event prep) | 6 wk, 6 d/wk | gym or DB, bench, bike or skin hill | L | open |
| 66 | Mountain Guide Pre-Season | mountain-guide-pre-season.md | Mountain/Wilderness Professional | NEW: mountain-guiding (alpine) | pre-season | 6 wk, 5 d/wk | commercial gym, barbell, DB/KB, boulder gym | G | open |
| 67 | 30 Minutes/Day Dryland Ski Training Plan - V2 | 30-minutes-day-dryland-ski-training-plan-v2.md | Skiing & Backcountry Skiing | alpine-skiing (alpine-recreational) | pre-season | 4 wk, 5 (20 sessions, est) d/wk | DB, limited equipment | L | open |
| 68 | Dryland Ski Training Plan V6 | dryland-ski-training-plan-v6.md | Skiing & Backcountry Skiing | alpine-skiing (alpine-recreational) | pre-season | 7 wk, 5 d/wk | 12-15 in box, sandbag, DB pair, pull-up bar | L | open |
| 69 | In Season Ski Maintenance - V2 | in-season-ski-maintenance-v2.md | Skiing & Backcountry Skiing | alpine-skiing / ski-mountaineering | in-season | 12 wk, 2-3 (36 sessions) d/wk | gym, barbell, DB/KB, pull-up bar (est, equipment line blank) | G | partly distilled (id 297 splitboard source) |
| 70 | Monster Factory | monster-factory.md | Skiing & Backcountry Skiing | alpine-skiing (freestyle-skiing) | off-season | 4 wk, 4 d/wk | commercial gym, free weights, barbell | G | open |
| 71 | Backcountry Ski Pre-Season Training Plan V6 | backcountry-ski-pre-season-training-plan-v6.md | Skiing & Backcountry Skiing | ski-mountaineering (backcountry-touring) | pre-season | 7 wk, 6 d/wk | 25 lb DB pair, sandbag, 25 lb pack, timer | L | partly distilled (ids 295-296 splitboard source) |
| 72 | Colorado Grand Traverse Ski Mountaineering Training Plan | colorado-grand-traverse-ski-mountaineering-training-plan.md | Skiing & Backcountry Skiing | ski-mountaineering | pre-season (event prep) | 7 wk, 6 d/wk | DB or KB, sandbag, skins and skis | E (chassis circuits under 30 min) | open |
| 73 | Heliski Trip Training Plan | heliski-trip-training-plan.md | Skiing & Backcountry Skiing | alpine-skiing | pre-season (event prep) | 5 wk, 6 d/wk | sandbag, 25 lb pack, timer | L | open |
| 74 | Randonee Race | randonee-race.md | Skiing & Backcountry Skiing | ski-mountaineering | pre-season (event prep) | 16 wk, not stated (16 wk, hours per week 6.5 to 19) d/wk | skis, boots, skins, HR monitor, trekking poles | E (read and log) | open |
| 75 | 10k Nordic Ski Race Training Plan | 10k-nordic-ski-race-training-plan.md | Skiing & Backcountry Skiing | xc-skiing (db only) | pre-season (event prep) | 6 wk, 6 d/wk | DB pair, pull-up bar, benches, roller skis or snow | L | open |
| 76 | 15k Nordic Ski Race Training Plan | 15k-nordic-ski-race-training-plan.md | Skiing & Backcountry Skiing | xc-skiing (db only) | pre-season (event prep) | 7 wk, 6 d/wk | DB pair, pull-up bar, benches | L | open |
| 77 | 20k Nordic Ski Race Training Plan | 20k-nordic-ski-race-training-plan.md | Skiing & Backcountry Skiing | xc-skiing (db only) | pre-season (event prep) | 7 wk, 6 d/wk | DB pair, pull-up bar, benches | L | open |
| 78 | 30k Nordic Ski Race Training Plan | 30k-nordic-ski-race-training-plan.md | Skiing & Backcountry Skiing | xc-skiing (db only) | pre-season (event prep) | 8 wk, 6 d/wk | DB pair, pull-up bar, benches | L | open |
| 79 | 50k Nordic Ski Race Training Plan | 50k-nordic-ski-race-training-plan.md | Skiing & Backcountry Skiing | xc-skiing (db only) | pre-season (event prep) | 10 wk, 6 d/wk | DB pair, pull-up bar, benches | L | open |
| 80 | Dryland Snowboard Training Plan - V2 | dryland-snowboard-training-plan-v2.md | Snowboarding and BC Snowboarding | snowboarding / splitboarding | pre-season | 7 wk, 5 d/wk | 25 lb DB pair, sandbag, 25 lb pack | L | distilled (ids 295-296, 301) |
| 81 | Mountain Sledding Training Plan | mountain-sledding-training-plan.md | Snowmobiling | NEW: snowmobiling (mountain sledding) | pre-season | 6 wk, 5 d/wk | DB, KB, barbell, gym | G | open |
## 4. Plans that are not sport prep

| Plan | Reason |
|---|---|
| Mountain Base Artemis, Atalanta, Danae V3, Helen V3, Alpha (5 plans) | Multi-sport base fitness for mountain athletes. They map to general-fitness, which Easy Strength (id 298) already serves. Useful only as a second generic base voice. |
| Mountain Athlete In-Season Flex | Generic in-season supplement for all mountain sports. Already distilled into ids 310 to 315. |
| Wilderness Professional Training Packet | Day-to-day job fitness for game wardens and rangers. The file holds the overview only, with no sessions. |
| Mountain/Wilderness SAR Fitness Assessment Training Plan | Search and rescue job assessment prep. |
| AMGA Alpine, Rock and Ski Guide Course plans (3) | Certification course prep for professional guides, tied to a 9 to 12 day course. |
| Mountain Guide Pre-Season | Guiding job prep. Gym content is good, but the audience is professionals. Listed as NEW mountain-guiding in the table. |
| Backcountry Hunting Fitness Assessment Training Plan | Prep for an MTI proprietary assessment, with assessment-gated progressions. Its lifts are usable and its assessment-gated progressions need rewriting. |
| Alpinist Fitness Assessment Training Plan | Same assessment-gated format for an MTI assessment. |

Hunting plans (6) map to the db-only backcountry-hunting slug and are kept in the main table as sport prep.

## 5. Counts and open questions

- 81 Mountain plans: 74 map to an existing sport slug (21 of those slugs are db only and absent from the onboarding catalog; 6 map to general-fitness) and 7 are NEW (4 guide or job plans plus the wilderness packet, SAR plan and Mountain Sledding).
- Strength mix: 32 G, 42 L, 3 E, 2 E/L and 2 L/G (the adventure race entries are estimates).
- Everest Training Plan holds three cycles (Base 7 weeks, Build 7 weeks, Peak 9 weeks) inside one file, and the INDEX count of 25 counts section headers.
- Could not determine: days per week for Mountain Base Alpha, Randonee Race, the 12-hour and 24-hour adventure races (overviews blank), and the Colorado Grand Traverse Ultra Run plus MTB plan (overview blank). Equipment for plans marked est was inferred from keyword counts.
- Not verified: whether the selector rolls child-sport routines up to a parent sport, whether `backcountry-touring` resolves to the ski rules (SportProfile lists only alpine-skiing, ski-mountaineering, snow-sports and snowboarding explicitly), and whether xc-skiing is authored-served. Servable counts use the goal and duration gates but I did not read each routine's movements.
