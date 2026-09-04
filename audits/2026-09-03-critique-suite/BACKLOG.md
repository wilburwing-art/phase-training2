# 2026-09-03 critique-suite backlog

Source: the 13 critiques in this directory, run sequentially 2026-09-03.
Every item cites the critique and finding it came from; open that finding for
the evidence before acting.

## How to run this

Top-down. Tier 0 first. One commit per item.

**Per-item: verify the factual premise against the code you are about to edit
before writing the fix** (`verify-audit-claim-before-implementing`,
`ios-audit-finding-false-positives`). This suite corrected one of its own
findings mid-run (01 F1, see 12 F4); assume it can be wrong again.

**Build gate: `xcodebuild test` on the WHOLE scheme, not the unit target.**
That distinction is item T0-2 and is why the previous cycle shipped with a red
UI suite (13 F5).

## What NOT to touch

- The season engine is the only generator. Do not resurrect legacy-generator
  behaviour (`phase-training-season-generator-engine-pitfalls`).
- `SportCatalog.isPlannable` and the pilot-sport routing are deliberate scope,
  not a bug. The scope question is T3-1, an owner decision.
- Both entitlement `proRequired` flags are held open by dated product
  decisions. Flipping them is T3-4, not a fix.
- `PlanStore+LLMRefinement`'s disabled state is correct and should stay disabled
  until the generator consumes `strategy`.
- Segment-grain and pool-size decisions in `PhaseRule` are tuned by hand. Do not
  bulk-edit weights; 01 F2 says most of them cannot change the output anyway.

---

## Tier 0 — ship blockers, safety, App Review

**Status 2026-09-04: ALL 7 landed.** One commit per item, straight to main.
Two turned out to be product bugs rather than the doc/test problems they were
scoped as: T0-3 found "Start workout" gated on having a NAME, and T0-4 found
the privacy manifest declared in a file Apple does not read.

Gated on the whole scheme rather than the unit target, which is the lesson from
the previous cycle (13 F5). Each item was verified against the tests it claims
to fix as it landed; all seven of main's previously-red UI tests pass.

