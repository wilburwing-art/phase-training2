# 12. Backlog re-verification

**Status:** closed 2026-09-03
**Lens:** meta

## Question

83 items in `audits/2026-08-23-backlog.md` are marked done. Are they? Portfolio
history says an entry that overstates completion is worse than no entry, because
it stops the next audit from looking.

## Depth actually reached

All 10 Tier 0 items checked against current code. 11 of 59 Tier 1 items sampled,
chosen for being settleable by a grep. Tier 2 checked at the section level rather
than item by item. All 7 unchecked Tier 4 items reviewed, one spot-verified as
still live.

## Headline

**The backlog holds up.** Every item sampled had actually landed, several with
the deviation from the audit's prescription recorded in the item itself, which is
the behaviour a re-verification wants to find. Two exceptions and one meta
failure follow.

## Findings

### F1 (high) T0-5 is checked and one of its three sub-items was not done

The item reads, in full, as three linked edits in one commit: (a) stop
pre-selecting consent, (b) rewrite the modal copy so it names body metrics and
injuries, (c) "Include the privacy-policy link `CoachConsent.swift:6` promises
(docs/privacy.md exists; needs a hosted URL)."

- (a) landed. `OnboardingCoachConsentScreen.swift:35` is
  `nextEnabled: localOn != nil`, and neither option is pre-selected.
- (b) landed. `CoachConsent.modalBody` itemizes body metrics and injury notes.
- (c) **did not land.** A grep for a privacy URL across `PhaseTraining/` returns
  the Info.plist manifest key and a code comment, and nothing else. The consent
  modal still contains no link.

The completion note on the item mentions (a) and (b) and is silent on (c), so
the checkbox reads as fully done. See critique 11 F2.

### F2 (critical, meta) The cycle that landed 83 items also broke CI, and the gate it used could not see it

The backlog's stated gate is: "Build gate between items: `xcodebuild test` on
**the unit suite**." Each tier's status note reports against it: "969 unit tests
green", "ALL 59 landed, 972 unit tests green", "ALL 12 landed, 972 unit tests
green".

The unit suite was green throughout and is presumably still green. The **UI**
suite is not. Main's latest CI run (`33837141294`, 2026-09-04) fails with a
seven-test roster, and `gh run list --workflow test.yml` shows failure on every
run back to 2026-08-29, the full visible window.

Two of those seven are caused by T0-5 itself: the consent gate that item
correctly added made `onboarding-continue-coachConsent` a disabled button, and
two UI tests tap it without picking an option
(`TapBudgetTests.swift:292`, `OnboardingPlanDetailUITests.swift:30`). T0-5
landed 2026-08-24. See critique 05 F1 and F2 for the evidence chain.

So the gate was doing its job on the target it was pointed at, and the target
excluded the suite the change broke. The remaining five failures
(`test_completeScreen_presentsWithKettle`, `testTapBudget_discardWorkout`,
`testBuildAndStartWorkoutRoutesIntoLiveLog`, `testTapBudget_buildAndStartWorkout`,
`testTapBudget_startSavedWorkout`) are a separate cluster around starting and
finishing a session, and this critique does not have a cause for them.

### F3 (medium) The Tier 2 header undercounts its own section

`## Tier 2` says "ALL **12** landed". The section contains **14** checked
checkboxes and zero unchecked ones. Either two items landed without being
counted, or the note was written before two were added. Cosmetic, and worth
correcting so a future reader does not go hunting for two missing items.

### F4 (medium, correction to this suite) T1-52 landed, and critique 01 initially misattributed a defect to it

T1-52 ("Empty-demand slots silently dropped with no backfill") is implemented.
`SportSeasonGenerator.swift:84-98` holds a real backfill loop, ordered by the
rule's own demand weights and deterministically seeded.

Critique 01 F1 originally attributed the four-exercise session to that
shortfall. It was wrong, and has been corrected in place. The actual mechanism
is `targetMovementCount`: `TrainingMemory.sessionMinutes` defaults to 45
(`TrainingMemory.swift:51`), the ski off-season band clamps it up to 50, and
`50 / 11` integer-divides to 4.

