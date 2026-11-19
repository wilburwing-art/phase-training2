# Gap backlog, November 2026 (fifth round): a program for every catalog sport

Owner request 2026-11-18: every sport in `sport_categories` gets a program.
Programs come from real ones, distilled. A real program is an MTI plan, a
journal sample program, a program a named credentialed coach published, or a
community program with heavy positive peer review. Nothing is generated. 20 of
217 sports are plannable today. The other 196 are listed under "Per-sport
tracker" with a bucket each. Counts are from `db/coach.db` at b128f61, using
the `authoredRoutineIds` filter (25+ minutes, 3+ exercises, no prehab or
mobility goal).

| Bucket | Sports | What it needs |
|---|---|---|
| A | 36 | Already has 2+ routines. Needs a profile row and a picker entry. |
| B | 43 | An MTI plan in `~/repos/training-kb/data/training.db` covers it. Distill. |
| C | 71 | No source in hand. Find one, distill. |
| D | 46 | A variant or family member. Gets its parent's program, per the owner's rule. |

Owner decisions already made (2026-11-18):
- Sources: the four kinds above. Distill the exercise selection and sets/reps,
  and write notes in our own words.
- When a source names a family of sports, the siblings share it.
- A sport with no real S&C program maps to its parent.
- MTI sports go first.
- The 111 routines with no `source_name` stay. The owner says they were
  distilled from hand-authored routines.

Plan file: `~/.claude/plans/shiny-hatching-ripple.md`.

Item sizing: each box is one /next session. Hours are estimates from reading the
code and the six existing `scripts/db/distill_*.py` scripts (147 to 258 lines
each). "Logic" goes to builder-heavy, "UI" to builder, and "Content" to builder,
which loads `phase-training-coachdb-add-exercise-source-pipeline` and
`phase-training-authored-routine-serving` first. /next skips items that wait on
a Phase 0 decision.

Content check used below, written once. `DB` means
`python3 scripts/db/build_db.py && python3 scripts/db/test_build_db.py && python3 scripts/db/validate_coverage.py`,
with every check passing. `T(Class)` means the single-class xcodebuild run
described in the 11d header, with no lines from the grep.

## Phase 0: owner decisions (no code until settled)

- [x] **#1 Family profile rows (owner decision).** Yes, 2026-11-18. Do you approve these defaults for the 15 family roots with no `SportProfile` row (rules `.general`, signature, family)? Martial arts: contactStrength, upperDominant. Golf: core, legsDominant. Racquet: power, legsDominant. Surf and wave: pullEndurance, upperDominant. Swimming: pullEndurance, upperDominant. Multi-sport endurance: legEndurance, legsDominant. Team and rec: power, legsDominant. Skating and wheeled: legEndurance, legsDominant. Yoga and movement: bodyTension, upperDominant. Strength sports: maxStrength, legsDominant. Sailing and air: core, legsDominant. Equestrian: core, legsDominant. Archery and shooting: pullEndurance, upperDominant. Fishing and hunting: legEndurance, legsAndCarry. Dance: legEndurance, legsDominant. Yes unblocks 1.1 as written. Changes get edited into 1.1 first.
- [x] **#2 Parent overrides (owner decision).** Yes, 2026-11-18: the three overrides apply. Map via ferrata to scrambling, geocaching to day hiking, and bikejoring to mountain biking? Or keep the strict parent rule, which leaves geocaching and bikejoring with no program, because `misc-outdoor` has none? Yes edits item 5.1. No marks those three as unsupported in 5.1.
- [x] **#3 Pilot set (owner decision).** Yes, 2026-11-18: table tennis stays, tennis stays in A. Run the external pilot on boxing, fencing, dressage, dinghy sailing and table tennis? Or keep tennis in it? Tennis was in the plan, but it already has 5 routines (bucket A). Yes runs 4.1 as listed. Tennis swaps it in for table tennis.

## Phase 1: wiring (Logic, UI)