- [x] **T0-1 The authored path applies no injury filter, and the UI promises it does.** `AuthoredRoutine.workout` (`AuthoredRoutine.swift:127`) maps every routine row with no reference to `profile.excludedExerciseIds`, while `InjuriesEditorSheet.swift:117` tells the user "We'll filter out exercises that aren't safe for the injuries you pick." Seven of ten plannable sports are served by this path, climbing included. 12 injury types have contraindicated exercises inside authored routines; a declared finger-pulley injury can be served `Climbing Finger Strength Protocol (Repeaters)`. Fix: filter `rows` by the excluded set before the map, and return nil if the filter empties the routine. Add the invariant test from T2-4 in the same commit. *(03 F1, F2)* **DONE `594654a`** — `profile` is a required parameter, not a defaulted empty set. Ships the injury-contraindication invariant (T2-4's first half) across both paths, 5 phases and 3 slots. Mutation-checked: with the filter removed the climbing case fails on Weighted Pull-Up and Hangboard Repeaters.
- [x] **T0-2 CI has been red for 13+ consecutive runs; two onboarding tests tap a button T0-5 correctly disabled.** `TapBudgetTests.swift:292` and `OnboardingPlanDetailUITests.swift:30` call `onboarding-continue-coachConsent` without picking a consent option; `OnboardingCoachConsentScreen.swift:35` gates it on `localOn != nil`. Both walks stall and time out on the plan preview. Fix: tap a consent option first in both tests, and bump `tap-budget-baseline.json` `onboarding-to-first-plan` 12 → 13. *(05 F1, F2; 12 F2; 13 F1)* **DONE `0908b1c`** — `OnboardingPickRow` already had an `a11yId` parameter, so this passes one at each call site. Both walks decline consent. Budget 12 -> 13.
- [x] **T0-3 Diagnose the five-test start/finish cluster.** `test_completeScreen_presentsWithKettle`, `testTapBudget_discardWorkout`, `testTapBudget_startSavedWorkout`, `testBuildAndStartWorkoutRoutesIntoLiveLog`, `testTapBudget_buildAndStartWorkout` all fail on main, all three retries, and all launch from `--ui-test-onboarded` seeds so T0-2 does not explain them. Assertions point at starting a built workout and at Finish presenting the summary. This is the core loop; establish whether it is a rig problem or a live regression before anything else in Tier 1. *(06 F6; 13 F1)* **DONE `139d4bc`** — three causes, one of them a real bug: Start workout was gated on `canSave` (needs a NAME) while its own footer says starting does not save. Split `canStart` out. The other two were T1-3's Finish confirm and an unnamed routine failing Save. Also hardened `TapCounter.tap` to require `isEnabled`, which is how all three hid.
- [x] **T0-4 No `PrivacyInfo.xcprivacy` exists.** `find . -name "*.xcprivacy"` is empty and the string appears in no build config. `NSPrivacyCollectedDataTypes` is declared in Info.plist, which is not where Apple reads a manifest, and the single declared type is `OtherUserContent` while the Coach transmits body metrics and injuries. Fix: add the manifest, declare the `UserDefaults` required-reason API, and declare Health/Fitness data types. **Re-check Apple's current requirements first** — that rule has moved. *(11 F3)* **DONE `a148e76`** — adds the manifest, declares UserDefaults CA92.1, and declares Health + Fitness alongside OtherUserContent. Verified no other required-reason API is used.
- [x] **T0-5 `docs/privacy.md` misdescribes the Coach payload, and the promised privacy link does not exist.** The policy says the app sends "your messages plus a snapshot of your current plan, recent workout feedback, and today's plan day"; the context actually assembles 22 blocks including body metrics, structured injuries, strength estimates, dislikes, constraints, sport-log notes and feedback notes. Separately, `CoachConsent.swift:8` says the modal presents "a link to the privacy policy" and no such link exists in the app — this was sub-item (c) of the previous cycle's T0-5, which is checked off. Fix: rewrite the policy from `CoachConsent.modalBody` plus the four undisclosed free-text blocks, host it, add the link. *(11 F1, F2; 12 F1)* **DONE `a148e76`** — policy rewritten from the actual 22 context blocks; consent modal gained the four free-text blocks; GitHub Pages URL verified live (HTTP 200) and wired into `CoachConsent.privacyPolicyURL` plus a Link on the onboarding consent screen.
- [x] **T0-6 The app prescribes loads to injured users and carries no disclaimer.** One grep across `PhaseTraining/` and `docs/` finds a single hit, inside `CoachSystemPrompt.swift:60`. Fix: a disclaimer on the onboarding welcome or the injury editor, plus a line in `docs/privacy.md`. *(03 F4; 11 F6)* **DONE `e66c760`** — onboarding welcome and the injury editor.
- [x] **T0-7 The paywall sells a capability that does not run.** `PaywallView.swift:74`: "plus an AI coach that personalizes every workout." Seven of nine `GeneratorStrategy` fields never reach the generator. The sibling refinement path disabled itself over this exact claim, calling it "pure token spend plus a false product claim" (`PlanStore+LLMRefinement.swift:44-63`). Fix: either wire strategy (T1-6) or rewrite the sentence to sell the deterministic seasonal planner, which is the real differentiator. *(08 F1, F2; 09 F3)* **DONE `e66c760`** — the feature list carried a SECOND false claim the critique missed ("Personalized workout polish on every plan generation" is the disabled refinement pass). Both rewritten to season-phase and two-sport planning.

## Tier 1 — user-facing correctness

- [ ] **T1-1 The default user hits a dead Today screen on the Monday after week one.** Nothing regenerates on a date change (`needsRegeneration` is inputs-hash only, `PlanStore.swift:634`); rollover snapshots without replacing (`:333`); the only thing that stages next week is the Weekly Check-In, presented only from a notification deep link; that notification is off by default (`WeeklyReminderScheduler.swift:35`). With a stale plan, `todayPlan` is nil, the upper-1 fallback is gated on `plan == nil`, and `TodayScreen.swift:548` disables Start with no explanation. **Confirm by moving the simulator clock forward 8 days before fixing.** *(06 F1)*
- [ ] **T1-2 Every session is four exercises because of an integer division.** `sessionMinutes` defaults to 45 (`TrainingMemory.swift:51`), ski off-season clamps it up to its 50-minute floor, and `50 / 11` is 4 (`SportSeasonGenerator.swift:253`). Four slots also make the smallest expressible demand share 0.25, which zeroes every demand weighted under a quarter — including `hipLateral` and `prehab`, the two the off-season objective promises will "fix imbalances". Fix: round rather than truncate, or lower the 11-minute divisor to match the 33-minute sessions the assembler actually measures. *(01 F1, F2, F4)*
- [ ] **T1-3 A three-day week is the same workout three times.** Ski off-season sessions 1 and 3 are identical and session 2 differs in one slot; event prep is worse. Needs either more movements per pool or week-level demand distribution rather than per-session. Larger than T1-2 and gated on it. *(01 F3)*
- [ ] **T1-4 A Coach swap writes `exerciseId: 0` and inherits the replaced exercise's prescription.** `WorkoutDiff.swift:88-103`. Three effects: the row detaches from the catalog so no injury contraindication can match it, sets/reps/rest/pattern carry over from a different movement, and `rpe`/`tempo` are dropped by the initializer. This is the third instance of the defect T0-9 fixed at two other sites last cycle. Fix: resolve `toName` to a catalog exercise, derive identity and prescription from it, clear what does not transfer. *(04 F2)*
- [ ] **T1-5 42 of 56 declarable injuries filter nothing.** Only 14 rows in `common_injuries` carry any `contraindicated` mapping. The 42 without include meniscus tear, hamstring strain, achilles tendinopathy, shoulder dislocation, and three stress-fracture entries. Fix: extend `exercise_injury_relevance`, starting with the load-management cases. *(03 F3)*
- [ ] **T1-6 The Coach Request screen bills an LLM call whose output is mostly discarded.** `CoachRequestScreen.swift:459` passes a strategy into `generateLift`, which drops it on both paths. Only `durationMinutes` and `focus` leak through indirectly. Either wire strategy into the season and authored generators, or gate the screen the way `PlanStore+LLMRefinement` gated itself. *(04 F1, F6)*
- [ ] **T1-7 The set-completion control is 22pt.** `checkDot` (`LogSetRow.swift:275-289`) against a 44pt minimum, and it is the most-tapped control in the product. The code already diagnosed the size and fixed the test's ability to hit it rather than the user's. Fix: `contentShape` or padding to 44, keeping the 22pt visual. *(07 F2)*
- [ ] **T1-8 The deload is a badge, not a program change.** `MesocycleProgression` computes real cycle status and its only non-test consumer is `SeasonPhaseBadge`. `weekNumber` reaches the generator and is used only in the seed string (`SportSeasonGenerator.swift:45`). Week 4 of a block shows DELOAD above the same prescription as week 1. *(06 F2)*
- [ ] **T1-9 24 authored routines contain a single exercise and are served as a day's workout.** 42 of 113 have one or two. `AuthoredRoutine.workout` returns nil only for zero. Fix: a minimum-size gate, or merge the fragments. *(02 F5)*
- [ ] **T1-10 A climbing user can pick a variant the generator ignores.** `SupportPatternEditor.swift:18` offers boulder and tradAlpine; the generator always resolves `.sportRoute` from `defaultVariant(forSport:)`. Same shape for ski, where backcountry and skimo are unreachable and take 4 `aerobicUphill` movements with them. *(01 F9, F10)*

## Tier 2 — coverage and accessibility

- [ ] **T2-1 The app ignores Dynamic Type completely.** `TypeSpec.font` is `Font.custom(fontName, size:)` with no `relativeTo:` (`Typography.swift:37`), and `relativeTo` appears in zero of 134 `.custom(` call sites. Body copy is fixed at 13pt, labels at 10pt. Must be done together with the fixed row frames in `LogSetRow` or the log clips. *(07 F1, F3)*
- [ ] **T2-2 VoiceOver has nothing to read on the logging surface.** 3 `accessibilityLabel`s across LogScreen, LogSetRow, LogExerciseBlock and CompleteScreen, against 16 identifiers. The check dot has an identifier and no label. Do it a screen at a time, starting there. *(07 F4)*
- [ ] **T2-3 Write gate test 3: the `wireHistory()` contract.** `wireHistory` appears zero times in the unit target. It decides what conversation history is sent to Anthropic. Pure function over an array of turns; role alternation and empty-assistant filtering. Unblocks Tier 3 architecture work. *(13 F2)*
- [ ] **T2-4 Port an invariant test for the season engine.** `GeneratorInvariantTest` (312 lines, incl. the injury-contraindication safety invariant) was deleted with the legacy engine in `449bd8d` and never replaced. Start with the one T0-1 needs: no contraindicated exercise appears in any generated session, for any profile, on **either** path. *(13 F3)*
- [ ] **T2-5 Close gate 1: warmup-flag round-trip through SessionStore.** `isWarmup` appears in eight test files and none of them is `SessionStoreTests`. *(13 F2)*
- [ ] **T2-6 Seven Tier 0/1 fixes sit in files with zero unit-test coverage.** `CoachClient` (the T0-1 spend ceiling; `dailyRequestCeiling` is asserted nowhere), `BackupCoordinator` (T0-2), `RestTimerState` (T1-2), `MiniWorkoutDiffCard` (T1-46), `InsightGenerator` (T1-47), `InactivityReminderScheduler` (T1-55), `CoachConsent` (T0-5). Start with the spend ceiling. *(13 F4)*
- [ ] **T2-7 Make the tap-budget tracker report a missing flow.** It is non-gating by decision, which is fine; it prints nothing when the emitting test stops running, which is not. Three baselines have been unobserved for two weeks. One loop over the expected flow names. *(05 F3; 13 F6)*
- [ ] **T2-8 Add one Dynamic Type assertion.** Nothing in either target references `dynamicTypeSize`. A single test that a font resolves differently at two content-size categories would have caught T2-1 at any point. *(07 F7 / 13 F7)*
- [ ] **T2-9 Load prescription steps up unconditionally and never down.** `progressiveOverloadHint` always applies a 2.5% step from the all-time best, with no branch for missed reps, soreness, or a deload phase. The Epley math itself is correct; the gap is autoregulation. Interacts with T1-8 and with the parked adaptive layer. *(03 F6)*
- [ ] **T2-10 Readiness scaling exists and neither live generator uses it.** `WorkoutGenerator.swift:152-166` implements a readiness set multiplier and an RPE cap; `SportSeasonGenerator` contains zero occurrences of `readiness` or `soreness`, and the authored path preserves authored sets and reps by design. The app asks for a soreness check-in and prescribes the identical session either way. Same change as T1-6. *(03 F5; 01 F11)*

## Tier 3 — owner decisions, not defects

Each of these is a call to make, not a bug to fix. Listed so they are not lost.

- [ ] **T3-1 The acquisition research and the product target different people.** All ten niche briefs are gym-strength communities; all ten plannable sports are mountain sports. `STRATEGY.md:172` picks hybrid-hyrox, which has no slug in the app. Either the product grows toward the research (general strength path, canonical templates, drop the sport gate) or the research grows toward the product (briefs for the mountain-athlete communities no file covers). *(02 F1, F2)*
- [ ] **T3-2 Three shipped routines are distilled from MTI's paid plans.** Two name `MTI Mountain Bike Pre-Season V2` directly; two pass through the owner's own shralpinism program. The exercise vocabulary is MTI's branded naming ("Leg Blaster"), `source_url` is empty on all six attributed rows, and MTI sells these at $35/month. Not a legal opinion; three facts to weigh before App Store submission. *(10 F2)*
- [ ] **T3-3 Price is set against the wrong tier.** $49.99/yr is mid-pack among gym loggers where the app is outmatched, and an order-of-magnitude story against MTI's $420/yr where it is not. The strategy asked for $40/yr **plus $99 lifetime** and argued the lifetime option twice; no lifetime product exists and a monthly tier the strategy did not ask for does. *(09 F5; 10 F4)*
- [ ] **T3-4 Nothing is gated and the free feature is the expensive one.** Both `proRequired` flags are false by dated decision. The Coach costs real money per install and is free; the support-sport reflow is named in code as the intended first paid feature and is also free. The code is already shaped for the flip, and `SupportPatternEditor` is the moment-of-value screen the paywall should route from. *(09 F1, F2, F6)*
- [ ] **T3-5 Kettle is a face with no voice.** Either the mascot is decoration and the terse coach register is the app's voice, which is coherent, or Kettle speaks and the onboarding and empty states should carry it. *(08 F5)*

## Tier 4 — polish, separate sitting

- [ ] ~19 prose em/en dashes remain (four went with T0-7) in user-facing `Text()` literals, against the house ban. Two more are numeric ranges and are a separate call. *(08 F4)*
- [x] `OnboardingWelcomeScreen.swift:27` said "Eight quick questions"; `OnboardingStep.total` is 10 and welcome is not a question, so it now says nine. **DONE `e66c760`**, in the same paragraph as T0-6's disclaimer. *(12)*
- [x] `CoachConsent.swift:4-5` said the coach is "on by default for new installs"; T0-5 made it an affirmative choice. **DONE `a148e76`**. *(11 F5)*
- [x] ~~`docs/privacy.md:23` says Health-confirmed sessions may reach the Coach context.~~ **REFUTED 2026-09-04.** Raw HealthKit data does not, but confirming a detected activity writes a `SportLogEntry` (`Health/ActivityDetection.swift:136`) and sport logs are one of the 22 context blocks. The sentence is correct; the finding was not. *(11 F4)*
- [ ] The Tier 2 header in `audits/2026-08-23-backlog.md` says "ALL 12 landed"; the section has 14 checked items. *(12 F3)*
- [ ] The climbing off-season objective says "hypertrophy" and prescribes 4x4-6 at RPE 7-8, which is max strength. Either the objective string or the `pullStrength` `DemandScheme` is wrong. *(01 F7)*
- [ ] Hangboard max hangs appear in all three off-season climbing sessions. Standard protocols put max hangs at two a week. Feeds T1-3 and is the most quotable output in the dump. *(01 F8; 02 F6)*
- [ ] `progressiveOverloadHint` keys prior-best by lowercased display name. Low blast radius, same class as T0-9. *(03 F7)*
- [ ] The gateway account id is a string literal alongside the compiled-in token. Part of the still-open T0-1 external work from the previous cycle. *(11 F7)*
