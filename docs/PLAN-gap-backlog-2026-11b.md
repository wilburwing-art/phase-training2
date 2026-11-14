# Gap backlog, November 2026 (second round)

From the eight gap analyses run 2026-11-10 against commit bb17ca1 (build 171):
feature, signals, competitive, reach, screens, accessibility, generator eval and
coverage. Full reports with file:line evidence are in
`audits/2026-11-10-gap-round/`. The 20 items from the 2026-10-31 round
(`PLAN-gap-backlog-2026-11.md`) all held; none regressed.

Estimates come from the reports, which read the code. Generator and coverage
numbers were measured (a 4,958-week sweep and a full unit run: 1,739 tests, 0
failures, 28.4% line coverage, Data layer 85.8%).

## Phase 0: owner decisions (no code until settled)

- [x] **Coach in TestFlight (decided 2026-11-11: coach stays off until the app is ready).** `release.yml:61` defaults to beta, which blanks the gateway token, yet onboarding consent, the Profile coach toggle and `InsightGenerator` never check `CoachEntitlement.coachAvailable`. Testers enable a coach that cannot send. Decide whether testers get the coach; the guard in Phase 1 is right either way.
- [x] **Pricing and the paid line (decided 2026-11-13: the first store build ships without the coach and charges for Pro; Pro is the Support Sport editor and two-sport reflow at $2.99/mo and $24.99/yr with a one-week trial; flip `SupportEntitlement.proRequired` in the build that ships the App Store Connect products; prices are revisited when the coach returns behind Pro).** `proRequired = false` everywhere, product IDs are placeholders, StoreKit config says $2.99/mo and $24.99/yr. The AI and periodization apps list $12.99 to $34.99/mo. Decide what is paid before wiring products.
- [ ] **Physiology reader (decided 2026-11-13: the reader stays and belongs to the next-gen track, `PLAN-next-gen.md` step 1c; it is no part of the first store release. Still owed: the 2026-10-24 twin review outcome, which needs a backup export from the phone).** Nightly HRV, resting HR and sleep capture works end to end and nothing reads it. The 2026-10-24 twin review that gates the reader has no recorded outcome. Record it or set a new date. Competitors JuggernautAI, TrainHeroic and Pedestal all sell readiness adjustment.
- [x] **Dead or unwired logic (part decided 2026-11-12: delete `Planner.pickRoutine` and `Planner.applyFeedbackBias`, both deleted the same day with their private filter helpers and `CoachDatabase.requiredEquipmentSlugs(forRoutineId:)`; `AutoregulationEngine` was wired the day before in fc20b72, phase 4 item 5: `HistoryProfile` classifies each lift and `ProgressionSuggestion.regulated` eases or raises the suggested weight on the Log screen, with a test class for it. Decided 2026-11-13: keep it).** `Planner.pickRoutine` (0/79 lines) and `Planner.applyFeedbackBias` (a wrapper over the live `applyRecentSignalBias`) have no caller. `AutoregulationEngine` output lands only in notes no screen shows. Wire or delete each.
- [x] **Snowboarding (decided 2026-11-11, 1A in Phase 3b: snowboarding uses the ski rules).** "Snowboarding" and "Skiing / Snowboarding" are separate sports; only the second gets Discipline, Support sport and the season engine. Pick the intended behaviour.
- [x] **Deload suggestion (decided 2026-11-13: keep the automatic deload and label it, Phase 7).** Does the earlier no-auto-deload decision still stand? If so, a one-tap suggestion card after three build weeks is still open (6 to 8 h). The premise was out of date: `PlanArc` has applied a deload after three build weeks since 2026-09-10 (58fee2b) and shows nothing for it.

## Phase 1: quick fixes (one build, about 1.5 days)

