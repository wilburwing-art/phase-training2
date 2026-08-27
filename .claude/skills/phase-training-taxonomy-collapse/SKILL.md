---
name: phase-training-taxonomy-collapse
description: When the user asks to "declutter" / "show fewer / 6ish tiles" / "remove secondary muscle groups" in a phase-training-family iOS app (phase-training, phase-training2, workout-plan), the load-bearing question BEFORE editing is which of two taxonomies they want — rollup (every item has a home, e.g. biceps lives under Arms) or curated (accessory items dropped entirely, e.g. biceps/calves removed). Different contexts inside the SAME app often want different answers — soreness UI tends to want curated (chest/back/shoulders/quads/hams/glutes/core), Library UI tends to want rollup (chest/back/shoulders/arms/quads/hams+glutes/core) — so ask both. Trigger when the user says "remove all secondary muscle groups", "show fewer muscle tiles", "6ish main groups", "declutter the [feature]", or any variant of collapsing the 11-bucket `MuscleBucket` into a coarser UI taxonomy. Skip for non-taxonomy work (renaming, restyling) or for adding a brand-new feature (use phase-training-feature-gap-checklist).
when-to-use: User wants to collapse the 11-bucket `MuscleBucket` enum (or 40-pattern `MovementCategory`) into a 6-7 tile UI taxonomy for soreness, Library, picker sheets, or chip strips. Triggered by phrases like "remove all secondary muscle groups", "6ish main groups", "declutter the muscle tiles", "fewer chips".
---

# Phase-training taxonomy collapse: ask BEFORE editing

## The two taxonomies (and why same app uses both)

Phase-training's `MuscleBucket` ships 11 cases: chest, back, shoulders, biceps, triceps, forearms, quads, hamstrings, glutes, calves, core. Any "collapse to ~6 tiles" request has two valid answers:

- **Rollup (every item has a home):** Chest, Back, Shoulders, Arms, Quads, Hams+Glutes, Core. Arms swallows biceps+triceps+forearms; Hams+Glutes swallows calves. Right when the surface needs to expose every exercise (Library, picker sheet) — no exercise should be unreachable.
- **Curated (drop accessories):** Chest, Back, Shoulders, Quads, Hamstrings, Glutes, Core. Biceps/triceps/forearms/calves removed entirely. Right when the data point is itself optional (soreness check-in) — accessory soreness is noise (side-effect of compounds), not a recovery signal worth a chip.

The user's phrase "remove all secondary" maps to curated. "Show fewer tiles" maps to rollup. They're not interchangeable.

## What to do

1. Before any code edit, fire `AskUserQuestion` with both options for EACH surface being collapsed. Soreness and Library separately — don't assume they share a taxonomy.
2. Add a new enum (e.g. `LibraryTile`) alongside `MuscleBucket` in `ExerciseFilters.swift`. Don't mutate `MuscleBucket.allCases` — downstream code (`MuscleFreshness`, `WorkoutGenerator`, `bucket(forSlug:)`) depends on the 11-case ground truth.
3. For curated UI: add `static let sorenessPrimaryCases: [MuscleBucket]` + `static let sorenessPrimarySlugs: Set<String>` properties. Use the slugs set to filter-on-read in `CoachContext` + `GeneratorContext` so legacy entries with dropped slugs don't leak into coach summaries.
4. For rollup UI: define a tile enum where each case maps to `[MuscleBucket]` members. `memberSlugs` becomes `members.flatMap { $0.memberSlugs }`. Compound tiles (>1 member) get a sub-bucket chip row inside the drill-down so users can narrow to a single MuscleBucket.

## Counts sanity check (run before promising "<20 items per screen")

```sh
sqlite3 PhaseTraining/Resources/coach.db <<'SQL'
SELECT mg.slug, COUNT(DISTINCT em.exercise_id)
FROM muscle_groups mg
JOIN exercise_muscles em ON em.muscle_group_id = mg.id AND em.role='primary'
GROUP BY mg.slug ORDER BY 2 DESC LIMIT 20;
SQL
```

Most tile bodies will exceed 20 exercises (Back ~98, Hams+Glutes ~179). The "All filters" sheet (modality/difficulty/compound-iso) is what gets the user under 20, not the tile-level taxonomy.
