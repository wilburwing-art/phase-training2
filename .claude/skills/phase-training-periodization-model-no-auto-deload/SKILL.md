---
name: phase-training-periodization-model-no-auto-deload
description: Map of phase-training2's periodization/season data model and the load-bearing fact that there is NO auto-scheduled mesocycle or deload — weekTone==.recovery is the only real "deload this week" signal. Use before building or surfacing any phase/mesocycle/deload UI (badges, countdowns, "week N of M") in the phase-training family, so you don't fabricate a feature the data layer doesn't support.
when-to-use: When asked to surface, build, or extend phase / season / mesocycle / deload / periodization UI in phase-training2 (or phase-training / workout-plan). Trigger on "phase badge", "show the mesocycle", "deload indicator", "where are we in the block", "week 3 of 4". Skip for unrelated lift/log/catalog work.
---

# phase-training2 periodization model

The app is named for periodization, but the model is lighter than "mesocycle" implies. Know exactly what exists before you surface it — the namesake area is where it's tempting to invent structure that isn't there.

## Where the data lives (all on `TrainingMemory`)
- `seasonForPlanner: SeasonPhase` (`TrainingMemory.swift:257`) — resolves the active phase: prefers `seasonsBySport[primarySport]`, falls back to `defaultSeason`. Phases are **per-sport**, not one global value.
- `SeasonPhase` enum (`:379`): offSeason / preSeason / inSeason / eventPrep / maintenance, each with `.label`, `.subtitle`. `.maintenance`'s label is "Year-round / maintenance" — too long for tight chrome; I added `.compactLabel` for that.
- `peakDate: Date?` — only meaningful for `.eventPrep`; the Planner already tapers when it lands in the week (`Planner.swift:663`). A "peak in N days" countdown is honest.
- `weekTone: WeekTone?` on `PlanStore.overrides` (`WeekOverrides.swift:221`) — per-week dial: typical / recovery / build / busy, user-picked on the **Week tab**. `.recovery` maps to the generator's `.deload` intensity bias.

## The landmine
There is **NO** mesocycle week counter ("week 3 of 4") and **NO** auto-scheduled deload. Deload = the user choosing Recovery tone for that week. So:
- DO surface: phase label, event-prep peak countdown, and `DELOAD` derived from `weekTone == .recovery`.
- DON'T fabricate: "week N of M", "deload next week", auto-progressing blocks. Building those means building a new mesocycle model first — a separate, larger piece of work. Flag it; don't fake it.

## Surfacing notes
- Prior state (pre-2026-06): phase showed only in Profile + `SeasonsEditorSheet` + check-in. The Today header eyebrow was the first main-surface placement.
- `TabHeader` (`Components/TabHeader.swift`) is shared **text-only** chrome (eyebrow / eyebrowTrailing / title / subtitle / caption) and is **not tappable** — putting the phase there can't carry a deep-link to the editor. Use a pill in the scroll stack if tap-to-edit matters.
- Build to verify: see [[xcodebuildmcp-session-defaults-cross-worktree]] (defaults often point at a stale worktree — build the main repo with explicit `-project`) and [[phase-training2-gitignored-pbxproj]].