- [x] **1.1 Profile parent fallback (Logic, 3 h).** Landed 2026-11-18. 17 `Sport.catalog` sports became pickable: swimming, tennis, pickleball, soccer, basketball, volleyball, golf, surfing, yoga, pilates, crossfit, powerlifting, martial-arts, bjj, boxing, muay-thai, rowing. `isPlannable` needs one routine, so swimming, surfing, crossfit, boxing and muay-thai serve a single routine until Phases 3 and 4. The widened grids found the defects in 1.5. Nine family roots with routines in only some phases are pinned in `AuthoredRoutineTests.knownPhaseGapSports`. `SportProfile.of(slug)` currently returns `unlisted` for any slug not in `table`. Change it to fall back to the nearest ancestor's row through `sport_categories.parent_id`, using a new lookup in `CoachDatabase`. The inherited row keeps the ancestor's signature and family. It always gets rules `.general`, `supportFeature: false` and `writtenFirst: false`. Without that, freestyle skiing would inherit `.ski` and land on the season engine, and every bouldering child would land on the climbing engine. Add the #1 rows to `table`, and change `SportCatalog.outdoorAuthoredSlugs` to "any slug whose resolved profile is `.general`". Done: `T(AuthoredRoutineTests)` with new cases. `freestyle-skiing` resolves to `.general` with eccentricLeg. `tennis-clay` resolves to the racquet row. `isPlannable("golf")` flips to true, and the assertion at `AuthoredRoutineTests.swift:108` gets updated with the reason. `T(SportCatalogSlugTests)`. Verified on commit 85613c2: six classes (AuthoredRoutineTests, FilterCompositionTests, GeneratorWeekInvariantTests, PlanStoreSeamsTests, SportCatalogSlugTests, SportProfileTests), 110 tests, 0 failures, on the iPhone 17 Pro and iPhone 17 Pro Max simulators.
- [ ] **1.2 Picker from the catalog (UI, 4 h).** `Sport.catalog` (`TrainingMemory.swift:514`) is a hardcoded list of 35, shown flat in `OnboardingSportsScreen.swift:31` and `SportsEditorSheet.swift:24`. Read the plannable sports from coach.db instead. Group them under their family root, add a search field, and keep the curated names as display overrides. Done: in the simulator, onboarding shows family sections, and a search for "fencing" returns nothing until fencing has routines. Screenshot attached to the commit message.
- [x] **1.5 Defects the 1.1 widening found (Logic, 4 h).** Landed 2026-11-18, all three sets empty. Loadable: complement legs days on the general-fitness pool had five or six legStrength slots, and Glute Bridge, Lunge and Squat (Bodyweight) ranked level with Bulgarian split squats, so they took the last slots; the fit's extra row also picked them because they were the cheapest under the fatigue cap. `loadRank` now ranks beginner-level bodyweight movements as regressions (new `CoachDatabase.exerciseDifficulty`), and backfill for a strength demand sorts by load and skips regressions. Deload: the deload week used its own accessory seed, so it was a different session from the week before; it now reuses that week's seed (share 0.61 to 0.79 over 279 cells). Anchor drift: backfilled anchor-demand rows tie-broke on the weekly seed; they now use the block seed. 11c 3.6 (paddle-sports, sup) is fixed by the same change. `GeneratorWeekInvariantTests` on the 1.1 commit. Each defect is pinned exactly, so fixing a sport without removing it from its set fails. Deload week outside 0.60 to 0.80 of the week before: basketball, martial-arts, rowing, surfing (`knownDeloadBandSports`, 7 of 279 cells, 0.58 to 0.89). Anchor lift changes between weeks 1 and 3: boxing, muay-thai, pilates (`knownAnchorDriftSports`, 5 of 186 blocks). Bodyweight or band regressions in heavy gym slots: bjj, martial-arts, muay-thai, pilates, rowing, surfing, swimming, yoga, joining paddle-sports and sup in `knownRegressionSports` (86 of 16,723 slots). Start with the loadable slots: it is the same Glute Bridge and Lunge (Bodyweight) pattern 11c 3.6 holds for paddle sports, so fix them together. Done: `T(GeneratorWeekInvariantTests)` with all three sets empty.
- [x] **1.6 Stale migration test: running is a supported sport (Tests, 0.5 h).** `SeasonFidelityTest.test_migration_reonboards_unsupported_sport_without_loop` fails on d73f71a with 4 assertions at `SeasonFidelityTest.swift:590-596`: it uses `running` as the unsupported sport, and `migrateToSupportedSportGate` now keeps it. Pick a slug that is still unsupported (or build one that cannot resolve, such as `not-a-sport`) and keep the three assertions. Done: `T(SeasonFidelityTest)` 0 failures. Ticked 2026-11-19 (3ced882): the fixture uses `retired-sport-fixture`, a slug outside the catalog, and asserts it is unplannable. `T(SeasonFidelityTest)` 28/28.
- [ ] **1.7 Deload week under rotation (Logic, 1 h).** 1.5 makes the deload week reuse the week before's accessory seed, which the invariant test checks with an empty `recentMovementIDs`. In the app last week's accessories are recent, so `rotationTier` (`SportSeasonGenerator.swift:800`) ranks them below fresh ones and the deload week can still serve other accessories. Measure first: a `GeneratorWeekInvariantTests` case that feeds week N-1's exercise ids into `recentMovementIDs` for the deload week and compares the 0.60 to 0.80 share. If it fails, skip the recency tier in a deload week the way anchors do. Done: the new case passes over the same 279 cells.
- [ ] **1.3 Coverage check (Content, 1 h).** Add a check to `scripts/db/validate_coverage.py`: every sport whose program resolves to itself or its parent has 2+ qualifying routines, and every routine added after b128f61 has a `source_name`. Report sports that aren't covered yet as a count. They're expected until Phase 5 closes, so don't fail on them. Done: `DB`. At b128f61 the check prints 160 uncovered sports: the 116 with no routines and the 44 with one.
- [x] **1.4 Week invariant runtime (Tests, 1 h).** Landed 2026-11-19: plannable sports measured 31 (not 56); the grid takes one sport per `SportProfile` (24) and rotates session length for every sport except alpine-skiing and climbing. Class 190.7 s to 65.8 s on the dev Mac, grid build 175 s to 54 s. CI verdict comes from the next main run. `GeneratorWeekInvariantTests` iterates every plannable sport (see b128f61), and 1.1 grows that set from 20 to about 56, with the rest to come. Measure `T(GeneratorWeekInvariantTests)` before and after. If it more than doubles, iterate one sport per family root plus the ones in `knownRegressionSports`. Measured 2026-11-19 on 3ced882: the CI unit job (run 44544230552) hit its 25-minute timeout at `SpokenCueTests`, with tests starting 6 min in. CI times: `test_climbingPushPullRatioIsBalanced` 472 s (it builds the shared week grid; 172 s on the dev Mac), `FilterCompositionTests` 391 s after 3ced882 cut it from 467 s local to 158 s local. Every main run from 85613c2 to 3ced882 ended cancelled, six of them at the timeout. Done: the runtime is recorded in the commit message, and the main `test` run's unit job finishes under its timeout (`gh run list -b main -w test -L 1` shows success).
- [x] **1.8 FilterCompositionTests CI runtime (Tests, 1 h).** After 1.4, `test_everyPlannableSportSurvivesInjuryAndEquipmentTogether` is the largest unit test: 391 s on CI in run 44544230552 (158 s on the dev Mac after 3ced882), against a 25-minute job that spends 6 min building. If the first main `test` run after 1.4 times out or its unit job runs past 20 min, rotate the gear axis over (sport, injury) the way soreness rotates over slot and phase, keeping every bodyweight cell in `knownShortBlockedCells`. Done: `FilterCompositionTests` passes, and `gh run list -b main -w test -L 1` shows success with the unit job under 20 min. Update 2026-11-19: the unit job is now three parallel shards (`core`, `filter-grid`, `season-grids` in `test.yml`), so this suite has its own 25-minute job (497 s of tests on CI in run 44563801469, plus about 6.5 min of build). Tick when the first main run after the split shows `test (filter-grid)` green under 20 min; rotate the gear axis only if it does not. Ticked 2026-11-19: run 44579737847 (a0a2f17) unit shards all green, `test (filter-grid)` 16 m 47 s, `test (season-grids)` 16 m 32 s, `test (core)` 7 m 44 s. FilterCompositionTests 4/4 on iPhone 17 Pro B. Gear axis left as is.
- [ ] **1.9 UI test job past its 60-minute budget (Tests, 2 h).** `ui-tests` was cancelled at 60 min in run 44563801469 (4a67c73) after starting 41 suites, and runs 44487206277 and 44544230552 ended the same way or failed. Read the step log for the slowest suites (gap between `Test Suite ... started` lines, as in the unit shard split), then shard `-only-testing:PhaseTrainingUITests/<Class>` across a matrix the way the unit job is split, keeping the tap-budget steps on the shard that runs the flows they parse. Done: `gh run view <newest main run> --json jobs` shows every `ui-tests` job concluded success under 45 min. Update 2026-11-19: nightly run 44586959390 (6708422) spent 51 min in tests, started 41 of 47 suites and was cancelled inside `TapBudgetTests` (616 s by then); the six unrun were UnmatchedNames, VoiceLog, VoiceSettings, WorkoutCSVExport, WorkoutWheel, YourLifts. `ui-tests` is now three matrix shards in `test.yml` with a 45-minute timeout: `taps` (TapBudget, LogFlow, MotivationBatch, plus the three tap-budget steps), `screens` (ProgressScreen, CustomExercise, PaywallHero, Phase2Reach, ArcDeloadNotice) and `flows` (everything else by skip list), about 18 min of tests each by the per-suite times from runs 44544230552 and 44586959390. actionlint clean. Tick when the first main push run after the split shows all three `ui-tests` shards success under 45 min. Run 44598396591 (af69ba1): timing met, `ui-tests (screens)` 17 min, `ui-tests (taps)` 28 min, `ui-tests (flows)` 36 min (1501 s of tests over 51 cases). Not ticked: `flows` and `screens` failed on two tests that also failed in runs 44487206277 and 44544230552 before the split; see 1.12. Tick 1.9 on the first main push run where all three shards are green.
- [ ] **1.10 Grid suites intermittently plan empty sessions on the dev Mac (Tests, 2 h).** On 2026-11-19 between 17:10 and 17:25 UTC, `SportProfileTests` failed 58 cases on two clean simulators (iPhone 17 Pro and iPhone 17 Pro B, DerivedData-A and B) at 4a67c73, and once with 5 failures at docs-only 58408f9, in about 2 s instead of 78 s: snowboarding got 0 written sport days and mountaineering complements came back with 0 rows. `SeasonInvariantTests` failed 1823 cases in the same window ("grid collapsed to 20 week pairs"). Re-runs at 17:37 and 17:39 UTC passed 10/10 at the same commit, and CI passed `SeasonInvariantTests` on 4a67c73. The output looks like `CoachDatabase.shared` returning no routines or exercises, which points to the open in `CoachDatabase.swift:305` failing or being raced. Reproduce with five back-to-back `-only-testing:PhaseTrainingTests/SportProfileTests` runs; if one goes red, log the `sqlite3_open_v2` result and the routine count at the start of the suite. Done: a guard (an `XCTSkip` or a hard fail naming the open result when `listRoutines()` is empty) in `SportProfileTests` and `SeasonInvariantTests` setUp, and both classes pass.
- [ ] **1.11 Late nightly run cancels the push run on main (CI, 30 min).** `test.yml` puts every event in `concurrency: test-${{ github.ref }}` with `cancel-in-progress: true`. On 2026-11-19 the nightly cron (`17 9 * * *`) fired at 18:21 UTC as run 44586959390 and cancelled the push run 44583334374 on 6708422 mid-UI-suite, after its three unit shards had passed. The scheduled run skips the unit shards, so `/next`'s `gh run list -b main -w test -L 1` then reads a run with no unit verdict, and a UI timeout there (1.9) reads as red main. Give scheduled runs their own group (for example `test-${{ github.ref }}-${{ github.event_name == 'schedule' && 'nightly' || 'push' }}`) and have `.claude/commands/next.md` read the newest `push` run (`gh run list -b main -w test -e push -L 1`). Done: actionlint clean, next.md reads the push run, and after the next nightly the push run on that day's newest main commit shows its `ui-tests` job concluded success or failure on its own.
- [ ] **1.12 Two UI tests red on main before the shard split (Tests, 1 h).** Both fail all three retries in runs 44487206277, 44544230552 and 44598396591. (a) `OnboardingSportGateUITests.test_outdoor_authored_sports_are_selectable_in_onboarding` (`OnboardingSportGateUITests.swift:29`): `XCTAssertFalse(onboarding-sport-golf.exists)` fails with "golf must not be offered". 1.1 made golf pickable through the parent fallback and owner decision #1 approved golf's profile row, so the assertion is stale: check that golf is meant to show in onboarding, then assert a sport that is still unplannable instead. (b) `Phase2ReachUITests.test_historyCheckShowsOnProgressWithoutAnImport` (`Phase2ReachUITests.swift:24` area): the `progress-history-check` link is not found after 10 swipes on the `--seed-progress-demo` Progress tab. Find whether the seed no longer has a break over 8 weeks or the card moved, and fix the seed or the query. Done: `-only-testing:PhaseTrainingUITests/OnboardingSportGateUITests` and `-only-testing:PhaseTrainingUITests/Phase2ReachUITests` pass locally, and the next main push run shows `ui-tests (flows)` and `ui-tests (screens)` green (which also ticks 1.9).

