---
name: phase-training-exercise-search-broadening
description: >
  Before broadening exercise-name search in phase-training/phase-training2
  CoachDatabase (separator-insensitive matching, fuzzy/typo tolerance,
  synonyms, "did you mean"), know which of the THREE search methods you're
  touching and where broadening is safe. The non-obvious trap: `listExercises(search:modality:)`
  is used for EXACT-NAME RESOLUTION (callers re-filter by == name), not user
  search — the user-facing picker is the multi-filter overload. Trigger when
  asked to make exercise search typo-tolerant, fuzzier, punctuation-insensitive,
  or "find X even if mistyped" in a phase-training-family iOS repo.
when-to-use: >
  Implementing any search-matching change in CoachDatabase.swift (fuzzy, edit
  distance, separator/punctuation normalization, synonyms). Skip for routine
  search UI work unrelated to matching logic, or non-CoachDatabase search.
---

# Exercise-name search broadening in CoachDatabase

`CoachDatabase.swift` has **three** name-search methods. Match the change to the role:

1. **`listExercises(search:modality:)`** — overload 1. Despite the name, this is the
   **exact-name resolution** path. Callers (`ExerciseLookupCache`, `MuscleVolume.defaultResolve`,
   `WorkoutGenerator+Accessories`, `DayWorkoutPreviewSheet`, etc.) pass a stored canonical
   name then **re-filter with `.first { $0.name == name }` / `caseInsensitiveCompare`**. They
   throw away anything that isn't the exact name.
2. **`listExercises(search:muscleSlugs:patternSlugs:...)`** — overload 2. The **user-facing
   picker/search box** (`ExercisePickerSheet`, `LibraryMuscleScreen`). Results are rendered as
   a list. This is where free-text typos actually happen.
3. **`listRoutines(search:goal:)`** — searches the `routines` table, NOT exercises. Out of
   scope for exercise-search work; leave it alone.

## Where broadening is safe
- **Separator/punctuation normalization** (strip ` - ' ' .` from both query and column before
  LIKE): safe on **both** overloads — overload-1 callers re-filter, so a broader candidate set
  can't pick a wrong row; it's a no-op for exact lookups anyway.
- **Fuzzy / typo fallback** (OSA edit distance): put it on **overload 2 ONLY**, gated on a
  **zero substring result**. Firing fuzzy on overload 1's not-found case is wasted work — the
  caller filters every near-match out — and overload 1 runs on the hot `ExerciseLookupCache`
  per-row path.

## Mechanism that kept the diff small
To re-query "all filters minus the name" for the fuzzy candidate set without duplicating the
160-line WHERE-builder, **call the same overload recursively with `search: nil`** and the same
other filters. `lock` is an `NSRecursiveLock`, so re-entering `withLock` is safe, and `search:nil`
means it can't recurse back into the fuzzy branch.

## Notes
- Catalog has 572 rows; no bare "Bench Press"/"Deadlift" — names are qualified ("Barbell Bench
  Press", "Conventional Deadlift"). Use those as stable test probes, guarded with `XCTSkipUnless`.
- Use **OSA (restricted Damerau-Levenshtein)** not plain Levenshtein — an adjacent transposition
  ("benhc"→"bench", "deadlfit"→"deadlift") is the dominant typo and OSA scores it as 1 edit.
- New test files need `xcodegen generate` (pbxproj is generated/gitignored — see
  [[phase-training2-gitignored-pbxproj]]). Build/test via `xcodebuild -only-testing:...` with an
  explicit `-project` path; the XcodeBuildMCP session-default profile may point at a stale
  worktree (see [[xcodebuildmcp-session-defaults-cross-worktree]]).
