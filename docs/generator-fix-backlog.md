# Workout Generator — Fix Backlog (tiered)

Source: per-input-variable sweep critique (2026-06), tiered + **re-verified against
on-disk code** by a second pass. Companion to `docs/generator-audit.md` (the grounded
hypothesis audit) — that doc is the *evidence base*; this doc is the *actionable,
checkbox-able work list*. Written to a separate file on purpose: two other sessions
are editing the generator + the audit doc right now (see "Coordination" at bottom).

The sweep critique **over-reached on five claims** — they are listed under
"Refuted / already-fixed (do NOT re-do)" so a runner doesn't burn time re-fixing a
working filter or reverting a per-spec behavior. Three of the critique's "worst three"
turned out to be partly wrong; the corrected ranking is in Tier 0.

## How to run this

1. **Re-pull + re-run the sweep first.** The generator is moving under you. Run
   `scripts/generator-sweep.sh` (or the `GeneratorSweepReportTest`) against *current*
   `main`, not the critique text. Several critique claims are already fixed in the
   working tree.
2. Work **Tier 0 → Tier 1 → Tier 2**. Tier 2 items each begin with a **verify** step.
3. Tier 3 is **gated on the test list** in §"Test coverage gate." Don't start it without those tests.
4. One commit/PR per item. Don't bundle across tiers. (No branch protection on main —
   both founders push direct — so small, rebased, single-purpose commits.)

---

## Tier 0 — Safety / ship blockers (real physical-harm blast radius)

- [ ] **T0.1 — Accessory layer bypasses readiness scaling, deload, soreness exclusion, dislike filter, and the duration budget.** ONE root cause, multiple symptoms.
  - Root: the hypertrophy accessory layer is a **parallel pick+prescribe path** appended *after* the main slot loop. It is never passed `context`, never applies `combinedSetsMul`, never applies `excludeKws`, never checks the budget.
    - Append site: `WorkoutGenerator.swift:287-332` (unconditional `picks.append`, adds to `elapsedSec` with **no budget gate**).
    - Pick path: `pickAccessoryByName` `WorkoutGenerator.swift:858-882` — applies env + equipment + `excludedIds` only.
    - Row build: `makeAccessoryRow` `WorkoutGenerator.swift:897-940` — uses **raw** `prescription` sets; never multiplies by `combinedSetsMul` (the readiness × deload multiplier the main loop computes at `:200-208`).
  - Confirmed symptom sites:
    - Sore chest/shoulders/triceps → Cable Lateral Raise + Rope Pushdown still appended (sore-tissue load↑).
    - Sore quads/hams/glutes → Lying Leg Curl still appended (direct hamstring work on sore hams).
    - readinessScore 0.0 → accessory at full sets while every main lift is scaled down.
    - Deload week → accessory at full sets (deload only scales the main loop).
    - Dislike 'machine'/'cable' → accessory survives (it never sees `excludeKws`).
    - Low session minutes → accessory pushes day over budget (not gated).
  - **Fix locus (preferred):** route accessory candidates through the same pipeline the main loop uses — thread `context` (for `recentSoreAreas` + `readinessScore`) and `excludeKws` into `appendHypertrophy*Accessories`, apply the sore filter, multiply `makeAccessoryRow` sets by `combinedSetsMul`, and gate the append on the duration budget (mirror `:217-220`).
  - **DO NOT "fix" injury or env/equipment here** — the accessory path *already* respects them (`excludedIds` carries `profile.excludedExerciseIds`; `pickAccessoryByName` checks env + `requiredEquipmentSlugs`). Those are correct.

- [ ] **T0.2 — Injury protection under-fires: filter works, data + substitution don't.** (Corrects the critique's "rotator cuff = zero changes / lumbar swaps INTO trap bar.")
  - The injury **filter is correct and tested** — `profile.excludedExerciseIds` → `pickedIds` `WorkoutGenerator.swift:146` → enforced `CoachDatabase.swift:587`; covered by `test_injuryContraindications_areExcluded`. **Do not rewrite it.**
  - Real gap A (data): `exercise_injury_relevance` is sparse (87 rows). `rotator-cuff-injury` contraindicates only 4 niche exercises (Campus Board, Explosive Pull-Up, Landmine Rotational Press, Ring Dip) — so Seated OHP and barbell pressing survive for a rotator-cuff user. **Verify** per-injury coverage, then fill contraindications for the common injuries against the default pressing/hinge leads.
  - Real gap B (no safe-substitute backfill): injuries only *remove*. Excluding RDL / conventional / back-squat for lumbar herniation leaves heavier axial options (e.g. Trap Bar Deadlift) in the pool with nothing steering toward the safest hinge. **Decide:** add an injury-aware substitute step (new `injury_context` on `exercise_substitutions`, or an `exercise_injury_substitutions` mapping) queried alongside the pick path.

