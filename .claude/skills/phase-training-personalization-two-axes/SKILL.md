---
name: phase-training-personalization-two-axes
description: When planning a personalization layer for phase-training-family fitness apps (phase-training, phase-training2, workout-plan) that mixes self-reported experience level with training history (HealthKit / CSV / native sessions), keep them as TWO orthogonal axes routed to different generator seams. The temptation is to collapse them ("derive level from HealthKit"); resist it. Also records that a third axis (age-derived training-era affinity) was BUILT and then DELETED, so proposals to re-add it start from what actually happened.
when-to-use: Triggers when adding ANY personalization that touches more than one of {self-reported level/experience, training history, HealthKit data, age} in phase-training / phase-training2 / workout-plan. Also use when a user proposes auto-overriding level from device data, using age as a workout difficulty knob, or re-introducing a training-era / cohort / aesthetic axis. Skip for single-axis additions (just a new HealthKit field, just an onboarding question) with no interaction.
---

## The two axes (DO NOT collapse)

| Axis | Source | What it controls | What it MUST NOT control |
|---|---|---|---|
| **Competency / ceiling** | Self-reported `ExperienceLevel` (`.beginner/.intermediate/.advanced`) | Movement selection (barbell back squat vs goblet), technical complexity | Volume, intensity, progression rate |
| **Current readiness** | Derived `readinessScore (0-1)` from HK workouts + imported sets + native sessions over 28d | Starting volume, RPE caps, progression rate, `recommendedLiftDaysPerWeek` floor | Movement selection, experience UI label |

A detrained ex-college-athlete who picks "advanced" should still get barbell back squats (competency axis) at 60% of historical peak with a conservative ramp (readiness axis). The two differ — neither auto-derives the other.

## Routing in the codebase

Both land at `GeneratorContext.from(...)` in `GeneratorContext.swift` (the single aggregation seam). Then:

- Competency → exercise-candidate filter via `DemographicProfile.preferredDifficulties`.
- Readiness → set-count multiplier + RPE cap + the lift-day floor in `Planner.applyReadinessLiftDayFloor`. Silent path.

## Surface vs silent rules

- **Readiness** — SILENT. Never display a "you might be detrained" prompt. Never auto-mutate `experience` or `startingState`. Scaling happens inside the generator only.
- **Competency** — self-reported, never auto-overridden from data.

## The deleted third axis: era / aesthetic affinity

There WAS a third axis: an age-derived "training era" cohort (`EraCohort`, six cases from `veteranStrength` to `currentMeta`), surfaced as its own onboarding step with a user `eraOverride`. It was removed entirely (2026-09-06). Two things are worth knowing before anyone proposes bringing it back:

1. **Most of it was already dead.** `EraStyle` carried five payload fields. By the time it was deleted, `splitPreference`, `repRangeBias`, `aestheticTags`, and `archetypalPrograms` had ZERO production readers — the legacy `WorkoutGenerator` selection engine that consumed them was removed in the season-engine pivot, and the season path never picked them up. `DemographicProfile.eraStyle` was populated and read only by tests.
2. **The two live consumers were narrow.** `terminologyHints` fed an LLM vocabulary block in `CoachContext.snapshot`, and the cohort picked the sessions/week denominator in `ReadinessSignal.densityComponent` (a 2.5–4.5/wk ladder). That density norm is now a flat `ReadinessSignal.sessionsPerWeekNorm = 3.0` for everyone.

So the axis cost a mandatory onboarding step and a `planInputsHash` component (which reseeded `deterministicPick`, reshuffling picks on change without changing any generation rule) in exchange for coach word choice and one denominator. If you re-add anything like it, wire the generation-side effects FIRST and confirm they survive; a preference axis nothing reads is worse than no axis.

## Anti-patterns this skill blocks

- "If HealthKit shows 4 months idle, demote `experience` to `.beginner`." NO — readiness handles volume; competency stays.
- "Age 55+ gets simpler exercises." NO — that's competency. Age is not a difficulty knob.
- "One `personalizationScore` blending level + readiness." NO — the axes route to different generator decisions and must stay separate.
- "Add a style/aesthetic/cohort preference." Only with live generator wiring on day one. See the deleted-axis section above.