Recording it here rather than quietly editing, because the failure mode is the
one this critique exists to catch: an audit finding that assumes a fix did not
land, when it did.

## Verified landed

Tier 0, all ten:

| item | evidence |
|---|---|
| T0-1 gateway token | `dailyRequestCeiling` referenced in `CoachClient`; **external half still open, exactly as the item's own note says** |
| T0-2 erase-all resurrect | 6 reset/clear calls in `BackupCoordinator` |
| T0-3 backup envelope | `sportLogs` / `importedWorkouts` appear 14 times in `BackupManager` |
| T0-4 silent DB failure | `unavailableReason` present in `UserDatabase` |
| T0-5 consent | **partial, see F1** |
| T0-6 import deletion | `confirmationDialog` in `CSVImportSection` |
| T0-7 ski pools | `SportSeasonGenerator.poolSlug(for:)` aliases ski and climbing variants |
| T0-8 check-in week | `stagePlan` exists; `WeeklyCheckInFlow` anchors on `Self.nextWeekStart()` at :151 and :212 |
| T0-9 swap identity | both named sites derive identity from the picked exercise |
| T0-10 demo seed | `seedSupersetsDemo()` is inside `#if DEBUG` (`PhaseTrainingApp.swift:58-61`) |

Tier 1 sample, all eleven landed:

`T1-2` rest-timer `UNTimeIntervalNotificationTrigger` present · `T1-14` search
wired in `LibraryScreen` · `T1-20` the leading-space matcher is gone and the
remaining `" squat"` string is inside the comment explaining the fix ·
`T1-33` region search in `InjuryPickerSheet` · `T1-38` developer copy moved
behind `#if DEBUG` (independently confirmed in critique 09 F4) · `T1-42`
verified thoroughly: 28 files construct a `DateFormatter` without
`en_US_POSIX`, and **every one of them uses a display format** (`EEE`,
`MMM d`, `EEEE, MMM d, yyyy`); every machine `yyyy-MM-dd` formatter carries
POSIX plus a Gregorian calendar · `T1-45` `stop_reason` read in the Coach layer ·
`T1-46` re-entry guard present in `MiniWorkoutDiffCard` with its rationale
comment · `T1-52` see F4 · `T1-53` pool-aware redistribution (`sinks`) present ·
`T1-54` sport logs threaded into `MissedWorkoutAutopilot.detect` ·
`T1-55` generation token in `InactivityReminderScheduler`.

## Unchecked items, reviewed

All 7 are Tier 4, which the backlog says to leave for a separate sitting. They
were left correctly. One spot-verified as still live and still accurate:

> "Eight quick questions" vs 9 steps vs "STEP X OF 10"
> (`OnboardingWelcomeScreen:28`)

`OnboardingWelcomeScreen.swift:27` still says "Eight quick questions."
`OnboardingStep.total` is `allCases.count - 1` = **10**, rendered as
"STEP X OF 10" (`OnboardingFlow.swift:44,266`). The flow has 11 screens. The
welcome copy is wrong by two, and is the first sentence a new user reads.

## What this says about the process

The 2026-08-23 cycle is the strongest piece of work in this repo's history and
the re-verification supports its claims. Two process notes are worth carrying:

1. **A per-item note that names the deviation is what made this cheap.**
   T1-15, T1-42 ("six sites, not four"), T1-51 and T2-6 each record where the
   implementation diverged from the audit's prescription. Every one of those
   held up on re-check, and none of them cost time to chase.
2. **A gate named for a subset will be read as a gate.** "969 unit tests green"
   was true and was never a claim about the UI suite, but it is what the status
   notes lead with, and the UI suite has been red since inside that window.
   Naming the gate "unit only" in the status line, or pointing it at the whole
   suite, is the difference.

## Ordering

F2 first, and it is the same fix as critique 05 F2: two lines in two test files.
F1 second, folded into critique 11's privacy work. F3 is a one-word edit.
