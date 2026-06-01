# Workout Generator — Grounded Audit

Scope: `PlanStore.generate` → `Planner.generate` → `WorkoutGenerator.generateLift`, the bundled `coach.db`, and the test suite. Every claim cites source (`file:line`) or a computed value from a standalone Swift/SQL harness. Bundled DB = `PhaseTraining/Resources/coach.db` (the git-tracked, shipped copy) unless noted.

## Entry path & stale-name flags

| Symbol in priors | Exists? | Truth |
|---|---|---|
| `PlanStore.generate` | ✓ | `PlanStore.swift:219` |
| `Planner.generate` | ✓ | `Planner.swift:24` |
| `WorkoutGenerator.generateLift` | ✓ | `WorkoutGenerator.swift:48` |
| `exercise_substitutes` (table) | ✗ name | Real table is **`exercise_substitutions`**; code queries the correct name (`CoachDatabase.swift:443`). Prior used a loose name; code is fine. |
| "staples table" | ✗ | Not a table. `ExerciseStaples` is a Swift hardcode (`ExerciseStaples.swift:25`), keyword-by-pattern. |
| "sports table" | ✗ | No `sports` table. Sports are a Swift catalog (`Sport.catalog`); DB has `exercise_sport_relevance`, `sport_categories`. |
| "cohort norms" (DB) | ✗ | Swift (`ReadinessSignal.cohortNorm`), not DB. |

---

## 1. Verdict table

| # | Hypothesis | Status | Class | Evidence | Computed |
|---|---|---|---|---|---|
| 1 | Progression = priorBest×1.025 round-5lb | **CONFIRMED** | **BUG** | `max(w, (w*1.025/5).rounded()*5)` `WorkoutGenerator.swift:591-592` | **≤100 lb → +0 (no-op)**; 135→140 (+3.7%); 225→230 (+2.2%); 315→325; 405→415 |
| 2 | priorBest = heaviest non-warmup set @ any reps; reps→target string | **CONFIRMED** | **BUG (minor)** | heaviest-by-weight any-reps `GeneratorContext.swift:270-281`; hint uses `prior.reps` `WG:593`; row reps use focus band `WG:995-1002` | Note "×3" vs set "6-12" can disagree |
| 3 | e1RM exists | **CONFIRMED** | n/a | `StrengthStandards.epley1RM` `:88`, used for stagnation `GeneratorContext.swift:387`. No Brzycki. Progression does NOT use it | — |
| 4 | Readiness = freq/recency only, nothing else | **CONFIRMED** | DESIGN | `compute(events,cohort,now)` `ReadinessSignal.swift:79`; density/recency/trend `:112-176`. No sleep/HRV/load/soreness/feedback | — |
| 5 | feedback/tooHard orphan vs readiness | **CONFIRMED** | DESIGN | only in `applyRecentSignalBias` `Planner.swift:102-104`; never reaches `ReadinessSignal` | — |
| 6 | readiness can push sets > baseSets (1.5^.4) | **REFUTED** | n/a (prior over-reached) | `combine` clamps `min(max(exp(logSum),0),1)` `ReadinessSignal.swift:191` | best case 1.5/1/1 → raw 1.18 **clamped 1.0** → setsMult **1.0** |
| 7 | cohort norm = era-aesthetic axis (leak?) | **PARTIAL** | DESIGN | norms `:121-130`; same `EraCohort` also drives `applyEraAesthetic` `WG:378` + derives from age `DemographicProfile.swift:261` | same 3/wk: magBB **0.92** vs sci **0.78**; Δsets 0.97 vs 0.91 |
| 8 | model rewards overtraining volume | **CONFIRMED** | DESIGN (limit) | no load/strain counter-signal | 6/wk daily → score **1.0**, setsMult **1.0**, RPEcap **9.0** |
| 9 | stagnation: first sub, no hysteresis, can oscillate | **CONFIRMED** | DESIGN→BUG | flat e1RM ≥3 sess/4wk `GeneratorContext.swift:370-404`; first sub by `similarity_score DESC` `CoachDatabase.swift:446`; no cooldown `WG:530-566` | A↔B thrash possible across weeks |
| 10 | substitutes sparse → swap no-ops | **CONFIRMED** | DATA | shipped DB | **170/564 = 30.1%** have ≥1 sub; ~70% no-op |
| 11 | sore filter = substring on labels; false negatives | **CONFIRMED** | **BUG** | `applySoreFilter` matches bucket rawValue vs primary **label** substring `WG:338-351`; correct bridge `MuscleBucket.memberSlugs` exists & is used by RPE path `WG:868` but NOT here | **MISS: quads, shoulders, back, calves, core**; works: chest/glutes/hams/biceps/triceps |
| 12 | hashSeed position-only, no time salt | **CONFIRMED** | DESIGN | default seed = `planInputsHash` `Planner.swift:517`; salt only on explicit regen `PlanStore.swift:709,883` | 2 consecutive gens, same ctx → identical |
| 13 | empty pool → slot dropped, no escalation | **CONFIRMED** | DESIGN | 3 passes then `return nil`→`continue` `WG:127` | workout shrinks; no count floor |
| 14 | focusBias keyed only on focus, overrides DB | **CONFIRMED** | DESIGN | `focusBias(PrimaryFocus)` `WG:1022-1060`; bias beats `defaultSets/Reps/Rest` `WG:945-953` | table below |
| 15 | duration sets×(45+rest)+30; warmups uncounted | **CONFIRMED** | DESIGN | `baseDurSec` `WG:171`; warmups synth after, not added to `elapsedSec` `WG:213-219,240` | 4-slot GS = 1155+525×3 = **2730s** |
| 16 | warmups only first compound | **CONFIRMED** | DESIGN | gate `slotIdx==0 && isCompound && !sore` `WG:213` | 2nd compound (deadlift after squat) → no ramp |
| 17 | age = flat −1 set, volume only | **REFUTED** | n/a (prior under-counted) | age≥55 also: sess-min −1/cap60 `DemographicProfile.swift:156`, lift-day floor `:163`, age≥60+adv difficulty demote `:173`, derives cohort `:261` | −1 set is 1 of ≥4 age effects |
| 18 | experience/floor/bias all silent | **CONFIRMED** | DESIGN→risk | clamps `WG:930-934`; floor `Planner.swift:71-83`; bias `:119-126`; no reason string for reduction | declared 5 → emit 3 fires; no UI explanation |
| 19 | zero-history "advanced" → uncapped, self-report only | **CONFIRMED** | DESIGN (risk) | `hasData=!events.isEmpty` `GeneratorContext.swift:156`; advanced no cap `WG:933` | novice→advanced gets 5×5 @ RPE 8-9, no data check |
| 20 | LLM in deterministic hot path? | **CONFIRMED deterministic** | DESIGN | default always `strategy=.auto`, no network; LLM = consent-gated (default OFF) async post-render overlay; fail→keep deterministic; clobbered on regen | see §3 |

