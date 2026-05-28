# Part: Library + Progress + History

Scope: LibraryScreen, LibraryMuscleScreen, ExerciseDetailSheet, ExerciseFilterSheet, ProgressScreen, ProgressRecoverySection, HistoryScreen, WeekScreen, WeekDayEditSheet, CustomRoutineEditSheet + Components (BodyAnatomyView, MuscleChipBadge, MuscleChipGeneratorView, ExerciseThumbnail, CachedAsyncImage, InsightCard). Data layer: Exercise.swift, ExerciseFilters.swift, CoachDatabase.swift.

DB facts (coach.db, verified): 551 exercises; **989** substitutions; **2303** sport-relevance rows (475 ex); **1133** phase rows (326 ex); **593** movement-pattern links; **224** injury-relevance rows (167 ex); **752** equipment links (all 551 ex); recovery_demand/cns_load/intensity_category populated on **all 551**; **0** alias rows; 546 ex with image_url, 387 with video_url; 148 stock routines (none surfaced).

---

## Per-screen findings

### LibraryScreen — Correctness 4 / UX 3 / Data-gap 2 / Perf 4 / A11y 3
- The eyebrow count runs a **full unfiltered `listExercises` on every body re-render** (LibraryScreen.swift:80-92) just to `.count` 551 rows. That's a full SQL query + 551 `Exercise` allocations per render, discarded. Cache it or add a `countExercises()`. (Perf)
- 148 stock `routines` in coach.db are completely invisible — the "Workouts" segment shows only user-built `CustomRoutine`s (LibraryScreen.swift:257). A library that ships 148 curated routines and surfaces zero of them is the single biggest browse gap on this tab. (Data-gap)
- `metaLine(_:)` (LibraryScreen.swift:319) is dead — exercises route through `tileGrid`, never a flat row, so this function is never called. (Hygiene)
- Search bar on Workouts only appears at ≥5 routines (LibraryScreen.swift:40,98); reasonable, but there's no count affordance telling the user why search vanished.

### LibraryMuscleScreen — Correctness 4 / UX 3 / Data-gap 2 / Perf 3 / A11y 3
- `rows` is a computed property hitting `listExercises` (LibraryMuscleScreen.swift:215). It is read **twice per render** — once in `header` for `\(rows.count) EX` (line 75) and once in `list` (line 189). Two identical SQL queries + 2× Exercise array builds every keystroke while typing in the search field. Memoize into `@State` via `.task(id:)` or compute once. (Perf — material with 551 rows + per-keystroke search.)
- Cardio/mobility/conditioning exercises have **no muscle relations**, so they match no `LibraryTile` and are **unreachable from the Library landing grid entirely** — the 7 tiles are all muscle buckets. A user can never browse to "Jump Rope" or a breathing drill. (Correctness/Data-gap)
- Movement-plane, energy-system, and modality richness exist but the only secondary filters are modality/difficulty/environment/compound (ExerciseFilterSheet). No filter for unilateral, low-energy, pre-event-safe, warmup-compatible — all populated columns.

