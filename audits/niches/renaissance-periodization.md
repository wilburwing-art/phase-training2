# Niche: Renaissance Periodization / Dr. Mike Israetel

## Community surface area

- **RP YouTube**: 3.86M subscribers as of 2026-05 (verified live, [youtube.com/@RenaissancePeriodization/about](https://www.youtube.com/@RenaissancePeriodization/about)). Brief said 3.8M; current is 3.86M.
- **RP Instagram**: ~1.5M+ followers [LOW CONFIDENCE].
- **RP TikTok**: ~1M+ [LOW CONFIDENCE].
- **Mike Israetel Instagram personally**: ~1.5M+ [LOW CONFIDENCE].
- **RP Hypertrophy app**: paying subscribers, polarized App Store reviews. Self-reports on r/naturalbodybuilding suggest tens of thousands of paying users [LOW CONFIDENCE].
- **RP Diet Coach app**: separate app, also paying subscribers.
- **RP Strength**: branded strength app.
- Subreddit overlap: r/naturalbodybuilding (447K), r/Renaissance_Periodization (smaller, [LOW CONFIDENCE 10-30K]), r/Bodybuilding, r/StrongerByScience.
- **Discord**: RP Discord [LOW CONFIDENCE 5-15K].
- **Patreon**: Dr. Mike runs a Patreon with multiple tiers [LOW CONFIDENCE thousands of patrons].
- Activity: RP posts 1-3 videos/day across the channel(s); Mike does AMAs / Q&A streams regularly. Comment-heavy, ~1-5K per video.

## Existing app competition

- **RP Hypertrophy app itself**: ~$24.99/mo. The niche's namesake product. **This is the entrenched competitor you'd be displacing.**
- **RP Diet Coach**: ~$19.99/mo [LOW CONFIDENCE]. Nutrition app, complementary not competitor.
- **Boostcamp**: free / $9.99/mo / $59.99/yr [LOW CONFIDENCE]. Carries some MEV/MRV-style hypertrophy templates.
- **Hevy / Strong**: standard loggers.
- **Caliber / Future**: $200-400/mo human coach.

Top complaints about RP Hypertrophy app (recurring on r/nbb, App Store):
- "Beautiful but rigid — once I deviate from the prescribed exercise, the algorithm punishes me."
- "Asks me 'how was the pump?' / 'how was the soreness?' surveys that feel performative."
- "The app crashes / has bugs / doesn't sync across devices."
- "It tells me to do exercises I can't (no machines available, traveling) and the substitution flow is bad."
- "Subscription price keeps creeping up [LOW CONFIDENCE on rate-hike claims]."
- "Auto-progression is too aggressive — pushes me into MRV territory and I get hurt."

**Feature gap Phase Training could attack**: Same as r/naturalbodybuilding — a flexible MEV/MRV-aware hypertrophy app whose Coach **explains its reasoning** instead of mechanically pushing volume. Where RP's app says "add a set," Phase Training's Coach can say "you're at MEV +1 set on chest, last week your bench RIR climbed from 2 to 4 — let's hold volume and improve technique on the press." This is the *actual* RP methodology being explained, which the RP app itself doesn't do because it's optimized for autopilot.

## Willingness-to-pay signals

- RP app subscribers pay $24.99/mo. This is the strongest signal in any of the 10 niches: the EXACT audience already pays a $25/mo price for an app *with the exact problem Phase Training would solve*.
- Mike Israetel's Patreon: $5-25 tiers.
- RP Strength Programs: $50-150 one-time PDFs.
- Coaching from RP-affiliated coaches: $200-400/mo [LOW CONFIDENCE].
- **Best-fit pricing: Option C ($19.99/mo + $99/yr)**. Directly undercuts RP Hypertrophy app at $24.99/mo. The framing: "$19.99 RP-methodology app that explains itself, vs $24.99 RP app that doesn't." If positioned as cheaper-AND-flexible-AND-Coach-explains, conversion math is favorable. The "$20 AI vs $200 human coach" framing also lands.

## Distribution — map to the 4 channels

- **Subreddit infiltration**: **High**. r/naturalbodybuilding allows mentions in routine-review threads if value is real. Sharing "I built a flexible alternative to RP app — here's MEV/MRV tracking with exercise swap support" earns engagement IF written respectfully toward RP.
- **YouTube creator integration**: **High**. Direct RP is impossible (Mike won't promote a competitor). Adjacent science-based creators are the lane:
  - **Eric Helms / 3DMJ**: ~150K [LOW CONFIDENCE]. Open to integrations.
  - **Eugene Teo**: ~1M [LOW CONFIDENCE]. Coaching-focused; takes deals.
  - **Geoffrey Verity Schofield**: ~250K [LOW CONFIDENCE]. Natural pro coach.
  - **Sean Nalewanyj**: ~600K [LOW CONFIDENCE]. Science-based.
  - **Jared Feather, Coach K, Jay Vincent**: mid-tier, more accessible.
  - **Jeff Nippard**: 8.4M but partnered with Boostcamp — won't take.
  - **Greg Doucette**: ~2M. Frequently shits on RP / Mike publicly. Awkward fit, but if positioned as "anti-RP rigidity" could work — risky.
  - Realistic: 200-500K-sub mid-tier creator, $1-3K + free Pro for integrated mention.
- **Newsletter wedge**: **Medium-High**. MASS dominates research summaries; a "Weekly Hypertrophy Volume Decisions" newsletter focused on *applied* programming decisions has open lane.
- **TikTok daily clips**: **High**. RP has its own TikTok dominance, but adjacent voices can carve attention. Mike's own clips are screenshot-worthy ("Mike Mentzer-style aggression but with data") and have set the tone — a similar founder voice could compound.

**THE best channel: ONE YouTube creator integration with a 200-500K-sub science-based hypertrophy coach** (Eugene Teo, Schofield, Nalewanyj). The audience overlap with RP buyers is high; integration cost is reasonable.

**Cheapest "first 10 users"**: post a thoughtful "What I'd change about the RP app" thread on r/naturalbodybuilding — *constructive*, not destructive, with screenshots of Phase Training as the proof-of-concept solution. Mike Israetel might even comment (publicity).

## Product fit + Path A vs Path B

**Path A — Coach-first.** This niche's wedge IS the Coach explaining MEV/MRV decisions. Without the Coach, you're just another logger competing with RP's polished app — and you lose.

**Non-negotiables**:
1. MEV / MAV / MRV per muscle group with rolling estimates.
2. **Exercise swap that preserves volume math** (RP's app failure mode).
3. RIR per set; visualization of RIR drift across blocks.
4. Mesocycle structure: accumulation → intensification → deload → maintenance.
5. Apple Health for bodyweight + body comp.
6. **Coach explains its progression decision** every time it recommends a change.

**What Phase Training has**: 167 routines (PLAN-routines.md — audit for hypertrophy templates); 4 Coach tools (PLAN-coach.md). The `propose_workout_changes` tool with rationale is precisely what RP users want. Memory store can hold per-muscle-group volume preferences.

**Build work**:
1. MEV/MAV/MRV math + UI surface (most important — multi-week build).
2. Exercise swap engine that preserves volume contribution per muscle group.
3. RIR per set (probably exists from Phase 6 — verify).
4. Mesocycle phase awareness in the Coach system prompt.
5. Audit coach.db for hypertrophy templates labeled by volume landmarks.
6. Apple Health integration.

This shares 80% of the build work with the naturalbodybuilding niche and Jeff-Nippard niche. They are essentially **the same product build with three distribution lanes**.

## Unit-economics check

RP-style users are **high power users on the Coach**. They want explanations, comparisons, justifications. Estimate 50-80 turns/month [LOW CONFIDENCE — higher than nbb general because of explain-the-reasoning expectation].

Cost math:
- Per turn ≈ $0.009.
- 80 turns/month = **$0.72/user/month**.

At $19.99/mo - 30% Apple = $14 net - $0.72 = **$13.28 / $14 = 95% gross margin**. **Viable.**

Watch: longer explanations push output tokens up. A 1500-token Coach answer × 80/month = $0.18 input + $1.80 output = ~$2/month cost. Still 86% margin but worth monitoring.

## Founder/content fit

Wilbur as a solo dev *can* credibly own this niche by leaning into the engineer-who-implements-the-science framing. RP audiences respect Mike because he's a PhD; they'd respect an engineer who built a tool that actually *implements* the methodology correctly. The cofounder boost would be: a coach with RP-style credentials (some flavor of kinesiology / nutrition science background, ideally with their own modest YouTube/IG following).

The hardest part: don't accidentally piss off Mike Israetel publicly. He's the audience gatekeeper. Position as complementary ("for people who love RP methodology but want flexibility") rather than competitor.

## Path B alternative — programming planner, no Coach

- **Pricing fit**: This is the niche with the **strongest existing WTP signal** of any in the audit — the RP Hypertrophy app charges $24.99/mo and converts well. $40/yr ($3.30/mo) is a screaming-deal undercut. $20 one-time also works as "RP-app refugee one-time purchase." **Best Path B price: $40/yr** — captures the subscription-tolerant majority while signaling "we're cheaper AND we explain ourselves."
- **Feature set (Coach stripped)**: MEV/MAV/MRV per muscle group with rolling estimates AND visualization (the polish RP app gets right); **exercise swap that preserves volume math** (THE RP-app failure mode — fix this and you have a wedge); RIR per set; mesocycle phase tracker; Apple Health for body comp; bundled hypertrophy templates labeled by volume landmarks. The Coach's "explain why we're holding volume" becomes static rule-explanation tooltips with citation-style links to Schoenfeld / Helms research summaries (curated, not generated).
- **Distribution under Path B**: Subreddit infiltration on r/naturalbodybuilding becomes safer — "I built a $40/yr alternative to the RP app" reads less hostile than "$20/mo subscription competitor." YouTube creator integration becomes easier (lower ongoing-revenue-scrutiny). Still avoid attacking Mike directly under either path.
- **Funnel math at $40/yr**: 3,000 subs = $120k ARR. At 12-15% conversion (highest of any niche — RP audience is *primed* to convert), required reach = 20-25K trials. RP-aware addressable: 30-50K. **Cleanly within range.** At $20 one-time: 6,000 sales/yr = 40-50K reach at 12% = also viable.
- **Ramp speed vs Path A**: **Path B wins decisively** — RP-app refugees are *actively shopping* and the lower price + one-time-feeling annual purchase is a clean conversion lift over yet-another-subscription. Path A's first $1k MRR requires retained subs (months); Path B's $1k MRR equivalent can land in week one of a single thoughtful r/nbb post.
- **Verdict for THIS niche**: **Path B wins on every dimension except long-term ceiling.** Given the "someday" timeline, ceiling matters less than ramp + risk. Ship Path B. The Coach is the *upsell* once a paying user base exists: "you bought the planner — add the Coach for $10/mo for personalized explanations of your block decisions."

## Risks & landmines

- **Mike Israetel's reach.** If he frames Phase Training as a competitor on his channel, the niche is closed. He's vocal and quick to defend his app. Mitigation: thoughtful positioning, never directly attack RP.
- **MEV/MRV IS RP's terminology / IP.** Use the concepts (they're scientific common-language now), but use language carefully — "volume landmarks" is safer than direct verbatim copying.
- **Crowded space.** Eric Helms, Greg Nuckols, 3DMJ, Jeff Nippard, Doucette — many science-based voices. Phase Training must be excellent or it's the 7th option.
- **Output length pressure.** "Explain the math" expectations push token costs. Cost discipline matters.
- **Show-prep liability.** Bad mesocycle advice during contest prep affects physiques. Coach must include disclaimers and conservatism.

## Funnel napkin math — solving for $10k MRR

- Combined RP-aware addressable: ~30-50K (subset of r/naturalbodybuilding + RP app churn users + adjacent creator audiences) [LOW CONFIDENCE].
- Trial→paid conversion: **10-15%** [LOW CONFIDENCE — highest of all niches because RP audience has ALREADY proven $25/mo willingness to pay and is actively frustrated with current RP app].
- At Option C ($19.99/mo), need **500 paid subs** for $10k MRR.
- Required reach: 500 / 0.12 ≈ **4,200 trial users** = ~10-15% of addressable. Realistic.
- **Aggressive (6 months): MEDIUM-HIGH** — if the build delivers MEV/MRV + exercise-swap flexibility + Coach explanations, and one creator integration lands.
- **Relaxed (12-18 months): HIGH** — this is arguably the **single highest-conversion niche** of the 10, because the audience is already trained to pay $25/mo for the *same product*.

**Note**: this niche is conceptually a subset of the broader "science-based hypertrophy" niche (= naturalbodybuilding + Jeff-Nippard + RP). The three should be treated as one product build with overlapping distribution. Combined addressable: 50-100K+, with the highest WTP signal of any niche in the audit.
