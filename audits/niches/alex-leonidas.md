# Niche: Alex Leonidas / AlphaDestiny — generalist natural lifters

## Community surface area

- **Alex Leonidas YouTube**: 823K subscribers as of 2026-05 (verified live, [youtube.com/@AlexLeonidas/about](https://www.youtube.com/@AlexLeonidas/about)). Brief said 420K (likely conflating AlphaDestiny secondary channel); the main "Alex Leonidas" channel is ~823K. AlphaDestiny secondary may be ~449K [LOW CONFIDENCE].
- Alex publishes long-form lifting videos + critiques of fitness industry / influencers / programming. His audience is **generalist natural strength + hypertrophy + occasionally powerbuilding**, less science-citation-heavy than Jeff Nippard's, more "what actually works for real natty trainees over 5+ years."
- IG: ~200K [LOW CONFIDENCE]. TikTok: present but smaller [LOW CONFIDENCE].
- Subreddit overlap: r/naturalbodybuilding (447K), r/weightroom (394K), r/leangains, r/Stronglifts5x5 (117K), r/Fitness (12.5M). Members of r/Alphadestiny [LOW CONFIDENCE small].
- Alex's signature programs: **NSuns 5/3/1 LP**, **AlphaDestiny novice/intermediate strength templates**, the **NSuns / Geoff Verity Schofield Lifestyle Bodybuilding** mashups. These are *passed around freely* in his audience as Google Sheets and threadposts.
- Activity: Alex posts ~1-2 videos/week on the main channel; longer pieces. Comment sections 500-3K per video.

## Existing app competition

- Same competitor set as the broader natural bodybuilding / lifting space:
- **Boostcamp**: free / $9.99/mo. Carries NSuns and other Alex-adjacent templates.
- **Hevy**: free / $5.99/mo / $39.99/yr.
- **Strong**: $4.99/mo / $29.99/yr [LOW CONFIDENCE].
- **RP Hypertrophy**: $24.99/mo. Some Alex viewers use it.
- **Spreadsheets**: huge in this audience. NSuns LP is a SPREADSHEET-FIRST program. Many Alex fans run their training out of Google Sheets.
- **No Alex-branded app exists** — this is significant. Unlike Jeff (Boostcamp partnership) or RP (own app), Alex hasn't commercialized into an app yet [LOW CONFIDENCE current as of 2026-05].

Top complaints from this audience:
- "I'm running NSuns and the apps don't render the wave correctly."
- "I want to track multiple programs — bulk/cut/maintenance — and apps assume one continuous plan."
- "Influencers like RP are too rigid; influencers like Jeff are too academic; I want practical."

**Feature gap Phase Training could attack**: NSuns-correct implementation + flexible mesocycle tracking + Coach that's *practical* (not academic, not over-engineered). Alex's audience values *common sense* programming. The Coach saying "skip your back-off sets today if RPE 9 on top set, here's why" matches Alex's voice. This audience is also more likely to actually use a Coach as a peer-style assistant rather than a coach-replacement.

## Willingness-to-pay signals

- Alex sells e-books / programs via Gumroad-style — $20-80 one-time [LOW CONFIDENCE].
- Patreon: $5-25 tiers, several thousand patrons [LOW CONFIDENCE].
- His audience is mid-WTP: pays for programs and tools, less likely to pay for $200/mo coaches.
- **Best-fit pricing: Option A ($10/mo Pro) or Option C ($19.99/mo)**. The "$20 vs $200" framing lands less here than for powerlifters because this audience is anti-elitist about coaching. Option B ($5/mo) might convert better volume given the price-conscious culture. Option D ($99 lifetime) would crush in this niche — Alex's audience loves one-time-fee programs.

## Distribution — map to the 4 channels

- **Subreddit infiltration**: **Medium**. No Alex-specific large sub; r/naturalbodybuilding + r/weightroom carry his audience. Use the broader-niche subreddit strategies.
- **YouTube creator integration**: **High — and Alex himself is a realistic candidate.** Alex is mid-tier in YouTube terms (823K), not a $30K-sponsorship name. He has historically taken brand deals for products he uses (supplements, equipment). A pitch like "I built a logger that handles NSuns correctly, free for you + your audience" might actually land. Estimated ask: $1-3K + free Pro [LOW CONFIDENCE — could be free if framed as a peer].
  - **Backup creator picks**:
    - **Sean Nalewanyj**: ~600K [LOW CONFIDENCE]. Similar generalist natty voice.
    - **Mike Thurston**: smaller / different niche.
    - **Jay Vincent**: smaller, mid-tier hypertrophy.
- **Newsletter wedge**: **Low**. This audience doesn't really do newsletters; they prefer YouTube + Reddit.
- **TikTok daily clips**: **Medium**. Possible but smaller payoff than YouTube.

**THE best channel: ONE YouTube creator integration with Alex Leonidas himself**, OR with a peer-tier (300-700K subs) generalist natty creator. The pitch must be peer-to-peer: "I built this, I think it solves NSuns rendering / multi-program tracking, would you try it?" — not transactional sponsorship.

**Cheapest "first 10 users"**: post a "Phase Training renders NSuns LP correctly — screenshots" thread on r/Fitness (huge, but anti-self-promo; needs careful framing) or r/naturalbodybuilding. Alternatively: comment on an Alex video about how NSuns is hard to track and link to a public screenshot of Phase Training rendering NSuns wave correctly.

## Product fit + Path A vs Path B

This niche **leans Path B — programming-first planner** with Path A as a paid upsell. Alex's audience wants the *program* rendered right; the Coach is bonus.

**Non-negotiables**:
1. NSuns 5/3/1 LP rendering (the wave structure: top set → AMRAP → back-offs across the week).
2. 5/3/1 variants: BBB, Building the Monolith, FSL, PR sets.
3. Multi-program-cycle tracking: bulk → cut → maintenance switches with hypertrophy/strength toggle.
4. Honest 1RM tracking with options: actual 1RM tested vs training max vs estimated 1RM.
5. RIR / RPE as auxiliary, not mandatory.
6. CSV export (this audience moves between apps and spreadsheets).

**What Phase Training has**: 167 routines (PLAN-routines.md) — high likelihood NSuns and 5/3/1 variants are in coach.db (verify). Routine system + Coach. The Coach can be tuned to Alex's voice via system prompt.

**Build work**:
1. NSuns LP and 5/3/1 variant verification in coach.db — multi-day work to ensure rendering is correct.
2. Multi-phase cycle UI: switch bulk → cut → maintenance with appropriate training max adjustments.
3. AMRAP set tracking with PR set logic.
4. CSV export.
5. If shipping Path B, defer Coach.

## Unit-economics check

This audience is **lower-to-moderate** Coach power user. They want their program rendered, not constant chat. Estimate 15-30 turns/month if Path A [LOW CONFIDENCE].

Cost math:
- Per turn ≈ $0.009.
- 30 turns/month = **$0.27/user/month**.

At $9.99/mo (Option A) - 30% Apple = $7 net - $0.27 = **$6.73 / $7 = 96% margin**.

At $19.99/mo (Option C) - 30% = $14 net - $0.27 = **$13.73 / $14 = 98% margin**.

**Path B = zero API cost** — extremely viable at $20-40 one-time or $40/yr.

## Founder/content fit

Wilbur as a solo dev fits this niche **better than the academic/science niches** because Alex's audience values practical over credentialed. The story "I built this because I run NSuns and no app renders it right" is exactly the voice this niche resonates with. No coach-cofounder strictly necessary, though a partnership with Alex (or a peer) would significantly accelerate.

## Path B alternative — programming planner, no Coach

- **Pricing fit**: Alex's audience is the **most one-time-fee-tolerant** of any niche evaluated — anti-subscription bias is part of the culture. Alex himself sells one-time program PDFs. $20 one-time is *exactly* the price this audience expects. $40/yr would feel like a tax. **Best Path B price: $20 one-time + optional $40/yr "stay updated" tier** — the "stay updated" tier preserves some MRR.
- **Feature set (Coach stripped)**: NSuns 5/3/1 LP rendered correctly (THE differentiator); 5/3/1 BBB / Building the Monolith / FSL / PR sets variants; multi-program-cycle tracking (bulk → cut → maintenance with training-max adjustments); honest 1RM tracking (actual tested vs training max vs estimated); AMRAP set tracking with PR-set logic; CSV export. The Coach's "should I skip back-offs after a hot top set?" becomes a static rule the user toggles per program ("skip back-offs if top set RPE ≥ 9").
- **Distribution under Path B**: Alex himself is more likely to integrate at no/low cost under Path B — endorsing a "tool I use to track my NSuns" reads differently from endorsing "a competing AI coach subscription." The pitch becomes peer-to-peer, not transactional. r/Fitness and r/naturalbodybuilding subreddit posts work better under Path B.
- **Funnel math at $20 one-time**: 6,000 sales/year = $120k ARR equivalent. At 5-8% conversion, required reach = 75-120K trials. Alex's audience: ~30-60K addressable. **Not viable from Alex alone**; requires creator stack (Alex + Nalewanyj + r/Fitness/r/nbb posts). At $40/yr: 3,000 subs at 5% = 60K reach = also tight.
- **Ramp speed vs Path A**: **Path B wins by a wide margin.** Anti-subscription audience converts to $20 one-time *much* faster than to any monthly. Path B's first $1k MRR equivalent = 50 one-time sales = realistic week-one after an Alex integration. Path A's first $1k requires monthly retention through this niche's specifically high anti-subscription resistance.
- **Verdict for THIS niche**: **Path B wins, unambiguously.** This is the *cleanest* Path B fit of any niche. The audience self-identifies as the "anti-subscription, anti-Patreon, anti-Future-app" crowd. $20 one-time is the only pricing that respects the culture. Ceiling is real but with "someday" timeline, the volume from this niche alone is unlikely to hit $10k MRR regardless of path — better as a feeder to broader natty / generalist channels.

## Risks & landmines

- **No Alex-specific large community**: this niche is creator-defined and overlaps heavily with r/nbb and r/weightroom. Distribution is inseparable from the creator integration.
- **NSuns is a *community* program** with strong opinions on implementation. Render it wrong = roasted on r/Fitness.
- **Alex is opinionated and might publicly critique the app** if he doesn't like something. That's free press but only if the app holds up.
- **Price-sensitivity caps revenue ceiling.** $10/mo is a stretch for some of this audience.
- **Spreadsheet stickiness is highest in this niche** of any — many viewers have run NSuns from a Google Sheet for years and won't switch.

## Funnel napkin math — solving for $10k MRR

- Alex's 823K subs + secondary 449K = ~1.2M total impressions per video, but unique addressable subset is smaller.
- Realistic addressable (Alex viewers + adjacent generalist natty audience): **30-60K** [LOW CONFIDENCE].
- Trial→paid conversion: **5-8%** [LOW CONFIDENCE — slightly lower than science-niche conversion because lower WTP].
- At Option A ($9.99/mo), need **1,000 paid subs** for $10k MRR.
- Required reach: 1,000 / 0.07 ≈ **14,300 trial users** = ~30% of addressable. Aggressive.
- At Option C ($19.99/mo), need **500 paid subs**. Required reach: 500 / 0.07 ≈ **7,200** = ~15% of addressable. More comfortable.
- **Aggressive (6 months): LOW-MEDIUM** — requires Alex integration to land hard.
- **Relaxed (12-18 months): MEDIUM** — viable if Alex integration plus sustained generalist-natty community presence.

This niche is **distinctly different from the science-based stack** (RP / Jeff / nbb) — practical over academic, NSuns over MEV/MRV. It's a separate product positioning even if the underlying app could serve both. Trying to serve both audiences simultaneously dilutes the voice. Pick one or run with two distinct tones (risky).
