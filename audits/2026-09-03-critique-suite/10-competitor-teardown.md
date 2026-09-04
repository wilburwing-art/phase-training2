# 10. Competitor teardown

**Status:** closed 2026-09-03
**Lens:** business

## Question

What is the one-sentence reason to switch from what someone already uses? The
app already parses Fitbod's CSV export, which means the assumed switcher is a
Fitbod user.

## Depth actually reached

Full on the in-repo side. Competitor pricing was web-searched this session and
is **reported, not first-party verified**: the numbers below come from
comparison articles (one of them Boostcamp's own site, one a competing app's
blog), except MTI's, which is from mtntactical.com's own shop page. Re-verify
any figure before it goes into marketing copy.

## The competitive set is not the one the repo assumes

The app imports Fitbod CSV (`FitbodCSVParser`, `FitbodRealCSVSmokeTests`), which
encodes an assumption that the switcher is coming from a general gym-logging
app. Per critique 02, the product plans only for ski, climbing, snowboarding,
MTB, mountaineering, trail running, hiking and thru-hiking. Those users are not
choosing between Fitbod and Hevy. They are choosing between MTI, Evoke Endurance
and a PDF.

### Gym-logging tier (the set the repo prepared for)

| app | annual | free tier | what it does |
|---|---|---|---|
| Hevy | $23.99 | yes, real | logging plus social |
| Boostcamp | $59.99 | yes, non-expiring | canonical program library (5/3/1, GZCL, nSuns) plus tracking |
| Fitbod | $95.99 | no | algorithmic per-session generation from recovery state |
| **Phase Training** | **$49.99** (nothing gated) | everything | seasonal periodization for one mountain sport |

Against this tier the app loses on every axis a gym lifter cares about. Boostcamp
owns the template library and Phase Training has none of the canonical programs
(critique 02 F4). Fitbod owns algorithmic generation and does it from a catalog
orders of magnitude larger than 69 movements. Hevy owns price and logging
quality.

### Mountain-athlete tier (the set the product actually competes in)

| provider | price | shape |
|---|---|---|
| Mountain Tactical Institute | $35/month master subscription | plan library, sport- and season-specific, human-authored |
| Evoke Endurance | plan sales plus coaching (price not confirmed) | Scott Johnston's plans, revised from Uphill Athlete |
| Uphill Athlete | plan sales plus coaching | the canonical mountain-endurance methodology |
| **Phase Training** | $49.99/year | the same idea, automated and personalized |

This is the tier where the pitch works. MTI at $35/month is **$420 a year**
against Phase Training's $49.99, and MTI sells a static plan you follow, not a
plan that reshapes around your logged sessions, your declared injuries and your
second sport.

## The switch sentence

> "MTI's plan, adapted to your week, for a tenth of the price."

Whether the app supports it, honestly:

| the sentence promises | reality |
|---|---|
| MTI-grade programming | 3 routines are literally distilled from MTI plans; the rest is a 69-movement season engine (critique 01) |
| adapted to your week | the support-sport reflow is real and unique; readiness and soreness reach nothing (03 F5) |
| a tenth of the price | true, and currently free (09 F1) |

So one third of the sentence is fully true, one third is half true, and one
third is the thing critique 01 says needs work.

## Findings

### F1 (high, positioning) The one defensible differentiator is not the one being sold

Nothing in either tier does seasonal periodization against a sport calendar with
a second-sport de-confliction layer. `PhaseRule` plus `SupportScheduler` is a
real moat, and `SupportEntitlement.swift:5-7` already identifies the support
feature as the first thing worth charging for.

The paywall leads with the AI coach instead (`PaywallView.swift:74`), which is
the feature every competitor can add in a quarter and which critique 04 shows
does not currently reach the generator.

### F2 (critical, legal exposure) Three shipped routines are distilled from a paid competitor's named plans

`SELECT name, source_name FROM routines WHERE source_name IS NOT NULL` returns
six rows. Three name MTI directly:

- `MTB Pre-Season Strength — Leg Blasters + Grind` — "MTI Mountain Bike Pre-Season V2 (distilled)"
- `MTB Pre-Season Strength — Power Grind` — "MTI Mountain Bike Pre-Season V2, week 5 (distilled)"
- plus two splitboard routines sourced to "shralpinism (MTI Backcountry Ski Pre-Season V6, distilled)"

The splitboard pair is the more defensible case: `scripts/db/distill_snowboard.py`
documents the chain as the owner's own shralpinism program, "which itself credits
MTI Backcountry Ski Pre-Season V6, MTI In-Season Ski Maintenance V2, and Uphill
Athlete freeride/skimo plans". The MTB pair has no such intermediary.

Three specifics make this worth a decision before App Store submission:

1. MTI sells these plans at $35/month. The distilled versions ship inside the
   IPA and are served to users for free.
2. The exercise names carry MTI's branded vocabulary. `distill_snowboard.py`
   states it adds a "curated SIGNATURE shortlist (Tibialis Raise, Kneeling
   Slasher, Mini Leg Blaster, Standing Founder, Poor Man's Leg Curl)" so "the
   sessions read like the source". Leg Blaster is MTI's signature movement name.
3. `source_url` is empty on all six rows, so the app credits the source in a
   field no user sees and links to nothing.

This is not a legal opinion. It is three facts the owner should weigh, and the
portfolio already treats the underlying material as paywalled (the
`mtntactical-plans` and `uphillathlete-archive` repos are described as an
offline archive of paywalled third-party content).

### F3 (medium) The Fitbod importer is the right feature aimed at a user who will not arrive

`FitbodCSVParser` plus its real-CSV smoke test is careful work, and importing a
switcher's history is exactly the right onboarding accelerant. The problem is
that a Fitbod user is a gym lifter, and `SportCatalog.isPlannable` will not let
them pick a sport. They import five years of bench press history into an app
that will plan them a ski off-season.

The equivalent feature for the audience the product serves would import from
TrainingPeaks or Strava, neither of which is wired.

### F4 (medium) Price is set against the wrong tier

$49.99/year sits mid-pack among gym loggers, above Hevy and Boostcamp and below
Fitbod, in a tier where the app is outmatched on features. Against MTI's $420 a
year it is an order-of-magnitude story that sells itself.

Same number, entirely different pitch, depending on which tier the marketing
names. Currently nothing names a tier.

## Refuted

- **"Phase Training has no competitive moat."** It has one:
  season-phase-driven programming with support-sport de-confliction. Neither
  tier does it. Critique 01 is about the moat being under-built, not absent.
- **"The distilled routines are copied wholesale."** Not established, and the
  splitboard ones are documented as passing through the owner's own program. The
  finding is about the MTI-named pair and the branded movement vocabulary, not
  about a wholesale copy.

## Sources

- [Fitness App Pricing 2026: What Hevy, Strong, Fitbod, and SensAI Cost per Year](https://www.sensai.fit/blog/fitness-app-pricing-free-tier-comparison)
- [Fitbod vs Strong vs Hevy vs SensAI](https://www.sensai.fit/blog/fitness-app-comparison)
- [Boostcamp vs Fitbod](https://www.boostcamp.app/vs/fitbod)
- [MTI Master Subscription Plan](https://mtntactical.com/shop/master-subscription-plan/)
- [Evoke Endurance](https://evokeendurance.com/)
