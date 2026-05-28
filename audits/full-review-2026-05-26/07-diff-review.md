## Uncommitted Diff Review

Scope: 4 modified files + 1 new file.
- `OnboardingAboutScreen.swift` — NavigationStack wrapper for keyboard toolbar crash fix
- `OnboardingConstraintsScreen.swift` — label + comment update for new step ordering
- `OnboardingFlow.swift` — adds `coachConsent` step between `constraints` and `planPreview`
- `OnboardingCoachConsentScreen.swift` — new consent gate screen
- `TodayScreen.swift` — replaces drag-handle reorder with action-sheet Move up/down

---

### Findings by file

#### OnboardingCoachConsentScreen.swift

**[HIGH] `consentGranted` default mismatch — `@AppStorage` property declares `= false` but first-arrival intent is ON**

Line 14: `@AppStorage(CoachConsent.storageKey) private var consentGranted: Bool = false`

The `@AppStorage` default (`false`) is the value returned before anything is written to `UserDefaults`. On first launch `hasMadeChoice` is `false`, so `.onAppear` sets `localOn = consentGranted || !hasMadeChoice = false || true = true` — which is correct for first-arrival. But the screen also writes `consentGranted = localOn` on Continue, so the AppStorage default itself is irrelevant once the screen is reached. The risk is not a crash, but a conceptual gap: every other consumer of this key (`PhaseTrainingApp`, `CoachRequestScreen`, `CoachSettingsRow`) also declares `= false` as the default, which means an existing user who upgrades past this commit **and somehow never re-runs onboarding** will default to coach-off. That matches `CoachConsent.swift`'s stated intent ("AI Coach off by default for existing installs") so this is consistent, but it diverges from the in-screen comment that says "Defaults to ON". No code path is broken; the comment is the misleading part.

*Suggested fix:* Update the `@AppStorage` default to `false` in the new file (already done) and reconcile the top-of-file comment "Default is ON" to say "Default is ON for new installs, OFF for upgrades (no key in UserDefaults)."

---

**[HIGH] `hasMadeChoice` reads from `UserDefaults.standard` — AppStorage suite mismatch risk**

Line 64: `UserDefaults.standard.object(forKey: CoachConsent.storageKey) != nil`

`@AppStorage` without an explicit `store:` argument binds to `UserDefaults.standard`, so the suites match in production. However, onboarding previews that pass a custom `UserDefaults` suite (see `OnboardingFlow` `#Preview`) will have `@AppStorage` writing to `.standard` while `hasMadeChoice` reads from `.standard` — those previews never customise the suite here, so previews are fine. The real hazard: if a future refactor adds `store:` to the `@AppStorage` declaration without also updating the `hasMadeChoice` check, the logic silently breaks. Low operational risk today, but the divergence is fragile.

*Suggested fix:* Pull the `object(forKey:)` check through the same store the `@AppStorage` property uses, or simplify by checking `consentGranted` vs a sentinel (e.g. -1 stored as an optional).

---

**[MEDIUM] Step counter shows "STEP 10 OF 10" for `coachConsent`**

`OnboardingStep.total` is computed as `allCases.count - 1`. With the new `coachConsent` case, `allCases` has 11 members (welcome…coachConsent + planPreview), so `total = 10`. `coachConsent.humanIndex = rawValue + 1 = 10`. The scaffold will render **"STEP 10 OF 10"** on the consent screen. That's technically correct, but the previous final questionnaire step (`constraints`) showed "STEP 9 OF 10", which may look abrupt to users. No crash or data loss; purely a UX signal.

*No code change strictly required* — if the intent is to present coachConsent as the final numbered step, the counter is accurate.

---

**[LOW] `OnboardingCoachConsentScreen` is not skippable — back-then-forward resets `localOn` to AppStorage**

The `.onAppear` guard mirrors the persisted value, so if a user: (1) backs into the screen from `planPreview`, (2) the screen re-appears and `hasMadeChoice` is now `true` (it was written on first pass), and (3) `consentGranted` is whatever they chose. The mirror logic is correct in that scenario. The only gap: if a user reaches this screen, changes `localOn` in the UI but then navigates *back* (to `constraints`) without tapping Continue, `consentGranted` is **not** written — which is intentional (deferred commit on Continue). Backing all the way out and re-entering will restore from AppStorage. This is correct behaviour but worth confirming the UX intent.

---

#### OnboardingFlow.swift

**[NIT] File header still says "8-step first-launch onboarding"**

Line 1: `// OnboardingFlow.swift — coordinator for the 8-step first-launch onboarding.`

There are now 10 numbered questionnaire steps (welcome=1 through coachConsent=10) plus planPreview. The header is stale.

*Suggested fix:* Update to "10-step" or drop the number from the comment.

---

**[LOW] `advance()` / `back()` rely on contiguous raw values — adding `coachConsent` between `constraints` and `planPreview` shifts `planPreview.rawValue` from 9 to 10**

