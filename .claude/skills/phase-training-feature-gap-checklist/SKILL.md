---
name: phase-training-feature-gap-checklist
description: Before adding a "missing" lifting-tracker feature to phase-training, phase-training2, or workout-plan, run feature-gap-audit primed with the standard fitness-app foundations checklist. The recurring finding is that the user's mental model is out of date — most "missing" features are already SHIPPED or one screen away over existing data. Trigger when the user says "should I add X to the app", "we need to build X feature", "let's add muscle recovery / 1RM / PR tracking / rest timers / plate calc / etc." in a phase-training-family iOS repo. Skip for non-fitness apps and for changes scoped to a single existing screen (use feature-gap-audit directly).
when-to-use: User proposes adding a fitness-tracker feature to a phase-training-family iOS repo. Run this before any implementation discussion.
---

# Phase-training feature gap checklist

Sister to `feature-gap-audit` — primes the audit with the canonical fitness-tracker foundations and the phase-training-family-specific finding that the data layer runs years ahead of the UI.

## The 11-item probe

Pass this list to the `Explore` Agent in the audit brief. For each, classify as **SHIPPED / HIDDEN / THIN UI / MISSING** with file path evidence:

1. **Muscle recovery model** — `muscle_groups` table, per-muscle freshness %, anatomical body view
2. **1RM projection** — Epley/Brzycki formula, surfaced in Progress
3. **Per-muscle weekly volume** — aggregation by muscle × date range
4. **PR detection** — best weight per (exercise, reps) tuple + UI badge
5. **Progressive overload trending** — sparklines + "suggested next weight"
6. **RPE / RIR logging** — set-level fields + log UI
7. **Working-set vs warmup distinction** — `setType` enum or `isWarmup` flag
8. **Plate calculator** — barbell-loading helper
9. **Mesocycle / deload phase surfacing** — `SeasonPhase` enum + main-UI badge
10. **Rest timers** — countdown between sets
11. **Exercise progression suggestions** — deterministic progression scheme (not just LLM coach)

Also flag stumbled-upon: supersets, drop sets, AMRAP, body-weight trend, body-composition log, exercise substitution, exercise notes, video form references, workout templates.

## What you'll find (from 2026-05-20 phase-training2 audit)

The classification distribution is consistently top-heavy on **SHIPPED + HIDDEN**, not MISSING. Specifically in phase-training2:
- SHIPPED but user forgot: 1RM (Epley at `StrengthStandards.swift:88`), PR detection, rest timers, RPE, exercise substitution
- HIDDEN capability (data exists, no UI): **phase/mesocycle surfacing** (the app's NAMESAKE — `SeasonPhase` enum drives the planner but only shows up in profile + check-in), supersets (`routine_exercises.superset_group` column), body-weight trends, soreness/feedback
- TRULY MISSING: plate calculator, warmup flag, RIR

## Priority ordering rule

When synthesizing, lead with the "data layer is way ahead of UI" framing and order recommendations:

1. **Pure UI over existing data** (HIDDEN → surface it) — phase badge, recovery body view, body-weight chart, supersets visual
2. **Thin UI extensions** (THIN → fill it in) — "next weight" suggestion over PR data
3. **New schema + UI** (MISSING → build it) — plate calculator, warmup flag

## Why not just feature-gap-audit

Generic `feature-gap-audit` works on a single feature surface ("critique the library screen"). This skill is feature-gap-audit pre-loaded with (a) the right candidate list for lifting apps and (b) the phase-training-family priors about data-layer-ahead-of-UI. Saves a clarifying round and prevents shallow recommendations like "add 1RM!" when 1RM has been shipped for months.
