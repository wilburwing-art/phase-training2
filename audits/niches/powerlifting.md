# Niche: r/powerlifting — RPE-driven meet preppers

## Community surface area

- **r/powerlifting**: 588,072 subscribers as of 2026-05 (live JSON, [reddit.com/r/powerlifting/about.json](https://www.reddit.com/r/powerlifting/about.json)). The 556K figure in the brief was close — niche is still growing.
- Adjacent: r/weightroom (394K), r/PowerliftingBro (smaller [LOW CONFIDENCE ~10K]), r/StartingStrength [LOW CONFIDENCE 50K], r/Stronglifts5x5 (117K).
- Federation forums: USAPL, USPA, IPF national pages on Facebook; OpenPowerlifting.org is *the* canonical results database (multi-million records, no real social layer but enormous reach via shared rankings links).
- Discord: USAPL has an active Discord; many independent meet-prep Discords run by mid-tier coaches [LOW CONFIDENCE on counts].
- In-person: meet circuit — USAPL/USPA/SPF/WRPF. Year-round, weekly meets in most metros. Members travel and crosspost meet reports constantly.
- Hangouts: the [weekly Meet Day thread](https://www.reddit.com/r/powerlifting/) (pinned), the daily "What's your training look like" megathread, and [program recommendation threads](https://www.reddit.com/r/powerlifting/wiki/programs) — the wiki includes a canonical program list (5/3/1, Sheiko, Calgary Barbell, Bulgarian Method, etc).
- Activity: 30-60 top-level posts/day; meet reports easily hit 200-500 comments [LOW CONFIDENCE]. Faster cadence than r/weightroom but slightly more beginner-tolerant.

## Existing app competition

- **Boostcamp / Boostcamp Pro**: free / $9.99/mo / $59.99/yr [LOW CONFIDENCE]. Strong powerlifting template library: 5/3/1, Calgary Barbell 8/16-week, GZCL, nSuns, Sheiko. Their wedge into r/powerlifting is *deep*.
- **Hevy**: free / $5.99/mo / $39.99/yr. Common as a "I just want a clean log" choice.
- **Strong**: $4.99/mo / $29.99/yr [LOW CONFIDENCE]. Older default; losing share to Hevy.
- **RP Strength / Renaissance Periodization Strength**: now exists as a separate strength app [LOW CONFIDENCE ~$24.99/mo], aimed at hypertrophy more than meet prep.
- **Juggernaut AI**: $35/mo. Chad Wesley Smith. Specifically powerlifting/strongman. Closest direct competitor.
- **OpenPowerlifting**: free. Tracking-only. Most lifters keep their meet history here as social proof.
- **Custom coaches**: $150-500/mo, often via spreadsheet + WhatsApp/Telegram.

Top complaints (App Store + Reddit):
- Boostcamp: "Hard to deviate from the template if I want to autoregulate."
- Hevy: "No periodization features at all."
- Juggernaut AI: "It tells me to do volume work the day before a meet — its algorithm doesn't account for my actual fatigue."
- All apps: "I have to pick percentages or RPE — neither system handles both."

**Feature gap Phase Training could attack**: a logger that natively understands BOTH percentage *and* RPE, can convert between them based on actual logged top sets, and where the Coach explains the conversion when it makes a recommendation. PLAN-coach.md's `propose_workout_changes` tool with `adjust_set_target` is ideal — "your top single was RPE 9 on Monday, your Wednesday back-off should be 75% not 80%."

## Willingness-to-pay signals

- Online coaching is the standard: $150-300/mo for a named coach, $300-500/mo for elite-tier [LOW CONFIDENCE].
- Meet entry fees: $75-125/meet, 2-4 meets/year. So $200-500/year in fees alone.
- Singlets, belts, knee sleeves, wraps: $100-400 every couple years.
- Program PDFs (Calgary Barbell, Boris Sheiko, Mike Tuchscherer's RTS): $40-100 one-time, hundreds of buyers each.
- **Best-fit pricing: Option C ($19.99/mo + $99/yr)** — and this is the niche where the "$20 AI vs $200 human coach" framing lands *hardest*. Many in this niche have hired and fired a coach because they couldn't afford it, or because the coach was bad. The AI Coach pitch is a real substitute.
- Option D ($99 lifetime) would also convert well as a one-time meet-prep purchase, but capping MRR.

## Distribution — map to the 4 channels

- **Subreddit infiltration**: **High**. r/powerlifting allows self-promo more than r/weightroom but bans broscience and unsourced claims. A founder posting (1) "AI coach + RPE conversion explainer with screenshots", (2) "I tracked Wilks across my last 6 meets — here's the regression" earns reputation.
- **YouTube creator integration**: **High** — this is potentially THE niche where it works best. Candidates:
  - **Calgary Barbell / Bryce Krawczyk**: ~225K subs [LOW CONFIDENCE], does sponsorships, makes programming videos. Direct fit.
  - **Brian Alsruhe**: ~177K subs [LOW CONFIDENCE], strongman-leaning powerlifter, takes deals, very open to indie creators.
  - **Alan Thrall (Untamed Strength)**: ~500K subs [LOW CONFIDENCE], more general but powerlifting-heavy.
  - **Mark Bell**: 700K+ subs, expensive, not a fit for an indie indie pitch.
  - **Smaller picks**: Coach Christian Anto, Bromley (Alex Bromley) ~150K [LOW CONFIDENCE], Greg Doucette (controversial, broscience-ish, skip).
  - Estimated rate: Calgary Barbell dedicated read = $2-5K [LOW CONFIDENCE]; Brian Alsruhe might do free Pro + script if pitched as a peer.
- **Newsletter wedge**: **Medium**. Stronger By Science newsletter / MASS dominate the space. Narrow wedge: "Weekly Sheiko / Calgary Barbell program-of-the-week breakdown" or "Meet-prep peaking math, illustrated."
- **TikTok daily clips**: **Low-Medium**. Meet PR clips do well on TikTok, but the *programming* conversation lives on Reddit/YouTube. Possible to grow but not the primary lane.

**THE best channel: ONE YouTube creator integration**, specifically Brian Alsruhe or Calgary Barbell-tier. Reasoning: this niche watches programming-focused YouTube *more* than they read subreddits when making product decisions. A 60-second integration in a Calgary Barbell programming video can drive 5-10K visits.

**Cheapest "first 10 users"**: post a meet report on r/powerlifting that organically references your tracking method (with a Phase Training screenshot) — meet reports get protected from the no-self-promo rule when the app mention is incidental and the report is substantive.

## Product fit + Path A vs Path B

**Path A — Coach-first** is the right call for this niche, *if* the Coach demonstrably understands meet prep. Powerlifters want a coach replacement, not a journal. PLAN-coach.md Phase 13c (`propose_plan_edits`) and 13d (workout-edit tools) cover the core asks: "move Thursday to Friday because my SHW openers are Saturday," "swap front squats for paused squats this block."

**Non-negotiables**:
1. RPE @ X notation natively (e.g. "200kg x 1 @ RPE 9").
2. Percentage *and* RPE concurrent — auto-convert based on actual logged top sets.
3. Meet-day countdown / peaking-block awareness.
4. Wilks/IPF GL score auto-calc from bodyweight + lifts.
5. Top-set + back-off-set programming primitives.
6. Logged 1RM history with attempts (success/fail/red lights).

**What Phase Training has** (PLAN-coach.md + PLAN-routines.md): the 4 typed Coach tools cover swap/adjust; 167 bundled routines — high likelihood several are powerlifting programs (verify in coach.db schema); per-day conversations; cost caps.

**Build work**:
1. Audit coach.db for canonical powerlifting templates (Calgary Barbell 8-week, 5/3/1 BBB, GZCL, nSuns 5/3/1 LP). Label with the original source.
2. Implement RPE↔percentage conversion math in the Coach's tool surface.
3. Wilks/IPF GL calculator (one-day build, deferred from Phase 6).
4. Meet-day peaking instructions in the system prompt — Coach should know to taper.
5. CSV/OpenPowerlifting-compatible export.

## Unit-economics check

Powerlifters are **moderate-to-high power users**. They log every set with RPE; they ask the Coach during peaking blocks especially. Estimate 40-80 Coach turns/month per active user [LOW CONFIDENCE — higher than WR average because peaking decisions are higher-stakes].

Cost math (Sonnet 4.5/4.6, 90% prompt cache, ~2K system + 500 output + 500 input per turn):
- Per turn ≈ $0.009 (same model as the WR analysis).
- 80 turns/month = **$0.72/user/month**.

At $20/mo - 30% Apple = $14 net - $0.72 Coach = **$13.28 / $14 = 95% gross margin**. **Viable at $20/mo with margin to spare.**

Watch: meet-prep weeks are spike weeks — a user 2 weeks out from a meet might do 8-10 Coach turns/day, then 0 for 6 months. The 50/day soft cap accommodates this; monthly average stays manageable.

## Founder/content fit

This niche is **the** niche where credibility = lift numbers. Wilbur needs either: (a) a respectable raw total publicly shared (e.g., 1300+ lb total at 200lb bw), or (b) a powerlifter cofounder/advisor as the public face. Posting "I built an AI coach app" without a single meet report or video PR attempt is going to get downvoted on day one. The same engineer-who-lifts framing that works on r/weightroom works here, but the bar for "actually lifts" is meet-attestable.

If Wilbur doesn't compete or train at a credible level, a creator-cofounder profile would be: a regional-level USAPL/USPA lifter, ~25-35 years old, already posts breakdowns on Reddit/YouTube, willing to be the face. Equity + revenue share.

## Risks & landmines

- **Strict broscience policing.** Sources must be cited (Helms, Nuckols, Israetel, Tuchscherer). Coach claims must be defensible.
- **Boostcamp is the entrenched competitor.** Their template library and zero-cost tier are dominant. Phase Training's wedge has to be the Coach, not the templates.
- **OpenPowerlifting is the de facto record-keeper.** If Phase Training doesn't export to OpenPowerlifting-compatible CSV, lifters won't use it as their primary log.
- **Sheiko-style programs are 13-week spreadsheets** that few apps render correctly. If you ship a Sheiko template that "doesn't work like the PDF," reviewers will rip it apart.
- **Peaking-block decision liability.** A bad Coach taper recommendation could cost someone a meet. This is a real reputational risk that broader audiences don't carry.

## Funnel napkin math — solving for $10k MRR

- Subscribers: 588,072. Active fraction (last-30-day posters/commenters): ~6-8% = ~35-47K [LOW CONFIDENCE].
- Realistic addressable subset (competing/meet-prepping, on phone-based logging): ~40% of active = **14-19K**.
- Trial→paid conversion: **10-15%** [LOW CONFIDENCE — higher than default because this niche pays for coaching, sees the $20 vs $200 framing immediately].
- At Option C ($19.99/mo), need **500 paid subs** for $10k MRR.
- Required reach: 500 / 0.12 ≈ **4,200 trial users** = ~25% of addressable.
- **Aggressive timeline (6 months) compatibility: MEDIUM.** Achievable if one Calgary Barbell-tier creator integration lands well + sustained subreddit presence.
- **Relaxed (12-18 months): HIGH.** This is one of the most realistic $10k MRR paths, *if* the Coach can actually deliver on meet-prep depth.
