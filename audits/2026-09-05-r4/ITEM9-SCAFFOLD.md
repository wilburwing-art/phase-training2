# Item 9: niche briefs for the communities the app actually serves (T3-1)

## Problem
All ten acquisition briefs in `audits/niches/` target gym-strength
communities (powerlifting, natural bodybuilding, Jeff Nippard, hybrid HYROX,
tactical barbell, r/bodyweightfitness, r/xxfitness, r/weightroom, RP, Alex
Leonidas), and `STRATEGY.md` picked hybrid-hyrox, a sport with no slug in the
app. Every plannable sport is a mountain sport. The owner agreed on 2026-09-04
(decision 5a) that the research should grow toward the product.

## Done means
Seven briefs in `audits/niches/mountain/`, one per community, in the exact
section structure of the existing ten (see `alex-leonidas.md`), each with
every audience figure read from the page that states it, dated, and every
figure that could not be read marked as an estimate with its basis. Filed,
not acted on: pricing and the gate are deferred (5c, 5d), so no brief ends in
a launch plan with dates. The ranking table in STRATEGY.md is NOT redone here;
that is a later, owner-led step once the briefs exist.

## Communities (grouping the ten plannable slugs by where the people are)

| brief | app slugs it serves |
|---|---|
| ski-and-snowboard | alpine-skiing, snow-sports, snowboarding |
| ski-mountaineering-and-splitboard | ski-mountaineering (and the backcountry half of snowboarding) |
| climbing | climbing, bouldering, sport-climbing, trad-climbing |
| alpinism-and-mountaineering | mountaineering, alpine-climbing, ice-climbing, mixed-climbing |
| mountain-biking | mountain-biking |
| trail-and-ultra-running | trail-running |
| hiking-and-thru-hiking | hiking-trekking, thru-hiking |

## Research rule (the one that failed last time)
STRATEGY.md records that the first ten briefs' audience numbers were wrong by
up to +137% (r/bodyweightfitness quoted at 2M, actually 4.7M) and in one case
3x too large (r/Hyrox). So:

1. Every subreddit member count, YouTube subscriber count, Strava club size,
   forum size or podcast download figure is read from the page and quoted with
   the URL and the date read. WebFetch: verbatim or NOT ON PAGE.
2. A number that could not be read is written as an estimate with its basis,
   never as a fact.
3. Competitor apps: name, price as shown on their pricing page today, and what
   they do that this app does not. Uphill Athlete, TrainingPeaks, Mountain
   Tactical, Lattice, Crimpd, TrainHeroic, Vert.run, Coros/Garmin coaching,
   Strava, MTB-specific and hiking-specific apps as relevant.
4. No em dashes or en dashes.

## Shape
Fan-out, one agent per brief, each writing ONLY
`<scratchpad>/niches/<brief>.md`. The lead copies into
`audits/niches/mountain/`, checks every figure has a URL or an estimate
marker, and commits. Agents do not touch the repo.
