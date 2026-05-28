# Architecture Review

Scope: Data/generator layer of the PhaseTraining iOS app. Read-only; no build/run.
Lens: Ousterhout module depth, god-objects, coupling, testability, error handling, concurrency.

## Module-by-module depth assessment

**Deep modules (good — simple interface, rich behavior):**
- `DemographicProfile` (256 LOC) — single `from(memory:)` entry, encapsulates all the ACSM/NSCA rule lookups (lift days, session minutes, difficulty bias, equipment→slug allow-list, injury contraindications). Callers never see the rule tables. Best-designed type in the layer.
- `WeekPlan` / `TrainingMemory.planInputsHash` (`WeekPlan.swift:305`) — a deterministic djb2 fingerprint is a clean, hidden mechanism; the whole drift-detection / auto-regen contract rests on this one computed property. Genuinely deep.
- `TrainingMemory` (680) — tolerant Codable with explicit per-field migration; complex internally but the public surface is just a value struct. Appropriate depth, though the decode (`TrainingMemory.swift:119-195`) is doing real work (legacy focus/season/injury migration) that is untested as a unit.
- `MuscleBucket` / `MovementCategory` (`ExerciseFilters.swift`) — taxonomy collapse hidden behind small enums. Deep and correct.

**Shallow / pass-through types:**
- `WorkoutTemplate` (73) — fine, it's a DTO + one hardcoded template. The hardcoded `upper1` is dead-ish (only `byId("upper-1")` reaches it) and could be deleted.
- `ExerciseStaples` (69) — a static keyword map + `isStaple`. Reasonable, but it's a *data* table living in code; it's tightly coupled to coach.db's exact exercise names (comment admits it). Brittle but shallow.
- `PatternSlot` (`WorkoutGenerator.swift:1107`) — a `final class` with a mutable `var satisfiedBy` used purely so the picker can write back which alternative won. This is the one mutable-reference wart in an otherwise value-typed generator; it's why `pickForSlot` has a side effect (`slot.satisfiedBy = pattern`) instead of returning a tuple.

**Logic smeared across places (should be one place):**
- **Rest-string parsing exists 3×**: `WorkoutGenerator.parseRestSeconds` (`:959`), `PlanStore.parseRest` (`:200`), and the `:` logic again inline. Identical algorithm, three copies.
- **djb2 deterministic pick exists 2×**: `WorkoutGenerator.deterministicPick` (`:792`) and `Planner.deterministicPick` (`:857`) are byte-identical. Also re-implemented inline in `planInputsHash` and `stableTemplateId`.
- **Exercise row decode (21-column) exists 3×** inside `CoachDatabase`: `decodeExerciseStartingAt` (`:398`), the inline copy in `substitutes` (`:463-491`), and the offset variant. The substitutes copy is hand-maintained and will drift from `decodeExercise` whenever a column is added.
- **Leading-digit reps parsing** repeated in `SessionStore` (`:171,181`), `WeekPlan.parseRepsLeading` (`:247`).

## Top coupling / god-object problems (ranked, with file:line)

1. **`CoachDatabase.shared` is a hard global reached from 23 call sites, incl. 12 screens.** `CoachDatabase.shared` (`CoachDatabase.swift:5`) is a non-injectable singleton bound to `Bundle.main`. Screens call it directly — `TodayScreen`, `LogScreen`, `DayWorkoutPreviewSheet` each hit it 6×; `ExerciseDetailSheet`, `ProfileScreen`, `CoachRequestScreen`, etc. The generator (`WorkoutGenerator`), `GeneratorContext.buildPatternFrequency` (`:176`), `DemographicProfile.from` (`:197,213`), and even `TrainingMemory.init(from:)` (`:181`) reach into it. **This is the dominant coupling problem**: a value-type Codable decoder hitting a SQLite singleton means you cannot decode a `TrainingMemory` in a context without the bundled DB. There is no protocol seam — every consumer is welded to the concrete singleton.

2. **`WorkoutGenerator` (1124) is a god-object doing 6 distinct jobs.** It owns: focus selection (`WorkoutFocus.lift`), slot recipes (the `slots` switch, `:1041-1099`), candidate querying + 4-tier fallback (`pickForSlot`, `:272-407`), stagnation swap (`:435`), prescription math (`prescription`/`focusBias`, `:811-938`), RPE/tempo (`:522`), warm-up synthesis (`:170`), and the two hypertrophy accessory layers (`:589-674`). The accessory layers in particular are hardcoded eval-rig mirroring ("Cable Lateral Raise" etc., `:609`) — programming policy frozen into the generator. Seams to split: (a) `WorkoutRecipe`/`WorkoutFocus` → its own file (the `slots` data is pure); (b) `Prescription` (focusBias + clamps + the hypertrophy rest bumps `:862-879`) → standalone, it's the most testable unit and is already partly unit-tested; (c) `AccessoryLayer` strategy → separate type so adding push/pull/legs layers doesn't grow the generator.