---

## Tier 1 — User-facing bugs (one-function fixes)

- [ ] **T1.1 — Bodyweight pull day collapses to ~1 exercise.** `vertical-pull` and `horizontal-pull` have **zero** bodyweight-only options in coach.db (Body Row requires gymnastic-rings), so both required slots return nil and are skipped; only `scapular-retraction` (1 bodyweight option) survives. Recipe: `WorkoutGenerator.swift:1335-1341`. Fix: data (tag/ add bodyweight pull options — inverted row, towel/door rows) **or** pattern-escalation in `pickForSlot`.
- [ ] **T1.2 — Time-based movements prescribed in reps.** Prescription ignores coach.db `default_duration` ("30-60 sec") and synthesizes a rep band when `default_reps` is null (Tuck Hold → `3×10-12`; Reverse Plank / Wall Sit / Battle Ropes / Farmer Carry → "3×8-12"). Fix: emit a **time** prescription when `default_reps` is null and `default_duration` is set. Locus: `WorkoutGenerator.swift:~1080-1081` + `defaultRepsFromFormula` `:1214-1217`.
- [ ] **T1.3 — No graceful-degradation floor when equipment empties slots.** `pickForSlot` nil → `else { continue }` `WorkoutGenerator.swift:159-171`; no escalation, no minimum-exercise count. (Same root as T1.1.) Fix: a count floor or pattern-fallback chain.
- [ ] **T1.4 — Duration budget is dead upward.** Budget only *drops* optional slots when low (`:217-220`); it never *adds* work when minutes are high, so 45 = 60 = 90 = 120 produce identical content. Fix: a high-minute volume/accessory tier, or document the ceiling. Budget calc `:136-139`.
- [ ] **T1.5 — Beginner gets unmodulated near-max work.** Experience caps **sets only** (`min 3 / min 4 / uncapped`) `WorkoutGenerator.swift:1061-1067`; reps and RPE are not experience-modulated, so a beginner in a low-rep focus gets 3-6 reps @ RPE 8-9. Fix: experience-based RPE cap / rep floor in `rpeTempoHints` (`:687-745`) or `focusBias`.
- [ ] **T1.6 — Advanced ≡ intermediate dose.** Advanced set clamp is `break` (uncapped) but both land at the focus-bias cap, so output is identical. Decide whether advanced should carry more volume; the uncapped clamp currently never binds. `WorkoutGenerator.swift:1061-1067`.
- [ ] **T1.7 — Dislike filter is name-substring, not equipment-tag.** Dislike 'machine' removes "Triceps Extension (Machine)" but keeps "Lying Leg Curl" + cable work. `CoachDatabase.swift:600-602`, kws built `WorkoutGenerator.swift:151`. Fix: also filter on `requiredEquipmentSlugs` (already fetched at the stagnation-swap path) so equipment dislikes match by tag.

---

## Tier 2 — Half-finished feedback loops (verify, then act)

- [ ] **T2.1 — priorBest / bodyweight progression.** **Verify** the critique's "190/165 lb broadcast everywhere incl bodyweight push-up" against a *fresh* sweep — current code skips `weight=0` from priorBest (`GeneratorContext.swift:263-273`), so bodyweight gets **no** target (contradicts the critique). Real gap to implement: reps-based progression for `weight==0` lifts. Hint builder `WorkoutGenerator.swift:591-593`.
- [ ] **T2.2 — Age 55→70 undifferentiated; no power/balance bias by 70.** **Verify** (confirmed: no `age>=70` branch; both → `.magazineBodybuilding`, `EraAffinity.swift:162-171`). Then add a 70+ branch (lower volume, power/balance bias). Age effects live `DemographicProfile.swift:156-173`.
- [ ] **T2.3 — Era cohort over-couples (root of the age + split contamination).** Era is **derived from age** and then **rewrites split shape** — `eraStyle.splitPreference` overrides the day-count→split default (so age 45 → tNationForum → U/L flip, age 18 → currentMeta). **Verify** the override precedence: default split `WorkoutGenerator.swift:1282` vs `eraStyle.splitPreference` `:~72-75`. Then constrain era to **cosmetic** flavor (implement/rep tweaks), not structural split/volume changes. This single fix de-contaminates the `age` AND `liftDaysPerWeek` variables.
- [ ] **T2.4 — sessionMinutes downward overrun.** **Verify** after T0.1 lands (the accessory layer not being budget-gated is a major contributor). Remaining: required slots can't drop below the floor, so a 20-min leg day may still exceed budget. Re-run the sweep post-T0.1 before acting.
- [ ] **T2.5 — Stagnation swap can cross movement pattern.** Farmer Carry → Wall Sit (carry → quad isometric). **Verify** `exercise_substitutions` returns cross-pattern subs, then constrain the swap to same `movement_pattern`. `WorkoutGenerator.swift:553-589` (= existing audit H9).

