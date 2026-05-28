# Part: Onboarding + Profile + Editors

Scope: `PhaseTraining/Screens/Onboarding/*`, `ProfileScreen.swift`, 11 editor sheets + 2 picker sheets. Data model: `TrainingMemory.swift`, `DemographicProfile.swift`, `MemoryStore.swift`, `CoachConsent.swift`. Axis scores 1-5 (5 = best).

## Per-screen findings (axis scores + evidence)

### OnboardingFlow.swift (coordinator)
- **Correctness 3** — Step count is fragile. `coachConsent` was inserted as a new case; `OnboardingStep.total = allCases.count - 1` (Flow:39) is correct only because `planPreview` is the single excluded case, but the "STEP X OF Y" label and progress fill both derive from `humanIndex`/`rawValue`, so any future reordering silently mis-numbers every screen. Comment at top still says "8-step" (Flow:1) while there are now 9 questionnaire steps + preview.
- **Correctness 4** — `finish()` (Flow:105) commits `draft → store.memory`, stamps onboarding, regenerates plan. Clean. But coach consent is NOT part of `draft`; it's written to `@AppStorage` inside `OnboardingCoachConsentScreen` (see below). Two separate commit paths for one flow.
- **UX 3** — 9 questionnaire steps + preview is long for a fitness app first-run. Sports → seasons → focus → availability → equipment → experience → about → constraints → coach → preview. Drop-off risk is real; `about` and `constraints` are fully optional yet still full-screen steps.

### OnboardingWelcomeScreen.swift
- **UX 4 / Accessibility 3** — Clean single-CTA. Hardcoded `size: 38` headline (Welcome:19) with `.fixedSize` won't scale with Dynamic Type; large accessibility sizes will clip/overflow. Same pattern recurs in every `displayL`/SpaceGrotesk title.
- **Correctness 3** — Body copy says "Eight quick questions" (Welcome:24); the flow is now 9. Stale.

### OnboardingSportsScreen.swift
- **Correctness 4** — `nextEnabled: !draft.sports.isEmpty` (Sports:20) gates progress; auto-promotes first to primary on Next (Sports:23). Good. `WrappingFlow` Layout lives here (Sports:80) — reused everywhere.
- **UX 3** — 32-sport flat chip cloud (TrainingMemory:289) with no search or grouping; that's a lot of tapping/scanning. Contrast with InjuryPickerSheet which has search + region grouping. Inconsistent treatment of comparably-sized lists.
- **Accessibility 2** — `OnboardingChip` is 13pt Inter with 9pt vertical padding (Flow:280-284); hit target well under 44pt and font is fixed-size.

### OnboardingSportSeasonsScreen.swift
- **Data-gap 3** — `peakDate` exists in the model (TrainingMemory:32) and SeasonsEditorSheet captures it, but this onboarding step never surfaces a peak-date field even when a sport is set to `.eventPrep`. A new user who picks Event Prep here gets taper behavior with a nil peak date until they later find Profile → Seasons.
- **UX 4** — Per-sport pickers + a default fallback is well-modeled. Default picker shown even with sports set (SportSeasons:33) is slightly redundant but defensible (covers later-added sports).

### OnboardingFocusScreen.swift
- **Correctness 3** — `draft.focuses` defaults to `[.generalStrength]` (TrainingMemory:23), and `OnboardingFlow.onAppear` copies `store.memory` into `draft` (Flow:63), so this screen arrives with "Get stronger" pre-selected and `nextEnabled` already true. The user can blow past the goal screen without a conscious choice — the most planner-load-bearing input is effectively opt-out.
- **UX 4** — Primary-reorder sub-picker on 2+ is good.

### OnboardingAvailabilityScreen.swift
- **Data-gap 3** — `liftDaysPerWeek` default is 3 (TrainingMemory:42) regardless of experience, but `DemographicProfile` recommends 2-3 for beginners and 4-5 for advanced (DemographicProfile:127). The default isn't seeded from experience, so a beginner who doesn't touch this ships a value at the top of their recommended band and an advanced user ships below theirs. ProfileScreen's tuning section will then flag "You set 3" as a mismatch (ProfileScreen:270) for the advanced case.
- **UX 4** — Steppers are 48pt (Availability:107) — meets hit-target minimum. Good copy ("0 = no lift slots").

