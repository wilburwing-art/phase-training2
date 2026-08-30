---
name: phase-training-tab-time-horizon-rule
description: phase-training2's tabs are a time-horizon gradient (Today = one day, Week = seven, Progress = twelve weeks) and the interaction model widens with it. The placement rule the owner endorsed 2026-08-29 is: if a thing's natural time horizon is wider than one day, it does not belong on Today. Trigger before adding ANY card, tile, pill, badge or prompt to a screen in this repo, when deciding which tab a new feature lives on, and when a Today screen critique proposes "just add it to Today".
---

# Which tab does this go on

## The gradient

| tab | horizon | verb | scrolling |
|---|---|---|---|
| Today | one day | do | nothing that matters; header fixed, list short, one button |
| Week | seven days | arrange | none by design (see below) |
| Progress | ~12 weeks | read | yes, the first tab that admits it cannot fit |

Tense runs alongside it: Today is present imperative ("Start workout"), Week is
near future ("Plan next week", drag days), Progress is past ("Last 12 weeks",
PR feed, recent sessions).

What makes the three feel like one app rather than three is `TabHeader`: the
same eyebrow / title / subtitle rhythm across all five tabs while the content
model underneath changes completely.

## The rule (owner call, 2026-08-29)

**If a thing's natural time horizon is wider than one day, it does not belong
on Today.**

Every item stripped from Today that day landed at a wider horizon, and none
went sideways or narrower:

- season badge → Week and Progress (a phase is a multi-week idea)
- soreness check-in → Progress (body state, and it feeds the recovery data there)
- recovery readout → Progress
- last session → Progress
- plan next week → Week header
- missed workouts → the weekly check-in's first step

Apply the rule before writing the view, not after. "It's only one small tile"
is how the five that were removed got there.

## Load-bearing details

- **Week's seven rows are `GeometryReader`-fitted on purpose** so all seven
  always sit at fixed positions ("row 3 = Wed" muscle memory). Anything tall
  added to the Week header steals row height. That is why Plan next week is a
  chip and not a pill.
- **`TabHeader` is one primitive across five tabs** with a "do not deviate per
  tab" spec ref. Extend it with an OPTIONAL parameter (the Today title wheel
  did this) rather than forking a per-tab header.

## Where the structure is under strain

- **Progress is the undesigned one.** Today has a principle, Week has a strong
  one, Progress is twelve-plus cards in a scroll with no stated order. It is
  where long-horizon things accumulate. Ask what it is for before adding a
  thirteenth.
- **Library breaks the sequence.** It sits between Week and Progress and is
  atemporal, a catalog. The rule does not explain it.
- **The Today title wheel is a live tension.** It is a Today control that
  reaches at workouts which are not today's plan. It holds because the question
  is still "what am I doing right now"; extending it to browse other programs
  would make it a Library gesture on the Today screen.
- **The weekly check-in is a horizon with no tab.** It is a moment rather than
  a place, now doing real work (review the week, then plan the next), reachable
  only from a chip in the Week header.

See also [[phase-training-feature-gap-checklist]], which decides WHETHER a
feature is needed. This decides where it goes once it is.