## Phase 2: bucket A goes live (Content)

- [ ] **2.1 Spot-check the 36 bucket A sports (Content, 2 h, after 1.1).** For each one, list its qualifying routines, and confirm each routine's name and notes match the sport. Untag the ones that don't, and record what was untagged. Done: `DB`, the 1.3 count does not rise (an untag can drop a sport below 2), and the simulator picker shows the A sports.

## Phase 3: MTI distillation, bucket B (Content)

Each item writes one `scripts/db/distill_<family>.py`, following `scripts/db/distill_paddle.py`:
- Catalog exercise ids, checked against the expected name.
- Unmatched movements named in the notes.
- `source_name` set to "<MTI plan> (distilled)".
- Safe to re-run.
- At least 2 routines per sport, across base or off-season, build, and maintenance where the plan has them.

Read sessions with `sqlite3 ~/repos/training-kb/data/training.db "SELECT raw_text FROM session WHERE plan_id=<id> ORDER BY idx"`. Done for every item: `DB`, and each listed sport shows in the picker.

- [ ] **3.1 Surf family (3 h).** Surf Pre-Season V2 (445). Tag surf-wave-sports, surfing, bodyboarding, bodysurfing and skimboarding.
- [ ] **3.2 Swimming (3 h).** Swimming Improvement (184). Tag swimming, lap-swimming and open-water-swimming. swim-butterfly comes through D.
- [ ] **3.3 Triathlon and adventure racing (4 h).** Sprint, Olympic, Half Ironman and Ironman (380, 379, 376, 377). Then 6, 12 and 24-hour Adventure Race (245, 242, 243). Tag triathlon, multi-sport-endurance and adventure-racing.
- [ ] **3.4 Hiking and mountaineering children (4 h).** Half Dome Day Hike (222), Mountaineering & Hiking Prep (215), Backpack Pre-Season V2 (210), Rim to Rim to Rim (211), Kilimanjaro (214), Rainier (228), Teton Grand Traverse (223), Denali (226), Big Mountain V3 (225), Peak Bagger V5 (216). Tag day-hiking, backpacking, fastpacking, international-trekking, non-tech-mountaineering, technical-mountaineering, expedition-mountaineering and scrambling.
- [ ] **3.5 Running children (4 h).** Mountain Marathon (248), Alpine Running (247), 100K Ultra (305), 100 Mile Ultra (252), Obstacle Race Short/Medium/Long V2 (394, 393, 392), Cross Country Pre-Season Peak (408). Tag fell-running, mountain-running, trail-ultra-100k, trail-ultra-100mi, obstacle-course-racing and orienteering-foot.
- [ ] **3.6 Nordic and backcountry ski (3 h).** 10k to 50k Nordic Ski Race (272 to 276), Backcountry Ski Pre-Season V6 (268), Dryland Ski V6 (265), In Season Ski Maintenance V2 (266). Tag xc-skiing, backcountry-touring and telemark-skiing.
- [ ] **3.7 Grappling (2 h).** Tactical BJJ packet (579 to 583). Tag wrestling and sambo, plus bjj, bjj-gi, bjj-nogi and judo, which add depth to their A content.
- [ ] **3.8 Football and roller derby (3 h).** Football Base, Build, Pre-Season Peak and In-Season (409 to 412). Then Roller Derby Pre-Season (406). Tag flag-football and roller-derby.
- [ ] **3.9 Golf (2 h).** SF45 Golf (432). Tag golf-fitness and golf-senior, plus golf, which adds depth.
- [ ] **3.10 Hunting (3 h).** Backcountry Big Game Hunting Preseason V5 (203), Backcountry Hunting Base, Build 1 and Build 2 (204 to 206), Whitetail Deer Preseason (208). Tag fishing-hunting, backcountry-hunting and bow-hunting.
- [ ] **3.11 Strength sports (2 h).** Hypertrophy For Skinny Guys (294), High Rep Kettlebell Snatch (307), Kettlebell Strength TLU and Working Strength (301, 302). Tag bodybuilding and kettlebell-sport.
- [ ] **3.12 Paddle and climbing tags (2 h).** Tag the existing Kayak/Paddling routines to canoeing and rafting. Distill Alpine Rock Climb (219), AMGA Rock Guide Course (229) and Big Wall Climbing (230). Tag multi-pitch and aid-climbing.