### OnboardingEquipmentScreen.swift
- **Correctness 4** — Tier→array mapping is sound; `currentTier` derives from exact array equality (Equipment:55). NOTE the divergence with EquipmentEditorSheet: onboarding's custom tier starts EMPTY (`draft.equipment = []`, Equipment:70) while the editor seeds `[.bodyweight, .dumbbells]` (EquipmentEditorSheet:97). Two different "what does Custom mean" behaviors for the same concept.
- **Correctness 3** — Custom can produce `draft.equipment == []`, but `nextEnabled: !draft.equipment.isEmpty` (Equipment:23) blocks Next in that state — so a user who taps Custom then deselects everything is stuck with a disabled button and no explanation. Minor dead-end.

### OnboardingExperienceScreen.swift
- **Correctness 2** — Neither `experience` nor `startingState` is gated by `nextEnabled` (Experience:21). Both have defaults (`.beginner`, `.freshStart`), so a user can skip the screen entirely and silently ship beginner. `startingState` drives the calibration-week mechanic (TrainingMemory:50) — capturing it by default-only undercuts the feature.
- **UX 4** — Two clean single-selects with good subtitles.

### OnboardingAboutScreen.swift (MODIFIED/uncommitted)
- **Correctness 4** — Age TextField mirror/commit dance (About:60-69, 113-125) is careful and correct: clamps 13-99, treats empty as skip. `BodyMetricsEditor` (About:181) handles imperial/metric, European commas (About:441), bidirectional sync.
- **Correctness 3 / Perf 3** — Double keyboard toolbar risk: this screen registers a `.toolbar(placement: .keyboard)` Done (About:50-55) AND the embedded `BodyMetricsEditor` registers its own (About:228-234) inside the same NavigationStack. The top comment (About:30-34) explicitly notes iOS 26 crashes when two keyboard toolbars coexist and claims the NavigationStack fixes it — but both toolbars still live in one stack here. This is exactly the documented crash setup; worth a runtime check.
- **Accessibility 2** — 34pt JetBrainsMono age field is fixed-size; no VoiceOver label distinguishing the bare TextField beyond placeholder "—".

### OnboardingConstraintsScreen.swift (MODIFIED/uncommitted)
- **Correctness 3** — Two free-text lists (`dislikes`, `constraints`). The `constraints` list is the LEGACY free-text path — DemographicProfile tokenizes it into name-substring excludes (DemographicProfile:205) which the file's own header calls "false-positive prone." Onboarding still steers users into free-text injuries ("e.g. left knee", Constraints:39) even though the structured InjuryPickerSheet exists and is strictly better. New users generate legacy data on day one that the Profile injuries editor then labels "OTHER NOTES (LEGACY)".
- **UX 3** — No keyboard toolbar / Done here, unlike the editor-sheet twin (DislikesEditorSheet:47); on a free-text step that's a small dismissal friction.

### OnboardingCoachConsentScreen.swift (NEW/uncommitted)
- **Correctness 2** — The `@AppStorage(CoachConsent.storageKey)` default is `false` (CoachConsent:14) but `CoachConsent.swift` documents "on by default for new installs" (CoachConsent:8). The screen's `localOn` defaults `true` and writes on Continue (Consent:30-32), so the intended-ON only happens IF the user reaches and completes this step. If onboarding is ever exited early, or this step is skipped, consent stays false — the exact bug the file claims to close (Flow:26) is only closed on the happy path.
- **Correctness 3** — `hasMadeChoice` (Consent:63) reads `UserDefaults.standard` directly while the value is written via `@AppStorage` (also standard) — works, but couples to the global suite; under the preview/test suites used elsewhere this would read the wrong store.
- **UX 4** — Clear two-option pick, honest copy, default-ON is the right call. Coherent screen.

### OnboardingPlanPreviewScreen.swift
- **Correctness 4 / Perf 4** — Generates once, caches in `@State` (PlanPreview:56), guards re-gen on back-nav. `Planner.generate` runs synchronously on `.onAppear` (PlanPreview:59) on the main thread; for a heavy catalog query this could stutter the transition, but a ProgressView is shown until non-nil. Acceptable.

