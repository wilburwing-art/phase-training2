# Reach gap analysis

Date: 2026-11-10. Commit: bb17ca1 (build 171). Analyst: gap-reach.
Method: listed all 152 `struct ... : View` types under PhaseTraining/ and counted non-preview, non-comment references to each (any type with 0 or 1 references was opened and its single call site read). Traced every `.sheet`, `.fullScreenCover`, `NavigationLink` and `navigationDestination` in the five tabs, Log, Complete and Profile. Read every `#if DEBUG` site, the Coach entitlement chain, the release workflow and the Watch app. Read-only; no code was run, so tap counts are from reading the view code, not from a device.

Tab model (RootTabView.swift:55-76): five tabs, Today, Week, Library, Progress, Profile. Tap counts below are from cold launch on an onboarded install and count the tab tap.

## Findings, ranked by impact

### 1. Every TestFlight build offers the AI coach and none of it works

Evidence:
- `.github/workflows/release.yml:61` sets `PHASETRAINING_BETA: ${{ vars.PHASETRAINING_BETA || '1' }}`, and `scripts/generate-coach-secrets.sh:64` blanks the gateway token when it is 1. The default is beta.
- `CoachEntitlement.coachAvailable` is `!CoachSecrets.gatewayToken.isEmpty` (Coach/CoachEntitlement.swift:53). It is consulted only inside `CoachEntitlement.unlocked`, which gates CoachBubble (CoachBubble.swift:72), CoachRequestScreen (:36), CompleteScreen (:540), TodayScreen (:422) and the insight caption (TodayScreen+Derived.swift:95).
- Three surfaces never ask: `OnboardingCoachConsentScreen` (Onboarding/OnboardingCoachConsentScreen.swift:34-60, title "Want a coach in your pocket?", "Enable AI Coach"), `CoachSettingsRow` (Coach/CoachSettingsRow.swift:25-37, 98-111, subtitle "On. Chat reaches Claude via our proxy"), and `InsightGenerator.runIfDue` (Coach/InsightGenerator.swift:37, which builds a full CoachContext snapshot and then `CoachClient.send` throws at CoachClient.swift:96).

Effect: A tester is asked during onboarding whether to enable a coach, says yes, and gets no bubble, no "Ask coach", no polished explanation, and no message. Profile shows the toggle on with a subtitle claiming chat works. Consent to send health-adjacent data is recorded for a feature that cannot send anything. Testers cannot report the missing coach as a bug because the app told them it was on.

Fix: Hide the onboarding consent step (skip it in `advance()` the way `healthAvailable` already does, OnboardingFlow.swift:172) and hide or disable `CoachSettingsRow` with "Not in this build" when `!CoachEntitlement.coachAvailable`. Add the same guard at the top of `InsightGenerator.runIfDue`. Separately, decide whether beta testers should ever get the coach; the workflow comment (release.yml:55-60) says that waits on gateway rate and spend limits (T0-1 in audits/2026-08-23-backlog.md).
Effort: 1.5 h.

### 2. First body-weight and body-composition entry is reachable only from Profile, and the Progress cards that would show it stay hidden until it exists

Evidence:
- `bodyWeightTrendCard` returns `EmptyView()` when the log is empty (Progress/ProgressScreen+BodyCards.swift:23-25, comment :19-20 says "Hidden entirely when the user has never logged a weight"). The composition card has the same gate (:93-100).
- The only presenters of `BodyWeightLogSheet` and `BodyCompositionLogSheet` outside those hidden cards are the two rows in Profile ABOUT YOU (ProfileScreen.swift:132-141, :357-360). No Today, Log, Complete or Week surface presents either.

Effect: A user who opens Progress to look at body trends sees no sign the feature exists. First entry costs Profile tab, Body weight row, field, save (4 taps plus typing). The Progress tab is where the 12-week trend reads, so by the app's own rule (phase-training-tab-time-horizon-rule: a thing's natural horizon decides its tab) the entry point belongs there. Profile keeps the row as a second door.
`HealthImportsScreen` has a body-metrics sync section (Screens/HealthImports/BodyMetricsSyncSection.swift), but it is also Profile-only (ProfileScreen.swift:351), so a Health-connected user also has to find Profile first.

