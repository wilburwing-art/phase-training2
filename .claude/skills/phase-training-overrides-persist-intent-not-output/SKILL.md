---
name: phase-training-overrides-persist-intent-not-output
description: >
  How to make a per-day workout customization survive plan regeneration in
  phase-training2: persist the user's INTENT in WeekOverrides (as an
  Optional field) and re-derive the output deterministically inside
  applyCustomRoutineOverrides / post-generate processing — never store the
  derived GeneratedWorkout. Trigger when adding any per-day feature that
  modifies a day's workout (refresh prescriptions, pin/deload-this-day,
  per-day intensity) and the edit "reverts on regen", or when adding ANY
  new field to WeekOverrides.
when-to-use: adding per-day plan customizations or WeekOverrides fields in phase-training2
---

Built 2026-06-07 for "Refresh prescriptions" (WeekOverrides.swift,
PlanStore+Generation.swift, WorkoutGenerator+Represcribe.swift).

## The regen-clobber constraint
Every regen path funnels through `generate(from:today:)` →
`applyCustomRoutineOverrides` → `composeWorkout(fromCustom:)`, which
re-derives each override day from stored data. Anything written only to
`day.generatedWorkout` is clobbered on the next generate(). So:

1. **Persist intent** in WeekOverrides (e.g.
   `prescriptionRefreshByDate: [Date: Mode]?`), mirroring how
   `customRoutineByDate` works.
2. **Re-derive output** in a post-generate pass — deterministic (no RNG;
   hashSeed from stable row ids), so two generate() calls are identical.
3. Run derivations needing the week layout (focus from lift index) in a
   SECOND pass after all kind flips, or the layout is mid-mutation.

## Three load-bearing traps
- **New WeekOverrides fields MUST be Optional** (`weekTone` pattern).
  Synthesized Codable throws keyNotFound for a missing non-optional key —
  even with a default value — and PlanStore's `try?` decode then resets
  the WHOLE week's overrides. Test by encoding, stripping the key via
  JSONSerialization, decoding.
- **Extend `clearDate(_:)`** with the new field's same-day purge — and use
  same-day-normalized get/set helpers (keys may carry time-of-day).
- **Reuse `makePickedRow`, don't recreate it.** It was private + took a
  PatternSlot; the refactor (private → internal, slot → `pattern: String?`)
  let represcribe share the exact row composer with the main loop and
  degradation floor. A parallel composer = the dual-path drift trap.

LLM-refinement protection needs nothing extra: `refinementCandidates`
excludes on `customRoutineId(for:)` and the composed `refinedByLLMAt: nil`.

Tests to copy: PlanStoreSeamsTests "Prescription refresh" MARK (identity
kept, survives second generate, no-op without the parent override) and
WeekOverridesClearTests legacy-payload decode.