### ProfileScreen.swift
- **Consistency 5** — SettingsRow + focused-sheet pattern is the cleanest surface in the app. Tuning section (ProfileScreen:259) honestly surfaces recommended-vs-actual with mismatch hints. Strong.
- **Correctness 4** — Session length / lift days use a tap-to-edit alert (ProfileScreen:226-235) with numberPad + clamp (ProfileScreen:474). Backup/restore surfaces correctly hoisted to parent so child-sheet dismissal doesn't kill them (ProfileScreen:199-205).
- **Correctness 3** — Restore flow tells the user to "Restart the app to refresh every screen" (ProfileScreen:224) — a manual-restart requirement after restore is a real correctness gap; in-memory `@Published` stores aren't reloaded from the restored UserDefaults/DB.
- **Accessibility 3** — Rationale bullets at 12pt Inter fixed-size (ProfileScreen:302); the whole screen leans on fixed font sizes.

### Editor sheets (Sports / Seasons / Focuses / Equipment / Experience / Dislikes / About / Reminders / Data)
- **Consistency 4** — Strong shared skeleton: NavigationStack + `Color.bg` + ScrollView + `.presentationDetents([.medium,.large])` + `.preferredColorScheme(.dark)` + topBarTrailing "Done". They clearly came from one template.
- **Consistency 2** — But each re-implements its own chrome inline rather than sharing a scaffold the way onboarding has `OnboardingScaffold`. The micro-label header, the dark-bg ZStack, the Done toolbar are copy-pasted ~9 times. DislikesEditorSheet re-implements the exact tag-list that OnboardingConstraintsScreen's `EntryList` already implements (two copies of add/remove/dedupe-case-insensitive logic: Constraints:103 vs Dislikes:122).
- **Correctness 4** — All write through `store.update {}` so persistence is immediate (e.g. SportsEditorSheet:74). No draft/commit gap. AboutYouEditorSheet routes `BodyMetricsEditor`'s Binding back through `store.update { $0 = newMemory }` (AboutYou:76-79) — works but is a whole-struct overwrite on every keystroke-commit; fine at this size.
- **Correctness 3** — Injuries editor + onboarding constraints both write injuries, but to DIFFERENT fields (`userInjuries` vs `constraints`). A user who typed "left knee" in onboarding and later picks the structured ACL injury ends up with both, surfaced as a structured card AND a legacy chip. The summary count (`structuredCount + legacy.count`, ProfileScreen:430) can double-count the same real-world injury.
- **Accessibility 3** — Editors inherit OnboardingChip's sub-44pt targets and fixed fonts. InjuriesEditorSheet's severity/side cycle-chips are 12pt with 5pt padding (Injuries:223-226) — tiny tap targets for a 3-state cycle that isn't discoverable as cyclic without the code comment.

### InjuryPickerSheet.swift
- **Correctness 4 / UX 4** — Search + region grouping over 56 injuries, multi-select with Cancel/Done diffing back through `commitInjuries` (Injuries:261). This is the model the Sports picker should follow.

### ExercisePickerSheet.swift
- **Perf 2** — `results` is a computed property that runs `CoachDatabase.shared.listExercises(...)` on EVERY body re-evaluation (ExercisePicker:35-48), and it's read twice per render (rows + the count label at ExercisePicker:162). No debounce on `query`; each keystroke fires a fresh SQL query synchronously on the main thread. On a large exercise catalog this is the most likely jank source in this part.
- **Accessibility 4** — Good: `accessibilityLabel`/`accessibilityIdentifier` on info button and rows (ExercisePicker:195, 228). Best a11y in the set.

## Note on the uncommitted onboarding rework (is it coherent / complete?)

The rework adds `coachConsent` as step 10 and modifies About/Constraints/Flow. It is **coherent in intent, incomplete in execution**:
- Coherent: inserting an explicit consent gate before plan preview is the right place for it, the screen is clean, default-ON matches stated policy.
- Incomplete / risky:
  1. **Consent default mismatch** — `@AppStorage` default `false` (CoachConsent:14) contradicts the "ON for new installs" intent; the ON only lands if the user completes the step. The bug the step claims to fix (Flow:26-28) survives any non-happy-path exit.
  2. **Two commit channels** — every other answer flows through `draft` and commits atomically in `finish()`; consent writes to AppStorage mid-flow (Consent:30). Backing out of onboarding after the consent step leaves consent written but `onboardedAt` nil — partial state.
  3. **Stale counts** — Welcome ("Eight quick questions", Welcome:24) and Flow header ("8-step", Flow:1) / SportsScreen ("step 2 of 8", Sports:1) were not updated for the 9th step.
  4. Constraints still pushes free-text injuries despite the structured picker existing — the rework didn't reconcile the two injury-capture paths.

## Cross-cutting issues