- [x] Hide the onboarding coach consent step, the Profile coach row and `InsightGenerator.runIfDue` when `!coachAvailable` (1.5 h).
- [x] "Log all" on Log (`LogScreen.swift:408`, `:627`) marks every remaining set done with no confirm or undo, next to Finish, which confirms. Add an undo toast or a confirm above N sets (2 h).
- [x] Dashes, the class the last round missed:
  - 596 string fields in `db/source/*.json` (558 of 585 exercise descriptions), rebuild coach.db, add a `build_db.py` lint on U+2014 and U+2013 (3 h).
  - About 20 "—" empty-value placeholders in Swift; one shared constant (1.5 h).
  - `GoalMilestoneNotifier.swift:117` push copy (0.25 h).
  - Coach system prompt models em dashes and has no rule against them (0.5 h).
- [x] Contrast: heatmap day numbers 2.38:1 on level-1 cells (`ProgressScreen+Heatmap.swift:108-112`, 1 h); five sites dimming ink3 to 0.6 or 0.7 opacity, 2.6 to 3.2:1 (0.5 h).
- [x] Watch: labels on skip rest, set-complete toggle and the plus and minus 15 buttons; confirm on End session (1 h).
- [x] 44pt hit area on the 12pt trash buttons in the body-weight and body-composition logs and the 18x14 warmup pill (0.5 h).
- [x] Profile "Goals" and "Goal" rows share an icon (`ProfileScreen.swift:137`, `:190`); rename to "Performance goals" and "Training focus" (0.5 h).
- [x] Progress stat tiles stagger because labels wrap; VoiceOver reads "Prs" (0.75 h).
- [x] coach.db equipment mis-tags: Ab Wheel Rollout (id 7) and two sled pushes tagged bodyweight, so 743 bodyweight-plan rows prescribe an ab wheel (1 h).
- [x] Delete four views nothing presents: `TodayRecoveryCard`, `NotificationSettingsScreen`, `PlanDiffSheet`, `ExerciseSparkline`. `InsightCard` is also unshown; delete it or make the Today insight caption tappable into the coach (1 to 2 h).
- [x] Hide Profile "Subscription / Upgrade" while nothing is for sale (0.5 h).

## Done 2026-11-11 beyond the ticks

- Beginner climbing: four new routines in coach.db (three beginner, one intermediate no-campus), climbing movements gated by catalog level, routine selector filters by experience.
- Age 60+ lowers explosive volume and lengthens rest. Swapping jumps for lower-impact movements is not done.
- Four new catalog exercises for beginner pull progressions (dead hang, scapular pull-up, band-assisted and negative pull-ups) are not added: they need generated images.
- `build_db.py` now refuses a build with an em or en dash in user-visible catalog text.
- Log "Log all" asks for confirmation; the two UI tests that tap it were updated and not run (UI target takes about 60 minutes).

## Phase 2: safety net (tests only, about 2 days)

Comes before Phase 3 because Phase 3 changes the weights and exercises the app suggests.

- [x] Generator invariants, written to fail on today's code (the old sweep and invariant tests were deleted in 449bd8d):
  - catalog reps with a unit (sec, ft, per side) keep it in the plan;
  - beginner total sets <= intermediate <= advanced; age 70 <= age 32;
  - `estimatedMinutes` within budget + 5 and >= 0.6 x budget for 30 to 75;
  - every week has at least one rest day;
  - no advanced authored routine for a beginner, no repeated routine id in a week;
  - no power movement after an RPE 7+ movement.
  (4 h; folds the per-finding tests below into one suite.)
- [x] `SessionStore+GoalMetrics` (0 of 51 lines), which feeds every goal progress bar (2 h).
- [x] `PlanStore.regenerateToday` (21%) and refresh paths (3 h).
- [x] LLM plan refinement (16%): edited and logged days untouched, bad response leaves plan as is (4 h).
- [x] Phone-side Watch sync `apply` (24%): duplicate and out-of-order messages do not drop sets (4 h).
- [x] `BackupCoordinator.eraseAllData` empties every store and key; export then restore round trip (3 h).

## Phase 3: generator (changes suggested weights, about 3.5 days)

