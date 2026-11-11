# Competitive gap analysis, Phase Training

Date: 2026-11-10. Commit: bb17ca1 (build 171). Analysis: COMPETITIVE.

## Method

- Phase Training claims cite file:line read in this session. GAP_ANALYSIS.md (commit 46b5a4d, 2026-09-10) was used only as a list of claims to re-check.
- Competitor facts come from three sources that cannot summarize: the iTunes Search/Lookup JSON API (app description text and version dates), the App Store product pages fetched with curl (the In-App Purchases list), and curl of vendor pages (Lattice, Crimpd, JuggernautAI). Each quote below is verbatim from one of those.
- WebFetch is not available to this agent. Three web-fetch subagents were launched and their reports never arrived in this session, so none of their output is used here.
- Prices are the App Store In-App Purchases list read 2026-11-10. The list gives names and price points. It does not always label the billing period, so where two price points share a name the period is marked "unlabeled". US storefront.
- Anything I could not fetch is marked "unverified" and the reason given.
- Search-snippet claims (Rivo, letsgooo-fit, Uphill Athlete prices) are unverified.

Source URLs (App Store pages, each also queried through `itunes.apple.com/lookup?id=<id>`):

| App | URL |
|---|---|
| Strong | https://apps.apple.com/us/app/strong-workout-tracker-gym-log/id464254577 |
| Hevy | https://apps.apple.com/us/app/hevy-workout-tracker-gym-log/id1458862350 |
| Fitbod | https://apps.apple.com/us/app/fitbod-gym-fitness-planner/id1041517543 |
| JuggernautAI | https://apps.apple.com/us/app/juggernautai/id1515756471 |
| RP Hypertrophy | https://apps.apple.com/us/app/rp-hypertrophy/id1555614554 |
| Ladder | https://apps.apple.com/us/app/ladder-strength-training-plans/id1502936453 |
| Future Pro | https://apps.apple.com/us/app/future-pro-personal-training/id1288178982 |
| TrainHeroic | https://apps.apple.com/us/app/trainheroic-strength-training/id955074569 |
| TrainingPeaks | https://apps.apple.com/us/app/trainingpeaks-plan-train-lift/id408047715 |
| Boostcamp | https://apps.apple.com/us/app/boostcamp-workout-tracker/id1529354455 |
| Crimpd | https://apps.apple.com/us/app/crimpd/id1252333138 |
| Lattice | https://apps.apple.com/us/app/lattice-training-for-climbing/id1607997399 |
| ClimbMax | https://apps.apple.com/us/app/climbmax-climbing-training/id6751116958 |
| Pedestal | https://apps.apple.com/us/app/pedestal-ai-athlete-training/id1586902208 |
| MTNTOUGH | https://apps.apple.com/us/app/mtntough-fitness-resilience/id1587103337 |
| Capacity | https://apps.apple.com/us/app/capacity-hybrid-training/id6759235311 |

## Competitor matrix

All apps below still exist and shipped an update between 2026-10-08 and 2026-11-11 (the iTunes `currentVersionReleaseDate` field), except Future Fitness 24/7 and the SmartBarbell app, which are not covered here. Ratings are App Store counts read today.

