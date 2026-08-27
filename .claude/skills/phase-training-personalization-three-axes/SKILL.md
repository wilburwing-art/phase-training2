---
name: phase-training-personalization-three-axes
description: When planning a personalization layer for phase-training-family fitness apps (phase-training, phase-training2, workout-plan) that mixes age, self-reported experience level, and training history (HealthKit / CSV / native sessions), keep them as THREE orthogonal axes routed to different generator seams. The temptation is to collapse them ("derive level from HealthKit", "use age as a hard constraint"); resist it.
when-to-use: Triggers when adding ANY personalization that touches more than one of {age, self-reported level/experience, training history, HealthKit data} in phase-training / phase-training2 / workout-plan. Also use when a user proposes auto-overriding level from device data, or using age as a workout difficulty knob. Skip for single-axis additions (just a new HealthKit field, just an onboarding question) with no interaction.
---

## The three axes (DO NOT collapse)

| Axis | Source | What it controls | What it MUST NOT control |
|---|---|---|---|
| **Competency / ceiling** | Self-reported `ExperienceLevel` (`.beginner/.intermediate/.advanced`) | Movement selection (barbell back squat vs goblet), technical complexity | Volume, intensity, progression rate |
| **Current readiness** | Derived `readinessScore (0-1)` from HK workouts + imported sets + native sessions over 28d | Starting volume, RPE caps, progression rate, `recommendedLiftDaysPerWeek` floor | Movement selection, experience UI label |
| **Era / aesthetic affinity** | Age → cohort table, with `eraOverride` for user dismissal | Split style, rep-range bias, exercise-aesthetic tiebreak, LLM coach vocab | Volume, intensity, movement competency |

A detrained ex-college-athlete who picks "advanced" should still get barbell back squats (competency axis) at 60% of historical peak with conservative ramp (readiness axis) in whichever split style fits their era (affinity axis). All three differ — none auto-derives the others.

## Routing in the codebase

All three land at `GeneratorContext.from(...)` in `GeneratorContext.swift` (the single aggregation seam). Then:

- Competency → `WorkoutGenerator` exercise-candidate filter (existing path).
- Readiness → `WorkoutGenerator` set-count multiplier + RPE cap (new silent path, see plan `silly-growing-penguin.md`).
- Era style → `DemographicProfile.eraStyle`, then split picker in `WeeklyShape.swift`, rep prescriptions in `WorkoutGenerator`, deterministic-pick tiebreak via `aestheticTags`, plus `CoachContext.snapshot(...)` for LLM vocab.

## Surface vs silent rules (from Wilbur's product decisions)

- **Era affinity** — SURFACE as confirm/override/dismiss in onboarding (people have strong feelings about being typecast by age). Persist `eraOverride` in `TrainingMemory`.
- **Readiness** — SILENT. Never display a "you might be detrained" prompt. Never auto-mutate `experience` or `startingState`. Scaling happens inside the generator only.
- **Competency** — self-reported, never auto-overridden from data.

## Anti-patterns this skill blocks

- "If HealthKit shows 4 months idle, demote `experience` to `.beginner`." NO — readiness handles volume; competency stays.
- "Age 55+ gets simpler exercises." NO — that's competency, not aesthetic. Use cohort to pick body-part split + 8–12 rep bias, not to dumb down movement selection.
- "One `personalizationScore` blending age + level + readiness." NO — the three axes route to different generator decisions and must stay separate.

## See also

- Plan at `~/.claude/plans/silly-growing-penguin.md` (the worked example).
- Reference: `~/Downloads/The Definitive Reference Foundational Weightlifting Programs Since 1990.md` for the era→program lineage table.
- Phase 4 program library couples to `[[eval-rig-encode-canonical-program]]` — programs are the natural Phase 4 expression of the affinity axis.