- [x] Season engine turns timed, hold and distance work into rep counts (Side Plank 10-15, Hollow Body Hold 3x6-10): 5,465 of 51,991 rows, and "per side" dropped on 14,299. Keep non-numeric catalog reps verbatim; the fix lived in the deleted legacy generator (3 h).
- [x] Authored climbing ignores experience: 59% of beginner sessions include campus or weighted pull work, one note reads "advanced only", and the same routine repeats in 81 of 122 two-session weeks. Filter by difficulty, rotate inside the week, add RPE (3 h).
- [x] Experience and age do not change prescription: intermediate and advanced identical in 1,374 of 1,440 pairs; ages 19, 45 and 68 byte-identical. Add experience and age modifiers in `SetScheme.modulated` (5 h).
- [x] Session budget: a 75-minute budget averages 28 minutes, a 30-minute ski budget gets 44 to 56. Recalibrate minutes per movement and let the budget lower the phase floor (3 h).
- [x] 5 and 6 lift-day requests give seven-day weeks with no rest (504 of 720, 648 of 720). Reserve one rest day (2 h).
- [x] Heaviest lift sits in the last two slots in 20 of 36 ski sessions. Sort by training order after picking (2 h).
- [x] Complement strength slots for gym users get knee push-ups and bodyweight lunges at RPE 7-8 (512 of 1,818 heavy-slot rows). Rank by loadability when equipment allows (3 h).
- [x] No progression inside a block: weeks 1 to 3 flat and the press exercise changes weekly. Fix anchor lifts per block, add a weekly ramp, one deload factor (4 h).
- [x] Weekly push floor: two-day skiers get zero pressing; climbers run push to pull at 1:2.5 (2 h).
- [x] Injury tags are thin for tennis elbow (4), stinger (5), finger pulley (6), hip flexor (10). Tagging pass plus clinical review (3 h plus review).

## Phase 3b: sports without their own rules (about 1.5 days, after Phase 4)

Found 2026-11-11 from an owner report: a snowboarder's "Upper body" days were
3 movements, 1 to 2 sets, about 14 minutes. Only the ski and climbing sports
have season rules. Every other plannable sport (snowboarding, mountain biking,
mountaineering, trail running, hiking, thru-hiking) resolves to
`skiing[.maintenance]` in every season (`PhaseRule.resolve`), a deload rule
capped at 45 minutes, and its complement days inherit it. Decisions made
2026-11-11: 1A and 2A below.

- [x] One sport-profile table that every per-sport decision reads: rules, signature demand, complement emphasis, two-sport eligibility. About ten places decide ski or climbing membership today (listed in `phase-training-season-generator-engine-pitfalls`), and two of them add snowboarding by hand.
- [x] 1A: snowboarding uses the ski rules, the same plan "Skiing / Snowboarding" gets.
- [x] 2A: a general season rule for the other authored-only sports' complement days (build off-season, hold pre-season, maintain in-season, deload only in a real deload week). Test: no non-deload week serves deload sets to any plannable sport.
- [x] Signature demands for the authored-only sports, so a session keeps the movement the sport needs most.
- [x] Complement emphasis for mountaineering (upper back and trunk with the legs).
- [x] Rebuild-role mismatch: CNS balance, the arc deload and skip-streak de-emphasis turn lift days into rest after generation, so a later rebuild assigns sport and complement roles from the wrong count. Move them to regenerate the week with the changed inputs, as the rest-day reserve now does.
- [x] Content: in-season routines for mountaineering, hiking-trekking and thru-hiking (0 today) and a pre-season routine for trail running (0 today). Done 2026-11-12: routines 310 to 317, two per cell, distilled from MTI In-Season Flex, Mountaineering & Hiking Prep and Ultra Running Pre-Season (`scripts/db/distill_inseason_outdoor.py`). The thru-hiking cell uses Flex sessions because 4 of the 7 blocks in the Thru Hike plan's strength day have no catalog exercise. `testEveryServedSportHasAServableRoutineInEveryPhase` holds every sport that serves written routines to its own phase pool. Alpine, ice, mixed and trad climbing have no routine in any phase and are built by the season engine, so the test leaves them out.

### Phase 3b content, the plan (decided 2026-11-12)