Fix: When the log is empty, render a one-line "Log body weight" prompt row at the bottom of Progress (same presenter, no new sheet). Do the same for composition, or fold both into one "Body" prompt. Do not add anything to Today.
Effort: 1.5 h.

### 3. Injuries are reachable only from Profile, and nothing prompts for them anywhere

Evidence:
- `InjuriesEditorSheet` has one presenter, ProfileScreen.swift:324 (row at :179-182, Profile tab, ADJUSTMENTS, 3 taps to the picker).
- The onboarding gate was cut to sport and season, so it no longer asks (OnboardingFlow.swift:99-101 only restores a saved draft; the Welcome screen only warns, OnboardingWelcomeScreen.swift:41).
- `ProfileField` offers five assumption chips: equipment, experience, availability, goal, history (PlanAssumptionsRow.swift:104-109). Injuries are not one, and neither the setup checklist nor the weekly check-in screens mention them (grep for injur/pain/sore in Screens/WeeklyCheckIn returns nothing).
- Soreness check-in (SorenessCheckInPill, Progress only, ProgressScreen.swift:151,184) records pain flags for 24 hours; it does not lead to the injury editor.

Effect: The injury filter is a safety property (AuthoredRoutine.swift comment: "InjuriesEditorSheet promises We'll filter out exercises that aren't safe"). A new user with a bad shoulder gets a plan with no filter and no prompt to set one, and the place they feel it (an exercise in Log, the post-workout feedback sheet) has no "this hurts" route. The exercise action sheet already has "Don't recommend again" (Components/ExerciseActionSheet.swift:108) so the pattern exists for dislikes.

Fix: Add an "Injury or pain?" row to ExerciseActionSheet that opens `InjuriesEditorSheet`, and an Injuries assumption chip or checklist row (SetupChecklistSheet) shown while `userInjuries` is unstated.
Effort: 3 h.

### 4. Four finished views have no production presenter

| View | Evidence | Note |
|---|---|---|
| `InsightCard` | Only references are its own previews (Components/InsightCard.swift:113-118) and comments (InsightGenerator.swift:14, CoachInsight.swift:8-10, CoachConversationStore.swift:8). | InsightGenerator makes a billed model call per day and the result is shown as the Today hero caption (TodayScreen+Derived.swift:96-98), not through InsightCard. The "tap the insight to open the coach with the text prefilled" behaviour the comments promise does not exist. |
| `TodayRecoveryCard` | Preview only (Components/TodayRecoveryCard.swift:71). | Removed from Today 2026-08-29 per the tab rule; recovery lives in `ProgressRecoverySection` (ProgressScreen.swift:194). Safe to delete. |
| `NotificationSettingsScreen` | Preview only (Screens/NotificationSettingsScreen.swift:60). | Replaced by `RemindersEditorSheet` (ProfileScreen.swift:327). Delete. |
| `PlanDiffSheet` | Preview only (Components/PlanDiffSheet.swift:219); named in a comment at Data/PlanEdit.swift:4. | Coach diffs go through `MiniPlanDiffCard` in the drawer (CoachDrawer.swift:211). Delete or wire. |
| `ExerciseSparkline` | Zero references; the Progress tiles use `SparklineView` (Components/ExerciseTile.swift:219). | Defined at Progress/ProgressCharts.swift:113. Delete. |

Effect: About 600 lines of dead UI that still compile, still get audited, and mislead anyone reading comments. The InsightCard row also hides a behaviour gap: users cannot tap a coach insight to discuss it.
Fix: Delete the four dead views (user rule: remove obsolete code immediately). For the insight, either make the hero caption tappable (open `conv.present(withPrefill:)`) or correct the comments.
Effort: 1 h to delete, 1 h more for the tappable caption.

### 5. Snowboarders who pick "Snowboarding" miss the ski-tier Profile rows and season engine