Raw values are auto-assigned as sequential integers. `planPreview` was previously `rawValue = 9`; it is now `rawValue = 10`. Any code that stores or compares raw values directly (e.g. persistence, analytics) would silently break. Searching the codebase finds no raw-value comparisons for these specific cases outside of `next()`/`prev()`, so no live regression exists today. Flag for awareness if analytics or step-persistence is added.

---

#### OnboardingAboutScreen.swift

**[MEDIUM] Nested `NavigationStack` inside a `fullScreenCover` — iOS 26 behaviour noted in comment, but toolbar interaction with the outer hierarchy is untested for other Onboarding steps that also add `.toolbar` modifiers**

Only `OnboardingAboutScreen` wraps itself in a `NavigationStack`. The other 9 steps do not. The `.toolbar(.hidden, for: .navigationBar)` suppresses the nav bar. In iOS 17–18 this pattern is safe; the comment says the crash only appears in iOS 26. The fix is targeted but means this one step has a structurally different view tree from all others, which could cause subtle animation or focus-chain differences at the `constraints → coachConsent` transition boundary (no transition between these two steps involves `OnboardingAboutScreen`, so the risk is low in practice).

*No change needed*; document the iOS 26 dependency.

---

#### OnboardingConstraintsScreen.swift

No correctness issues. Label changed from "See my plan" → "Continue" and comment updated to "penultimate questionnaire step." Both match the new flow. ✓

---

#### TodayScreen.swift

**[MEDIUM] Stale index capture in action-sheet closures — `wrapped.index` is captured at sheet-build time, but `editableTemplate` mutation (Move up/down) immediately replaces the template. The sheet dismisses before the move fires (via `dismiss()` in `ExerciseActionSheet`), so the index is valid at the moment of the call. However, the `count` binding computed at sheet-presentation time (`let count = editableTemplate?.exercises.count ?? 0`) is captured by value, so `onMoveDown` guard `wrapped.index < count - 1` reflects the count at open-time, not after any previous move. If two quick taps open the sheet twice (unlikely but possible during animation), the stale count could allow an off-by-one.**

In practice this is defended by the `tmpl.exercises.indices.contains(target)` guard inside `moveExercise(at:by:)`, so a stale count would at worst produce a no-op rather than a crash. Severity is MEDIUM for awareness rather than BLOCKER.

---

**[LOW] Removal of `.onMove` + `.environment(\.editMode, .constant(.active))` is correct and complete — no orphaned references found**

The old `moveInlineExercise(from:to:)` function is deleted. No other call sites exist. The `List` no longer needs `editMode = .active` since drag-handles are gone. `inlineExerciseCard` no longer passes `.onMove`. Confirmed clean removal. ✓

---

**[NIT] `inlineExerciseCard` docstring no longer mentions drag reorder; reference to `swiftui-drag-reorder-custom-styled` is removed. Both correct.**

---

### Build-registration check (is OnboardingCoachConsentScreen in the build?)

**Registered. No action required.**

`Project.yml` uses `path: PhaseTraining` with a recursive source glob (xcodegen default), so any `.swift` file dropped under `PhaseTraining/` is auto-included on the next `xcodegen generate`. Additionally, `PhaseTraining.xcodeproj/project.pbxproj` already contains:

```
7FC6CD55681A0A042CC59FC5 /* OnboardingCoachConsentScreen.swift in Sources */
2E0682F87C89D2FD36998093 /* OnboardingCoachConsentScreen.swift */ = {isa = PBXFileReference; ... }
```

The file is already in the build graph. The pbxproj is not gitignored in this repo (confirmed by `git status` showing it as tracked), so this registration will persist across clones.

---

### Tiered backlog

#### P0 — blockers before commit
None. No hard blockers found. The new screen compiles (pbxproj already includes it), persists consent correctly via AppStorage on Continue, is wired into the flow in the correct position, and the TodayScreen move logic has an index-bounds guard that prevents crashes.

#### P1 — high-value, fix soon
| # | Finding | Effort |
|---|---------|--------|
| 1 | Reconcile the "Default is ON" comment in `OnboardingCoachConsentScreen.swift` with the `@AppStorage = false` default and the existing-install upgrade path. No code change required — comment-only. | S |
| 2 | `hasMadeChoice` uses a raw `UserDefaults.standard` lookup — add a note or extract a helper that matches the AppStorage binding store. | S |

#### P2 — low risk, clean up when convenient
| # | Finding | Effort |
|---|---------|--------|
| 3 | Update `OnboardingFlow.swift` header from "8-step" to "10-step". | S |
| 4 | Confirm UX intent for "STEP 10 OF 10" on the consent screen — or renumber total to exclude coachConsent from the denominator (matching the planPreview exclusion pattern). | S |
| 5 | Add inline comment to TodayScreen action-sheet sheet builder noting that `count` is captured by value and why the `indices.contains` guard in `moveExercise` is the real safety net. | S |