3. **`CoachDatabase` (1014) mixes catalog reads + programming policy.** `foundationTagThreshold` (`:15`), the sport-visibility three-bucket policy (`:297-332`, duplicated in `exercises(matchingPattern:)` `:527-549`), and `difficultyRank` (`:905`) are *domain rules* living in the DB accessor. The class is otherwise a clean repository. The sport-visibility SQL is copy-pasted between `listExercises` and `exercises(matchingPattern:)` — a real divergence risk.

4. **`PlanStore` (648 + 236) is an `ObservableObject` doing persistence, generation orchestration, edit-diff application, custom-routine post-processing, AND LLM refinement orchestration.** It holds 6 optional store refs wired post-init (`recentPicks`, `sessionStore`, `sportLogStore`, `customStore`, `memoryStore`) (`:30-63`). This "set it later or get degraded behavior" pattern is a hidden-dependency minefield: every method must defensively `guard let`. The `composeWorkout`/`parseRest` helpers (`:170,200`) duplicate generator logic. The `@Published plan` setter triggers a SwiftUI cascade that the code itself notes can hit the 5s watchdog (`:312-317`) — generation work is happening on the main actor.

5. **LLM refinement reaches across three subsystems with no seam.** `PlanStore+LLMRefinement.refineSingleDay` (`:116`) constructs a `CoachClient()`, streams, decodes a tool call, rebuilds a `GeneratorStrategy`, and re-runs `WorkoutGenerator` — and reads consent straight from `UserDefaults.standard` (`:48`) bypassing the injected `defaults`. It mutates `@Published plan` from inside a `TaskGroup`. No protocol over the network client; untestable without live LLM.

## Test-coverage gaps on critical paths

29 test files, strong on the *pure* edges. Gaps concentrate exactly where coupling is worst:

- **No test runs `applyStagnationSwap` end-to-end.** `GeneratorContextTests` proves `stagnantExercises` is *computed* correctly (`:80-127`) but nothing feeds a stagnant context into `generateLift` and asserts the substitute actually swapped. The swap's constraint re-checking (`WorkoutGenerator.swift:448-470`) is untested.
- **The hypertrophy accessory layers are untested** (`appendHypertrophyUpperPushAccessories` `:589`, `appendHypertrophyLowerBodyAccessories` `:637`). The muscle-slug-vs-group disjoint check at `:664` is exactly the trap the project's own skill warns about, yet no test guards it.
- **Duration-budget slot-dropping is untested** (`:145` optional-slot drop). No test sets a tiny `sessionMinutes` and asserts optional slots fall off while required slots survive.
- **`sore-area` exclusion through `generateLift` is untested** — `recentSoreAreas` is computed-tested, but the `applySoreFilter` pick exclusion (`:295-308`) and the RPE-7 cap (`:575`) have no integration test.
- **The entire LLM refinement path has zero tests** (`grep` confirms no test references `refineCurrentPlanWithLLM`/`CoachClient`). The `applyRefinedWorkout` plan-swap-guard (`:225-229`) — load-bearing against a race — is unverified.
- **`PlanStore.applyCustomRoutineOverrides`, `migrateIfStale`, `swap`** — no `PlanStoreRegenTests` coverage of the custom-routine or legacy-migration branches (those branches each touch `UserDefaults` + the generator).
- **`TrainingMemory` decode migrations untested** — the legacy focus/season/injury promotion (`:130-189`) is the riskiest decode in the app and has no round-trip test; it also silently calls `CoachDatabase.shared` mid-decode.
- **Well-covered (credit):** `WorkoutFocus.lift` rotation, `focusBias` schemes, equipment/injury/dislike filters, determinism, `Planner` (1002-LOC test file), strategy decode clamping, concurrency.

## Error handling

- **No `fatalError`, no `try!`, no force-unwraps in the Data layer** — good.
- **`CoachDatabase` fails loud, by design.** Open-with-verify retry loop (`:51-77`) and `isOpen` mean a broken DB returns `[]` rather than crashing; the concurrency test relies on this. Reasonable.
- **`try?` swallowing is heavy where it matters:** 5 in `PlanStore` (every `encoder().encode` → `try?`, `:351,626,632`). A persistence failure (disk full, encode error) is silently dropped — the user's edit looks applied in-memory but never lands on disk, and there's no signal. `UserDatabase` `sqlite3_exec` migration errors are caught and freed but **never surfaced** (`:140-150`); a failed migration just yields empty reads later.
- **`UserDatabase` write methods are fire-and-forget `Void`** — `save`, `saveSession`, `delete` (`:237,288,506`) return nothing and ignore every `sqlite3_step` result. A failed insert is invisible to the caller and to the `@Published` cache, which then disagrees with disk.

