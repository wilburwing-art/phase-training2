---
name: phase-training-trainingmemory-field-needs-probe
description: When a new field on phase-training2's TrainingMemory makes ProfileFieldCoverageTests.test_everyTrainingMemoryFieldHasAProbe fail ("New TrainingMemory field(s) need a Probe: [...]"), resolve it by deciding wire-vs-skip per field, not by blindly adding empty probes. The decision is driven by two seams: WeekPlan.planInputsHash (does changing it regen the plan?) and CoachContext.snapshot (does the coach read it?). Trigger when adding a stored property to TrainingMemory (phase-training / phase-training2 / workout-plan), or when ProfileFieldCoverageTests / test_probesEnforceTheirContracts goes red after a profile-field change. Skip for non-phase-training repos.
when-to-use: A new var was added to TrainingMemory and ProfileFieldCoverageTests fails until every field has a Probe. Also fires from test_probesEnforceTheirContracts when a probe's mutator doesn't actually move planInputsHash / the snapshot.
---

# Adding a TrainingMemory field → ProfileFieldCoverageTests gate

This test (build-78 regression guard) Mirror-reflects every `TrainingMemory`
stored property and forces each to have a `Probe` in `ProfileFieldCoverageTests.probes`.
A new field fails it until you add one. Don't add an empty probe — categorize.

## The two seams to check before categorizing
1. **`WeekPlan.planInputsHash`** (`PhaseTraining/Data/WeekPlan.swift:~305`) — the
   canonical list of planner inputs. If changing the field should trigger a plan
   regen, it must appear here AND the probe sets `mutateForHash`.
2. **`CoachContext.snapshot`** (`PhaseTraining/Coach/CoachContext.swift`) — what the
   LLM coach reads. If the coach should see it, it must render here AND the probe
   sets `mutateForSnapshot` + a `snapshotMarker` substring that lands in the output.

## Categories (match an existing probe as precedent)
- **Real config** (sports, focuses, equipment, experience, peakDate…): wire BOTH
  seams; probe sets both mutators + marker, `skipReason: nil`.
- **Body-metric scalar** (weightKg, heightCm, gender): intentionally skip the hash
  (a weight log must not regen the week) but IS in the snapshot via `bodySection` —
  `mutateForHash: nil`, snapshot mutator + marker set.
- **Append-only history / display-only** (feedback, soreness, body*Log, phaseStartedAt):
  skip BOTH with a written `skipReason`. The coach reads history via its own params
  (recentFeedback/recentSoreness), not the memory snapshot.

## Findings from the run that created this skill (build 103 fields)
- `phaseStartedAt` → **skip both**. Only `SeasonPhaseBadge` reads it (via
  `MesocycleProgression`/`weeksInCurrentPhase`); never the planner or snapshot. The
  season change that stamps it already drifts the hash via seasonsBySport/defaultSeason.
- `bodyWeightLog` / `bodyCompositionLog` → **skip both**. Append-only series; the coach
  reads the mirrored `weightKg` scalar via `bodySection`, and `planInputsHash` excludes
  body metrics by design. Raw logs surface only on Profile + Progress.

Tip: `test_probesEnforceTheirContracts` independently verifies that any probe claiming
a mutator actually moves the hash / emits the marker — so a wrong category fails loudly.
