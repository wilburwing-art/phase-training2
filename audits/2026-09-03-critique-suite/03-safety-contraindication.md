# 03. Safety and contraindication

**Status:** closed 2026-09-03
**Lens:** output

## Question

The app prescribes loads to people who declared injuries. What does a declared
injury actually change in the output, and where does the prescription outrun
what the app knows?

## Depth actually reached

Full on the injury path and the load math, both traced end to end and measured
against the shipped `coach.db`. Not covered: clinical accuracy of the 56-injury
catalog's naming, and whether the 39 contraindication mappings that do exist are
individually correct. Those need a physio, not a code read.

## Findings

### F1 (critical, safety) The app makes an explicit safety promise it does not keep on the path most users are on

`InjuriesEditorSheet.swift:117` tells the user, verbatim:

> "We'll filter out exercises that aren't safe for the injuries you pick."

The season engine honors that. `filteredPool` subtracts
`athlete.contraindicatedExerciseIDs` from the pool
(`SportSeasonGenerator.swift:143`), populated from
`DemographicProfile.excludedExerciseIds`, which resolves from
`exercise_injury_relevance` (`DemographicProfile.swift:99-102, 284`).

The authored path does not. `AuthoredRoutine.workout`
(`AuthoredRoutine.swift:127`) reads `db.exercises(forRoutineId:)` and maps every
row straight into `GeneratedExercise`. There is no injury filter, no equipment
filter and no experience filter in that function. `excludedExerciseIds` is never
consulted, and the caller returns the result unmodified
(`WorkoutGenerator.swift:68`).

The authored path is not an edge case. It is tried **first** for every sport
(`WorkoutGenerator.swift:61`), climbing is the declared pilot that prefers
authored over the engine (`AuthoredRoutine.swift:50`), and the six
`outdoorAuthoredSlugs` sports have no other content path. So of the ten sports a
user can pick, seven are served entirely by the unfiltered path.

### F2 (critical, safety) Twelve injury types have contraindicated exercises sitting inside authored routines

Measured by joining `exercise_injury_relevance` (role `contraindicated`) to
`routine_exercises`:

| injury | authored routines containing a contraindicated exercise |
|---|---|
| lumbar-disc-herniation | 18 |
| finger-pulley | 11 |
| shoulder-impingement | 9 |
| acl-injury | 5 |
| rotator-cuff-injury | 4 |
| whiplash | 2 |
| stinger-burner | 2 |
| wrist-sprain, slap-tear, patellar-tendinopathy, hip-labral-tear, hip-flexor-strain | 1 each |

Named examples, straight from the join:

- A climber who declares **finger-pulley** can be served
  `Climbing Finger Strength Protocol (Repeaters)`, whose content is
  `Hangboard Repeaters (7/3 Protocol)` — the contraindicated exercise is the
  entire routine.
- The same injury appears as `Campus Board Ladder (1-3-5)` in
  `Climber Pre-Season Power Block`.
- A user who declares **lumbar-disc-herniation** gets `Barbell Back Squat` and
  `Romanian Deadlift (Barbell)` in `Climber Off-Season Strength Foundation`,
  `Cyclist Off-Season Strength Foundation`, `Cyclist In-Season Maintenance` and
  `Runner Off-Season Strength`.

Climbing and the finger-pulley case are the sharpest pairing, because climbing
is exactly the sport routed to the authored path by the pilot flag.

### F3 (high, safety) 42 of 56 declarable injuries filter nothing, anywhere

Only **14** of the 56 rows in `common_injuries` have any `contraindicated`
mapping, and there are 39 such mappings in total. The 42 with none include:

`meniscus-tear`, `hamstring-strain`, `achilles-tendinopathy`,
`shoulder-dislocation`, `mcl-sprain`, `plantar-fasciitis`, `it-band-syndrome`,
`pfps`, `spondylolysis`, `shin-splints`, `quad-strain`, `groin-pull`,
`ankle-sprain-lateral`, `frozen-shoulder`, `carpal-tunnel`, `lumbar-strain`,
`compartment-syndrome`, `femoral-stress-fracture`, `tibial-stress-fracture`.

