---
name: phase-training-planner-add-a-rule-pass
description: >
  Add a new plan-level rule pass to phase-training2's Planner.generate (the
  step-based [DayPlan?] slot pipeline) — e.g. a taper, a buffer, a sport-day
  stamp, a lightening reflow. Covers the four things that bite: (1) where the
  seam is + ordering, (2) planInputsHash lives in WeekPlan.swift NOT
  TrainingMemory.swift, (3) reconciling with the EXISTING multi-sport model
  (seasonsBySport + applySecondarySportPromotion) so you don't double-place,
  (4) the direct-slot-fixture test recipe. Trigger when adding a Planner pass,
  a new plan-affecting TrainingMemory input, or a "reflow/annotate the week"
  feature. Skip for PlanStore mutation seams (that's
  phase-training-planstore-mutation-seams-and-week-caps) and generator-internal
  bias (phase-training-generator-bias-weight-pool-not-reorder).
when-to-use: adding a rule pass to Planner.generate or a new plan-affecting memory input
---

Verified adding `applySupportPattern` (primary/support de-confliction) 2026-07-14.

1. **The seam.** `Planner.generateUnbiased` builds `var slots: [DayPlan?]`
   Monday-first (`mondayCal.firstWeekday = 2`; slot i ↔ `Weekday(rawValue: i+1)`,
   monday = 1). Steps 1–6 place events/overrides/shape; by step 6.5 every slot
   is a non-nil DayPlan. Add your pass as a numbered step AFTER placement and
   BEFORE the step-7 best-practice passes (`applyPreSportBuffer` etc.) if those
   should see your changes. A pass is a `static func(_ slots: inout [DayPlan?],
   memory:, calendar:)` that mutates only `!slot.protected` slots (events +
   overrides are protected — never rewrite them). Set `generatedReason` (append
   with " · ") so the change surfaces: WeekScreen already renders it, so
   annotation IS the UI for free.

2. **planInputsHash lives in `WeekPlan.swift`**, not TrainingMemory.swift,
   despite being a `TrainingMemory` computed property (`var planInputsHash`).
   A new input that should REFLOW the week (e.g. a declared pattern) MUST be
   folded into that `canonical` array or the PlanStore auto-regen subscription
   dedupes the edit → silent no-op. (Contrast: a generator signal that must NOT
   auto-rebuild stays OUT — see [[phase-training-generator-bias-weight-pool-not-reorder]].)
   Adding a stored field to TrainingMemory = 4 sites: property, CodingKeys,
   `init(from:)` `decodeIfPresent` (so old saves load), `encode` `encodeIfPresent`.

3. **Reconcile with the existing multi-sport model.** The app ALREADY has
   `memory.seasonsBySport` + `applySecondarySportPromotion` (converts a rest
   slot to a crude placeholder `.sport` day for any non-primary in-season
   sport, capped 2). If your feature owns a sport's placement, add a
   `.filter { $0.key.slug != <yourSlug> }` to that promotion's candidates or
   you double-place. Don't invent a parallel model that fights it.

4. **Test the pass directly** (PlannerTaperPromotionTests / PlannerSupportPatternTests
   style): it's a pure slot transform, so build `[DayPlan?]` fixtures anchored
   to a fixed Monday (`2026-05-11`), call the static func, assert on slots — no
   Planner.generate, no coach.db, no wall clock. Assert protected/lift slots are
   untouched and nil-input is a strict no-op (`slots == before`).

Pairs with [[phase-training-overrides-persist-intent-not-output]] (persist the
input, re-derive the week) and [[phase-training-support-scheduler-tied-loads]].

## A Planner test fixture with no sport generates empty lift days (2026-10-28)

`PlannerTests.fixtureMemory()` (equipment only) produces `.lift` days titled
"Rest" with ZERO exercises, so any assertion over exercise lists passes on
empty arrays. Set `primarySport` (e.g. `Sport.resolve(slug: "alpine-skiing")`),
`onboardedAt`, `experience` and `sessionMinutes` to get real season-engine
sessions. Then compare lift days by title: the engine titles each one
"<phase> · Session N" from its lift index, so a repeated title is a repeated
session even when a seed difference changes one exercise. Pinned
(`dayOverrides`) lifts and queue-filled lifts were numbered in separate index
spaces, both starting at 0, which is how a Week-tab drag produced two
"Session 1" days (`testSwappedLiftDayDoesNotDuplicateAnotherLiftDay`).

The same holds in the app: `--seed-missed-consolidation-demo` seeds a profile
with no sport, so the first edit that regenerates the week turns every lift day
into "Rest" with no exercises. A UI test screenshot after any Week edit with
that seed shows empty lift rows; that is the seed, not the change under test.

Real users reach the no-sport path one way: deselecting the last sport in
Profile, Sports (`SportsEditorSheet.toggleSport`), which sets `primarySport`
to nil and makes the memory subscription rebuild an empty week. Build 150
blocks removing the last sport, the same floor onboarding enforces.

## Bump `Planner.version` when saved weeks should change (build 150)

A rule pass that changes output for a week users already have does not
reach them until something regenerates the week. Bump `Planner.version` in
`Planner.swift`, and `PlanStore.migrateIfStale` rebuilds every plan stamped
lower on the next launch. Leave the version alone for changes that only need
to apply from next week on, because each bump rebuilds every tester's
current week once.