1. **Two injury-capture systems coexist** — free-text `constraints` (onboarding) vs structured `userInjuries` (Profile picker). Onboarding feeds the worse one; Profile then quarantines it as "LEGACY". New users generate the legacy/false-positive-prone data on first run. (DemographicProfile:201-209, Constraints:39, Injuries:74)
2. **Defaults let the planner's load-bearing inputs go unset.** `focuses=[.generalStrength]`, `experience=.beginner`, `startingState=.freshStart`, `liftDaysPerWeek=3` all pass their screens with `nextEnabled` true or no gate. A user can tap through and ship a generic-beginner profile having "answered" nothing. (TrainingMemory:23,42,50; Experience:21)
3. **`liftDaysPerWeek` default not seeded from experience** — guarantees an immediate recommended-vs-actual mismatch banner in Profile for non-beginners. (Availability vs DemographicProfile:127)
4. **Fixed font sizes everywhere** — SpaceGrotesk/JetBrainsMono titles + Inter chips use hardcoded `size:` + `.fixedSize`, so Dynamic Type / accessibility text sizes don't scale and large sizes clip. App-wide.
5. **Sub-44pt hit targets** — `OnboardingChip` and the editor cycle-chips are below Apple's minimum. (Flow:280, Injuries:223)
6. **Editor-sheet chrome is copy-pasted ~9x** — no shared sheet scaffold analogous to `OnboardingScaffold`; tag-list logic duplicated between Constraints and Dislikes.
7. **Restore requires manual app restart** to refresh in-memory stores (ProfileScreen:224) — data-integrity rough edge.
8. **`usesImperial` defaults true (US)** with the toggle buried inside the height/weight section — non-US users see imperial first with no onboarding-level locale hint. (TrainingMemory:64)

## Tiered backlog — P0 / P1 / P2

### P0
- Fix coach-consent default so "ON for new installs" holds regardless of step completion (write default in onboarding entry, or flip AppStorage default + gate). **S** — `OnboardingCoachConsentScreen.swift` / `CoachConsent.swift`
- Gate `experience`/`startingState` and force a conscious `focus` choice (clear `focuses` default to `[]` and require ≥1, or mark a "chosen" flag). **S** — `OnboardingFocusScreen.swift`, `OnboardingExperienceScreen.swift`, `TrainingMemory.swift`
- Stop steering new users into free-text injuries; route onboarding's injury input to the structured `InjuryPickerSheet`/`userInjuries`. **M** — `OnboardingConstraintsScreen.swift`
- Verify/fix the double keyboard-toolbar setup the file itself flags as an iOS 26 crash. **S** — `OnboardingAboutScreen.swift`

### P1
- Seed `liftDaysPerWeek` (and session minutes) from experience-derived `DemographicProfile` defaults so Profile doesn't immediately flag a mismatch. **S** — `OnboardingAvailabilityScreen.swift`
- Reconcile injury double-count in summary + de-dupe structured vs legacy for the same injury. **M** — `ProfileScreen.swift`, `InjuriesEditorSheet.swift`
- Update stale step counts ("8 questions" / "step 2 of 8" / "8-step"). **S** — `OnboardingWelcomeScreen.swift`, `OnboardingFlow.swift`, `OnboardingSportsScreen.swift`
- Reload in-memory stores after restore instead of asking for a restart. **M** — `ProfileScreen.swift` (+ store layer)

### P2
- Extract a shared editor-sheet scaffold + a single reusable tag-list view; collapse the ~9 copies. **M** — all `*EditorSheet.swift`
- Add search/grouping to the 32-item Sports cloud (mirror InjuryPickerSheet). **M** — `OnboardingSportsScreen.swift`, `SportsEditorSheet.swift`
- Debounce/throttle `ExercisePickerSheet.results` and compute it once per render. **S** — `ExercisePickerSheet.swift`
- Adopt scalable type + ≥44pt hit targets across onboarding chrome (chips, cycle-chips, numeric fields). **L** — `OnboardingFlow.swift` (shared chrome) + sheets
- Surface a peak-date field in `OnboardingSportSeasonsScreen` when a season is `.eventPrep`. **S** — `OnboardingSportSeasonsScreen.swift`
- Unify Custom-equipment seed behavior between onboarding (empty) and editor (`[.bodyweight,.dumbbells]`). **S** — `OnboardingEquipmentScreen.swift`, `EquipmentEditorSheet.swift`
