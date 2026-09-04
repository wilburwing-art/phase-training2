# 04. Coach red-team as a product

**Status:** closed 2026-09-03
**Lens:** output

## Question

Prompt injection was checked in 2026-06 and cleared. Unchecked: what a wrong
Coach answer costs. The Coach holds write tools against the plan, so its failure
mode is not a bad sentence, it is a mutated week.

## Depth actually reached

Full on the tool surface, the apply paths, and the ceilings. Not covered: live
adversarial prompting against the real gateway, which would need the token and
would spend real money. Every claim below is from the code.

## What holds up

Worth stating before the findings, because the tool design is the part most
likely to have gone wrong and did not:

- **All four tools are propose-only.** `propose_plan_edits`,
  `propose_workout_changes`, `propose_memory_update` and `build_workout` each
  produce a diff the user accepts or rejects; the descriptions say so and the
  apply paths are gated behind `MiniPlanDiffCard` / `MiniWorkoutDiffCard`.
  The model cannot mutate the plan on its own.
- **`isNoop` is real and wired.** `WorkoutDiff.isNoop` (`WorkoutDiff.swift:63`)
  is checked in both diff cards and in `PlanDiffSheet`, which disables the accept
  button and relabels the card "No change". `PlanStore.swift:455,507` guards
  again on apply. A proposal that resolves to nothing cannot be accepted.
- **Adjust arguments are clamped.** Sets to `1...20`, rest to `15...600`
  (`WorkoutDiff.swift:110-112`). A hallucinated 500-set prescription lands as 20.
- **The turn ceiling exists.** Soft cap 50, hard cap 100, plus the T0-1
  `dailyRequestCeiling` of 400 covering non-chat request paths
  (`CoachConfig.swift:33,37,56`).
- **The refinement path was correctly disabled rather than shipped broken.**
  `PlanStore+LLMRefinement.swift:32-63` carries a written explanation that
  `generateLift` does not consume `strategy`, and gates itself off until that
  changes. This is the right call and the reason F1 below is scoped to one
  screen rather than two.

## Findings

### F1 (critical, product) The Coach Request screen bills an LLM call whose output is mostly discarded

`CoachRequestScreen.runGenerator` (`CoachRequestScreen.swift:459`) takes the
`GeneratorStrategy` the model produced and passes it to
`WorkoutGenerator.generateLift(..., strategy: strategy)`. That function either
returns an authored routine, whose builder takes no `strategy` parameter at all
(`AuthoredRoutine.workout`, `AuthoredRoutine.swift:123`), or routes to
`SportSeasonGenerator.generateSession`, which has no `strategy` parameter either.

Of the nine fields on `GeneratorStrategy`, two leak through indirectly and seven
are dropped:

| field | reaches output? |
|---|---|
| `durationMinutes` | yes, via `mem.sessionMinutes` into `targetMovementCount` |
| `focus` | partly, via `liftIndexTotalPair` changing the session index |
| `emphasizePatterns` | no |
| `deprioritizePatterns` | no |
| `targetWeightOverrides` | no (authored calls `progressiveOverloadHint` without a strategy, so it defaults to `.auto`) |
| `rpeOverrides` | no |
| `tempoOverrides` | no |
| `intensityBias` | no |
| exercise preferences | no |

The user picks chips, waits on a streamed call, and is shown `coachReasoning`
above a preview. The reasoning is a real explanation of a workout that was not
built from it. This is the same defect the refinement path documented and
disabled itself over; this screen did not get the same treatment.

### F2 (high, correctness) A Coach swap writes exerciseId 0 and inherits the replaced exercise's prescription

`WorkoutDiffBuilder.apply` (`WorkoutDiff.swift:88-103`) constructs the
replacement as:

```swift
id: existing.id,          // keep slot id
exerciseId: 0,            // 0 = "not from coach.db" sentinel
name: to,
pattern: existing.pattern,
isCompound: existing.isCompound,
sets: existing.sets,
reps: existing.reps,
restSeconds: existing.restSeconds,
notes: existing.notes
```

Three consequences:

1. **`exerciseId: 0` detaches the row from the catalog.** No detail sheet, no
   photo, no muscle attribution, and, load-bearing given critique 03, **no
   injury contraindication can ever match it**, because the exclusion set is a
   set of real exercise ids.