### focusBias table (H14, `WorkoutGenerator.swift:1022-1060`)

| Focus | Primary sets×reps / rest | Accessory sets×reps / rest |
|---|---|---|
| generalStrength | 5×5 / 180s | 3×6-8 / 120s |
| hypertrophy | 4×6-12 / 90s | 3×8-15 / 60s |
| sportPerformance | 5×3-5 / 180s | 3×5-8 / 120s |
| endurance | 3×10-15 / 60s | 3×12-20 / 45s |
| weightLoss | 3×8-12 / 60s | 3×10-15 / 60s |
| longevity | 3×5-8 / 90s | 3×8-10 / 90s |

---

## 2. Corrections to the prior analysis

| Prior claim | Reality |
|---|---|
| "readiness density 1.5 can leak volume above baseSets" | **False.** `combine` clamps to [0,1] (`ReadinessSignal.swift:191`); readiness setsMult ≤ 1.0 always. Only `intensityBias=.push` (1.15, LLM-only) can exceed base. |
| "age ≥55 is a flat −1 set, volume-only" | **Undercounted.** Age also compresses session minutes, raises the lift-day floor, demotes difficulty at ≥60+advanced, and derives the era cohort (→ readiness norm + aesthetic). |
| "table `exercise_substitutes`" | Real name `exercise_substitutions`; code is correct, prior was loose. |
| "sore filter excludes sore muscles" | Only for 5 of 11 buckets. Silently misses quads/shoulders/back/calves/core (the big compounds). |
| "muscleVolume drives accessory targeting" (doc comment) | **Dead signal** — never read in the generator (see N2). |
| "fully deterministic generator" | True for the **default** path only; ends when Coach consent is ON (async overlay). |

---

## 3. LLM path (H20)