| App | IAP price points (2026-11-10) | Apple Watch | Programming / AI | Readiness / wearables | Mountain or climbing content |
|---|---|---|---|---|---|
| Strong (108,547 ratings) | PRO 1 Month $4.99, 1 Year $29.99, Forever $99.99, plus legacy points | "Fully-featured Apple Watch app to log workouts with or without your iPhone" | None stated. Logger with routines, warm-up and plate calculators | Apple Health body measurements | None |
| Hevy (102,806) | Pro Monthly $2.99, Yearly $23.99, Lifetime $74.99 | "Log sets, start rest timers, and finish your workout without touching your phone", plus watch-face complications | "Hevy Trainer gives you the coaching you need, available with Hevy Pro" | HealthKit export only | None |
| Fitbod (289,593) | Monthly Plan $12.99 and $15.99, "A Year of Fitbod Elite" $79.99 and $95.99, legacy points $7.99 to $59.99 | "Strava, Fitbit, and Apple Watch integration" | "AI-Generated Workouts", "Adaptive AI learns from your edits" | "recovery and exercise tracking" | None |
| JuggernautAI (5,655) | Monthly $34.99 (listed twice) | Not stated in listing (unverified) | "Personalized Periodization Strategy", "phasic periodization plan" | "Readiness Rating System", adjusts "pre-session, intra-session, session to session, week to week" (source of the rating not stated) | None (powerlifting and powerbuilding) |
| RP Hypertrophy (315) | Monthly $34.99, Yearly $299.99 | Not stated in listing (unverified) | "personalized training recommendations" (listing is short) | Not stated | None |
| Ladder (220,087) | PRO $29.99, PRO Annual $179.99, PRO+ $34.99, ELITE $44.99, ELITE+ $49.99, annual points $329.99 to $479.99 | Not stated in listing (unverified) | "A NEW WORKOUT PLAN EVERY DAY", coach-built progressive overload | Not stated | None |
| Future Pro (10,803) | No IAP section on the page (unverified; human coaching priced off-store) | "With Apple Watch integration, Future tracks all your activity" | Human coach "actively refines your plan over time" | Apple Watch activity | None stated |
| TrainHeroic (1,847) | Athlete Pro Monthly $4.99, Athlete Pro $29.99, plus coach-sold plans at $29.99 | Not stated (unverified) | Coach-sold plans | "manage your recovery with Readiness Insights" | None |
| TrainingPeaks (12,772) | Monthly Premium $19.99, Annual $134.99, other points $48.99 and $119.99 | Not stated (unverified) | "Annual season planning" tools for coaches | Not stated | None; Uphill Athlete plans are delivered through it (unverified, see below) |
| Boostcamp (10,916) | Boostcamp Pro points $11.99 to $79.99 (periods unlabeled), limited offer $48.99 | Not stated in listing | "11,000+ programs", "AI Coach", "progressions, periodization, and deloads" | "Syncs bodyweight with Apple Health" | None. "Live Activities put your set and rest timer on the Lock Screen and Dynamic Island." |
| Crimpd (101) | Crimpd+ Monthly $12.99, Quarterly $29.99, Yearly $59.99 | Not stated | Plan builder, "over 20 pre-built Skill Templates" | Not stated | "built-in timer is designed specifically for climbing workouts, like hang boarding and interval circuits" |
| Lattice (25 ratings, 3.36) | LatticePlan Monthly $29.99, Yearly $149.99, Founder Yearly $119.99 (US). UK site shows monthly £22.99 | Not stated | "Adaptive LatticePlans: Workouts adjust intelligently as you log sessions" | Not stated | Climbing only. Web page lists coach-written plans, in-app coach chat |
| ClimbMax (0 ratings) | Premium Monthly $9.99, Annual $69.99 | Not stated | "adaptive training plan" (paid); logging, strength and finger workouts free | Not stated | Climbing only |
| Pedestal (2 ratings) | Monthly $12.99, Annual $79.99 | "Sync with Apple Watch, Garmin, Polar, WHOOP, Suunto, Fitbit, Wahoo, Oura" | "custom AI built training plans for ANY sport", "structured periodization" | "adapts to how you train, recover, and progress" | Generic sport drills. "training for a climb" is one example |
| MTNTOUGH (3,672) | Monthly $29.99, Yearly $239.99 | Not stated | Fixed programs | Not stated | "for mountain athletes and backcountry hunters". Strength and conditioning, no climbing or ski periodization stated |
| Capacity (19) | Monthly $29.99, Yearly $199.99, Founding Yearly $149.99 | Not stated | Hybrid run plus lift plans, "Three lifting styles" | Not stated | None |
| Uphill Athlete | Unverified. uphillathlete.com returned HTTP 403 to curl. A search summary listed skimo plans at $69 to $89 and a Training Library "starting at $26 a month", with conflicting page figures | No app found in the iTunes search | Static plans sold through TrainingPeaks (unverified) | n/a | Skimo and mountaineering plans (unverified detail) |
| Gritty Gains | No app found in the iTunes search (unverified that one exists) | n/a | n/a | n/a | n/a |

Rivo (ski AI plans) and letsgooo-fit surfaced only in search snippets. Neither could be fetched, so both are unverified and left out of the matrix.

## Where Phase Training leads