2. **The prescription is the old exercise's.** Sets, reps, rest, pattern,
   `isCompound` and the notes all carry over to a different movement. This is
   the defect class T0-9 fixed at `TodayScreen+TemplateEditor.swift:233` and
   `LogScreen.swift:120`. `WorkoutDiff.swift` is a third site with the same
   shape and was not in T0-9's scope.
3. **`rpe` and `tempo` are dropped**, because the initializer omits them. A
   swap for a tempo-prescribed movement (the ski pool uses `4-0-1-0` on the
   Nordic curl and eccentric calf raise) loses the tempo without saying so.

The tool schema invites this: `toName` is documented as "Free text — use a
common name (e.g. 'Goblet Squat')", and `WorkoutDiff.swift:24` repeats "free
text — no DB lookup in 13d". So the model is being asked for a string, not an
identity, and the apply path has no way to resolve one.

### F3 (high, correctness) Both tools match exercises by display name, case-insensitively

`propose_workout_changes` resolves `fromName` and `exerciseName` with
`caseInsensitiveCompare` against `workout.exercises` (`WorkoutDiff.swift:91,107`).
The tool description tells the model to "Address exercises by their CURRENT NAME
as shown in the context."

Name matching fails in the ways name matching always fails: a shorthand or alias
the context rendered differently, a name the model normalized ("Barbell Back
Squat" to "Back Squat"), or two rows in one session with the same display name,
where `firstIndex` silently picks the first. The failure is a dropped change,
which `isNoop` catches only when **every** change fails. A three-change proposal
where one resolves shows the user an accept button and applies a partial edit
they did not review as partial.

### F4 (medium, product) The medical boundary is one sentence in the prompt with nothing behind it

`CoachSystemPrompt.swift:60` is the whole of it: "Don't give medical advice. If
the user mentions pain that sounds serious, suggest they see a clinician — don't
keep coaching through it."

That is a reasonable instruction and it is the only control. There is no
classifier, no refusal path in code, no logging of pain mentions, and, per
critique 03 F4, no disclaimer anywhere in the app for it to fall back on. The
Coach also holds the user's declared injuries in context
(`CoachContext+InjuryBlocks.swift`), so it is being handed exactly the input
most likely to draw a medical question.

### F5 (medium, cost) The ceilings are client-side and the token is still in the binary

The three caps (`softTurnCap` 50, `hardTurnCap` 100, `dailyRequestCeiling` 400)
all live in `CoachConfig` and are enforced by the client against its own
`UserDefaults`. T0-1 in the 2026-08-23 backlog says the external half is still
open: rotate the compiled-in gateway token and set spend limits on the Cloudflare
gateway itself. Until that lands, every client-side number here is advisory
against anyone who extracts the token, and the backlog's own note already says
"no client-side change can substitute for" the gateway limit.

Nothing new found. Recorded so this critique does not read as if the cost
surface came back clean.

### F6 (low, product) build_workout survives as a live tool on a screen where it cannot work

Given F1, the honest options for `CoachRequestScreen` are to wire `strategy`
into the season and authored paths, or to gate the screen the way
`PlanStore+LLMRefinement` gated itself. Shipping a tool the generator ignores is
the state that produces a plausible explanation attached to an unrelated
workout, which is worse than either.

## Refuted

- **"Prompt injection is unhandled."** Settled in the 2026-06-01 audit as a false
  positive and not re-chased here. `sanitizeFreeText` covers every user-text
  interpolation point and `CoachPromptSanitizationTests` covers the fake-section
  vector.
- **"The Coach can mutate the plan directly."** It cannot. Every tool is
  propose-only, every apply goes through a diff card, and `isNoop` plus the
  `PlanStore` guards block an empty accept.
- **"A hallucinated set count could write an absurd prescription."** Clamped to
  1-20 sets and 15-600 seconds rest at `WorkoutDiff.swift:110-112`.

## Ordering

F2 first: it is a contained edit to one initializer plus a resolve step, it
removes the injury-filter hole the sentinel creates, and it closes the third
instance of a bug the backlog already fixed twice. F1 second, and the decision
there is product, not engineering.