### ExerciseDetailSheet — Correctness 3 / UX 4 / Data-gap 1 / Perf 3 / A11y 2
- **This is where the data-richness gap is most acute.** The header comment claims it "surfaces every field on `Exercise` that the rest of the app discards" — but `Exercise` (Exercise.swift:3-35) only carries ~21 of ~50 exercise columns. The struct never loads recovery_demand, cns_load, intensity_category, energy_system, movement_plane, contraction_type, default_tempo, desk_worker_notes, age_considerations, contraindications, injury_prevention_notes, pt_rehab_relevance, common_compensations, tags, equipment, or image attribution. The sheet can't show what the model never selected (CoachDatabase.swift:228-232 SELECT list).
- **989 substitutions are not shown here.** `substitutes()` exists (CoachDatabase.swift:434) but is only called from SubstituteExerciseSheet / CoachRequest / generator — never from the detail view. The detail sheet shows a "Difficulty chain" (pattern+difficulty adjacency) but not the curated, context-tagged ("home_friendly", "pre_event_safe") substitution graph. (Data-gap)
- Anatomy section discards secondary + stabilizer roles (ExerciseDetailSheet.swift:172-175) — only `primary` renders. Yet `anatomyLegend` still exists and `BodyAnatomyView.HighlightIntensity` ships a 3-tier red/orange/yellow scale that nothing in this screen uses anymore. The legend is a single "Primary" dot, so the multi-tier color machinery is dead weight here. (Consistency)
- `heroImage` (line 240) calls `CachedAsyncImage` with the **full image_url**, ignoring the bundle-first `ExerciseThumbnail`/`BundledExerciseImage` path. Detail always hits network (or URLCache) even though the bundled WebP exists on disk — a needless load + offline failure where the thumbnail in the list it came from rendered instantly offline. (Correctness/Perf)
- Watch-demo `Link` and external image both lack accessibility labels beyond default; `metaBadges` chips fine.

### ExerciseFilterSheet — Correctness 4 / UX 4 / Data-gap 3 / Perf 5 / A11y 3
- Modality list (line 18-24) hardcodes only 5 of the 17 schema modalities (flexibility, mobility, balance, sport_drill, pt_rehab, prehab, breathing, recovery, warm_up… all omitted). Filtering by "Mobility" or "Prehab" is impossible despite the data. (Data-gap)
- Custom `FlowLayout` (line 163) is fine and correct.
- Chips have no `accessibilityAddTraits(.isSelected)` — selection state is color-only, invisible to VoiceOver. (A11y) Same pattern in LibraryMuscleScreen sub-bucket chips.

### ProgressScreen — Correctness 3 / UX 4 / Data-gap 4 / Perf 3 / A11y 2
- `volumeCard` uses `Double(set.weight)` / `Double(set.reps)` (lines 200-203). Bodyweight-offset entries logged as `"+25"` (used in the previews/history, e.g. weighted pull-up) **fail `Double()` and are silently dropped from volume**. Same in `topExerciseSeries` (line 732 `Double(set.weight)`). Any "+N" or "BW" set contributes 0 volume and never appears in per-exercise trends. (Correctness — real data-loss bug.)
- `ExerciseSparkline` (Swift Charts, line 828) is **defined but never used** — `perExerciseCard` switched to `ExerciseTile(.sparkline:)` with hand-normalized points (line 371). Dead Charts code + an unused `import Charts` cost. The file header still claims Charts is used "where it pays back its weight." (Hygiene/Consistency)
- Charts are color-only with no axis labels or values on the bars/line (sessionsCard, volumeCard). Bar heights and the target line are unlabeled; `LineSpark` shows only first/last value. Hard to read precise weeks. VoiceOver gets nothing — no `.accessibilityLabel` on any chart. (UX/A11y)
- PR feed keys `ForEach` on `\.offset` (line 416) — fine for a static prefix(10) but fragile if it ever animates.
- Good: streak grace logic (line 681) and warmup exclusion are thoughtful and correct.

### ProgressRecoverySection — Correctness 4 / UX 3 / Data-gap 3 / Perf 2 / A11y 3
- **Perf concern:** every muscle row renders a **full live `BodyAnatomyView`** at 36×64 (line 143-147) — that's MuscleMap's ForEach-of-shape-paths per row, up to ~19 rows (`mainSlugs`). MuscleChipBadge exists precisely because "the live BodyAnatomyView blurs to a uniform silhouette below ~80pt" (MuscleChipBadge.swift:8) and is expensive at chip scale — yet this section renders the expensive live path 19× at 36pt anyway. Should use the pre-rendered chip asset. (Perf — biggest perf issue in the part.)
- `mainSlugs` is a hardcoded Set (line 208) duplicating muscle-bucket membership already encoded in `MuscleBucket.memberSlugs` — drift risk. (Consistency)

