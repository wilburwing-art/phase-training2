---
name: phase-training-generator-sweep-report
description: >
  Build or use the WorkoutGenerator controlled-variable sweep report — a fast
  local inner loop for validating generator changes by sweeping one input at a
  time and diffing the output side-by-side. Trigger when the user wants to
  "shorten the validation loop", "stress-test the generator", "see how each
  variable changes the workout", "which knobs are dead", or after editing
  focusBias/prescription/a GeneratorContext signal in phase-training-family
  iOS repos. Distinct from the eval-rig LLM-grader loop (the LONG loop).
when-to-use: validating WorkoutGenerator behavior locally without round-tripping through eval-rig
---

This already exists in phase-training2: `scripts/generator-sweep.sh` runs
`PhaseTrainingTests/GeneratorSweepReportTest.swift`, which writes
`/tmp/generator-sweep/report.html` (side-by-side, opens automatically) AND
`/tmp/generator-sweep/report.md` (paste-friendly twin — one labeled block per
variant, no side-by-side table since MD cells can't hold nested lists). Reuse it; don't rebuild. One
command: `scripts/generator-sweep.sh`.

## What it is
An XCTest (same headless-export-bridge pattern as `EvalRigExportSmokeTest`)
that sweeps one input at a time (OFAT) against a fixed baseline, regenerates a
full simulated week per value (`liftIndex 0..<liftDaysPerWeek`), and renders a
side-by-side HTML table: baseline column pinned sticky-left, variant columns
scroll, cells differing from baseline highlighted amber. A top summary table
flags any variable whose variants ALL match baseline as ⚠ DEAD. Runs ~0.5s.

## The load-bearing trap (why a naive sweep lies)
The app seeds the generator with `memory.planInputsHash`, which itself changes
when ANY memory field changes. If you use that as the seed in a sweep, you
confound "the logic reacted" with "the deterministic pick landed elsewhere
because the seed moved." **Use a FIXED seed** (`gen-sweep-day{N}`, constant
across every column) so any delta is attributable purely to the swept variable.

## Other recipe details that worked
- Seed context probes (priorBest, stagnantExercises) from the CONTROL week's
  actual picks (`baselineWeek.flatMap{$0.lines.map{name.lowercased()}}`), so the
  wiring test is guaranteed relevant instead of guessing catalog names.
- For readiness, include a `hasReadinessData=false` variant as a no-op control —
  scaling only fires when true; this proves the gate, not just the score.
- Variables: experience, primaryFocus, age, sessionMinutes, liftDaysPerWeek,
  equipment, soreness; context.readinessScore/priorBest/stagnant;
  strategy.intensityBias/durationMinutes/focus.
- Stored mutation closures can't capture `self` — put `makeSoreEntry` at file
  scope. Map params assigned to `Int?` fields (age, durationMinutes) get widened
  to optional → pin the type: `.map { (a: Int) in ... }`.
