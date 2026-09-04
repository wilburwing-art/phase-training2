# 02. Niche expert teardown

**Status:** closed 2026-09-03
**Lens:** output

## Question

Would each target community accept these programs, or mock them? The niches in
`audits/niches/` are the acquisition plan, so a program that reads as amateur to
its target audience is a distribution problem before it is a training problem.

## Depth actually reached

Full on the strategy side, partial on the per-niche grading. The 10 niche briefs
were read for their non-negotiables and risk sections; the rendered plans from
critique 01 were graded against them. The grading stopped early because of F1
below: for eight of the ten niches there is nothing to grade, since the app will
not plan for their sport at all.

## Findings

### F1 (critical, strategy) The acquisition research and the product target different people

All ten researched niches are gym-strength communities: r/weightroom,
r/powerlifting, r/naturalbodybuilding, r/xxfitness, r/bodyweightfitness,
r/tacticalbarbell, hybrid/HYROX, and the three creator audiences (Nippard, RP,
Alex Leonidas). Not one is a mountain-athlete community. `r/Mountainathletics`
and `r/MountainAthletes` appear exactly once across all ten files, as a
parenthetical adjacency in `tacticalbarbell.md:6`, marked LOW CONFIDENCE.

The product plans for ten sports and they are all mountain sports: three ski
slugs, `climbing`, and the six in `SportCatalog.outdoorAuthoredSlugs`
(snowboarding, mountain-biking, mountaineering, trail-running, hiking-trekking,
thru-hiking). Everything else is filtered out of onboarding.

The two lists do not intersect.

### F2 (critical, strategy) The chosen niche is the one the product cannot serve at all

`STRATEGY.md:172` picks **hybrid-hyrox** as the single niche, Path B, $40/yr plus
$99 lifetime. HYROX is not a sport this app can plan for. There is no `hyrox` or
`hybrid` slug in `sport_categories`, no such string anywhere in
`TrainingMemory.swift`, and the nearest thing, `obstacle-course-racing`, is in
`Sport.catalog` but fails `isPlannable` because it is neither season-engine
supported nor in `outdoorAuthoredSlugs`. A HYROX athlete downloading this app
cannot select their sport.

Ranked #2 and #3 are tacticalbarbell and powerlifting. Same answer: `powerlifting`
is in `Sport.catalog` and not plannable; there is no tactical slug at all.

### F3 (high, strategy) The product built the half the strategy deferred and deferred the half it prioritized

`STRATEGY.md:88`: "Top-level call: Path B first. Coach is a future $10/mo Pro
upsell once the base is established, not a v1 requirement." `STRATEGY.md:176`
repeats it: Coach at month 6 to 12, contingent on observed demand from paying
users.

What shipped is the Coach: `PhaseTraining/Coach/` is 20 files, it has a live
Cloudflare gateway, typed tools, conversation persistence, consent screens, an
entitlement gate and a turn ceiling. Meanwhile the Path B deliverable, a
programming planner with a template library, is the part critique 01 found
emitting four-exercise sessions from two movement pools.

This is worth stating plainly because the strategy's own reasoning for
deferring the Coach was unit-economics risk, and T0-1 in the 2026-08-23 backlog
is that exact risk arriving: a gateway token compiled into the IPA, still
awaiting an external rotation.

### F4 (high, content) The routine library is a third the size the strategy assumed and 95% of it is unattributed

`weightroom.md:56` describes "167 bundled routines via coach.db" and builds a
work item on auditing them. The shipped `coach.db` has **113**. Of those, **107
have a null `source_name`**; the six that carry one are the MTI and Easy Strength
distillations.

Attribution is not cosmetic for these audiences. `weightroom.md:59` lists it as
build work precisely because the niche's non-negotiable is knowing whose program
they are running. An unattributed template library reads as scraped.

None of the canonical strength programs are present. A query for 5/3/1, GZCL,
Texas Method, Starting Strength, Madcow and nSuns returns zero rows. Consistent
with the mountain-athlete scope, and disqualifying for the three gym niches the
strategy ranked highest.

### F5 (critical, content) 24 routines contain a single exercise, and they are served as a day's workout

Distribution of exercises per routine across the 113:

| exercises | routines |
|---|---|
| 1 | 24 |
| 2 | 18 |
| 3 | 21 |
| 4 | 18 |
| 5 | 19 |
| 6 | 8 |
| 7 | 4 |
| 8 | 1 |

Mean 3.3. `AuthoredRoutine.workout` (`AuthoredRoutine.swift:115`) returns nil
only when a routine has **no** exercises, so a one-exercise routine is served
verbatim as a session. 37% of the library is one or two exercises. Any audience
in the briefs would call a one-lift day a bug, and for the six outdoor authored
sports this is the only content path they have.

### F6 (high, credibility) Three sessions a week of max hangs is the screenshot that gets dunked on

Carried from critique 01 F8. `weightroom.md:92` names the mechanism: "One
screenshot of bad Coach output gets dunked on for a week." The same is true of a
generated program. `Hangboard Max Hang (20mm Edge) 5x8s` in all three off-season
climbing sessions is the single most quotable output in the dump, and a climbing
audience will read it as evidence the app was not built by a climber.

### F7 (medium, credibility) A three-day week that is the same workout three times fails every niche's basic sniff test

Critique 01 F3. None of the ten briefs need to be consulted for this one. It is
below the floor for any of them.

### F8 (medium, positioning) The one genuinely defensible asset is not what the strategy is selling

`PhaseRule` is a per (sport, variant, phase) table carrying an objective string,
a demand mix, a fatigue ceiling and a progression mode, with the season model
that produces it. Nothing in the competitor set does seasonal periodization
against a sport calendar. That is a mountain-athlete pitch, and it is the thing
the app is actually built around. The strategy sells a template planner to
powerlifters instead.

## Per-niche verdict

Eight of ten cannot be graded because the app will not accept their sport.
Recording the verdicts anyway, since the question was whether they would adopt:

| niche | verdict | driver |
|---|---|---|
| hybrid-hyrox (#1 pick) | cannot adopt | no HYROX sport; F2 |
| tacticalbarbell (#2) | cannot adopt | no tactical sport; no canonical templates |
| powerlifting (#3) | cannot adopt | sport present but not plannable; no RPE-driven meet prep content |
| weightroom | would mock | F4 attribution, F5 one-lift days, no GZCL/531 |
| naturalbodybuilding / RP / jeff-nippard | cannot adopt | no hypertrophy sport path; F7 kills it anyway |
| bodyweightfitness | cannot adopt | `calisthenics` has 3 routines and is not plannable |
| xxfitness | cannot adopt | no path; nothing in the app addresses the niche |
| alex-leonidas | cannot adopt | same as the hypertrophy cluster |
| **mountain athletes (unresearched)** | **plausible adopt** | the only audience the product serves, and the only one with no brief |

## Refuted

- **"The 113 routines are mostly filler because they are unattributed."**
  Not established. Null `source_name` proves the field is unfilled, not that the
  content is bad. The 6 attributed ones are real distillations (MTI, Easy
  Strength). F4 claims the attribution gap and the size discrepancy, both
  measured, and stops there.

## The one thing to decide

Either the product grows toward the researched niches, which means a general
strength path, canonical templates and dropping the sport gate, or the research
grows toward the product, which means briefs for the mountain-athlete
communities that no file in `audits/niches/` covers. Both are defensible.
Continuing to hold both at once means the acquisition plan cannot be executed
against the app that exists.
