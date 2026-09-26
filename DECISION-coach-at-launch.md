# Decision: does the AI Coach ship in the first App Store release?

Open. Raised 2026-09-21 while drafting the store listing, written up
2026-09-26 against build 144. Nothing is being built on this until it is
answered. The rest of the submission work (privacy policy, paywall terms,
screenshots, listing copy) is done and does not depend on it.

## Why this is a decision and not a task

Every install ships the same Cloudflare AI Gateway token, baked into the IPA
by CI (`scripts/generate-coach-secrets.sh`, secret
`PHASETRAINING_CF_AIG_PROD_TOKEN`). The gateway holds the upstream Anthropic
key under BYOK, so **every coach call from every user bills one Anthropic
account: Wilbur's.** There is no per-user metering anywhere in the path.

Today both Pro gates are held open (`CoachEntitlement.proRequired = false`,
`SupportEntitlement`), so on the current build anyone who installs from the
App Store and accepts the consent screen gets the coach free, on that key.

## What the code does today (build 144, verified)

- `CoachConfig`: `claude-sonnet-4-6`, falling back to `claude-haiku-4-5`;
  `maxOutputTokens` 1024; 20 s time-to-first-byte.
- Each turn sends a freshly assembled context snapshot: plan, past weeks,
  completed sessions and sets, body metrics, injuries, soreness, dislikes,
  derived figures. The privacy policy lists the full set.
- Caps, all client-side in UserDefaults: `softTurnCap` 50/day,
  `hardTurnCap` 100/day, `dailyRequestCeiling` 400/day across all callers.
  The comment in `CoachConfig.swift` says what they are worth: they limit
  accidental spend, not abuse, and anyone who extracts the token from the
  IPA bypasses them. **The real ceiling has to be a rate or spend limit on
  the Cloudflare gateway and on the Anthropic org.**
- Four callers reach the gateway, and two of them need no user input once
  consent is on: chat, "Ask coach to build", `InsightGenerator`'s daily
  insight, and background plan refinement (one call per lift day per regen).

## Cost, honestly

No verified per-token price was looked up for this note. From memory,
Sonnet-class pricing puts a turn with a few thousand tokens of context on the
order of a cent or two, so one user at the 100-turn cap is roughly a dollar
or two a day against $2.99 a month. Re-measure before relying on that. Two
conclusions hold whatever the exact number: **the subscription does not cover
a heavy user, and a leaked token has no per-user bound at all.**

## The options

**A. First store release without the coach.** A flag hides the Coach row, the
consent step, and the two coach bullets on the paywall; TestFlight keeps it
on. Pro then sells two-sport planning and season phases, which is what the
recorded product decision of 2026-07-14 in `SupportEntitlement.swift`
already calls the first paid feature, ahead of the coach. Zero cost
exposure, no review questions about generated training advice, one section
cut from the listing copy in `docs/store/LISTING.md`. Roughly a day, mostly
copy and one flag.

**B. Coach behind Pro, with hard caps outside the app.** Flip both gates, set
a rate limit on the Cloudflare gateway and a monthly spend limit on the
Anthropic org as the true ceiling, watch the dashboard for a month. Blast
radius is whatever cap is set: a heavy user or a leaked token burns it and
the coach goes dark for everyone until the month rolls. Cheap to start, and
it produces real usage numbers.

**C. Coach behind Pro with real metering.** A Worker in front of the gateway
validates an App Store receipt or an App Attest assertion and enforces a
per-subscriber quota. The only option where a bad actor cannot spend other
people's money, and the right long-term shape. Days of work, plus a backend
to run.

## Recommendation on file

A for 1.1.0, then B or C in a follow-up once there are subscribers to
measure. The coach is the most expensive feature to get wrong on day one and
the likeliest to draw App Review questions, and the app sells without it. If
the coach is meant to be the launch hook, B with a spend cap that would not
hurt to lose is the honest minimum.

Note that option C overlaps decision 5 in `PLAN-next-gen.md` ("a backend, a
data-collection posture, and licensing outreach"), which was answered yes on
2026-09-26. If that backend gets built for track 5, the metering Worker has a
natural home and C gets much cheaper.

## What changes once this is answered

- **A**: add the flag, cut the coach section from `docs/store/LISTING.md`,
  drop the coach paragraph from the App Review notes, re-shoot the paywall
  screenshot.
- **B or C**: flip `CoachEntitlement.proRequired` and `SupportEntitlement`'s
  switch in the same build that ships the App Store Connect products, or the
  subscription sells nothing gated. Keep the listing copy as drafted.
