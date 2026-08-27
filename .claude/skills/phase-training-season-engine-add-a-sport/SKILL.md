---
name: phase-training-season-engine-add-a-sport
description: >
  Step-by-step recipe to add a NEW sport (mountain bike, trail run, etc.) to
  phase-training2's season-aware generator (SportSeasonGenerator), once skiing +
  climbing exist. Six touch points + the multi-sport-seed gotchas. Trigger when
  extending the season engine to another sport, adding a PhaseRule table /
  sport_movements pool for a new sport, or wiring a sport's variants + signature
  demand. Sibling to phase-training-season-aware-generator-reuse-map (what exists
  / the seam) and phase-training-season-generator-engine-pitfalls (the §5 math).
when-to-use: adding a new sport to the SportSeasonGenerator season engine
---

Proven adding climbing after skiing (2026-06-26): green on the first full eval run.

## The six touch points (all additive — the engine needs no special-casing)
1. **PhaseRule.swift** — add a `static let <sport>: [SeasonPhase: PhaseRule]`
   table (demand weights per phase, sessionsPerWeek, progression,
   `sessionVolumeCap` fatigue points, `deferToSport`, minutes). Add the sport's
   slug set (`<sport>Slugs`), and a dispatch branch in `resolve()`.
2. **SportSeasonGenerator.signatureDemand** — add the sport's signature demand
   case (ski=eccentricLeg, climb=fingerStrength) — the one demand the fatigue
   cap protects + check 2 asserts.
3. **PhaseRule.applyingVariantOverride** — add the sport's `SportVariant` cases.
   The switch is exhaustive (no `default`) so the compiler forces you to handle
   every variant; nudge demands then renormalize to sum 1.
4. **gen_sport_movements.py** — add a `<SPORT>_POOL` to `POOLS`. Run it, then
   `python3 scripts/db/build_db.py`, verify `0 orphans` + the sport's signature
   demand is covered in pre/in and (for an inversion sport) the inversion demand
   dominates in-season.
5. **SeasonFidelityTest** — add the sport to the `sports` fixture list
   (slug, variant, signature). The parameterized checks then cover it; add a
   sport-specific check only for a unique behavior (e.g. climbing's antagonist
   inversion = check 6).
6. **Catalog** — slug-match SPEC movements vs `exercises.json` FIRST. Both sports
   so far needed ZERO backfill — the catalog already had curated blocks
   (ski ids ~600s, climb ids 1-56). Don't assume you must author exercises.

## Gotchas that bit
- **Per-sport seed dedup.** A movement can serve two sports (Pallof #63 is ski
  core AND climb core). Dedup by `(sport, exercise_id)`, NOT exercise_id alone;
  the row `id` PK must be GLOBALLY unique across pools. sport_movements PK is the
  row id, exercise_id is a repeatable FK — the accessor filters `WHERE sport=?`.
- **Encode the sport's "inversion" in the weights, not the engine.** Climbing's
  in-season antagonist 0.40 (dominant) + fingerStrength→0 in transition is pure
  PhaseRule data; the demand-weighted allocator handles it with no code change.
- **eventPrep pool = `allowed(eventPrep) OR allowed(preSeason)`.** A sport whose
  eventPrep differs from pre-season (climbing eventPrep is antagonist-heavy, not
  just "pre-season tapered" like skiing) still needs its sharp pre-season
  movements — accept either tag. (Refines engine-pitfalls #4.)
- **One onboarding slug per sport.** `Sport.catalog` has `"climbing"` /
  `"alpine-skiing"` (single slug); boulder/sportRoute/trad are a `SportVariant`
  sub-axis passed to AthleteState, not separate sports. Tag the seed with the
  onboarding slug so `sportMovements(sport:)` matches.
