# Niche: r/weightroom — serious lifters, autoregulation culture

## Community surface area

- **r/weightroom**: 394,471 subscribers as of 2026-05 (live JSON, [reddit.com/r/weightroom/about.json](https://www.reddit.com/r/weightroom/about.json)). The 309K figure in the brief was stale — this niche has grown ~28% since.
- Adjacent surfaces: r/powerlifting (588K), r/strength_training [LOW CONFIDENCE ~80K], r/Stronglifts5x5 (117K), r/GYM (1.16M but much broader), r/weightlifting (328K, Olympic-skewed).
- **Discord**: SBS Barbell / Stronger By Science Discord (~10K members [LOW CONFIDENCE]); the WR-overlap "Power and Bulk" subreddit's Discord [LOW CONFIDENCE 2-3K].
- In-person: meet circuit (USAPL/USPA/SPF). Members regularly cross-post meet reports — the canonical [Meet Report Guidelines thread](https://www.reddit.com/r/weightroom/comments/1dbnfr/meet_report_guidelines/) is pinned in the sidebar.
- Where they actually hang out: daily threads. The Monday Mantra, Tuesday Trivialities, etc. are pinned ~daily threads where the regulars congregate. The [Routine Critique / Program Results](https://www.reddit.com/r/weightroom/comments/u37va/routine_critiques_program_results_posts/) thread is the canonical place to discuss programming.
- Activity level: ~10-20 top-level posts/day [LOW CONFIDENCE], 50-200 comments on a hot meet report or program review; daily threads carry 200-500 comments [LOW CONFIDENCE]. Mods aggressively delete low-effort posts (see sidebar: "No 'I just did x!' threads, no NSVs, no form checks outside the weekly thread").

## Existing app competition

- **Boostcamp / Boostcamp Pro**: free / $9.99/mo / $59.99/yr [LOW CONFIDENCE current price]. Owns "I just want to follow Greg Nuckols / Calgary Barbell / GZCL / 5/3/1" use case. Heavy r/weightroom presence.
- **Hevy**: free / $5.99/mo / $39.99/yr. Strong social-logger angle; popular with the "post my log" crowd.
- **Strong**: $4.99/mo / $29.99/yr [LOW CONFIDENCE]. The default minimalist logger. Owns the "I don't need anything fancy" segment.
- **Juggernaut AI**: ~$35/mo. AI-programmed; specifically targets the autoregulation crowd. The closest direct competitor to a "Phase Training-with-Coach" pitch for this niche.
- **TrainHeroic**: ~$15-25/mo (athlete tier). Coach-distribution platform; the white-label backend for many WR-respected programmers.
- **Spreadsheets**: still genuinely dominant. The [Power and Bulk Spreadsheet](https://docs.google.com/spreadsheets/) family and Calgary Barbell Excel templates are passed around constantly.

App Store / Reddit complaints surfaced across multiple threads:
- Boostcamp: "Can't customize a templated program without rebuilding it from scratch" — [r/weightroom thread on Boostcamp gripes, search "boostcamp customize"](https://www.reddit.com/r/weightroom/search/?q=boostcamp).
- Hevy: "Great logger, useless for actual periodization."
- Juggernaut AI: "Cookie-cutter when you push back on its decisions"; "Too expensive for what it does."
- Strong: "No deload logic, no autoregulation; basically a notepad with charts."

**The specific feature gap Phase Training could attack**: a logger that (a) ships pre-built canonical templates the WR crowd respects (5/3/1 variants, GZCL, Calgary Barbell, Sheiko-light), (b) supports RPE/RIR honestly, (c) lets the Coach explain *why* it picked Thursday's weight from your last logged top set — without forcing you onto a $35/mo "AI" black box. The Coach answering "why squats Thursday?" with a real reference to your last RPE 8 single (PLAN-coach.md Phase 13b acceptance test) is exactly what Boostcamp / Strong cannot do.

## Willingness-to-pay signals

- This audience already pays. Greg Nuckols' MASS research review = $35/mo. Calgary Barbell program PDFs = $40-60 one-time. Juggernaut AI = $35/mo. Online coaching from a named WR regular: $150-300/mo [LOW CONFIDENCE].
- Stronger By Science Patreon: $5-25/mo tiers [LOW CONFIDENCE]; thousands of supporters across creators.
- **Best-fit pricing: Option C ($19.99/mo + $99/yr "AI Coach replaces your $200/mo human coach")**. They already buy at this tier. The framing "$20 AI vs $200 human" lands, but with a caveat — this audience *also* respects expertise. The Coach has to demonstrably know GZCL block-structure jargon, RPE-vs-percentage tradeoffs, deload protocols, and not generate broscience.
- Option D ($99 lifetime) would *also* convert well in this niche — they're the spreadsheet-buying segment — but burns the MRR ceiling.

## Distribution — map to the 4 channels

- **Subreddit infiltration**: **High**. WR has tight rules (see sidebar — no self-promo, no low-effort posts, minimum karma) but they reward genuine contributions. A founder posting useful programming analysis, meet reports, or a "I wrote a tool to compare my last 6 squat blocks" deep-dive can earn the right to mention the app once. **Best of the four.**
- **YouTube creator integration**: **Medium**. The WR crowd watches Alan Thrall, Bromley, Calgary Barbell (Bryce Krawczyk), Greg Nuckols (rare videos), Garage Gym Reviews. None of them really do sponsored fitness app reads — Bromley and Calgary Barbell take sponsorships but are picky. Estimated ask: $1-3K for a Bromley dedicated read [LOW CONFIDENCE]; free Pro + a script unlikely to land with the bigger names but plausible with a smaller WR regular (e.g., Brian Alsruhe, ~177K subs, more open).
- **Newsletter wedge**: **Medium**. Stronger By Science newsletter and MASS are the entrenched players; competing head-on is suicide. A *very* narrow wedge ("Weekly RPE-to-percentage drift report" or "Block periodization templates explained") could carve a slot.
- **TikTok daily clips**: **Low**. Wrong demographic — WR skews 25-40M male, not TikTok-native. They live on Reddit and YouTube.

**THE best channel: subreddit infiltration on r/weightroom**, with a 60-day "earn the right to mention" plan. Post: (1) "I logged 18 weeks of RPE and the AI coach in Phase Training caught this drift" — share screenshots, not pitch; (2) meet report mentioning the app organically in the program section; (3) actual programming analysis using the app's data export.

**Cheapest "first 10 users"**: Post the [Program Reviews thread](https://www.reddit.com/r/weightroom/comments/u37va/routine_critiques_program_results_posts/) every Saturday for 4 weeks with a thorough writeup that uses Phase Training screenshots organically. Expect 10-30 TestFlight installs from a single well-received post.

## Product fit + Path A vs Path B

This niche **wants Path A — Coach-first**. They want the autoregulation conversation: "I hit RPE 9 on my top single, do I deload?" "Move Thursday's squats to Friday because of meet prep?" Phase 13b/13c acceptance tests ("why did you put squats Thursday?", "move Thursday's lift to Friday") are exactly the WR daily-thread conversation.

**Non-negotiables for this niche**:
1. RPE / RIR fields on every set (the prompt's existing Log schema must support — confirm in code).
2. Top-set + back-off-set programming primitives (GZCL T1/T2/T3).
3. Honest 1RM/e1RM tracking that uses Epley or Brzycki and exposes which.
4. Block / mesocycle awareness (the Coach should know we're in a "volume block" vs "intensity peak").
5. Data export (CSV/JSON) — this crowd will leave any app that traps their logs.

**What Phase Training has**: 167 bundled routines via coach.db (PLAN-routines.md) — likely includes 5/3/1 / GZCL / generic block templates; AI Coach with 4 typed tools including `propose_workout_changes` and `read_recent_feedback` (PLAN-coach.md Phase 13c-d); per-day persistent conversations; cost caps at 50/100 turns/day.

**Build work**: (a) audit the 167 routines for WR-canonical programs and label them with the original creator/source; (b) make sure RPE @ X notation renders correctly in Log; (c) ship a CSV export; (d) make the Coach demonstrate it can talk GZCL/RPE without faking it (prompt engineering + a "show your math" instruction).

## Unit-economics check

WR users are **power-user-heavy**. They log every set, every RPE, want analysis after every workout, ask the Coach multiple weekly questions. Estimate: 30-60 Coach turns/month per active user [LOW CONFIDENCE].

Cost math (Sonnet 4.5/4.6 pricing as of 2026-05): input $3/M tokens, output $15/M; with 90% cache hit on a ~2K system prompt and ~500 token responses:
- Per turn cached: 2K input @ $0.30/M cache read = $0.0006; 500 output @ $15/M = $0.0075; 500 token user msg @ $3/M = $0.0015. Total ≈ **$0.009/turn**.
- 60 turns/month = **$0.54/user/month**.

At $20/mo - 30% Apple = $14 net - $0.54 Coach = **$13.46 / $14 = 96% gross margin**. Niche is **viable at $20/mo**, comfortably so. The 50/day soft cap (PLAN-coach.md) protects against runaway. The math holds even if turns/month double to 120 ($1.08 cost, still 92% margin).

Watch: if Coach context grows (longer chat history, more memory blocks) or model upgrades to Opus, cost can 5-10x quickly. Path A on this niche depends on aggressive context discipline.

## Founder/content fit

Wilbur has no public fitness audience, but this niche **respects engineers who lift**. The Stronger By Science crew, Greg Nuckols, Eric Helms — all are credentialed-but-also-spreadsheet people. A solo iOS dev who lifts seriously and posts thoughtful analyses can carve a credible voice in 6-12 months. The barrier is *posting frequency + program-completion proof* — meet reports, finished blocks, before/after lift numbers. If Wilbur doesn't compete and doesn't have a substantial training log, he needs a credible WR-regular cofounder/advisor named in the launch.

If a creator-cofounder were needed: someone like Brian Alsruhe (~177K subs, Conjugate / strongman) or a mid-tier coach with WR regular flair. Not a top name — they're too expensive — but a respected mid-name.

## Path B alternative — programming planner, no Coach

- **Pricing fit**: $20 one-time would convert well — r/weightroom is the spreadsheet-buying segment, used to paying $40-60 for Calgary Barbell PDFs. $40/yr also viable but one-time matches the program-PDF mental model better. **Yes, this audience pays for one-time programming tools.**
- **Feature set (Coach stripped)**: 167 routines with rendering fidelity for 5/3/1 / GZCL / Calgary Barbell / Sheiko-light + RPE per set + e1RM tracking + auto block/mesocycle phase awareness based on logged data + CSV export + program-completion reviews. The "show your math" engine that the Coach was supposed to surface becomes a static "why this weight today" tooltip per workout instead.
- **Distribution under Path B**: Subreddit infiltration remains the best channel — but the pitch shifts. Under Path A: "AI coach explains your programming." Under Path B: "the spreadsheet that's not a spreadsheet — own it forever for $20." Path B pitches MUCH better on Reddit specifically because no subscription = no scam-suspicion friction. YouTube creator integration is *worse* under Path B (subscription is easier to script around).
- **Funnel math at $20 one-time**: $120k ARR equivalent = 6,000 sales/year = 500 sales/month. At 8% trial→purchase conversion, requires 6,250 trial users/month — roughly 75K trial users/year. Versus addressable active fraction ~20-30K from r/weightroom alone, this is **unachievable from r/weightroom alone**. $40/yr: 3,000 active subs = ~30% of addressable, much more credible.
- **Ramp speed vs Path A**: **Path B reaches first $1k MRR faster** — one strong r/weightroom post + word-of-mouth could do $1k in the first 30 days at $20 one-time (50 sales). Path A's first $1k requires 50-70 subscribers retained for a month — slower because trial→retained-paid friction is higher.
- **Verdict for THIS niche**: **Path B wins** for r/weightroom specifically. The audience matches one-time-purchase culture, the build is smaller (no Coach API), and the subreddit pitch is cleaner. Path A's higher ceiling matters less when timeline is "someday." **Recommendation: $40/yr (recurring) + $99 lifetime upgrade option, no Coach in v1.**

## Risks & landmines

- **Mod rules are strict.** Self-promo without earned reputation = ban. Plan for 60 days of pure-give before any mention.
- **Broscience detection is brutal.** Coach must never recommend "muscle confusion" or "anabolic windows" without nuance. One screenshot of bad Coach output gets dunked on for a week.
- **Boostcamp is entrenched.** They have the WR-canonical template library + 4 years of forum goodwill. Beating them requires a feature they cannot ship (the Coach) or a price they won't match.
- **Spreadsheet stickiness.** A nontrivial fraction of this niche will *never* switch from their custom spreadsheet. Reachable market is smaller than the 394K subscriber count implies.

## Funnel napkin math — solving for $10k MRR

- Subscribers: 394,471. Active fraction (posts/comments in last 30 days): ~5-8% = ~20-30K active [LOW CONFIDENCE].
- Realistic addressable subset (intermediate+, RPE-using, not glued to spreadsheets): ~50% of active = **10-15K**.
- Trial→paid conversion for a niche-fit power-user audience: **8-12%** [LOW CONFIDENCE — higher than the 5% default because this niche pays for tools].
- At Option C ($19.99/mo), need **500 paid subs** for $10k MRR.
- Required *reach*: 500 / 0.10 = **5,000 trial users** = ~33% of addressable active fraction. That's aggressive but not impossible over 12 months with sustained subreddit presence + one creator integration.
- **Aggressive timeline (6 months) compatibility: LOW.** 500 paid in 6 months from a cold start with no audience is heroic.
- **Relaxed timeline (12-18 months) compatibility: MEDIUM-HIGH.** Achievable if subreddit infiltration + one Bromley/Alsruhe-tier integration both land.