A user who declares a meniscus tear receives the same program as a user who
declares nothing, on both paths, while the editor tells them filtering happened.
The three stress-fracture entries are the ones to fix first: those are load
management questions and the app's answer is a 2.5% load increase.

### F4 (high, safety) No medical disclaimer exists anywhere in the app

A case-insensitive grep across `PhaseTraining/` and `docs/` for
`disclaimer`, `not medical`, `informational purposes`, `at your own risk`,
`before beginning`, `see a doctor`, `professional advice`, `consult`,
`physician`, `healthcare` returns exactly one hit, and it is inside the model's
prompt rather than in front of the user:

`CoachSystemPrompt.swift:60` — "Don't give medical advice. If the user mentions
pain that sounds serious, suggest they see a clinician."

There is no onboarding disclaimer, nothing on the injury editor beyond the
filtering promise in F1, and nothing in `docs/privacy.md`. An app that collects
declared injuries, prescribes barbell loads, and ships hangboard and campus board
protocols should carry one. Also feeds critique 11.

### F5 (high, correctness) Readiness scaling and the RPE cap are built, tested, and unreachable from both live paths

`WorkoutGenerator.swift:152-166` implements a readiness set multiplier
(`lerp(0.6, 1.0, readinessScore)`) and a compound-lift RPE cap. Both are real.

`SportSeasonGenerator.swift` contains **zero** occurrences of `readiness` or
`soreness` (grep). `AuthoredRoutine.workout` uses `context` only to look up a
weight hint and states in its own doc comment that it applies the authored sets
and reps "WITHOUT changing" them. So neither path that generates a user's
workout scales anything by readiness.

The scaling fires only through `makePickedRow` on the custom-routine
re-prescription path, which commit `449bd8d` kept alive for that purpose.

Net effect for safety: the app asks for a soreness check-in and a readiness
signal, and prescribes the identical session either way.

### F6 (medium, correctness) Load progression steps up unconditionally and never steps down

`progressiveOverloadHint` (`WorkoutGenerator+Prescription.swift:15`) resolves an
LLM override first, then falls to `context.priorBest[key]` and always applies
`steppedTargetLb`, a 2.5% increase. There is no branch that reads whether the
previous attempt succeeded, whether reps were missed, whether the user reported
soreness, or whether the phase is a deload.

The math itself is sound and worth saying so: it takes the heaviest prior set at
any rep count, converts to an Epley e1RM, maps back to the prescribed band's
midpoint, then steps. The doc comment at line 43 shows it was written against
exactly the failure it avoids (a 3-rep top set shown as a 12-rep target). The
gap is autoregulation, not arithmetic.

### F7 (medium, correctness) The prior-best lookup is keyed by exercise name

`let key = exercise.name.lowercased()` then `context.priorBest[key]`
(`WorkoutGenerator+Prescription.swift:22,28`). A rename, an alias, or a
shorthand that resolves differently produces a missing hint with no signal, and
two distinct exercises sharing a display name share a load target. T0-9 in the
2026-08-23 backlog fixed the sibling defect on the swap path by deriving
identity from the picked exercise rather than the old row; the same argument
applies here. Low blast radius (a missing hint is silent, not dangerous) but it
is the one place a load number could attach to the wrong movement.

## Refuted

- **"The season engine ignores injuries too."** It does not.
  `SportSeasonGenerator.swift:143` filters `contraindicatedExerciseIDs` out of
  the pool before allocation, and `AthleteState.from` populates it from the
  profile (`AthleteState.swift:99`). The defect is scoped to the authored path.
- **"The load math is wrong."** Checked and it is not. Epley e1RM with a rep-band
  remap is the right shape, and the 2.5% step is conventional. F6 is about
  missing autoregulation, not a bad formula.

## Ordering, if only one thing gets fixed

F1. It is a two-line change in shape (filter `rows` by
`profile.excludedExerciseIds` before the map, and drop the routine if the
filter empties it) and it converts a written safety promise from false to true
on seven of ten sports. F3 is the larger job and can follow.
