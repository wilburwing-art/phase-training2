# Screen critique, 2026-11-10

Commit bb17ca1 (build 171), main. Method: built the app into `/tmp/claude-501/dd-screens` on a dedicated simulator (iPhone 17 Pro, 402x874 pt) and captured real screens. Screens 01-07 come from the existing `StoreScreenshotUITests` run unmodified (`--seed-plan-demo`, `--seed-supersets-demo`, `--seed-progress-demo`). Profile (08) and Onboarding landing (09) came from `simctl launch` plus one tap. Stopped clicking when iTerm became frontmost. History, Coach, onboarding steps 2+, and Watch are code-only (no screenshot). Screenshots are in `audits/2026-11-10-gap-round/screens/`. The seeded plan shows 7 lift days and a "7 hard days in a row" banner; that is a seed artifact and is not reported.

Stale-context items not re-raised: the soreness check-in being unreachable (now reachable from Progress, `SorenessCheckInPill` at `ProgressScreen.swift:151`, test exists).

## Today (01-today.png)

1. **Em dash in 558 of 585 exercise descriptions shown in the detail sheet.** Evidence: `db/source/exercises.json` has 596 string fields with an em or en dash (558 `description`, 20 `time_efficient_variation`, 10 `instructions`, 5 `age_considerations`); `05-exercise-detail.png` shows "Anti-extension core work — bridges strength..." under Overview. Also `routines.json` (35 descriptions, 29 notes, 4 names), `exercise_substitutions.json` (281 notes), `sport_recovery_profiles.json` (61 notes). Effect: breaks the no-dash copy rule on the most-read text in the app. Fix: scripted replace in the source JSON (comma, colon or period by context, reviewed), rebuild `coach.db` per the add-exercise recipe, add a lint in `build_db.py` that fails on U+2014 and U+2013 in user-visible columns. Effort: 3 h (script 1, review 1.5, lint 0.5).
2. **Em dash in the goal-reached push notification.** `Data/GoalMilestoneNotifier.swift:117`: `"\(goal.templateId.label) — you did it."`. Fix: "Squat 315: you did it." Effort: 0.25 h.
3. **Dedicated duplicate accessibility label.** `TodayScreen.swift:~428-429` sets `.accessibilityLabel` twice on `coachPolishedBadge`; the first ("Coach adjusted today's workout, tap for why") is dead, the second wins. Effect: copy drift risk, no user harm. Fix: delete one. Effort: 0.1 h.
4. **CTA stack covers the fifth row and the Freestyle chip sits tight against the tab bar.** In 01-today.png the Start button (y 1537-1653 of 2000) overlaps the fourth exercise row and Freestyle floats between CTA and tab bar with about 50 px clearance. This is the intended floating layout and scroll inset is 210 pt (`TodayScreen.swift:~172`), so the last row is reachable; no change recommended except to verify the last row clears the CTA at max Dynamic Type. Effort: 0.5 h to check.

## Log (06-log.png)

1. **Three overlapping "log everything" controls.** Header "Log all" (`LogScreen.swift:408`), per-exercise "Log all sets" (visible under each block), and "Finish" next to them. `logAllSetsAllExercises` (`LogScreen.swift:627`) marks every remaining set done at planned values with no confirmation or undo, while Finish and Cancel both confirm. Effect: one mis-tap writes untrained sets as done, and it sits directly left of Finish. Fix: either confirm when more than N sets remain, or offer an undo toast that restores the prior `done` flags. Effort: 2 h.
2. **Tab bar stays on screen during a workout and the Now Playing card stacks on top of it.** In 06-log.png the music card (y 1665-1790) overlaps set rows and sits directly above the tab bar, leaving two stacked floating layers over the logging inputs. Fix: hide the tab bar while `store.active != nil` on Log, or give the scroll view a bottom inset equal to card plus bar. Effort: 2 h.
3. **Two exits plus a header close.** X (`log-cancel`), "Stop early" (`LogScreen.swift:513`), Finish. The distinction (cancel discards, stop early abandons with a reason, finish saves) is not explained in the UI. Fix: one-line subtitles in the confirm sheets. Effort: 1 h.
4. **LAST column is a single dash for every row in the seed.** Fine for a first session; real data not verified here.

## Week / Plan (02-week.png)

