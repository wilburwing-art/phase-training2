# Niche: r/bodyweightfitness — calisthenics

## Community surface area

- **r/bodyweightfitness**: 4,749,052 subscribers as of 2026-05 (live JSON, [reddit.com/r/bodyweightfitness/about.json](https://www.reddit.com/r/bodyweightfitness/about.json)). The ~2M figure in the brief was significantly stale — this is actually one of the largest fitness subs on Reddit.
- Adjacent: r/calisthenics (~250K [LOW CONFIDENCE]), r/GettingStronger, r/flexibility, r/Streetworkout (~50K [LOW CONFIDENCE]), r/handstand.
- IG / YouTube are *enormous* for calisthenics — visual sport, high media value. Top creators: Chris Heria, FitnessFAQs, Bar Brothers Groningen, Daniel Vadnal (FitnessFAQs).
- Discord: numerous coach-run servers; Reddit Recommended Routine (RR) Discord [LOW CONFIDENCE 5-10K].
- In-person: Battle of the Bars / King of the Bar competitions; less centralized than powerlifting meets.
- Hangouts: the [Recommended Routine](https://www.reddit.com/r/bodyweightfitness/wiki/kb/recommended_routine) wiki (canonical beginner program — *millions* of users have started here); the Move Tuesday / Form Check threads; [Skill Sunday]. The [Minimalist Routine](https://www.reddit.com/r/bodyweightfitness/wiki/kb/minimalist_routine) is another canonical anchor.
- Activity: 50-100 top-level posts/day [LOW CONFIDENCE]; very beginner-heavy, lots of "I want to start" posts. Comment-heavy on form checks and skill progressions.

## Existing app competition

- **Caliathletics / Caliathletics Programming**: ~$10-15/mo [LOW CONFIDENCE]. Calisthenics-specific.
- **Thenx (Chris Heria)**: $14.99/mo [LOW CONFIDENCE]. Massively marketed; mixed reviews ("repetitive," "too HIIT-cardio").
- **FitBod**: $12.99/mo / $79.99/yr [LOW CONFIDENCE]. Has bodyweight mode.
- **Boostcamp**: free / $9.99/mo. Has some bodyweight templates (RR, Convict Conditioning).
- **Hevy**: free / $5.99/mo / $39.99/yr. Used as a logger.
- **Strong**: $4.99/mo / $29.99/yr [LOW CONFIDENCE].
- **Calisthenics Workout app** (various): free / freemium.
- **GMB Fitness / Movement courses**: $50-200 one-time courses.
- **YouTube programs / FREE**: massive amount of free programming. r/bwf RR is free. The "I'll just follow the RR + YouTube" path is extremely sticky.

Top complaints:
- Thenx: "Way too expensive for what it is"; "Marketing-heavy, programming-light"; "Aerobic-cardio focus when I came for skills."
- Caliathletics: "Better but still rigid"; "No real progression logic."
- Generic loggers: "Can't log progressions like 'tuck planche 3x10s, advanced tuck planche 3x5s.'"
- "Nothing tracks bodyweight skill progressions properly — they're all sets x reps when I need time-under-tension or hold duration."

**Feature gap Phase Training could attack**: native support for skill progressions (planche, front lever, handstand) tracked as **isometric holds (time-under-tension)**, **assisted/weighted variations**, **rep counts at named progression levels**. Phase Training schema needs the equivalent of a "progression tree" per skill. The Coach could shine: "your tuck planche has been 3x10s for 4 weeks — try 3x12s or move toward advanced tuck." This is genuine whitespace.

## Willingness-to-pay signals

- Thenx: $14.99/mo proves $15-tier exists for calisthenics-curious users.
- GMB Fitness courses: $50-200 one-time, popular.
- FitnessFAQs (Daniel Vadnal) programs: $50-150 one-time [LOW CONFIDENCE].
- Coach pricing: $50-150/mo, less normalized than powerlifting coaching.
- Many users are price-sensitive: this niche skews younger, more international, more free-content-tolerant than powerlifting.
- **Best-fit pricing: Option A ($10/mo Pro) or Option B ($5/mo + $40/yr)**. The "$20 AI vs $200 human coach" framing **does NOT land here** — calisthenics isn't a "I pay $200/mo for coaching" niche. Pricing must be lower. Option D ($99 lifetime) might convert a chunk as a one-time program purchase if positioned correctly.

## Distribution — map to the 4 channels

- **Subreddit infiltration**: **Medium**. r/bwf is friendly to genuine contributors. The RR / Form Check threads are natural posting venues. Self-promo rules exist but are less strict than r/weightroom. However, the audience is *huge and noisy* — your post has to stand out.
- **YouTube creator integration**: **Very High**. Candidates:
  - **FitnessFAQs (Daniel Vadnal)**: ~3M subs [LOW CONFIDENCE]. The most respected name. Sponsorship rate: $5-15K [LOW CONFIDENCE].
  - **Chris Heria / ThenxAcademy**: ~6M subs [LOW CONFIDENCE]. Owns own app; direct competitor, won't promote.
  - **Hampton (Calisthenic Movement)**: ~2.5M subs [LOW CONFIDENCE]. German-based; takes sponsorships.
  - **Yerai Alonso (calistheniacs)**: ~1M+ subs.
  - **Bar Brothers Groningen**: ~1M subs.
  - **Smaller picks**: Austin Dunham (~1.4M), Tom Merrick, Coach Will. Mid-tier picks more open to indie deals.
  - Realistic ask: free Pro + $500-2K for an integration at the mid-tier (300-700K subs).
- **Newsletter wedge**: **Low-Medium**. Newsletter culture is weak in calisthenics. "Weekly Calisthenics Skill Notes" could work but the niche has migrated to YouTube + IG, not email.
- **TikTok daily clips**: **Very High**. Skills are visually spectacular (planche, muscle-up, handstand). Daily clip culture is well-established. Lowest-cost compounding channel — if the founder can do or partner with someone who can do the skills.

**THE best channel: TikTok daily clips** (with creator partner who can perform skills on camera) OR a single mid-tier YouTube creator integration (300-700K subs range, FitnessFAQs-adjacent, ~$1-2K + free Pro).

**Cheapest "first 10 users"**: post a "I'm building an app that tracks tuck planche progressions properly — here's what it looks like" thread on r/bwf with screenshots. Niche pain point + visual proof = installs.

## Product fit + Path A vs Path B

This niche **leans Path B — programming-first planner**. Calisthenics users want progression tracking and skill plans more than they want a chat coach. The Coach is nice-to-have, not the wedge. **Path B could ship faster and at lower price**.

**Non-negotiables**:
1. Skill progression trees (tuck planche → advanced tuck → straddle planche → full planche, each with hold times).
2. Isometric hold timer + log.
3. Assisted / unassisted / weighted variations on pull-ups, dips, muscle-ups.
4. Bodyweight-aware loading (the user's BW *is* the load).
5. Mobility / flexibility tracking integrated (front split, pancake, bridge progressions).

**What Phase Training has**: 167 routines (PLAN-routines.md) — probably *few* are calisthenics-specific; verify in coach.db. The Routine model accepts TEXT reps like "AMRAP" or "7-10 sec" (per PLAN-routines.md schema-mismatch resolution), which is *exactly* the format needed for isometric hold times. That's a real existing strength.

**Build work**:
1. Skill progression tree data model + UI (multi-week build).
2. Isometric hold timer in Log (likely doesn't exist yet).
3. Audit/expand coach.db for calisthenics templates (Recommended Routine, FitnessFAQs Foundations, Convict Conditioning, GMB Elements).
4. Bodyweight-aware load math (user's BW × multiplier for weighted pull-ups).
5. If shipping Path B, defer Coach entirely.

## Unit-economics check

This niche skews **lower power-user** for chat — they want clear progression rules, not conversations. Estimate 15-30 Coach turns/month per active user if Path A, [LOW CONFIDENCE].

Cost math (if Path A):
- Per turn ≈ $0.009.
- 30 turns/month = **$0.27/user/month**.

At $9.99/mo (Option A) - 30% Apple = $7 net - $0.27 = **$6.73 / $7 = 96% gross margin**. **Viable.**

At Option B ($5/mo) - 30% = $3.50 net - $0.27 = $3.23 / $3.50 = 92% margin. Still viable but every extra Coach turn matters.

**If Path B**: zero API cost. $20 one-time or $40/yr captures buyers, builds an audience, then layers Coach as an upsell later.

## Founder/content fit

Wilbur as a solo iOS dev with no calisthenics presence has the same problem here as in bodybuilding — physical credibility matters. Calisthenics is *visual*: if your social proof isn't "here's my muscle-up" or "here's my tuck planche," you're not credible.

Solution: partner with a mid-tier calisthenics creator (50-300K subs) as the on-camera face. Or position the app as engineering-focused: "I built this because I wanted to actually track my tuck planche progression and no app did that." This works if the dev story is honest.

## Risks & landmines

- **Chris Heria is litigious / aggressive** in the calisthenics space [LOW CONFIDENCE — based on community complaints about Thenx aggressive marketing]. Avoid direct positioning against Thenx.
- **Free content is the dominant alternative.** The RR is free, FitnessFAQs has 100s of free videos. Convincing this niche to pay $10/mo requires the app to do something *clearly* better than the free path.
- **International audience.** Calisthenics is much bigger in Eastern Europe, Brazil, Southeast Asia, where $10/mo is harder. iOS-only also misses a chunk of this audience (Android-heavy outside US/EU).
- **Skill progression is a *content* problem.** You need a credible progression tree per skill — getting this wrong publicly will get roasted by FitnessFAQs-fans.
- **Saturation of skill tutorials.** No competitor has won progression-tracking — but several have tried (Caliathletics, Thenx, GMB). Why did they fail? Probably: too few users care enough to pay for tracking when free YouTube exists.

## Funnel napkin math — solving for $10k MRR

- Subscribers: 4,749,052. Active fraction: ~3-5% = ~140-237K [LOW CONFIDENCE — large beginner population that posts once and leaves].
- Realistic addressable subset (intermediate, doing skill work, on iOS, willing to pay): ~10-15% of active = **14-35K**.
- Trial→paid conversion: **3-6%** [LOW CONFIDENCE — niche is much more price-sensitive than powerlifting/RP].
- At Option A ($9.99/mo), need **1,000 paid subs** for $10k MRR.
- Required reach: 1,000 / 0.05 ≈ **20,000 trial users** = ~60% of addressable. Aggressive.
- At Option B ($5/mo), need 2,000 paid — would require ~40K trials = larger than addressable. Tight.
- **Aggressive (6 months): LOW** — price ceiling caps revenue growth speed.
- **Relaxed (12-18 months): MEDIUM** — viable but slower than powerlifting/RP because price is lower.
- **Path B alternative**: $20 one-time × 5,000 buyers = $100K *one-time*, but no MRR. Useful for runway, not for the $10k MRR target.

This niche is large, but the price-sensitivity and ad-supported / free-YouTube-dominant culture work against the $10k MRR specifically. Better as a Path B side wedge than a primary niche.