## Phase 4: external sources, bucket C (Content)

Source standard: the author is named with credentials, and the venue is named (a journal, a book, a coach's own site, or a community page with its review count). Record the citation in `source_name` and the URL in `source_url`. Distill movements and doses only. Copy no prose. A sport with no source that meets the standard after one search pass moves to D, and the move is noted on its tracker line.

- [ ] **4.1 Pilot (6 h).** boxing, fencing, dressage, dinghy-sailing, table-tennis. Owner reviews the 5 sports' routines before 4.2 starts. Done: `DB`, plus a review note in this doc under 4.1.
- [ ] **4.2 Combat sports (6 h, after 4.1).** muay-thai, kickboxing, karate, taekwondo, krav-maga, aikido, kung-fu, capoeira, hema, kendo, iaido.
- [ ] **4.3 Racquet and team sports (6 h).** padel, badminton, racquetball, disc-golf, softball, ultimate-frisbee, hockey, lacrosse, cricket, team-handball.
- [ ] **4.4 Water and wind (6 h).** windsurfing, kitesurfing, wing-foiling, wakeboarding, wakesurfing, hydrofoiling, freediving, spearfishing, water-polo, artistic-swimming, swimrun.
- [ ] **4.5 Snow, wheels, air (6 h).** freestyle-skiing, ski-jumping, nordic-combined, roller-skiing, skateboarding, inline-skating, bmx, paragliding, hang-gliding, keelboat-racing, catamaran-sailing.
- [ ] **4.6 Movement, strength, dance (6 h).** tai-chi-qigong, movement-culture, pole-fitness, crossfit, olympic-weightlifting, highland-games, dance-fitness, ballroom-latin, swing-dance, salsa-bachata, contemporary-dance, hip-hop-dance, irish-dance.
- [ ] **4.7 Equestrian, archery, the rest (6 h).** equestrian-trail, equestrian-endurance, equestrian-eventing, show-jumping, polo, archery, sprinting-masters, canyoneering, slacklining, dog-agility.

## Phase 5: parent mapping, bucket D (Content)

- [ ] **5.1 Tag children to their parent's routines (2 h, after Phase 4).** One script, `scripts/db/tag_family_children.py`, with the mapping table taken from the D lines below. It adds `routine_sports` rows only. Done: `DB`, and the 1.3 count reads 0.

## Not scheduled

- MTI content for the five season-engine sports with zero routines. Engine-built days work for them now. Sources are in hand: Rock Climb Pre-Season V3 (231) for trad, Alpine Rock Climb (219) for alpine, Ice/Mixed Pre-Season (233) and Expedition Ice/Mixed (232) for ice and mixed, Randonee Race (271) and Colorado Grand Traverse Ski Mountaineering (269) for skimo. Needs an owner call on serving written routines first for those sports (the `writtenFirst` flag).

## Per-sport tracker

Plain bullets, no boxes. /next works the phase items above. Update a line's bucket when its sport moves.

### Martial Arts

- **Martial Arts** (`martial-arts`, id 260) A. 3 routines. Profile row through the family, then spot-check.
- **Brazilian Jiu-Jitsu** (`bjj`, id 261) A. 5 routines. Profile row through the family, then spot-check.
- **Judo** (`judo`, id 265) A. 2 routines. Profile row through the family, then spot-check.
- **Wrestling** (`wrestling`, id 266) B. MTI: Tactical BJJ packet (579 to 583). Has 1 routine now.
- **Muay Thai** (`muay-thai`, id 270) C. External source needed. Has 1 routine now.
- **Kickboxing** (`kickboxing`, id 271) C. External source needed. Has 1 routine now.
- **Boxing** (`boxing`, id 272) C. External source needed. **Pilot.** Has 1 routine now.
- **Mixed Martial Arts** (`mma`, id 275) A. 3 routines. Profile row through the family, then spot-check.
- **Karate** (`karate`, id 277) C. External source needed. Has 1 routine now.
- **Taekwondo** (`taekwondo`, id 281) C. External source needed. Has 1 routine now.
- **Krav Maga** (`krav-maga`, id 284) C. External source needed.
- **Sambo** (`sambo`, id 285) B. MTI: Tactical BJJ packet (579 to 583).
- **Aikido** (`aikido`, id 286) C. External source needed.
- **Kung Fu / Wushu** (`kung-fu`, id 287) C. External source needed.
- **Capoeira** (`capoeira`, id 288) C. External source needed.
- **Fencing** (`fencing`, id 289) C. External source needed. **Pilot.**
- **HEMA** (`hema`, id 293) C. External source needed.
- **Kendo** (`kendo`, id 294) C. External source needed.
- **Iaido** (`iaido`, id 295) C. External source needed.
- **BJJ Gi** (`bjj-gi`, id 262) A. 2 routines. Profile row through the family, then spot-check.
- **BJJ No-Gi** (`bjj-nogi`, id 263) D. Maps to parent bjj.

### Golf

- **Golf** (`golf`, id 320) A. 4 routines. Profile row through the family, then spot-check.
- **Traditional Golf** (`golf-traditional`, id 321) A. 2 routines. Profile row through the family, then spot-check.
- **Competitive Amateur Golf** (`golf-amateur`, id 326) A. 2 routines. Profile row through the family, then spot-check.
- **Disc Golf** (`disc-golf`, id 329) C. External source needed.
- **Topgolf / Range** (`topgolf`, id 330) D. Maps to parent golf.
- **Golf Fitness** (`golf-fitness`, id 331) B. MTI: SF45 Golf (432).
- **Senior Golf** (`golf-senior`, id 332) B. MTI: SF45 Golf (432).

### Racquet Sports

- **Racquet Sports** (`racquet-sports`, id 340) A. 2 routines. Profile row through the family, then spot-check.
- **Tennis** (`tennis`, id 341) A. 5 routines. Profile row through the family, then spot-check.
- **Pickleball** (`pickleball`, id 346) A. 3 routines. Profile row through the family, then spot-check.
- **Padel** (`padel`, id 349) C. External source needed. Has 1 routine now.
- **Badminton** (`badminton`, id 350) C. External source needed. Has 1 routine now.
- **Squash** (`squash`, id 353) A. 2 routines. Profile row through the family, then spot-check.
- **Racquetball** (`racquetball`, id 354) C. External source needed. Has 1 routine now.
- **Table Tennis** (`table-tennis`, id 355) C. External source needed. **Pilot.**
- **Beach Tennis** (`beach-tennis`, id 356) D. Maps to parent racquet-sports.
- **Tennis Singles** (`tennis-singles`, id 342) D. Maps to parent tennis.
- **Tennis Doubles** (`tennis-doubles`, id 343) D. Maps to parent tennis.
- **Clay Court Tennis** (`tennis-clay`, id 344) D. Maps to parent tennis.
- **Hard Court Tennis** (`tennis-hard`, id 345) D. Maps to parent tennis.
- **Pickleball Singles** (`pickleball-singles`, id 347) D. Maps to parent pickleball.
- **Pickleball Doubles** (`pickleball-doubles`, id 348) D. Maps to parent pickleball.
- **Badminton Singles** (`badminton-singles`, id 351) D. Maps to parent badminton.
- **Badminton Doubles** (`badminton-doubles`, id 352) D. Maps to parent badminton.

### Surf & Wave Sports

- **Surf & Wave Sports** (`surf-wave-sports`, id 420) B. MTI: Surf Pre-Season V2 (445). Has 1 routine now.
- **Surfing** (`surfing`, id 421) B. MTI: Surf Pre-Season V2 (445). Has 1 routine now.
- **Bodyboarding** (`bodyboarding`, id 426) B. MTI: Surf Pre-Season V2 (445). Has 1 routine now.
- **Bodysurfing** (`bodysurfing`, id 427) B. MTI: Surf Pre-Season V2 (445).
- **Skimboarding** (`skimboarding`, id 428) B. MTI: Surf Pre-Season V2 (445).
- **Windsurfing** (`windsurfing`, id 429) C. External source needed.
- **Kitesurfing** (`kitesurfing`, id 432) C. External source needed. Has 1 routine now.
- **Wing Foiling** (`wing-foiling`, id 437) C. External source needed. Has 1 routine now.
- **Wakeboarding** (`wakeboarding`, id 438) C. External source needed. Has 1 routine now.
- **Wakesurfing** (`wakesurfing`, id 439) C. External source needed. Has 1 routine now.
- **Hydrofoiling** (`hydrofoiling`, id 440) C. External source needed.

### Swimming

- **Swimming** (`swimming`, id 450) B. MTI: Swimming Improvement (184). Has 1 routine now.
- **Lap Swimming** (`lap-swimming`, id 451) B. MTI: Swimming Improvement (184). Has 1 routine now.
- **Open Water Swimming** (`open-water-swimming`, id 457) B. MTI: Swimming Improvement (184). Has 1 routine now.
- **Freediving** (`freediving`, id 460) C. External source needed.
- **Water Polo** (`water-polo`, id 463) C. External source needed.
- **Artistic Swimming** (`artistic-swimming`, id 464) C. External source needed.
- **Butterfly** (`swim-butterfly`, id 455) D. Maps to parent lap-swimming.

### Multi-Sport Endurance

- **Multi-Sport Endurance** (`multi-sport-endurance`, id 500) B. MTI: the triathlon plans below.
- **Triathlon** (`triathlon`, id 501) B. MTI: Sprint, Olympic, Half Ironman, Ironman (380, 379, 376, 377).
- **Adventure Racing** (`adventure-racing`, id 510) B. MTI: 6, 12, 24-Hour Adventure Race (245, 242, 243).
- **SwimRun** (`swimrun`, id 513) C. External source needed.
- **Rogaine** (`rogaine`, id 514) D. Maps to parent multi-sport-endurance.

### Team / Rec League Sports

- **Team / Rec League Sports** (`team-rec-sports`, id 530) D. Family root. Tag the soccer routines once they land.
- **Soccer** (`soccer`, id 531) A. 3 routines. Profile row through the family, then spot-check.
- **Basketball** (`basketball`, id 534) A. 3 routines. Profile row through the family, then spot-check.
- **Volleyball** (`volleyball`, id 537) A. 3 routines. Profile row through the family, then spot-check.
- **Softball** (`softball`, id 541) C. External source needed. Has 1 routine now.
- **Baseball (Adult)** (`baseball-adult`, id 542) A. 2 routines. Profile row through the family, then spot-check.
- **Flag Football** (`flag-football`, id 543) B. MTI: Football Base, Build, Pre-Season Peak, In-Season (409 to 412). Has 1 routine now.
- **Ultimate Frisbee** (`ultimate-frisbee`, id 544) C. External source needed.
- **Rugby** (`rugby`, id 545) A. 2 routines. Profile row through the family, then spot-check.
- **Hockey** (`hockey`, id 549) C. External source needed. Has 1 routine now.
- **Lacrosse** (`lacrosse`, id 553) C. External source needed. Has 1 routine now.
- **Cricket** (`cricket`, id 554) C. External source needed. Has 1 routine now.
- **Dodgeball / Kickball** (`dodgeball-kickball`, id 555) D. Maps to parent team-rec-sports.
- **Team Handball** (`team-handball`, id 556) C. External source needed. Has 1 routine now.
- **Recreational Soccer** (`soccer-recreational`, id 532) D. Maps to parent soccer.

### Skating & Wheeled

- **Skating & Wheeled** (`skating-wheeled`, id 580) D. Family root. Tag the roller-derby routines once they land.
- **Skateboarding** (`skateboarding`, id 581) C. External source needed.
- **Inline Skating** (`inline-skating`, id 586) C. External source needed.
- **Roller Derby** (`roller-derby`, id 587) B. MTI: Roller Derby Pre-Season (406). Has 1 routine now.
- **Roller Skiing** (`roller-skiing`, id 588) C. External source needed.
- **Mountain Boarding** (`mountain-boarding`, id 589) D. Maps to parent skating-wheeled.
- **Sandboarding** (`sandboarding`, id 590) D. Maps to parent skating-wheeled.

### Yoga & Movement

- **Yoga & Movement** (`yoga-movement`, id 600) A. 3 routines. Profile row through the family, then spot-check.
- **Yoga** (`yoga`, id 601) A. 5 routines. Profile row through the family, then spot-check.
- **Pilates** (`pilates`, id 608) A. 3 routines. Profile row through the family, then spot-check.
- **Tai Chi / Qigong** (`tai-chi-qigong`, id 611) C. External source needed. Has 1 routine now.
- **Movement Culture** (`movement-culture`, id 612) C. External source needed.
- **Adult Gymnastics** (`gymnastics-adult`, id 613) A. 2 routines. Profile row through the family, then spot-check.
- **Calisthenics** (`calisthenics`, id 614) A. 3 routines. Profile row through the family, then spot-check.
- **Parkour / Freerunning** (`parkour`, id 615) A. 3 routines. Profile row through the family, then spot-check.
- **Pole Fitness** (`pole-fitness`, id 616) C. External source needed. Has 1 routine now.

### Strength & Fitness Sports

- **Strength & Fitness Sports** (`strength-fitness-sports`, id 630) A. 3 routines. Profile row through the family, then spot-check.
- **CrossFit** (`crossfit`, id 631) C. External source needed. Has 1 routine now.
- **Powerlifting** (`powerlifting`, id 632) A. 2 routines. Profile row through the family, then spot-check.
- **Olympic Weightlifting** (`olympic-weightlifting`, id 635) C. External source needed.
- **Strongman** (`strongman`, id 638) A. 2 routines. Profile row through the family, then spot-check.
- **Bodybuilding** (`bodybuilding`, id 639) B. MTI: Hypertrophy For Skinny Guys (294).
- **Kettlebell Sport** (`kettlebell-sport`, id 640) B. MTI: High Rep Kettlebell Snatch (307), Kettlebell Strength TLU and Working Strength (301, 302).
- **Highland Games** (`highland-games`, id 641) C. External source needed. Has 1 routine now.

### Sailing & Air Sports

- **Sailing & Air Sports** (`sailing-air-sports`, id 660) D. Family root. Tag the dinghy-sailing routines once they land.
- **Dinghy Sailing** (`dinghy-sailing`, id 661) C. External source needed. **Pilot.**
- **Keelboat Racing** (`keelboat-racing`, id 662) C. External source needed.
- **Catamaran Sailing** (`catamaran-sailing`, id 663) C. External source needed.
- **Land Sailing** (`land-sailing`, id 664) D. Maps to parent sailing-air-sports.
- **Paragliding** (`paragliding`, id 665) C. External source needed.
- **Hang Gliding** (`hang-gliding`, id 666) C. External source needed.

### Equestrian

- **Equestrian** (`equestrian`, id 690) A. 2 routines. Profile row through the family, then spot-check.
- **Trail Riding** (`equestrian-trail`, id 691) C. External source needed. Has 1 routine now.
- **Endurance Riding** (`equestrian-endurance`, id 692) C. External source needed. Has 1 routine now.
- **Eventing** (`equestrian-eventing`, id 693) C. External source needed. Has 1 routine now.
- **Dressage** (`dressage`, id 694) C. External source needed. **Pilot.**
- **Show Jumping** (`show-jumping`, id 695) C. External source needed.
- **Polo** (`polo`, id 696) C. External source needed. Has 1 routine now.

### Archery & Shooting

- **Archery & Shooting** (`archery-shooting`, id 710) D. Family root. Tag the archery routines once they land.
- **Archery** (`archery`, id 711) C. External source needed.
- **Sporting Clays** (`sporting-clays`, id 715) D. Maps to parent archery-shooting.
- **Trap Shooting** (`trap-shooting`, id 716) D. Maps to parent archery-shooting.
- **Skeet Shooting** (`skeet-shooting`, id 717) D. Maps to parent archery-shooting.

### Fishing & Hunting (Fitness)

- **Fishing & Hunting (Fitness)** (`fishing-hunting`, id 720) B. MTI: the hunting plans below.
- **Fly Fishing** (`fly-fishing`, id 721) D. Maps to parent fishing-hunting (the hunting plans).
- **Spearfishing** (`spearfishing`, id 722) C. External source needed.
- **Bow Hunting** (`bow-hunting`, id 723) B. MTI: Whitetail Deer Hunting Preseason (208), Backcountry Hunting Base (204).
- **Backcountry Hunting** (`backcountry-hunting`, id 724) B. MTI: Backcountry Big Game Hunting Preseason V5 (203), Backcountry Hunting Base, Build 1, Build 2 (204 to 206). Has 1 routine now.

### Dance (Fitness)

- **Dance (Fitness)** (`dance-fitness`, id 730) C. External source needed.
- **Ballroom / Latin** (`ballroom-latin`, id 731) C. External source needed.
- **Swing / Lindy Hop** (`swing-dance`, id 732) C. External source needed.
- **Salsa / Bachata** (`salsa-bachata`, id 733) C. External source needed.
- **Contemporary** (`contemporary-dance`, id 734) C. External source needed. Has 1 routine now.
- **Hip Hop** (`hip-hop-dance`, id 735) C. External source needed. Has 1 routine now.
- **Irish Dance** (`irish-dance`, id 736) C. External source needed.

### Miscellaneous Outdoor

- **Miscellaneous Outdoor** (`misc-outdoor`, id 750) D. Family root with no program of its own; its children map elsewhere (#2). Stays unplannable.
- **Slacklining / Highlining** (`slacklining`, id 751) C. External source needed.
- **Geocaching** (`geocaching`, id 752) D. Maps to day-hiking (#2).
- **Dog Sports (Agility)** (`dog-agility`, id 753) C. External source needed.
- **Bikejoring** (`bikejoring`, id 754) D. Maps to mountain-biking (#2).

### Cycling

- **Road Cycling** (`road-cycling`, id 12) A. 2 routines. Profile row through the family, then spot-check.
- **Gravel Cycling** (`gravel-cycling`, id 21) A. 2 routines. Profile row through the family, then spot-check.
- **Cyclocross** (`cyclocross`, id 24) A. 2 routines. Profile row through the family, then spot-check.
- **BMX** (`bmx`, id 25) C. External source needed.
- **Indoor Cycling** (`indoor-cycling`, id 28) D. Maps to parent cycling.
- **E-Bike (Road/Gravel)** (`e-bike-road-gravel`, id 30) D. Maps to parent cycling.

### Running

- **Road Running** (`road-running`, id 51) A. 2 routines. Profile row through the family, then spot-check.
- **Fell Running** (`fell-running`, id 66) B. MTI: Mountain Marathon (248), Alpine Running (247).
- **Sprinting (Masters)** (`sprinting-masters`, id 67) C. External source needed.
- **Obstacle Course Racing** (`obstacle-course-racing`, id 68) B. MTI: Obstacle Race Short/Medium/Long V2 (394, 393, 392), Tough Mudder (396).
- **Orienteering (Foot)** (`orienteering-foot`, id 71) B. MTI: Cross Country Pre-Season Peak (408), Mountain Marathon (248).
- **Canicross** (`canicross`, id 72) D. Maps to parent running.
- **Marathon** (`marathon`, id 55) A. 2 routines. Profile row through the family, then spot-check.
- **Trail Ultra 100K** (`trail-ultra-100k`, id 61) B. MTI: 100K Ultra (305), 50 Mile Ultra V2 (244).
- **Trail Ultra 100mi** (`trail-ultra-100mi`, id 62) B. MTI: 100 Mile Ultra (252), 100-Mile Ultra Stage Race (253).
- **Mountain Running** (`mountain-running`, id 65) B. MTI: Mountain Marathon (248), Alpine Running (247).

### Climbing

- **Multi-Pitch** (`multi-pitch`, id 108) B. MTI: Alpine Rock Climb (219), AMGA Rock Guide Course (229).
- **Deep Water Soloing** (`deep-water-soloing`, id 112) D. Maps to parent climbing.
- **Competition Climbing** (`comp-climbing`, id 113) A. 2 routines. Profile row through the family, then spot-check.
- **Via Ferrata** (`via-ferrata`, id 117) D. Tag the scrambling routines (#2).
- **Aid Climbing** (`aid-climbing`, id 118) B. MTI: Big Wall Climbing (230).
- **Bouldering Indoor** (`bouldering-indoor`, id 102) D. Maps to parent bouldering.
- **Bouldering Outdoor** (`bouldering-outdoor`, id 103) D. Maps to parent bouldering.
- **Sport Lead** (`sport-lead`, id 105) D. Maps to parent sport-climbing.
- **Sport Top Rope** (`sport-top-rope`, id 106) D. Maps to parent sport-climbing.
- **Comp Lead** (`comp-lead`, id 114) D. Maps to parent comp-climbing.
- **Comp Boulder** (`comp-boulder`, id 115) D. Maps to parent comp-climbing.
- **Comp Speed** (`comp-speed`, id 116) D. Maps to parent comp-climbing.

### Mountaineering

- **Non-Technical Mountaineering** (`non-tech-mountaineering`, id 151) B. MTI: Rainier (228), Kilimanjaro (214).
- **Technical Mountaineering** (`technical-mountaineering`, id 155) B. MTI: Teton Grand Traverse (223), AMGA Alpine Guide Course (221).
- **Expedition Mountaineering** (`expedition-mountaineering`, id 159) B. MTI: Denali (226), Big Mountain V3 (225), Everest (227).
- **Scrambling (Class 3-4)** (`scrambling`, id 164) B. MTI: Peak Bagger V5 (216), WURL (224).
- **Canyoneering** (`canyoneering`, id 165) C. External source needed.
- **Altitude Acclimatization** (`altitude-acclimatization`, id 166) D. Maps to parent mountaineering.

### Snow Sports

- **Freestyle Skiing** (`freestyle-skiing`, id 208) C. External source needed.
- **Cross-Country Skiing** (`xc-skiing`, id 212) B. MTI: 10k to 50k Nordic Ski Race (272 to 276).
- **Backcountry / Touring** (`backcountry-touring`, id 216) B. MTI: Backcountry Ski Pre-Season V6 (268), AMGA Ski Guide Course (262).
- **Telemark Skiing** (`telemark-skiing`, id 220) B. MTI: Dryland Ski V6 (265), In Season Ski Maintenance V2 (266).
- **Snowshoeing** (`snowshoeing`, id 228) D. Maps to parent snow-sports.
- **Ski Jumping** (`ski-jumping`, id 229) C. External source needed.
- **Nordic Combined** (`nordic-combined`, id 230) C. External source needed.
- **Downhill Skiing** (`alpine-downhill`, id 205) D. Maps to parent alpine-skiing.
- **Recreational Alpine** (`alpine-recreational`, id 207) D. Maps to parent alpine-skiing.
- **Splitboarding** (`splitboarding`, id 226) D. Tag the 3 splitboard routines (ids 295 to 297), which are written for it.

### Paddle Sports

- **Kayaking** (`kayaking`, id 381) A. 7 routines. Profile row through the family, then spot-check.
- **Canoeing** (`canoeing`, id 390) B. MTI: Kayak/Paddling Pre-Season (218), tag the existing distilled routines. Has 1 routine now.
- **Rafting** (`rafting`, id 400) B. MTI: Kayak/Paddling Pre-Season (218), tag the existing distilled routines.
- **Dragon Boat Racing** (`dragon-boat`, id 403) A. 2 routines. Profile row through the family, then spot-check.
- **Rowing** (`rowing`, id 404) A. 2 routines. Profile row through the family, then spot-check.

### Hiking & Trekking

- **Day Hiking** (`day-hiking`, id 481) B. MTI: Half Dome Day Hike (222), Mountaineering & Hiking Prep (215).
- **Backpacking** (`backpacking`, id 482) B. MTI: Backpack Pre-Season V2 (210). Has 1 routine now.
- **Fastpacking** (`fastpacking`, id 484) B. MTI: Grand Canyon Rim to Rim to Rim (211).
- **Trekking (International)** (`international-trekking`, id 485) B. MTI: Kilimanjaro (214), Jackson Hole Everest 29029 (213).