1. **Four stacked info layers before the first day row.** Title, "7 lift", Set tone, Plan next week, "Assumed" chips, two issue banners, "+2 more". The first day row starts at y 833 of 2000; the Today row is below 40% of the screen. Effect: the week itself is the content and is pushed down. Fix: collapse "Assumed" chips into the banner area after the first week, or move "Plan next week" into the header menu. Effort: 3 h.
2. **Assumed chip row is clipped at the right edge.** "Beginner" is cut at x 884 with no fade or scroll hint (`02-week.png`). Fix: add a trailing fade or wrap. Effort: 0.5 h.
3. **"+2 more" is a bare mono label with no chevron.** Reads as static text. Fix: add chevron and 44 pt target. Effort: 0.25 h.
4. **Day rows show only kind badge and title.** "Push day" seven times gives no way to tell sessions apart without tapping (duration, exercise count, focus are absent). Fix: add a second line from `DayPlan` (exercise count, minutes). Effort: 2 h.

## Library (03, 04, 05)

(Library is not in the requested list; included because it is a tab.)

1. **Muscle tile icons mislead.** Chest uses a side-bending stretch figure, Back a lunging runner, Quads a sprinter (03-library.png). Fix: use muscle silhouettes already in the app (the Today rows carry highlighted-muscle thumbnails). Effort: 3 h.
2. **Tile grid rows are misaligned by a few px.** Chest vs Back tops differ (y 665 vs 668), Shoulders vs Arms tops differ by about 12 px (947 vs 958). Cause is intrinsic icon height per tile. Fix: fixed icon frame. Effort: 0.5 h.

## Progress (07-progress.png)

1. **Stat strip cells are unequal in height.** "THIS WEEK" and "PRs · 30d" labels wrap to two lines at four columns, so those tiles are taller and the row top edges stagger (1691, 1706, 1691, 1706 in the screenshot). Evidence: `Progress/ProgressScreen+StatCards.swift:20-31, 35-45`; no fixed height or `lineLimit`. Fix: `lineLimit(1)` with shorter labels ("WEEK", "PRs 30d") and `.frame(maxHeight: .infinity)` on the cell. Effort: 0.5 h.
2. **VoiceOver reads "Prs · 30d".** `label.capitalized` (`ProgressScreen+StatCards.swift:~68`) turns "PRs" into "Prs". Fix: pass an explicit accessibility string per cell. Effort: 0.25 h.
3. **The calendar takes about 40% of first screen height before any stat.** The numbers (week, streak, PRs, total) are below the fold at 1691+. Fix: move the stat strip above the calendar. Effort: 1 h.
4. **Soreness row copy is a question in tracked caps** ("HOW SORE ARE YOU TODAY?"), consistent with other rows; fine.

## History (code only)

1. **Custom "‹ Back" on a sheet.** `HistoryScreen.swift:~72` draws a text Back button in a view presented with `.sheet` (`ProgressScreen.swift:206`, also from Today `264`, `CoachRequestScreen.swift:141`, `DayWorkoutPreviewSheet.swift:131`). A sheet is dismissed, not navigated; the ASCII "‹" has no accessibility label of "Back" semantics beyond the text, and there is no drag-indicator guidance. Fix: use a toolbar Done, matching `ExerciseDetailSheet`. Effort: 1 h.
2. **Title duplicated.** Top bar says "History" and the content header says "Past sessions" (`HistoryScreen.swift:~114`). Effort: 0.25 h.

## Profile (08-profile.png)

1. **"Goals" and "Goal" are two rows with the same target icon.** `ProfileScreen.swift:137` "Goals" (value "None") and `:190` "Goal" (value "Sport performance"). Screenshot shows both. Effect: a user cannot tell which one drives the plan. Fix: rename to "Performance goals" and "Training focus", distinct icons. Effort: 0.5 h.
2. **About 23 rows in one scroll under Training Setup.** "Plan setup", "Session length", "Lift days" and "Equipment" duplicate the Recommended block above and the Plan setup checklist (`ProfileScreen.swift:125-190`). Fix: group into Plan, Body, Exercises, App; fold session length, lift days, equipment into Plan setup. Effort: 4 h.
3. **"Recommended for you" is the first block, above settings.** It is advice about settings the user has already set, all showing green ticks. Effect: first screen of Profile is a no-op. Fix: show only when a value mismatches. Effort: 1 h.
4. **DEBUG rows are `#if DEBUG`** (`ProfileScreen.swift:261`), so not shipped; fine.