---

## Tier 3 — Architecture debt (GATED on the test list below)

- [ ] **T3.1 — Unify the accessory pick path with `pickForSlot`.** The clean form of T0.1: instead of threading 4 signals into a parallel path, make accessory slots first-class `PatternSlot`s that flow through the same filter/prescription pipeline. **Do not start until T0.1's contract tests exist** (else you'll silently regress the bypass fix).
- [ ] **T3.2 — Split `WorkoutGenerator.swift` (1452 lines).** Recipe builder, prescription, accessory layer, superset structure are separable. Cosmetic; one PR per concern; gated on tests.

---

## Tier 4 — UX polish (separate sitting)

- [ ] **T4.1 — Surface a reason string** for silent set-clamp / lift-day reduction (declared 5 days → emits 3, no explanation). `Planner.swift:71-83`, Week UI. (= existing audit H18.)
- [ ] **T4.2 — Accessory note copy** is fine now ("auto-added for isolation coverage", `:935`); the critique's "auto-added for upper-push day" label is already gone. No action — listed so it isn't re-flagged.

---

## Cross-cutting

- **Accessory layer (T0.1)** is the single offender behind the soreness, readiness, deload, dislike, and budget symptoms. Fix once, five symptoms close.
- **Era→age coupling (T2.3)** cross-cuts the `age`, `liftDaysPerWeek`, readiness-norm, and aesthetic axes. Constraining era to cosmetic closes the `age` and split mismatches together.

---

## Refuted / already-fixed (do NOT re-do)

- **Sore filter substring bug** — ALREADY FIXED in working tree: main slot loop now uses the slug→bucket bridge (`WorkoutGenerator.swift:383-399`, comment cites the old miss). The *only* remaining sore leak is the accessory layer (T0.1). Do not revert to substring.
- **`patternFrequency` dead** — ALREADY DELETED 2026-06-04 (audit N8). Do not re-add. `emphasizePatterns` is documented-inert (N9), retained for the LLM `build_workout` tool surface — do not delete it either.
- **Injury filter "does nothing"** — REFUTED. It works and is tested (T0.2 reframes to data + substitution).
- **Lumbar "swaps INTO trap bar deadlift"** — REFUTED. No injury-driven swap exists; the only swap path is stagnation. (The real gap is no safe-substitute backfill — T0.2.)
- **liftDaysPerWeek "4 days = PPL+Push, contradicts spec"** — REFUTED. `case 4` returns `.upper/.lower` per spec (`:1282`); the PPL+Push the sweep saw is era `splitPreference` override (T2.3).

## What NOT to touch (load-bearing)

- Injury exclusion: `profile.excludedExerciseIds` → `pickedIds` → `CoachDatabase.swift:587` (tested). Correct.
- `liftDaysPerWeek` → split default `WorkoutGenerator.swift:1282`. Per spec; don't "fix" to PPL.
- Main-loop sore filter `WorkoutGenerator.swift:383-399`. Already fixed; don't revert.
- `combinedSetsMul` ordering — readiness BEFORE `intensityBias` (`:205-208`) is intentional.
- Deterministic hot path + `hashSeed` (no time salt by default), `CoachConsent` default OFF, async LLM overlay. Intentional.
- `emphasizePatterns` / `GeneratorStrategy` tool surface. Inert but part of the LLM contract.

## Test coverage gate (must exist before any Tier 3 refactor)

1. Accessory layer **respects sore exclusion** — sore delts ⇒ no Cable Lateral Raise appended.
2. Accessory layer **respects readiness/deload set scaling** — readiness 0.0 ⇒ accessory sets scaled like main lifts.
3. Accessory layer **respects dislike keywords**.
4. Accessory layer **respects the duration budget** — no append past budget.
5. **Time-based movement** emits a time prescription, not a rep band (Tuck Hold / Reverse Plank).
6. **Bodyweight pull day** has ≥ N exercises (degradation floor).

## Coordination (two other sessions live on main)

- Working tree is dirty on exactly the generator files: `GeneratorContext.swift`, `GeneratorStrategy.swift`, `WorkoutGenerator.swift`, `PlanStore.swift`, `ReadinessGeneratorShipGateTests.swift`, `docs/generator-audit.md`, plus untracked `GeneratorSweepReportTest.swift`, `scripts/generator-sweep.sh`.
- **Do not stage/commit those in-flight files.** This backlog is a new file; it touches nothing the other sessions hold.
- Before each item: re-pull, re-run the sweep, re-verify against current output (not the critique text).
- One commit per item; Tier 0 can go straight to main; Tier 3 wants one PR per file.
