---
name: phase-training-support-scheduler-tied-loads
description: >
  Two traps when building on the primary/support de-confliction layer
  (SupportScheduler / SupportPattern, PLAN-primary-support.md) in
  phase-training2. (1) Season-engine sessions in the same week share one
  PhaseRule → same slot allocation → same DemandSchemes, so their derived
  loads (Σ sets × RPE) frequently TIE EXACTLY — "the heaviest session" is
  ambiguous. SupportScheduler protects the FIRST maximal session (sort is
  load desc, index asc); Swift's `max(by:)` returns the LAST maximal element
  on ties, so a test or UI feature that picks "the heavy day" with max(by:)
  disagrees with the scheduler and fails/mislabels. Assert or display the
  tie-honest form: SOME max-load session satisfies the property, or re-derive
  identity with the scheduler's own tie-break. (2) `Weekday` already exists
  app-wide in TrainingMemory.swift (1-BASED, monday = 1, has `short` not
  `label`) — extend it, never redeclare; and any 0-based index → Weekday
  mapping must add 1 or `Weekday(rawValue:)` returns nil for 0.
  Trigger when writing tests against SupportScheduler output, adding "your
  heavy day" / key-session UI in phase 2, or any feature that ranks a
  generated week's sessions by load.
when-to-use: building on SupportScheduler/SupportPattern or ranking season-engine sessions by load
---

Verified building phase 1 of PLAN-primary-support.md (2026-07-13); trap 1 was a
real test failure against real generator output (synthetic fixtures with
distinct loads passed; the integration fixture failed).

1. **Tied loads are the NORM, not an edge case.** A season-engine week's
   sessions come from one PhaseRule: same `allocateSlots` result, same
   `DemandScheme` prescriptions — different movements, identical sets × RPE
   shape. `SupportScheduler.sessionLoad` therefore ties across the week.
   Consequences:
   - The scheduler's buffer protection applies to ONE maximal session (first
     by its deterministic order). Only Sunday may be buffer-legal under a
     Tue/Thu/Sat pattern — you cannot protect three tied sessions.
   - Any consumer picking "the heaviest" via `max(by:)` gets the LAST tied
     element and diverges from the scheduler. Compare with an epsilon and
     assert over the tied SET (`some max-load session is buffer-safe`), or
     expose/reuse the scheduler's tie-break (load desc, then input index).
   - Phase 2 "your heavy day" UI needs a deterministic definition — surface
     the scheduler's protected session, don't re-derive by max.

2. **Weekday reuse.** `TrainingMemory.swift:498` owns `enum Weekday` (Int,
   monday = 1, `short`/`letter` labels). SupportPattern extends it with
   `Comparable` + circular `daysUntil(_:)`. Redeclaring collides; 0-based
   math (`(i * 7) / count`) must add 1 before `Weekday(rawValue:)`.

Sibling: [[phase-training-season-generator-engine-pitfalls]] (engine math),
[[phase-training-overrides-persist-intent-not-output]] (why only the
SupportPattern is persisted, never the scheduled week).
