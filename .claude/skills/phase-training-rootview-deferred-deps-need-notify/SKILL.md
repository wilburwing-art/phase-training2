---
name: phase-training-rootview-deferred-deps-need-notify
description: phase-training2 wires PlanStore's injected stores (sessionStore, recentPicks, memoryStore, sportLogStore, customStore) in RootTabView's `.task` — AFTER first render, and they are plain `var`s, NOT @Published. So any PlanStore-derived view state that depends on them computes against nil on COLD LAUNCH and never refreshes (wiring them fires no objectWillChange). The Today missed-workout banner is the known victim: currentPendingMiss → pendingMissedWorkouts() does `guard let sessionStore` → returns [] at launch → banner absent until an UNRELATED @Published change re-renders. Trigger when a cold-launch banner/screen element doesn't appear until you tap around, when adding derived view state that reads planStore.sessionStore/memoryStore/recentPicks, when wiring a NEW injected store into PlanStore, or when an XCUITest that checks an on-launch element (with no prior interaction) fails while manual use "works". ALSO trigger before REMOVING or hiding the Today missed-workout banner: its buttons are the only callers of applyMissedReshuffle/dismissMissed, so it is the sole transition out of the pending state, not a notice.
when-to-use: cold-launch-only missing UI in phase-training2, or adding/​debugging PlanStore-derived state that depends on a .task-wired store.
---

# RootTabView deferred deps aren't @Published

## The trap (found fixing ConsolidateFlowTests, 2026-06-04)
`RootTabView.body`'s `.task { }` does `planStore.sessionStore = sessionStore`
(+ recentPicks / memoryStore / sportLogStore / customStore). Kept off
`PlanStore.init` on purpose (one-arg constructible for tests/previews). But:
- `.task` runs AFTER the first render.
- those props are plain `var`, not `@Published`.

So at cold launch `TodayScreen.currentPendingMiss` → `pendingMissedWorkouts()`
hits `guard let plan, let sessions = sessionStore?.savedSessions else { return [] }`
with sessionStore still nil → no missed banner. Wiring it in `.task` publishes
nothing, so the view never recomputes — the banner only appears once some other
@Published change (navigation, a log, regen) forces a re-render. Manual testing
hides it; a deterministic XCUITest checking an on-launch element catches it.

## The fix (minimal, respects the deferred-wiring pattern)
After the assignment block in `.task`, nudge observers once:
```swift
planStore.customStore = customStore
planStore.objectWillChange.send()   // deps feed derived state but aren't @Published
```
One re-render after deps are wired → derived state (the banner) recomputes with
sessionStore set. Alternative (heavier): make the dep `@Published`.

## Debug technique that isolated it (do this FIRST)
Before touching UI, reproduce the UI-derived logic at the STORE level in a fast
unit test (seconds vs a 5-min XCUITest). Mirror the XCUITest's seed exactly and
assert the gates directly — for the consolidate banner:
`pendingMissedWorkouts().last` (detect) → `proposeMissedReshuffle == nil`
(reshuffle drop) → `shouldOfferConsolidation == true` (offer). All three passed
→ logic was correct → the bug HAD to be UI render-timing → non-@Published dep.
Reuse the `PlanStoreMissedWorkoutTests` harness (`freshStore(today:)`,
`focusedLiftDay`, `restDay`, set `store.sessionStore` before `setPlan`).
Pairs with `phase-training-planstore-mutation-seams-and-week-caps`.

## The banner is the only exit from the pending state

Worth knowing before anyone declutters Today. `pendingMissedWorkouts()` returns
detected days minus those already recorded in `missedWorkouts`, and the only
things that record one are `applyMissedReshuffle` and `dismissMissed`. The
banner's Skip / Got it / Consolidate buttons are their only callers.

So the banner is a state machine's single transition wearing a notification's
clothes. Remove it and a missed day stays pending forever: never reshuffled,
never dismissed, accumulating in every later `pendingMissedWorkouts()` call,
with nothing rendering it and nothing failing.

If Today has to lose it, the resolve path has to land somewhere else first
(the weekly check-in and the Week tab's day rows are the two natural homes).
Deleting the view alone is not a UI change, it strands the data.