### HistoryScreen — Correctness 4 / UX 4 / Data-gap 4 / Perf 3 / A11y 3
- Solid. `displayedSessions`/`totalDoneSetsAllSessions`/`avgRpeAllSessions` recompute on each render but session counts are small. The expanded-detail comment notes the `pr` flag is absent on LoggedSet (line 292) — PRs computed in Progress aren't cross-referenced here, so History can't badge a PR set. (Data-gap, minor)
- `expandedDetail` keys inner ForEach on `\.offset` (line 274) — acceptable, list is static while expanded.

### WeekScreen / WeekDayEditSheet — Correctness 4 / UX 4 / Perf 4 / A11y 3
- WeekScreen drag-swap + fixed 7-row GeometryReader layout is clean and correct; self-drop guarded (WeekScreen.swift:209). `MovableDay` round-trips through a per-call `DateFormatter` (line 231-243) — allocs two formatters per drag, negligible.
- `DayRow` has no combined accessibility element; weekday/number/kind/title are 4 separate VoiceOver stops. (A11y)
- WeekDayEditSheet is action-routing only; not data-rich, fine.

### CustomRoutineEditSheet — Correctness 4 / UX 4 / Perf 4 / A11y 3
- Superset grouping + render-order/source-order index translation (moveExercises line 374, binding(forId:) line 235) is carefully done and correct. Swap binding via Int?→wrapper is sound.
- `binding(forId:)` getter falls back to `draft.exercises[0]` if id missing (line 237) — crashes on empty array, but `canSave`/delete flow makes empty transient; low risk.

### Components
- **CachedAsyncImage** (correctness 3): on `url == nil` it sets `didFail = true` and shows the failure (broken-photo) state rather than a neutral placeholder — a nil URL is "no image," not "load failed." Minor UX. Caches by absolute URL string; no in-flight dedup so two simultaneous views of the same URL double-fetch. NSCache 600-count / 64MB is reasonable for 551 line-art images.
- **ExerciseThumbnail / BundledExerciseImage**: bundle-first resolution is good and the right perf call. Detail sheet bypassing it (above) undercuts the win.
- **MuscleChipGeneratorView**: DEBUG-only asset generator, not shipped — fine.

---

## Data-richness gap table: coach.db data that exists but is NOT surfaced in Library/Progress UI

| Table / column | Rows / coverage | Where it could surface | Status |
|---|---|---|---|
| `routines` (stock) | 148 routines | Library "Workouts" segment | **Invisible** — only user customs shown |
| `exercise_substitutions` | 989 (ctx-tagged) | ExerciseDetailSheet "Alternatives" | Loaded only in SubstituteExerciseSheet, not detail |
| `exercise_sport_relevance` | 2303 / 475 ex | Detail: "Why this for [sport] (support_role, score)" | Used only for list *ranking*; never displayed |
| `exercise_phases` | 1133 / 326 ex | Detail: phase priority + volume_guidance | **No query exists in Swift** |
| `exercise_injury_relevance` | 224 / 167 ex | Detail: prehab/rehab/contraindicated flags | **Not queried** in library/detail |
| `exercise_equipment` | 752 / all 551 | Detail + a "Where/equipment" filter | Queried for planner only, never in browse UI |
| `recovery_demand`,`cns_load`,`intensity_category` | all 551 | Detail meta badges / Progress fatigue context | **Not in `Exercise` SELECT** |
| `energy_system`,`movement_plane`,`contraction_type` | populated | Detail "mechanics" / filters | Not in model |
| `desk_worker_notes`,`age_considerations`,`contraindications`,`injury_prevention_notes`,`common_compensations` | 43–72 each | Detail safety/notes sections | Not in model |
| `default_tempo` | populated | Detail Defaults grid (shows sets/reps/rest/dur only) | Not in model |
| modalities beyond 5 (mobility, prehab, breathing, …) | 17 total | ExerciseFilterSheet | Only 5 hardcoded |
| `tags` (JSON) | populated | Detail chips / search | Not loaded |