Problem: four sport and phase cells have no servable routine, so `AuthoredRoutineSelector` falls back to any phase. An in-season mountaineer gets base or pre-season volume in the weeks they also climb. Checked in coach.db 2026-11-12: mountaineering and thru-hiking have 0 `maintenance` routines; hiking-trekking has one (#81, goal `mobility`) that the full-session filter excludes; trail running has 0 `build` routines.

Owner decisions: distil from the MTI and Uphill Athlete archive (training-kb: "Mountain Athlete In-Season Flex", "Thru Hike Training Plan", "Mountaineering & Hiking Prep"), with the September credit line ("...; movement selection adapted by Phase Training (date)").

Done when:
- each of the four cells has 2 routines (8 total), so a two-lift week does not repeat one session;
- a test asserts every plannable sport has at least one servable routine in every phase;
- `AuthoredRoutineTests` passes and a generated in-season mountaineering week names the new routines.

Out of scope: new exercises (they need generated images), endurance or hike days, selector changes, thickening the existing routines.

Steps (about 4 to 5 h, an estimate made without reading the source sessions):
1. Pull the source sessions from training-kb and draft the 8 routines as a table. Stop for the owner's OK.
2. `scripts/db/distill_inseason_outdoor.py` on the `distill_mtb_preseason.py` template, catalog exercises only, `phase` = `maintenance` (in-season) or `build` (trail running pre-season), goal outside the excluded set, 25 minutes or longer.
3. `python3 scripts/db/build_db.py`; commit the JSON and both db copies together.
4. Coverage test, then `-only-testing:PhaseTrainingTests/AuthoredRoutineTests`.
5. Tick the box above.

## Phase 4: signals that do nothing (about 3 days)

- [x] Check-in pain is hard-coded false (`SorenessCheckInSheet.swift:211`), so four readers never fire. Add the toggle (2 h).
- [x] Swaps, favorites, dislikes and the PatternEngine "Stop planning it" accept reach only the season engine. Authored-routine days, which serve most sports, ignore them, and the user is told it was handled (5 h).
- [x] One-tap "How did it feel" reaches only coach text; the planner reads only the opt-in sheet. Map feel into the planner's difficulty signal (3 h).
- [x] Check-in energy (the only required field), time budget and equipment-changed have no plan effect. Wire energy to a one-day ease and time budget to today's regen, or make energy optional (5 h).
- [x] Post-workout hurt areas are joints; recovery reads muscle buckets. Map joints to buckets; delete the always-false `ranLong` (3 h).
- [x] Imported Hevy RPE does not reach progression, which the last backlog claimed it did (3 h).

## Phase 5: reach (about 1.5 days)

- [x] Generated warm-up ramp (40/60/80%) is dropped by `toWorkoutTemplate` and never shows in Log (5 to 7 h).
- [x] First body-weight and body-composition entry is Profile-only and the Progress cards hide until one exists. Add a prompt row on Progress (1.5 h).
- [x] Injuries are Profile-only with no prompt. Add "Injury or pain?" to the exercise action sheet and a setup checklist row (3 h).
- [x] Offer the weekly reminder after the first check-in or first completed session (2 h).

## Phase 6: features competitors ship (about 6 days)

- [x] Lock Screen rest timer (Live Activity). Strong, Hevy, JuggernautAI, Boostcamp and Lattice have one; Phase Training has a notification only (14 to 20 h). Done 2026-11-13: widget extension `PhaseTrainingWidgets` (`com.phasetraining.app.widgets`), written 2026-11-11 on a worktree branch and brought to main with two coordinator fixes (an expired rest kept losing its `finished` flag; a rest that had already run out could start a new activity). The Lock Screen and Dynamic Island show the workout, the exercise, "After set N of M" and the countdown, then "Rest done". Checked on the iPhone 17 Pro simulator with the phone locked: the countdown ran and turned to "Rest done" while the app was suspended. The "Rest's up" notification still fires as before. No Skip or +15 on the Lock Screen: rest state is LogScreen `@State`, which an App Intent cannot reach. A watch-marked set while the phone app is in the background updates an existing activity and cannot start one. Signing: `docs/HANDOFF-live-activity.md`; the profile secret was set 2026-11-12 and no tagged release has archived with it yet. Not checked: a physical device, the Dynamic Island views.
- [x] Today widget, in the same extension (6 h). Done 2026-11-13: `TodayWidget` in `PhaseTrainingWidgets`, small Home Screen and rectangular Lock Screen sizes. It shows the day's title, "N exercises · M sets" or "About N min", "Done" once a session is saved that day, and "No plan yet" when the week has no plan; a tap opens Today. The app writes a week snapshot (`TodayWidgetSnapshot`) to the new App Group `group.com.phasetraining.app` when the plan, the saved sessions or the abandoned list change, and the widget turns over at midnight from that snapshot without the app running. Checked on the iPhone 17 Pro simulator: the app wrote seven days to the group container. Not checked: the widget drawn on a Home Screen or Lock Screen, a physical device. A logged sport day does not read "Done" (sport logs are not saved sessions). Signing: both App Store profiles need the App Group before the next tag (`docs/HANDOFF-live-activity.md`).
- [x] Repeat a session and save it as a routine from History and Complete (4 to 5 h). Done 2026-11-12: Repeat and Save as routine on an expanded History row, Save as routine on Complete. Native sessions only. Repeat is hidden in the exercise drill-in History, which sits on another sheet.
- [x] Superset with next, from Log and the day preview (3 h). Done 2026-11-12: Log has it on the exercise long-press menu, the day preview on `ExerciseActionSheet` ("Superset with <next>" and "Remove from superset", both through `SupersetEditing`). In the preview the group now survives an edit, a replace and Save to library. Today's own exercise list does not offer it.
- [x] History search and tag filter (3 to 4 h). Done 2026-11-12: search over session name, exercise names, notes, tag labels and month or year; chips for the tags that occur.
- [ ] "Last exported" on the Data row plus a nudge, then a weekly iCloud Drive write (3 h, then 8 h). First half done 2026-11-12: the Profile Data row reads "Never exported", "Exported Nov 3", or "N workouts not backed up" in the accent colour at 10 or more since the last export (`BackupStatus`). The date is stamped when the share sheet reports a finished activity, so a cancelled share and the CSV export leave it alone. The iCloud Drive write is open and needs the owner call on the container entitlement.
- [x] Custom exercises in `user.db`, never picked by the generator (10 to 14 h). Done 2026-11-13: `user_exercises` table, `user.db` v11. The picker offers Create when a search finds nothing or nothing exact; a custom exercise logs with a weight field, shows in History, can be deleted from its detail sheet, and travels in the backup (envelope v3, which older builds refuse). Names that match a catalog name or alias are refused and there is no rename, because history and PRs are keyed by name. `CoachDatabase` stays catalog-only; `test_customExercisesNeverAppearInGeneratedWeeks` sweeps every plannable sport. The import-match picker leaves custom exercises out. Also in this change: `CoachDatabase` reads log SQLite errors under `[coach-db]` and an import index that builds empty is rebuilt on the next call. The intermittent empty catalog read in the test host (5 failures in one pass on 2026-11-13) did not recur in 24 later invocations, so its cause is still unnamed.
- [x] Set types: drop and failure alongside warmup (8 to 10 h). Done 2026-11-12 (6fdba29): `LoggedSet.setType`, `user.db` v10. Failure sets count toward PRs and e1RM, drop sets do not; both count toward volume. The watch shows the type and cannot change it. The `isWarmup` key is still written to session JSON for older watch and phone builds. Imported Hevy and Strong drop sets still feed imported PR baselines. The Log menu, History edit pill and watch caption were not checked in the simulator.

### Phase 6, what is left and in what order (planned 2026-11-12)

1. Done 2026-11-12. **Superset in the day preview** (1 h). Two rows in `ExerciseActionSheet`, calling `SupersetEditing` on the template's exercises. Done when a pair made in the preview starts in Log as A1 and A2.
2. Done 2026-11-12 except the iCloud write. **"Last exported" on the Data row** (3 h). Store the export date when `BackupCoordinator` hands the envelope to the share sheet; show it on the Profile Data row; nudge after 10 new sessions since the last export. Done when the row reads a date after an export and "Never" before one. The weekly iCloud Drive write (8 h) is a second step and needs an owner call on the iCloud container entitlement.
3. Done 2026-11-12. **Set types** (8 to 10 h). Replace `LoggedSet.isWarmup` with a `setType` (normal, warmup, drop, failure) decoded tolerantly from old payloads, a `user.db` migration, and the watch payload, which shares `Shared/Models/SessionModels.swift`. Decided 2026-11-12: drop sets do not count toward PRs.
4. Done 2026-11-13. **Custom exercises** (10 to 14 h). A `user_exercises` table merged into picker results only. Done when a custom exercise can be added from the picker's empty state, logged, shown in History and exported, and a generator sweep never picks one.
5. Done 2026-11-13, Today widget included. **Lock Screen rest timer** (14 to 20 h, then 6 for a Today widget). Last because it is the only item that adds a target: a widget extension in `Project.yml`, an App ID and provisioning profile in the portal, and a new profile secret in `release.yml`, the same portal work the watch target needed. Simulators show Live Activities, so the build can be checked before the portal step.

Items 1 and 2 fit one build (172) with the three finished today, the two planner deletions and the Phase 3b content. Items 3 and 4 both change `user.db` and should not land in the same build as each other.

## Phase 7: label the automatic deload (decided 2026-11-13, done 2026-11-13)

- [x] Show the arc deload and let the lifter decline it (3 to 4 h, an estimate made without reading the Week tab code). Done 2026-11-13: the week's answer is stored as `WeekOverrides.arcDeload` (`applied` or `declined`) and resolved with the tone by `PlanArc.resolve`. Today's eyebrow reads DELOAD for an arc deload week, and the Week tab shows "Three hard weeks in a row, so this week is lighter" with a "Train normally" button (VoiceOver: "Train normally this week") that regenerates the week at full volume. A declined deload does not start the cooldown, so the arc offers it again the next week while the streak holds. Tone rules: Build suspends the arc and the cooldown; Recovery counts as the deload and the arc no longer cuts sets a second time (it used to stack to about 0.49). Three faults in the old marker are fixed with it: a deload week went back to full volume on any second generate that week, a lifter with 2 lift days got a deload every week because the marker was only written when a "Recovery" rest day existed, and that check also matched the CNS budget's "Recovery" days (`isDeloadPlan`, deleted). `refreshForCurrentWeek` now clears last week's overrides when the app stays open across Monday; before, last week's tone carried over until a relaunch. Checked: 152 unit tests in nine classes, `ArcDeloadNoticeUITests` on the iPhone 17 Pro simulator (notice, all seven rows hittable at 49.5pt against a 48pt floor with two validation banners also showing, decline removes the notice and DELOAD). Not done: a week already in a deload when this build lands is not labelled; a week staged by the weekly check-in is planned with no arc, and the arc is first evaluated on that week's next regenerate, which can then turn it into a deload; no undo for a decline (the Recovery tone is the way back). How often the arc fires for real users is still not measured. Briefs: `docs/briefs/arc-deload-label.md` and its two follow-ups.

Problem: after three build weeks in a row (`PlanArc.buildWeeksBeforeDeload`, four-week cooldown), `Planner.generate` turns one lift day into a rest day titled "Recovery" and cuts sets on the other lift days (`demoteForDeload`, `scaleForDeload`). No screen says so. `PlanArc.swift` cites `PLAN-weekly-coach.md` section 6.1, "invisible to the user"; this decision replaces that. The Today eyebrow shows DELOAD only for a user-picked Recovery tone (`TodayScreen+Derived.swift`, `phaseEyebrow`).

Done when:
- a week generated with `arcSignal == .deload` shows DELOAD in the Today eyebrow, as a Recovery-tone week does;
- the Week tab carries one line with the reason ("Three hard weeks in a row, so this week is lighter") and a "Train normally this week" action;
- that action regenerates the week without the deload, the choice survives later regens of the same week, and the four-week cooldown is not started by a declined deload;
- a test covers each of the three, and the existing `PlanArc` tests pass.

Design points to settle in the brief:
- Where the "this week is an arc deload" fact is stored. Today it is inferred from a rest day titled "Recovery" (`PlanStore.isDeloadPlan`) and a `lastDeloadWeekKey` timestamp. The decline needs a per-week flag, most likely on `WeekOverrides`, which already holds `weekTone`.
- What happens when the lifter has picked the Build tone for a week the arc wants to deload. Not checked.
- How often the arc fires for real users. Not measured.

Out of scope: a "week N of M" counter, changing the three-week rule or the cooldown, readiness or RPE as extra triggers.

Also in the same change: correct the `phaseEyebrow` comment and the `phase-training-periodization-model-no-auto-deload` skill, both of which say no automatic deload exists.

Load before starting: `phase-training-planstore-mutation-seams-and-week-caps`, `phase-training-overrides-persist-intent-not-output`, `phase-training-tab-time-horizon-rule`.

## Later, not scheduled

- Closed 2026-11-13, no code change: 21 more tap targets under 44pt; one shared modifier (3 h). Measured on the iPhone 17 Pro simulator, iOS 26.4: the unmodified 28pt discard button on Log took taps up to 28pt from its centre on the left and below and missed from 32pt, and the unmodified 32pt play button on a Library saved-workout row took a tap 4pt above its circle and started the workout, with the row's own tap not firing. A `tapTarget` modifier was built on all 21 sites and a UI test passed the same with and without it at both sites, so it was discarded. iOS 17 and 18 were not measured. Design and the two test recipes: `docs/briefs/tap-targets.md`, `docs/briefs/tap-targets-followup.md`.
- Done 2026-11-13: Reduce Motion: 2 of 28 animation sites respect it, and the rest dot pulses forever (2 h). Every `withAnimation`, `.animation` and slide or scale `.transition` in the app target now goes through `Components/Motion.swift` (`withMotion`, `.motion`, `Motion.transition`), which tags each site `fade` or `movement`. With the setting on: the rest dot holds at full opacity, exercise thumbnails and the detail hero hold the start frame (a second endless loop the audit did not count), slides and scales become a crossfade, and expands, progress bars, the chevron, the coach press spring and the chat scroll land at once. Short opacity and colour fades stay. With the setting off nothing changes. The launch argument `--ui-test-reduce-motion` forces the reduced path. Checked: `MotionTests` (3) and `OnboardingGoalUITests` (1) on the iPhone 17 Pro simulator. Not checked: any screen viewed with the setting on, on a simulator or a device. The watch and widget targets have no animation. Briefs: `docs/briefs/reduce-motion.md` and its follow-up.
- Dynamic Type: 4 fixed-size text sites (2 h), 173 fixed-size icons (6 h).
- Chart accessibility labels and descriptors (2 h); `lineStrong` border token for inputs (2 h).
- Screen polish from `screens.md`: Week header stack, Library muscle icons, Profile 23-row list, Log tab bar under the music card.
- Health write-back for body weight and fat (4 h); progress photos (10 to 12 h); climbing grade and attempts plus a second assessment (10 to 14 h).
- iPad, localization, named program library: recorded ceilings.

## Corrections to the reports

- Coverage and signals disagreed on feedback bias. Both were right: `applyFeedbackBias` (`Planner.swift:304`) has no caller, while the function it wraps, `applyRecentSignalBias`, is live at `Planner.swift:61`.
- `competitive.md` lag 5 says demos are stills only. 579 of 585 exercises carry a `video_url` and the detail sheet shows "Watch demo" (`ExerciseDetailSheet.swift:302`). The gap is in-app playback, which is lower priority than the report ranks it.
- `competitive.md` marks Uphill Athlete pricing unverified. A sub-agent read it verbatim on 2026-11-10: "Buy now for $69" for the 12-week Grand Traverse ski plan, plans sold through TrainingPeaks. Uphill Athlete is also a content licensor (commit 36713d8).
- The root-level `GAP_ANALYSIS.md` and `FUNCTIONAL_GAP_ANALYSIS.md` describe commit 46b5a4d (2026-09-10) and are superseded by this round.