- Default `PlanStore.generate`→`Planner.generate(... )` runs with `strategy` defaulting to `.auto` (identity); `Planner`/`WorkoutGenerator` hold no client and never touch the network. Plan assigned synchronously (`PlanStore.swift:244`), then `kickOffLLMRefinementIfConsented` fires last (`:254`).
- Consent default **OFF** (`CoachConsent`/`CoachRequestScreen.swift:29`) → out-of-box is 100% deterministic.
- When ON: per-day async refinement via `CoachClient` (actor) → **Cloudflare AI Gateway** BYOK, model **`claude-sonnet-4-6`**, `max_tokens` 1024 (`CoachConfig.swift:13,21,40`). Off main thread; UI never blocks (deterministic plan already painted).
- Failure: `catch { return nil }` → day keeps deterministic workout (`PlanStore+LLMRefinement.swift:195-201`). **No app-set timeout** — inherits URLSession default (~60s).
- Refined output persists (`savePlan`) but is **clobbered on the next full regen** (fresh `GeneratedWorkout` with `refinedByLLMAt=nil`); guarded against stale mid-flight stamping by `inputsHash` check + task cancel.

---

## 4. DB & coverage facts (shipped `Resources/coach.db`)

| Table | Rows | | Table | Rows |
|---|---|---|---|---|
| exercises | 564 | | exercise_muscles | 1673 |
| movement_patterns | 40 | | exercise_equipment | 757 |
| exercise_movement_patterns | 574 | | equipment | 97 |
| **exercise_substitutions** | **537** | | muscle_groups | 80 |
| exercise_sport_relevance | 1374 | | common_injuries | 56 |
| exercise_injury_relevance | 87 | | routines | 107 |

- **Difficulty mix:** beginner 243, intermediate 252, advanced 63, elite 6.
- **Substitute coverage:** 170/564 (30.1%) source exercises; contexts: home_friendly 150, low_energy 133, lower_intensity 121, pre_event_safe 112, equipment_swap 16, age_friendly 5.
- **Sport-relevance coverage:** 285/564 (50.5%) exercises tagged.
- **Cohort norms (Swift, sessions/wk):** magazineBodybuilding 3.0, tNation 3.5, redditFitness 4.0, scienceBased 4.5, currentMeta 4.5 (`ReadinessSignal.swift:121-130`).
- **Movement patterns (40):** anti-extension, anti-lateral-flexion, anti-rotation, breathing-bracing, calf-raise, climbing-pull, crawling, cutting, deceleration, elbow-extension, elbow-flexion, ground-to-standing, hip-abduction, hip-adduction, hip-flexion, hip-hinge, horizontal-pull, horizontal-push, jumping-landing, loaded-carry, locomotion, olympic-derivative, paddle-stroke, pedal-stroke, racquet-swing, rotational-strike, scapular-protraction, scapular-retraction, single-leg-squat, skating-stride, squat, step-up, striking, swim-stroke, takedown-sprawl, terminal-knee-extension, throwing-casting, trunk-rotation, vertical-pull, vertical-push.
- **Staples** are a Swift keyword map over 22 patterns (`ExerciseStaples.swift:30-58`); the 18 non-staple patterns opt out of staple preference.

### ⚠ N1 — two divergent coach.db on disk

| Metric | `db/coach.db` (untracked) | `Resources/coach.db` (tracked/shipped) |
|---|---|---|
| md5 | f489dd4f… | 90c74098… |
| exercises | 551 | **564** |
| exercise_substitutions | **989** | 537 |
| exercise_sport_relevance | **2303** | 1374 |
| max exercise id | 979 | 1183 |

Only `Resources/coach.db` is git-tracked (`git ls-files`); last commit "coach.db: +91 Fitbod aliases". The two are **materially different databases**, and the shipped artifact has ~half the substitutions and sport-relevance of `db/coach.db`. Provenance of `db/coach.db` is unclear (stale source? regen target?). This is exactly the commit-vs-artifact drift hazard.

---

## 5. New findings (not in hypothesis list)