## Onboarding (09-onboarding-1.png, code for later steps)

1. **Disclaimer text is dim grey on near-black at 13-14 pt.** The medical disclaimer is the lowest contrast text on the landing screen. Not measured; verify with a contrast check. Effort: 0.5 h.
2. **Empty-value glyph.** Many fields use a bare "—" placeholder (`AboutYouEditorSheet.swift:128`, `BodyMetricsEditor.swift:121,137,157,193`, `ProfileScreen.swift:488`, `LogSetRow.swift:21,78,165,252`, `ExerciseTile.swift:209`, `CompleteScreen.swift:221,331`, `HistoryScreen.swift:198,373`, `ProgressRecoverySection.swift:39`, `BodyMetrics.swift:52,81`). These are user-visible em dashes (Log screenshot shows "—" in LAST and effort cells). Fix: one shared `Placeholder.empty` constant using a hyphen or "none", replace all. Effort: 1.5 h.
3. Step counter ("STEP n OF N", `OnboardingFlow.swift:296`) and a "Three quick questions" promise on landing are consistent; not verified past step 1.

## Coach (code only)

1. **System prompt teaches the model em dashes.** `Coach/CoachSystemPrompt.swift` contains 12 em dashes and its examples ("Glad the move stuck"; "Got it — no swap", line 54) model the habit; there is no instruction against dashes. Effect: coach replies the user reads will contain em dashes. Fix: add a style rule and rewrite the examples. Effort: 0.5 h.
2. **Coach drawer is nearly unlabeled.** Two `accessibilityLabel`s in `CoachDrawer.swift` (lines 112, 256) against icon-only buttons at 82, 92, 141, 618. Fix: label history, clear, and the proposal-apply arrow button. Effort: 1 h.
3. **User-facing em dash in the preview copy** (`CoachDrawer.swift:547`) is preview-only; not shipped.

## Watch (code only)

1. **Icon-only controls have no labels.** The done circle (`PhaseTrainingWatchApp.swift:~129`) and rest skip button (`~108`) expose SF symbol names to VoiceOver ("circle", "forward.fill"). Fix: labels "Mark set 2 done" and "Skip rest". Effort: 0.5 h.
2. **"End session" has no confirm** (`PhaseTrainingWatchApp.swift:~55`, `WatchSessionModel.swift:112`). It stops the workout, sends `sessionEnded` and clears state, destructive role but one tap away at the bottom of a scrolling List. Fix: `confirmationDialog`. Effort: 0.5 h.
3. **No jump to the next undone set.** The List opens at the top with "Start on watch" first; with 5 exercises the current set is off screen. Fix: `ScrollViewReader` to the first undone set. Effort: 2 h.
4. **"Reading..." uses three ASCII dots**; fine, mentioned for the copy sweep only.

## Cross-cutting

- Dashes: DB text (596 fields), 20+ UI placeholder sites, one notification, coach prompt. One lint over `db/source/*.json` and `PhaseTraining/**/*.swift` string literals would close the class.
- Floating layers (tab bar, CTA, now playing) overlay scrollable content on Today and Log with no consistent inset.

## Ranked summary

1. DB copy dashes (3 h), 2. Log-all without confirm (2 h), 3. Profile Goal/Goals duplication plus 23-row list (4.5 h), 4. Progress stat strip alignment (0.5 h), 5. Coach prompt dash rule (0.5 h), 6. Watch labels and End confirm (1 h).

## Checked and fine

- Onboarding landing layout, mascot, CTA contrast (09).
- Library search and Exercises/Workouts segment (03).
- Exercise detail hierarchy and muscle chips (05).
- Soreness check-in reachability (Progress pill present).
- Debug rows gated by `#if DEBUG`.
- Calendar heatmap legend and selected-day outline (07).
- Finish and Cancel on Log both confirm (`LogScreen.swift:~50`).

## Not covered

History, Coach drawer, onboarding steps 2+, Watch, paywall: no screenshots. The dedicated simulator `critique-screens` (UDID in `/tmp/claude-501/screens-udid`) is left booted because delete was denied.