## Concurrency

- **`CoachDatabase` is genuinely thread-safe.** `NSRecursiveLock` + `withLock` on every public method (`:29-36`), `SQLITE_OPEN_FULLMUTEX`, recursive lock chosen specifically so `adjacentByDifficulty`→`exercise(id:)` reentry doesn't deadlock. `CoachDatabaseConcurrencyTests` fires 50 concurrent reads and asserts stability, plus a reentry test. This is the most carefully-built part of the layer.
- **`UserDatabase` uses the same `withLock` + `FULLMUTEX` pattern** but is read-write; transactions use `BEGIN IMMEDIATE`/`COMMIT` (`:239`). The lock serializes Swift-side, so it's safe, but **there is no concurrency test for `UserDatabase`** — and unlike CoachDatabase it has mutating writes + the `.shared`/`.defaultStore()` ephemeral split (`:40-45`) that tests depend on.
- **Real risk: `@MainActor` + background generation.** LLM refinement runs a `TaskGroup` on `@MainActor` (`PlanStore+LLMRefinement.swift:89`) and each subtask calls `WorkoutGenerator.generateLift`, which synchronously hammers `CoachDatabase` (locked, but on the main thread). Combined with the `@Published plan` cascade the code already flags as watchdog-risky (`PlanStore.swift:312`), heavy regen is main-thread-bound. The lock makes it *safe*, not *responsive*.

## Tiered backlog of refactors

P0 — high payoff, low risk:
- **Introduce a `CoachCatalog` protocol over `CoachDatabase`'s read methods; inject it.** S→M. Payoff: unlocks unit-testing the generator/profile without the bundled DB, and removes the singleton from `TrainingMemory.init`. `CoachDatabase.swift`. (Start by injecting into `DemographicProfile.from` + `WorkoutGenerator`, leave `.shared` as the default arg — zero call-site churn.)
- **Add integration tests for stagnation swap, accessory layers, duration-budget drop, sore-filter+RPE-cap.** M. Payoff: covers the 4 most logic-dense untested generator branches; the accessory disjoint-slug bug class is a known repeat offender. `WorkoutGeneratorTests.swift` (no new files → no pbxproj edit).
- **Dedup rest-parse + djb2 into one `ParseUtil`/`DeterministicPick` helper.** S. Payoff: removes 3 rest-parse + 2 djb2 copies; **new file → pbxproj must be hand-edited** (see gotcha below). Low risk if folded into an existing file instead.

P1 — medium effort, real payoff:
- **Extract `Prescription` (focusBias + clamps + hypertrophy rest bumps) and `WorkoutRecipe` (focus + slots) out of `WorkoutGenerator`.** M. Payoff: shrinks the god-object ~250 LOC, makes prescription independently testable (already half-tested). `WorkoutGenerator.swift`. New files → pbxproj edit.
- **Hoist the sport-visibility SQL clause into one private method in `CoachDatabase`.** S. Payoff: kills the copy-paste divergence between `listExercises` (`:297`) and `exercises(matchingPattern:)` (`:527`). `CoachDatabase.swift`.
- **Make `UserDatabase` writes return a discardable `Bool`/throw, and surface `PlanStore` encode failures.** M. Payoff: silent persistence loss becomes observable. `UserDatabase.swift`, `PlanStore.swift`.

P2 — larger / structural:
- **Split `PlanStore`: extract `PlanGenerationCoordinator` (generate + custom overrides + LLM kickoff) from the `ObservableObject` persistence wrapper.** L. Payoff: separates orchestration from `@Published` state, gets generation off the main actor, makes LLM refinement injectable/testable behind a `CoachRefining` protocol. `PlanStore.swift` + `+LLMRefinement.swift`.
- **Add a `UserDatabaseConcurrencyTests` mirroring the CoachDatabase one.** M. Payoff: the only mutable shared store with no concurrency guard.
- **Replace the `PatternSlot` mutable-class `satisfiedBy` write-back with a returned `(Exercise, pattern)` tuple from `pickForSlot`.** M. Payoff: removes the one reference-mutation wart, makes the picker pure.

### iOS pbxproj gotcha (load-bearing)
`PhaseTraining.xcodeproj/project.pbxproj` is **gitignored** in this repo and uses **explicit `PBXFileReference` entries** (not `fileSystemSynchronizedGroups`/XcodeGen). Any backlog item that adds a new `.swift` file (the helper extractions, `Prescription`, `WorkoutRecipe`, new test files in a new file) requires the four-edits-per-file hand-patch to `project.pbxproj` or the build fails with "cannot find type X in scope" despite the file existing on disk. Tests added to the existing `WorkoutGeneratorTests.swift` avoid this entirely — prefer that for the P0 test work. (Refs project skills `phase-training2-gitignored-pbxproj`, `pbxproj-add-files-by-hand`.)