Evidence:
- The sport catalog lists "Skiing / Snowboarding" (`snow-sports`) and a separate "Snowboarding" (`snowboarding`) (Data/TrainingMemory.swift:528,531). Both pass `isPlannable`: snow-sports through the season engine, snowboarding through the outdoor authored list (AuthoredRoutine.swift:146-148).
- The Support sport row and the Discipline row key on `PhaseRule.skiSlugs` (ProfileScreen.swift:154-156, `skisPrimary` at TrainingMemory.swift:949), and `skiSlugs` excludes `snowboarding` (PhaseRule.swift:78). Yet the Progress ski cards key on `skis`, which includes `snowboarding` (SkiReadinessTest.swift:89-90).

Effect: The two entries look equivalent in the picker but one gets Discipline, Support sport and the season-engine plan, and the other gets ski cards on Progress and none of that. This is an unstated gate, and the picker gives no hint.
Fix: Confirm with the owner which behaviour is intended. If the authored path is meant to be lighter, label the row "Snowboarding (basic plan)"; if not, add `snowboarding` to `skisPrimary` and the support gate.
Effort: 1 h to label, 3 h to widen (needs a generator check).

### 6. Subscription row leads to an empty paywall while nothing is for sale

Evidence: Profile APP always shows "Subscription / Upgrade" (ProfileScreen.swift:223-226, ProfileScreen+RowSummaries.swift:160). Both gates are held open (`CoachEntitlement.proRequired = false`, Coach/CoachEntitlement.swift:36; `SupportEntitlement.proRequired = false`, SupportEntitlement.swift:31). With no App Store Connect products `PaywallView` renders its "not configured" state (PaywallView.swift:109-111). I could not verify whether the products exist; SubscriptionStore.swift:28 still carries a TODO to replace the IDs.
Effect: If the products are not live, a tester taps "Upgrade" and lands on a dead end. If they are live, the paywall sells Pro with no feature behind it.
Fix: Hide the row until `proRequired` flips or `products` is non-empty.
Effort: 0.5 h.

### 7. Sport restriction in onboarding blocks a pure strength lifter

Evidence: Onboarding and the Profile editor show only `isPlannable` sports (OnboardingSportsScreen.swift:31, SportsEditorSheet.swift:24), the Next button needs at least one sport (:15), and `migrateToSupportedSportGate` sends an existing user back to onboarding if their primary sport is not plannable (MemoryStore.swift:79-89). The plannable list is ski, climbing and six outdoor sports (AuthoredRoutine.swift:146-148, SportSeasonGenerator.swift:459-461).
Effect: A user whose sport is lifting, running on roads, or none cannot finish onboarding at all. That is an intentional narrowing (comment: "Ski/climb narrowing"), so this is a decision to confirm rather than a bug: the question is what the store listing says. Flagged because it is the largest gate in the app.
Fix: None unless the product widens. Make sure the listing and the first onboarding screen say who the app is for.
Effort: 0.5 h (copy only).

### 8. Weekly check-in has one in-app door and its reminder is opt-in

Evidence: `showWeeklyCheckIn` is set from the Week "Plan next week" chip (WeekScreen.swift:246-249) and the `plan-week` deep link (PhaseTrainingApp.swift:835) only. The chip is permanent (comment :241-245), so reach is fine: Week tab, chip, 2 taps. The deep link needs the weekly reminder, which asks for notification permission from the Reminders editor (WeeklyReminderScheduler.swift:45) reachable only from Profile (ProfileScreen.swift:327).
Effect: A new user sees the check-in only if they open Week and notice a chip. The retention loop depends on a reminder that requires a Profile visit to switch on.
Fix: Offer the reminder at the end of the first weekly check-in or after the first completed session (one-time prompt), not in onboarding.
Effort: 2 h.

### 9. Watch motion capture has no release-build consumer

Evidence: The watch records labelled motion per set (PhaseTrainingWatch/WatchSessionModel.swift:35,84,108) and the phone stores it (WatchSyncCoordinator.swift:205 into `MotionStore`). The only reader is `TwinScorecardSheet`, which is wrapped in `#if DEBUG` (TwinScorecardSheet.swift:8) and reached from a DEBUG-labelled Profile row (ProfileScreen.swift:216-219). `TwinPrediction`, `TwinDiagnosis` and `TrainingLoadModel` are referenced only by that sheet and `SignalsReadout`.
Effect: Documented as a data-collection phase (the sheet header says "nothing here ships"), so this is not a defect. It means testers carry the storage and battery cost of motion capture with nothing they can see. Confirm the B1b go/no-go date so the collection does not run indefinitely.
Fix: None now; calendar the review.
Effort: 0.