- **`expectsChange` anomaly flag (the load-bearing hardening, added 2026-06-04).**
  A per-VARIABLE live/DEAD verdict LAUNDERS per-VARIANT no-ops — one working
  sibling makes the whole row read "live" while a broken variant hides. Each
  `Variant` carries `expectsChange: Bool`; the report flags an expects-change
  variant whose weekSignature == baseline as a **NO-OP anomaly** (and
  expects-no-change that moved as UNEXPECTED). It caught the real bug
  (`strategy.emphasizePatterns` is inert at single-alternative slots — sibling of
  the deleted patternFrequency; audit N9, documented-not-deleted since it's an
  LLM lever) AND two of my OWN wrong expectations (readiness 1.0 correctly ==
  full-volume baseline; sessionMinutes 45 does drop a slot) → the flag forces you
  to STATE each expectation, not assume it. Set `expectsChange:false` for
  baseline-equal values + designed no-ops (hasReadinessData=false control,
  readiness 1.0, 90/120-min raises that can't add fixed slots).
- Signature + both renderers include `tempo` + `warmUps` (else a tempo-only or
  warm-up-suppression change reads false-DEAD); `source` skipped — always `.recipe`.
- **Tier-2 fidelity hardening (built + verified 2026-06-04).** (a) ONE seed per
  column, not a per-day salt — matches the app (single `planInputsHash` all week,
  Planner:517; variety comes from `recentlyPicked`, fed identically to every day),
  so repeated-focus days come out IDENTICAL as the app actually produces them
  (don't fake variety with a salt). (b) Multi-seed verdict: each `Column` carries
  `movedAnySeed`, re-checked across 4 fixed seeds ONLY when seed[0] shows no move,
  so a sparse probe (rotator-cuff injury whose contraindication isn't in this
  seed's picks) isn't falsely flagged DEAD. (c) Second baseline B
  (advanced/generalStrength/90min) via a `control: () -> TrainingMemory` carried
  in `BaselineCtx` — unmasks schemes baseline A clamps (PROVED: general_strength
  5×5 at B vs 4×5 capped at A by the intermediate set-cap). (d) End-to-end probe
  building context via `GeneratorContext.from(soreness:)` instead of hand-set
  fields — catches builder↔consumer drift (the H11 sore-filter class); read LIVE
  = no drift. STILL OPEN: explicit pairwise interaction combos
  (readiness×deload hits the set floor, focus×day-type accessory layers).

## Auditing coverage (which inputs the sweep is missing)
The authoritative input surface = what `generateLift` actually reads:
`grep -oE "(memory|profile|context|strategy)\.[a-zA-Z]+" WorkoutGenerator.swift | sort -u`
(~25 fields). The initial harness covered ~13. Sweep against this list, not intuition.
- **Dual-soreness trap:** `memory.soreness` drives ONLY the RPE-7 cap
  (`isMuscleSoreForExercise`); the pick-time candidate exclusion runs off a
  SEPARATE field, `context.recentSoreAreas` (`pickForSlot`). Sweeping one does
  NOT cover the other — a soreness column that only sets `memory.soreness`
  gives false coverage.
- **Fidelity caveat:** the harness sweeps `memory` and `context` as independent
  axes, but the live app DERIVES context from memory (`GeneratorContext.from`)
  and computes strategy from Planner state (season / mesocycle-deload / taper /
  missed-reshuffle). So `generateLift`-in-isolation answers "does each knob move
  output," not "does the real pipeline behave." Planner-level inputs only appear
  when they collapse to a swept strategy field (auto-deload → `intensityBias=.deload`).
- OFAT misses interaction-only branches (e.g. lower-body accessory layer needs
  hypertrophy + a legs/lower day; rest-bumps need hypertrophy + compound + focus).
- **Differential probe — proving a DEAD verdict is real, not an empty seed.**
  Pair the suspect knob with a sibling that feeds the SAME seed data through a
  STRONGER operation. If the sibling is live and the suspect is DEAD on identical
  data, the deadness is real. Caught 2026-06-04: `context.patternFrequency`
  (reorder, seeded with control patterns ×10) = DEAD, while
  `strategy.deprioritizePatterns` (same `day1Patterns`) = live → reordering by
  frequency is washed out by the staple pre-pass + deterministicPick; only
  REMOVING a pattern moves output. (See `...-dead-and-broken-signals` #6.)
  Always seed pattern probes from captured `GeneratedExercise.pattern` (add it to
  the captured row), so the seed is provably non-empty.

## Mechanics
New test file is auto-discovered via `Project.yml`'s `sources: PhaseTrainingTests`
(XcodeGen) — run `xcodegen generate`, no pbxproj edits. See
`phase-training2-gitignored-pbxproj`. Verdicts also print to stdout
(`live`/`DEAD` per variable) so a console run flags regressions without opening
the HTML. Pairs with `phase-training-generator-context-dead-and-broken-signals`
(what the DEAD flags mean) and `eval-rig-close-the-loop-workflow` (the long loop).

## Handing the report to a reviewer agent (Cowork / fresh agent)
Don't say "analyze it" or "critique it" — you get a summary or vague nitpicks.
The report is workout *programming output*, so the lens is a strength coach, not
a code reviewer, and the sweep has a built-in rubric: each variable has an
EXPECTED DIRECTION the workout should move min→max. Prompt = role + frame +
verdict format: "You're an evidence-based S&C coach. Each section varies ONE
input (baseline: intermediate/hypertrophy/age 32/60 min/full gym; amber =
differs from baseline). For each variable: (1) what should the workout do as it
goes min→max, (2) does the generator do that, (3) verdict correct /
wrong-direction / too-weak / too-strong / missing, cite column+exercise. Rank
the 3 worst. Don't praise what's fine." Two gotchas: (a) a remote/cloud agent
can't read `/tmp/` — copy the purpose-built `report.md` INTO the message
(`pbcopy < /tmp/generator-sweep/report.md`), not the HTML; for a quick gut-check
the Summary table (top ~25 lines) shows live/DEAD per variable on its own; (b) scope to judging BEHAVIOR, not "improve the code" (it sees
outputs, not the full generator → code suggestions are hand-wavy). Reviewing the
HARNESS/methodology is a SEPARATE prompt that needs CODE access (a local session
reading the files), NOT the report. Hand an adversarial reviewer the 5
false-confidence vectors — (1)(2)(4)(5) + per-variant masking are BUILT+VERIFIED
2026-06-04; only (3) explicit interaction combos remain open: (1) ✅ signature
captures `tempo`+`warmUps` + per-variant NO-OPs flagged via `expectsChange`;
(2) ✅ second baseline B (advanced/strength/90min) unmasks the 5×5 the
intermediate set-cap hid; (3) ⬜ OPEN — OFAT still misses interactions
(focus×day-type accessory layers, readiness×deload set-floor, soreness×focus) →
add 2-3 named pairwise combos; (4) ✅ one seed per column (matches app's single
`planInputsHash`, Planner:517) + multi-seed `movedAnySeed` verdict + a
`recentlyPicked` variety sweep; (5) ✅ end-to-end `GeneratorContext.from`
probe catches the H11 builder/consumer-drift class (read LIVE = no drift).
Always ask it to independently re-verify any DEAD/delete call (truly inert, or
only inert at this baseline?).