| # | Finding | Class | Evidence |
|---|---|---|---|
| N1 | Two divergent coach.db (above) | **BUG/hazard** | md5 + row counts |
| N2 | `muscleVolume` computed every regen (4-wk walk) but **never read** in generator | **BUG (dead)** | grep 0 reads outside `GeneratorContext.swift`; `MuscleVolume.rows` `:415` |
| N3 | `ReadinessEvent.duration` collected but unused — 20-min walk == 3-hr session for readiness | DESIGN gap | `ReadinessSignal.swift:37-40` |
| N4 | Hard sport days double-signed: trims a lift day (fatigue, `Planner.swift:116`) **and** raises readiness (training, `buildReadinessEvents`) | DESIGN conflict | two readers, opposite sign |
| N5 | `planInputsHash` excludes context/recentlyPicked/strategy → drift banner never fires on PR/soreness/readiness change though plan changes | BUG (UX) | `WeekPlan.swift:305`; detector `PlanStore.swift:852` |
| N6 | 45s/set is fixed regardless of reps; warmups uncounted → endurance days under-budgeted | DESIGN gap | `WG:171,213` |
| N7 | `generate()` rebuilds full `GeneratorContext` synchronously (walks all sessions: priorBest, stagnation, volume) on the calling thread | perf | `GeneratorContext.from` `:112`; `PlanStore.swift:221` |

---

## 6. Test-gap list (ranked by exposure)

| Rank | Untested path | Why it matters |
|---|---|---|
| 1 | **Sore-area exclusion** (`applySoreFilter`) — builder tested, consumption not | The H11 bug ships green; no test asserts a sore muscle is actually avoided |
| 2 | **Progression target math** — only `notes?.contains("target:")` asserted (`GeneratorContextTests.swift:146-177`) | The ≤100-lb no-op (H1) and the rep-mismatch (H2) are invisible to CI |
| 3 | **Build-97 deload/budget rule** (base vs scaled sets) | A refactor reverting it changes real workouts, passes all tests |
| 4 | **patternFrequency / muscleVolume consumption** | Only ever passed `[:]`; variety + (dead) volume path unguarded |
| 5 | weightLoss/longevity `focusBias` + endurance/weightLoss/longevity `rpeTempoHints` arms | Zero coverage |
| 6 | `feedbackExpand` (+1 day on 2× too_easy) | Zero coverage; all bias tests are trims |
| 7 | Stagnation-swap constraint conservatism + oscillation | Reject-and-fallback path untested; `XCTSkipIf` can no-op the one swap test |
| 8 | Era-affinity generator paths (`applyEraAesthetic`, split pref, rep-band) | Only exercised by non-CI eval-rig dumper |

Misleading tests: `test_nonHypertrophyDoesNotAppendAccessoryLayer` only asserts `count >=` (doesn't verify skip); `testRecencyTwentyEightDaysIsFloor` feeds 30 days not 28; `test_export_*` assert nothing.

---

## 7. Prioritized fix list

| Sev | Effort | Fix | File(s) |
|---|---|---|---|
| **High** | S | `applySoreFilter`: map exercise primary **slug** → `MuscleBucket.bucket(forSlug:)?.rawValue` and compare to sore areas, mirroring `isMuscleSoreForExercise`. Fixes quads/shoulders/back/calves/core misses | `WorkoutGenerator.swift:338-351` |
| **High** | S | Progression sub-100-lb no-op: round to 2.5 lb (or enforce a min +2.5/+5 step) so light/DB/beginner loads actually progress | `WorkoutGenerator.swift:591` |
| **High** | S+test | Pin progression target + sore-exclusion + build-97 budget in unit tests | `PhaseTrainingTests/` |
| Med | S | `muscleVolume`: wire into accessory targeting or delete the build (stop paying the 4-wk walk for nothing) | `GeneratorContext.swift:411-417` |
| Med | S | Reconcile hard-sport double-signing (N4): pick fatigue **or** training, not both | `Planner.swift`, `GeneratorContext.swift` |
| Med | M | coach.db provenance (N1): confirm canonical, delete/regen the stale copy, add a logical-content (row-count) test to catch artifact drift | `db/`, `Resources/`, tests |
| Low | S | H2 rep mismatch: target hint should use the prescribed rep band (or vice versa) | `WorkoutGenerator.swift:593` |
| Low | S | Surface a reason string for silent lift-day reduction / set clamp (H18) | `Planner.swift`, Week UI |
| Low | M | Stagnation hysteresis: swap cooldown to prevent A↔B thrash (H9) | `WorkoutGenerator.swift:530` |

### Calibration
The generator is a well-structured deterministic solver with genuinely good coverage on `focusBias`, `ReadinessSignal` sub-components, the RPE cap, and Planner taper/bias. The priors over-reached on H6 (clamp prevents the leak) and H17 (age does far more than −1 set), and were right-but-imprecise on H1/H11 — both of which are **real silent correctness bugs** now quantified. The single highest-value fix is the sore-filter taxonomy bridge: a safety feature that silently no-ops for the most commonly-sore compounds, with the correct mapping already sitting one function away.