Bottom line: the detail sheet's own header claims it surfaces "every field," but the `Exercise` struct selects ~40% of exercise columns and zero of the five rich relational tables (substitutions, sport-relevance, phases, injuries, equipment) reach the browse surface. The richness is real and largely invisible.

---

## Cross-cutting issues
1. **`Double(weight)` rejects bodyweight-offset entries** ("+25", "BW") across ProgressScreen volume + per-exercise trends (ProgressScreen.swift:201,732) and StrengthStandards consumers — silent data loss for the app's own canonical pull-up logging format.
2. **Repeated full-table queries in computed `var`s**: LibraryScreen eyebrow (every render), LibraryMuscleScreen `rows` (2× per render, per keystroke). No `countExercises()`; no memoization.
3. **Selection state is color-only everywhere** (filter chips, sub-buckets, segment control) — no `.accessibilityAddTraits(.isSelected)`. Charts have no accessibility representation.
4. **Live BodyAnatomyView used at sub-80pt scale** in ProgressRecoverySection rows despite MuscleChipBadge existing to avoid exactly that cost.
5. **Dead code**: `ExerciseSparkline` + `import Charts` usage (ProgressScreen), `metaLine` (LibraryScreen), unused tri-tier intensity scale in detail anatomy.
6. **Two parallel "easier/harder" systems** in detail: free-text regression/progression ("Coach notes") AND pattern-adjacency "Difficulty chain" — overlapping, no explanation of the difference to the user.

---

## Tiered backlog

**P0**
- Fix `Double(weight)` to parse "+N"/bodyweight offsets so volume + trends don't silently drop pull-up/dip data — S — ProgressScreen.swift (+ shared weight-parse helper)
- Surface the 148 stock `routines` in the Workouts segment (or a third segment) — M — LibraryScreen.swift + CoachDatabase.listRoutines wiring
- Memoize LibraryMuscleScreen `rows` and add `CoachDatabase.countExercises()` for the eyebrow; stop double-querying per keystroke — S — LibraryMuscleScreen.swift, LibraryScreen.swift, CoachDatabase.swift

**P1**
- Add a Substitutions / "Alternatives" section to ExerciseDetailSheet using existing `substitutes()` (989 rows, context chips) — M — ExerciseDetailSheet.swift
- Make ExerciseDetailSheet hero use bundle-first ExerciseThumbnail path (offline + instant) — S — ExerciseDetailSheet.swift
- Replace live BodyAnatomyView in recovery rows with the MuscleChipBadge pre-rendered asset — S — ProgressRecoverySection.swift
- Add `accessibilityAddTraits(.isSelected)` to all selectable chips/segments — S — ExerciseFilterSheet, LibraryMuscleScreen, LibraryScreen
- Make cardio/mobility/conditioning reachable from Library (an "Other / Conditioning" tile or modality entry) — M — ExerciseFilters.swift, LibraryScreen.swift

**P2**
- Extend `Exercise` model + SELECT to carry recovery_demand/cns_load/intensity/tempo/equipment and add a "Mechanics & demand" detail section — M — Exercise.swift, CoachDatabase.swift, ExerciseDetailSheet.swift
- Surface exercise_phases (volume_guidance) + sport_relevance ("why this for your sport") in detail — M — CoachDatabase.swift, ExerciseDetailSheet.swift
- Expose remaining modalities + unilateral/low-energy/warmup filters — S — ExerciseFilterSheet.swift
- Add axis labels / values + accessibility to Progress charts — M — ProgressScreen.swift
- Remove dead code (ExerciseSparkline + import Charts, metaLine, unused intensity tiers) — S — ProgressScreen.swift, LibraryScreen.swift, ExerciseDetailSheet.swift
