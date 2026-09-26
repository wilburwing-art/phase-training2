# State machines

Hand-written from the code, 2026-09-26. Each transition names the function that performs it, so a reader can check it. Re-verify after touching `SessionStore`, `DayOutcome`, `MissedWorkoutAutopilot` or `PlanStore+MissedWorkoutAutopilot`.

## A workout in progress

Source: `SessionStore.swift`, `TodayTab.swift`, `DayOutcome.derive`, `AbandonedWorkoutEntry.abandonmentThreshold` (0.70).

```mermaid
stateDiagram-v2
    direction LR
    state "No workout" as Idle
    state "Active<br/>(pt_active_session)" as Active
    state "Review<br/>(CompleteScreen)" as Review
    state "Saved to user.db" as Saved
    state ratio <<choice>>
    state kind <<choice>>

    [*] --> Idle
    Idle --> Active: Start, createSession + saveActive
    Active --> Active: log a set, swap, coach diff<br/>(saveActive on every edit)
    Active --> Idle: Cancel, clearActive
    Active --> Review: Finish
    Review --> Idle: Discard, clearActive
    Review --> Saved: Save, saveCompleted
    Active --> ratio: Stop early, saveAbandoned
    ratio --> Saved: 70% or more of sets done
    ratio --> Abandoned: under 70%
    state "Saved + AbandonedWorkoutEntry<br/>(reshuffle offer)" as Abandoned
    Saved --> kind: onSessionSaved, DayOutcome.derive
    Abandoned --> kind
    kind --> asPlanned: every planned exercise, no swaps
    kind --> modified: swaps, drops, adds, fewer sets
    kind --> switched: ran a different workout
    kind --> unplanned: no lift planned that day
    kind --> abandoned: stopped under 70%
```

While a workout is Active, `PlanStore` skips automatic plan regeneration so the template cannot change under you.

## A planned day

Source: `Planner.generate`, `PlanStore+LLMRefinement`, `WeekOverrides.dayOverrides` / `displacedPlanByDate`, `PlanEdit.protectDay`, `PlanStore+History.snapshotCurrentPlan`.

```mermaid
stateDiagram-v2
    direction LR
    state "Generated<br/>lift / sport / rest / event" as Gen
    state "Refined by coach LLM<br/>(consent only, lift days)" as Ref
    state "Overridden<br/>(original kept as DisplacedPlan)" as Ovr
    state "Protected event<br/>(protected = true)" as Prot
    state "Trained<br/>(DayOutcome recorded)" as Done
    state "Missed" as Miss
    state "Archived<br/>(pt_past_plans snapshot)" as Arch

    [*] --> Gen: Planner.generate
    Gen --> Ref: refineCurrentPlanWithLLM
    Gen --> Ovr: day override or custom routine
    Ref --> Ovr: day override or custom routine
    Ovr --> Gen: clear override, displaced plan restored
    Gen --> Prot: protectDay (coach or event)
    Gen --> Done: workout saved that day
    Ref --> Done: workout saved that day
    Ovr --> Done: workout saved that day
    Gen --> Miss: day passed, lift/sport, no session or sport log
    Ref --> Miss: day passed, no session
    Gen --> Gen: regenerate (profile drift, new week)
    Done --> Arch: week ends or plan regenerates
    Miss --> Arch
    Prot --> Arch
```

## A missed workout

Source: `MissedWorkoutAutopilot.detect` / `proposeReshuffle`, `PlanStore+MissedWorkoutAutopilot`, `PlanStore.consolidateMissed`.

```mermaid
stateDiagram-v2
    direction LR
    state "Detected<br/>(weekly check-in)" as Det
    state propose <<choice>>
    state "Reshuffle offered" as Offer
    state "Consolidate offered" as Cons
    state "reshuffledTo(date)" as Moved
    state "Folded into remaining<br/>lift days" as Folded
    state "dropped" as Dropped
    state "userDismissed" as Dismissed

    [*] --> Det: planned lift/sport, date passed,<br/>not unavailable, not overridden to rest
    Det --> propose: proposeMissedReshuffle
    propose --> Offer: valid slot and budget left (2 a week)
    propose --> Cons: no clean slot, consolidation cap has room (1 a week),<br/>2+ future lift days
    propose --> Dropped: 4+ lift days this week, or no slot
    Offer --> Moved: applyMissedReshuffle
    Cons --> Folded: consolidateMissed succeeds
    Cons --> Dropped: consolidateMissed declines<br/>(cap met, too few lift days, focus lost)
    Det --> Dismissed: user taps dismiss
    Offer --> Dismissed: user taps dismiss
    Moved --> [*]: MissedWorkoutEntry logged
    Dropped --> [*]: MissedWorkoutEntry logged
    Dismissed --> [*]: MissedWorkoutEntry logged
    Folded --> [*]: MissedWorkoutEntry logged consolidated
```

Reshuffle rules (`MissedWorkoutAutopilot`): drop at 4+ lift days, keep body-part coverage, never land the day after another hard day, skip protected, rest and event days, and respect the weekly budget. `dropped` and `userDismissed` leave the same plan; they are logged separately so the coach can tell "could not fit it" from "chose to skip". A successful consolidation logs `consolidated` (since 2026-09-26; it was logged `dropped` before, indistinguishable from a declined one). The banner lives only in the weekly check-in's missed step (`CheckInMissedScreen`) since build 122.
