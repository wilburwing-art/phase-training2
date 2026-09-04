# 08. Copy and voice

**Status:** closed 2026-09-03
**Lens:** experience

## Question

Does the app speak with one voice, and is that voice legible to a beginner?
Kettle replaced the Repelican on some surfaces, the Coach has its own register,
and the generator emits its own prose.

## Depth actually reached

Full on the Coach persona, the mascot intent, house-style compliance and the
promise-versus-behaviour check. Partial on register clustering: strings were
sampled by grep rather than exhaustively extracted, so the dash count below is a
floor.

## Findings

### F1 (critical, trust) Three user-facing strings promise personalization the generator does not perform

Each is a plain claim, and each is contradicted by a finding elsewhere in this
suite:

| string | location | contradicted by |
|---|---|---|
| "We'll filter out exercises that aren't safe for the injuries you pick." | `InjuriesEditorSheet.swift:117` | 03 F1 — the authored path applies no injury filter, and it serves seven of ten sports |
| "The coach picks exercises that fit your equipment, injuries, and dislikes. Tap Generate to see a workout" | `CoachRequestScreen.swift:179` | 04 F1 — seven of nine `GeneratorStrategy` fields are dropped before the workout is built |
| "an AI coach that personalizes every workout" | `PaywallView.swift:74` | 04 F1, and this one is on the paywall |

The third is the one that costs money. It is the sentence a user reads while
deciding to pay, and the feature it describes is the one
`PlanStore+LLMRefinement.swift:44-63` disabled itself over, in its own words,
as "pure token spend plus a false product claim".

### F2 (high, process) The codebase already caught this exact defect once and did it well

Worth naming as the standard, because it is the model for fixing F1. T2-2's
comment block reads:

> "the 'refined' workout is byte-identical to the deterministic one, and it was
> still stamped `refinedByLLMAt` and surfaced to the user as coach-personalized.
> That's pure token spend plus a false product claim."

It then gates the whole path on `Self.llmRefinementConsumesStrategy` and leaves
the machinery intact for the day the generator consumes strategy.

`CoachRequestScreen` is the same defect on a different screen and got none of
that treatment. One instance was diagnosed precisely and disabled; its sibling
ships.

### F3 (high, positioning) The Coach's system prompt hardcodes a persona the product cannot serve

`CoachSystemPrompt.swift:34`: "Concise. The user is a **busy hybrid athlete**;
they don't want preamble."

Per critique 02 F2, HYROX and hybrid are not sports this app can plan for; there
is no such slug in `sport_categories` and nothing in `Sport.catalog`. The ten
plannable sports are ski, climbing and four other mountain disciplines. The
Coach is being told, on every turn, to address a user the app will not accept.

The instruction itself is good writing. It is aimed at the wrong person.

### F4 (medium, house style) 25 user-facing strings use em or en dashes, against the stated ban

`grep -rn 'Text("[^"]*[—–]' PhaseTraining/` returns 25 hits. A sample:

- `PaywallView.swift:74` — "around a second one — plus an AI coach"
- `CoachRequestScreen.swift:237` — "Nothing generated yet — go back and tap Generate."
- `SubstituteExerciseSheet.swift:67` — "No curated matches — similar by muscle & movement pattern:"
- `RemindersEditorSheet.swift:53` — "Couldn't enable — notifications are off for this app."
- `DayWorkoutPreviewSheet.swift:184` — "Edits stay local — tap Save to library to keep them."

Two of the 25 are numeric ranges (`"Enter 5–600 minutes."`,
`"Enter \(lo)–\(hi) \(unit)."`), which are typographically conventional and are
a different call from the prose cases. The other 23 are prose dashes and each
one rewrites to a period, comma or parenthesis without loss.

### F5 (medium, coherence) Kettle is a face with no voice

`MASCOT2.md` specifies Kettle as a visual character (five animation loops, a
silhouette that reads at 44px, cream-lime-coral). It specifies nothing about how
the app talks, and nothing in the copy carries a Kettle register.

The result is two unrelated personalities: a friendly anthropomorphized
kettlebell on the welcome screen and the paywall, and an assistant instructed to
be "Concise. Direct. Specific. No preamble." Neither is wrong. They are not the
same app talking.

This is a decision to make rather than a bug to fix: either Kettle is decoration
and the voice is the terse coach, which is coherent, or Kettle has a voice and
the onboarding and empty states should carry it.

### F6 (medium) The mascot migration is clean in code and stale in the docs

`grep -rn "Repelican" PhaseTraining/` returns **nothing**, so the swap landed
completely in shipping code. `MASCOT.md` is correctly marked RETIRED with a
pointer to `MASCOT2.md` and an explanation of what Kettle does not inherit.

The residue is elsewhere: `handoff/mascot/` still carries the frozen Repelican
SVG exports, deliberately, as history. That is a defensible call and is noted
here only so a future cleanup does not read them as live assets.

## What holds up

- **Jargon does not leak.** The season engine's `provenance` string carries raw
  demand rawValues (`eccentricLeg`, `kneeStability`) and is rendered in exactly
  one place, `CoachPolishedExplanationSheet`. `TodayScreen+Derived.swift:200-202`
  records the decision: PlanBlurb "writes a sentence from the same facts
  instead; provenance stays" machine-side. A user never sees an enum.
- **The Coach's untrusted-data block is well written.** It names the exact
  fields that are data rather than instructions (dislikes, constraints, sport-log
  notes, feedback notes, injury notes) and says what to do with an embedded
  directive. It reads like someone thought about the attack rather than pasting
  a boilerplate line.
- **The injury-naming instruction is the right level of detail**: refer to
  "Patellar Tendinopathy", never `patellar-tendinopathy`
  (`CoachSystemPrompt.swift:30`). That is the kind of instruction that keeps
  slugs out of user-visible prose.

## Refuted

- **"The generator's demand vocabulary reaches the user."** It does not. F5's
  positive note above; the one render site is a sheet that is now near-dead.
- **"Repelican strings still ship."** They do not. The grep is empty.

## Ordering

F1, and specifically the paywall line, since it is a paid claim about a feature
that does not run. F2 shows the fix has a precedent in this repo: either wire
strategy through, or gate the screen and change the copy to describe what the
deterministic path actually does. F4 is a mechanical sweep of 23 strings.