### 10. Stale comment: RootTabView says 4 tabs

RootTabView.swift:1-5 says "4 tabs ... routine library lives behind sheets ... no longer a primary tab", while `AppTab` and the TabView have five tabs including Library (:15, :67-69). The tab-time-horizon skill also notes Library breaks the sequence. Fix the header comment. Effort: 0.1 h.

## Entry-point map (tap counts from cold launch)

| Feature | Path | Taps |
|---|---|---|
| Start today's workout | Today, Start | 1 to 2 |
| Switch today's workout | Today title wheel; "See all" opens OverrideTodaySheet | 1 to 3 |
| Log a sport day | Today, "Log session" (TodayScreen.swift:529) | 2 |
| Plate calculator | Log, weight cell (LogScreen.swift:204-207); also Profile TOOLS (ProfileScreen.swift:122-127) | in-flow 1 to 2 |
| Hold timer | Log, hold exercise (LogScreen.swift:208-218) | in-flow 1 |
| Weekly check-in | Week, "Plan next week" | 2 |
| Edit a day, add event | Week, day row | 2 |
| Soreness check-in | Progress, pill | 2 |
| Past sessions, edit or delete | Progress, "See all sessions" (ProgressScreen+ExerciseCards.swift:302) | 3 |
| History check | Progress, "History check" row, shown only when notable (:76-92) | 2 |
| Max hang test | Progress, FINGER STRENGTH, "Log a test"; card needs a climbing sport or a prior test (FingerCard.swift:14) | 3 with scroll |
| Ski readiness | Progress, ski card, needs a ski or snowboard sport (SkiCards.swift) | 3 with scroll |
| Body weight (first entry) | Profile, Body weight | 2 plus entry |
| Injuries | Profile, Injuries, picker | 3 |
| Health and CSV import, unmatched names | Profile, Health & Imports | 2 to 4 |
| Backup, restore, erase | Profile, Data | 2 to 3 |
| Coach chat | Bubble on any tab except Profile and Log; needs consent and a token | 1 |
| Library routines, muscles | Library tab, tile | 2 |

## Checked and fine

- No `if false`, no commented-out presenters, no `TODO` entry points. The one TODO is the product-ID placeholder (SubscriptionStore.swift:28, see finding 6).
- DEBUG-only surfaces (muscle chip generator, Twin scorecard, coach test ping, launch-argument seeds in PhaseTrainingApp.swift:24-100) are labelled and not reachable in Release. Not orphans.
- `StyleGuidePreview` is a design-reference preview, not a feature.
- Every other sheet in the 152-view list has a live presenter: Profile editors (ProfileScreen.swift:284-377), Week day editor and its sub-sheets (WeekDayEditSheet.swift:81-121), Today sheets (TodayScreen.swift:207-285), Log sheets (LogScreen.swift:167-233), Progress sheets (ProgressScreen.swift:205-217), Library (LibraryScreen.swift:95-123), weekly check-in screens (WeeklyCheckInFlow), onboarding screens (OnboardingFlow.swift:158-166).
- Plate calculator is reachable from Log with the target weight preloaded (regression check on the 2026-10-31 item: holds). History check is reachable without a CSV import (ProgressScreen+ExerciseCards.swift:76-92; holds).
- Support sport editor is gated to ski primaries or an existing pattern, with a stated reason (ProfileScreen.swift:143-156) and stays reachable once a pattern exists.
- The paywall gate for coach and support is held open by constants, so no feature is currently hidden behind payment.
- Watch: planned-session Start, set marking, rest timer, End session and Start on watch are all on the main screen (PhaseTrainingWatchApp.swift:21-80).
- Today stays within the one-day horizon; nothing found that should move, and no recommendation here shrinks rows.