1. **Season-phase engine for ski and climbing, no verified competitor equivalent.** `SportSeasonGenerator` plans around off-season, pre-season, in-season and event prep (`PhaseRule.swift:69-72`, ski slugs at `:78`), with strength emphasis per phase (`SportSeasonModels.swift:25-52`) and four ski variants plus three climbing variants (`SportSeasonModels.swift:72-81`). No listing quoted above describes season-phase periodization for either sport. Boostcamp, Juggernaut and Pedestal describe periodization in general terms, Lattice and Crimpd cover climbing only, and Uphill Athlete's plans could not be read.
2. **Ski readiness and ski days.** A ski discipline picker (`ProfileScreen.swift:309`, `SkiDisciplineSheet.swift`), a pre-season ski test with Progress card, and ski days read from detected Watch ski workouts (per `docs/PLAN-gap-backlog-2026-11.md`, Phase 6, shipped build 167). No lifting app in the matrix lists any of it.
3. **Hangboard loads inside a lifting plan.** The max-hang test log sets loads for `Hangboard Max Hang (20mm Edge)` at 85% and `Hangboard Repeaters (7/3 Protocol)` at 80% of tested total load (`PhaseTrainingApp.swift:204`; percentages per the backlog, taken from Lattice's published instructions). Crimpd and Lattice own this in climbing-only apps; none of the lifting apps lists it.
4. **Free coach and low price.** `CoachEntitlement.proRequired = false` (`CoachEntitlement.swift:41`, decision recorded at `:9`). The StoreKit config prices Pro at $2.99 monthly and $24.99 yearly (`PhaseTraining.storekit:23,48`). That sits next to Hevy ($2.99, $23.99) and under every AI or periodization competitor ($12.99 to $34.99 monthly).
5. **Apple Watch with a live HealthKit workout and labeled motion capture.** `WatchWorkoutController.swift:1-12` runs an `HKWorkoutSession` with heart rate and active energy; `MotionRecorder.swift:1-14` records 50 Hz wrist motion labeled at each set tap. No competitor listing mentions motion capture.
6. **Importers for three rivals.** CSV import accepts Fitbod, Hevy and Strong exports (`WorkoutCSVImporter.swift:48`), with a CSV exporter (`WorkoutCSVExporter.swift`). That lowers switching cost from the three biggest loggers.
7. **Recovery data stays on device.** `PhysiologyReader.swift:4-20` reads HRV, resting heart rate and sleep only after a separate user tap and keeps them local.

## Where Phase Training lags (ranked by impact)

### 1. Captured recovery data does not steer the plan
- Evidence: HRV, resting HR and sleep are stored nightly (`PhysiologyReader.swift:4-20`) but the file states they are "NOT part of the AI Coach snapshot", and the only other readers of `pt_physiology_nights` are the hourly refresh (`PhaseTrainingApp.swift:820`) and backup (`BackupManager.swift:81-128`). Generator readiness comes from logged sessions and sport days (`PlanStore+Generation.swift:214-242`).
- Competitors: JuggernautAI ("Readiness Rating System" at several time scales), TrainHeroic ("Readiness Insights"), Pedestal (WHOOP, Oura, Garmin and others listed).
- Why it matters here: the app's pitch is training around sport load. A skier with a poor-sleep week gets the same plan as a rested one.
- Response: show a nightly readiness line on Today first, then a bounded bias (one set or one RPE point) on pre-season and in-season days only. The backlog already says to re-run the shadow twin replay before any readiness work.
- Effort: 14 to 20 hours.

### 2. No Live Activity, no widget
- Evidence: no file in the repo imports ActivityKit or WidgetKit (recursive search of `*.swift`, zero hits). The rest timer is in-app plus a notification (`RestTimerState.swift`, commit 3a663a1).
- Competitors: Boostcamp ("Live Activities put your set and rest timer on the Lock Screen and Dynamic Island"), Hevy (watch-face complications). Widgets for Strong, Fitbod and Hevy are unverified here.
- Response: a rest-timer Live Activity first (about 8 hours), then a next-workout widget (about 6 hours). The Watch already carries the rest timer, so the phone Live Activity matters for people without one.
- Effort: 12 to 16 hours.

### 3. Monetization is not live
- Evidence: `SubscriptionStore.swift:4-7` says the product IDs are placeholders until created in App Store Connect; `CoachEntitlement.swift:41` holds the gate open. Nothing in the app is currently paid.
- Competitors price AI and periodization at $12.99 to $34.99 monthly (Fitbod, Pedestal, Lattice, JuggernautAI, RP). Hevy's $2.99 is the only listing near the configured price.
- Response: this needs a product decision before code. If the coach stays free, the $24.99 annual needs a gated feature that justifies it (candidates: readiness bias from item 1, ski and climbing season plans). The flip-day checklist at `CoachEntitlement.swift:24-40` lists the offline-launch gap to close first.
- Effort: 4 to 6 hours of code plus App Store Connect setup, after the product decision.

### 4. Climbing depth against climbing-only apps
- Evidence: `SportLog.swift` has no grade or attempts field (searched for "grade", no match). Hangboard loads exist for two protocols only. No route or board logging.
- Competitors: ClimbMax logs grade, attempts and notes for free, and sells an adaptive plan at $9.99 monthly. Crimpd sells 20+ skill templates and a plan builder at $12.99 monthly. Lattice sells adaptive plans built from assessments.
- Response: do not copy a logbook. Add one climbing assessment beyond max hang (for example a pull-up max or a repeater test) that feeds the same season engine, and a grade and attempts field on climbing days so the plan can see volume at grade.
- Effort: 10 to 14 hours.

### 5. Exercise demonstrations are still images
- Evidence: 2,108 `.webp` files in `PhaseTraining/Resources/ExerciseImages`, zero video players in the exercise or log screens (recursive search for AVPlayer and VideoPlayer in the exercise screens returned nothing). The catalog is 585 exercises (`db/source/exercises.json`).
- Competitors: Strong lists "a growing library of animated videos"; TrainHeroic says every exercise has "a demo video and coaching points"; Ladder lists "video demonstrations". Fitbod and Hevy video claims are unverified here.
- Response: animated webp loops for the top 60 lifts in the generated plans. A licensing check comes first.
- Effort: 20 to 40 hours, mostly asset work.

### 6. Named program library
- Evidence: no browsable library of named programs; plans are generated.
- Competitor: Boostcamp lists "11,000+ Programs" and names "nSuns, GZCLP, 5/3/1, Reddit PPL, PHUL, PHAT".
- Response: low priority for the mountain niche. Skip unless acquisition data says lifters leave for a named program.
- Effort: 40 or more hours.

### 7. Platform and language reach
- Evidence: iPhone only (`Project.yml` `TARGETED_DEVICE_FAMILY: "1"`), English only (the String Catalog holds one language, `en`).
- Competitor: Strong's site says it is "available on iPhone, Android, and Apple Watch". Boostcamp and Hevy Android claims are unverified in this pass.
- Response: out of scope for this quarter. Record it as a known ceiling.
- Effort: not estimated.

## Pricing comparison (App Store price points, 2026-11-10)

| App | Lowest monthly point | Yearly or lifetime points | Free tier |
|---|---|---|---|
| Phase Training (StoreKit config, not live) | $2.99 | $24.99 yearly | Everything, coach included |
| Hevy | $2.99 | $23.99 yearly, $74.99 lifetime | Yes (limits unverified here) |
| TrainHeroic | $4.99 | $29.99 | Yes (App Store lists "Free") |
| Strong | $4.99 | $29.99 yearly, $99.99 forever | Yes, "Strong Accounts are Free Forever" (strong.app) |
| ClimbMax | $9.99 | $69.99 yearly | Logging, strength and finger workouts free (listing text) |
| Pedestal | $12.99 | $79.99 yearly | Unverified |
| Crimpd | $12.99 | $29.99 quarterly, $59.99 yearly | Unverified |
| Fitbod | $12.99 and $15.99 | $79.99 and $95.99 yearly | Unverified |
| Boostcamp | $11.99 to $14.99 (periods unlabeled) | $59.99 to $79.99 | "free workout tracker" (listing text) |
| TrainingPeaks | $19.99 | $134.99 yearly | Unverified |
| Lattice | $29.99 (UK web £22.99) | $149.99 yearly | Unverified |
| MTNTOUGH | $29.99 | $239.99 yearly | Unverified |
| Capacity | $29.99 | $199.99 yearly | Unverified |
| Ladder | $29.99 (PRO, period unlabeled) | $179.99 annual PRO | 7-day trial, no credit card (ladder.fit) |
| JuggernautAI | $34.99 | None listed | Unverified |
| RP Hypertrophy | $34.99 | $299.99 yearly | Unverified |
| Uphill Athlete | Unverified | Unverified | n/a |

Reading: Phase Training's configured price is at the bottom of the table while its feature set (season periodization, coach, Watch) sits with the $12.99 to $35 group. Either the price is a chosen wedge or an unexamined default. That decision belongs to the product owner and is item 3 above.

## Changed since September (diff against GAP_ANALYSIS.md)

| September claim | Status at bb17ca1 | Evidence |
|---|---|---|
| "No Apple Watch app" (P0) | Closed. A watchOS target is embedded in the iOS app, with workout session, heart rate, rest timer and motion capture. Release signing profile is wired in the release workflow; whether the watch app has cleared App Store review is unverified. | `Project.yml:95,180`; `.github/workflows/release.yml:123-131`; `WatchWorkoutController.swift`; `MotionRecorder.swift` |
| "WatchSyncCoordinator skeleton, not built" | Superseded by shared sync types and a reducer | `Shared/WatchSync/WatchSyncEvent.swift`, `WatchSyncReducer.swift` |
| "No Live Activities / Dynamic Island" (P0) | Still open. The September doc listed it as "implied by RestTimerState"; no ActivityKit use exists | zero `ActivityKit` hits |
| "No widget" (P1) | Still open | zero `WidgetKit` hits |
| "Exercise library ~200 authored" | Stale. The catalog is 585 exercises, with four added in build 171 | `db/source/exercises.json` |
| "Exercise videos" (P1) | Still open; images only | `Resources/ExerciseImages` (2,108 webp) |
| "Free tier: none apparent" (P1) | Reframed. Coach is free by decision and nothing is gated yet; prices are set only in the StoreKit config | `CoachEntitlement.swift:9,41`; `PhaseTraining.storekit:23,48` |
| "Plate calculator not integrated into LogScreen flow" | Closed. Opens from a barbell set | `LogScreen.swift:205` |
| "RPE/RIR UI emphasis unclear" | Closed in substance. Logged RIR and RPE now steer the next weight, and RIR is saved (migration v5) | `ProgressionSuggestion.swift:20-23`; backlog Phase 4 |
| "Cardio logging UI missing" | Stale claim: `SportLogSheet.swift` exists. Depth of cardio logging not re-checked here | `Screens/SportLogSheet.swift` |
| "Training calendar heatmap missing" | Not re-verified in this pass | n/a |
| "Warmup calculator missing" | Not re-verified in this pass | n/a |
| Import "Fitbod/Strong/Hevy" parsers | Confirmed, plus CSV export | `WorkoutCSVImporter.swift:48`; `WorkoutCSVExporter.swift` |
| Ski variants "default inbounds for every skier" | Fixed in two steps: ski-mountaineering defaults to skimo, and a picker exists | `SportSeasonGenerator.swift:469-472`; `SkiDisciplineSheet.swift` |
| Climbing tools | New since September: hold timer on timed sets, max-hang test, loaded hangboard exercises | `HoldTimerSheet.swift`; `PhaseTrainingApp.swift:204` |
| Competitor list | Changes: Boostcamp now lists "11,000+ programs" and an AI coach with Live Activities (September doc said 14k+); Fitbod now lists $12.99 and $15.99 monthly, $79.99 and $95.99 yearly (September doc matched); MacroFactor Workouts and Dr. Muscle not re-checked. New entrants worth tracking: Pedestal (any-sport AI plans, wearables), ClimbMax (free logging plus adaptive climbing plan), Capacity (hybrid run plus lift), MTNTOUGH (mountain athlete content) | iTunes lookup, table above |
| September pricing advice ($9.99 monthly, $79.99 yearly) | Not adopted. The StoreKit config holds $2.99 and $24.99 | `PhaseTraining.storekit` |

## Summary of response order

1. Decide monetization and price (item 3), because it shapes what to gate.
2. Rest-timer Live Activity and a widget (item 2).
3. Readiness line and bounded bias from HRV and sleep (item 1), after the twin replay.
4. One more climbing assessment and grade logging (item 4).
5. Exercise motion assets (item 5) only after the above.
