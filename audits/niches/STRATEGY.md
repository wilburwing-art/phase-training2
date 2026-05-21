# Phase Training — User-Acquisition Strategy Synthesis

**Target**: $0 → $10k MRR.
**Timeline (per Step-0 answers)**: "Someday / no fixed date." Removes urgency that would have forced Path A; both paths are alive; compounding wins matter more than aggressive ramp.

---

## Step-0 inputs Wilbur supplied

| Input | Answer | Implication |
|---|---|---|
| TestFlight installs | 0-5, inner circle only | No cold-tester signal; "building in public from session #1" is mandatory, not optional. Niches that reward thoughtful early-build storytelling beat niches that require existing voice. |
| Cofounder | Full-time, product-side | Build velocity is high; **but no marketing-side leverage**. Distribution still falls on Wilbur unless solved by partnership / creator. Any niche that requires a specific creator-cofounder profile (e.g. xxfitness needs a credentialed woman coach) must either get one or get dropped. |
| Existing audience | None on any platform | Every distribution channel starts at zero. Compounding channels (newsletter, Reddit reputation, TikTok consistency) beat one-shot channels (single creator integration as the only play). |
| $10k MRR target date | Someday / no fixed | Path B's slower ramp and lower ceiling are NOT disqualifying. Risk-minimization (avoid Coach unit-economics blowup, avoid niche-cofounder dependencies) beats ceiling-maximization. |

---

## Brief-size corrections found during research

The original brief had several stale or wrong sub/follower counts. Live-fetched correct values as of 2026-05:

| Surface | Brief said | Actual (live JSON / page) | Delta |
|---|---|---|---|
| r/weightroom | 309K | **394,471** | +28% (grew) |
| r/Hyrox | 140K | **43,293** | **−69% (brief was wrong)** |
| r/bodyweightfitness | 2M | **4,749,052** | +137% (way larger) |
| r/hybridathlete | 24K | **43,826** | +82% (grew) |
| Alex Leonidas YouTube | 420K | **823K** (main channel) | +96% (brief conflated main + AlphaDestiny secondary) |
| Jeff Nippard YouTube | 8.3M | **8.4M** | +1% (close) |
| Renaissance Periodization YouTube | 3.8M | **3.86M** | +1.5% (close) |

The **r/Hyrox correction is the most consequential** — the brief's 140K figure suggested HYROX-prep was 3x larger than it actually is. The funnel math for hybrid-hyrox still works (combined with r/hybridathlete + r/tacticalbarbell + r/triathlon + creator audiences), but the dedicated-HYROX-only play is smaller than implied.

---

## Ranking table — all 10 niches

**Weights** (sum to 1.00):

- **Fit-to-current-product** (15%) — does Phase Training's existing substrate match what this niche wants without months of rebuild?
- **Addressable size at chosen price** (10%) — enough volume to clear $10k MRR or equivalent?
- **Willingness-to-pay** (15%) — does the niche already pay app-comparable prices?
- **Distribution accessibility** (15%) — can Wilbur reach this niche with zero existing audience?
- **Founder/content fit given solo-male-engineer + product-cofounder** (15%) — can the existing team credibly own the voice, or does it require a hire?
- **Unit-economics margin** (10%) — does Coach cost or other unit economics threaten the model?
- **Cultural fit** (5%) — will the niche tolerate / welcome a no-audience indie launch?
- **Competitive whitespace** (10%) — is there a genuine gap vs incumbents, or is this an entrenched-winner-takes-all space?
- **Timeline-to-$10k-MRR compatibility (relaxed/"someday")** (5%) — given no fixed date, this weight is small but tiebreaker.

Scores below are 1-5 (5 = best). Weighted total out of 5.

| Niche | Fit | Size | WTP | Dist | Founder | Margin | Culture | Whitespace | Timeline | **Weighted** |
|---|---|---|---|---|---|---|---|---|---|---|
| **hybrid-hyrox** | 4 | 4 | 5 | 5 | 5 | 4 | 5 | 5 | 4 | **4.55** |
| **renaissance-periodization** | 4 | 4 | 5 | 4 | 3 | 3 | 3 | 4 | 4 | **3.85** |
| **powerlifting** | 5 | 4 | 5 | 4 | 3 | 4 | 3 | 3 | 4 | **3.95** |
| **tacticalbarbell** | 5 | 3 | 4 | 4 | 4 | 4 | 5 | 4 | 4 | **4.10** |
| **weightroom** | 4 | 4 | 4 | 3 | 3 | 4 | 3 | 3 | 3 | **3.50** |
| **jeff-nippard** | 3 | 4 | 5 | 3 | 3 | 3 | 3 | 3 | 4 | **3.40** |
| **naturalbodybuilding** | 3 | 4 | 5 | 3 | 2 | 3 | 3 | 3 | 3 | **3.20** |
| **alex-leonidas** | 4 | 3 | 3 | 3 | 4 | 5 | 4 | 3 | 3 | **3.45** |
| **bodyweightfitness** | 3 | 5 | 2 | 3 | 2 | 5 | 4 | 3 | 2 | **3.15** |
| **xxfitness** | 2 | 5 | 4 | 4 | 1 | 4 | 2 | 4 | 3 | **3.20** |

**Top 4 by score**: hybrid-hyrox (4.55) → tacticalbarbell (4.10) → powerlifting (3.95) → renaissance-periodization (3.85).

**The naturalbodybuilding + jeff-nippard + renaissance-periodization niches are essentially the same product build** (MEV/MAV/MRV + RIR + Apple Health + hypertrophy templates) with three distribution lanes. Treating them as separate niches double-counts. Synthesis collapses them into "science-based hypertrophy" with RP as the lead distribution surface (highest WTP signal).

---

## Path A vs Path B — top-level decision

Given Step-0 constraints, Path B wins on every concrete dimension that matters for the "someday" timeline:

| Dimension | Path A (Coach-first, $20/mo) | Path B (Programming planner, $40/yr or $99 lifetime) |
|---|---|---|
| Build complexity | Coach + tool calling + cost controls + observability | Just the planner; ship the substrate that's already 80% done |
| Unit-economics risk | Power users could burn $5-15/mo at current Opus/snapshot-heavy setup | **Zero API cost** |
| Time to ship | 2-8 weeks for Coach-ready version | **1-3 weeks** for planner-ready version (kill Coach drift work, ship existing 167-routine library + RPE/RIR + CSV export) |
| First $1k MRR ramp | 50-70 retained $20/mo subs through Apple churn = 60-90 days minimum | **25 yearly sales = realistic week one of a single good post or creator video** |
| Creator integration ease | Subscription = ongoing scrutiny, harder ask | **One-time/yearly is lower-friction endorsement** |
| Subreddit reception | Subscription apps face suspicion | **One-time/yearly reads as "tool I bought" not "service I rent"** |
| MRR ceiling per user | $14 net | $3.30/mo equivalent at $40/yr — **4x lower** |
| $10k MRR sub count needed | 500 | **3,000 (yearly) or 6,000 (one-time)** |
| Compatibility with "someday" timeline | Higher-risk path that needs to land before runway concerns kick in | **Lower-risk path that compounds** |

**Top-level call: Path B first.** Coach is a future $10/mo Pro upsell once the base is established, not a v1 requirement.

The exception worth noting: **powerlifting** is the one niche where Path A's product-fit is genuinely uniquely powerful (peaking decisions, autoregulation calls, RPE-percentage conversion explanations). Even there, the per-niche verdict was "Path A narrowly wins on ceiling, Path B wins on ramp + risk." Under "someday" timeline, ramp + risk dominates.

---

## Top 3 niches — detailed

### #1: hybrid-hyrox (Path B, $40/yr + $99 lifetime)

**Why it wins**: All four critical dimensions align:

- **Founder fit**: Wilbur is implicitly designed for this niche per repos/CLAUDE.md ("hybrid-athlete support-role framing isn't replicated anywhere — that's the moat"). No physique gatekeeping; engineer-athlete credibility is welcome here.
- **Product fit**: Largest open product gap of any niche. No incumbent integrates lifting + running + HYROX work-cap movements. Phase Training's bundled-routine + Routine adapter substrate accepts TEXT-format reps ("AMRAP", "30s hold") which directly match HYROX work-cap movements.
- **Distribution**: Fergus Crawley is the cleanest reachable lead creator across all 10 niches (~250-400K subs, mid-tier indie-friendly). Beehiiv newsletter ("Weekly Hybrid Programming Notes") has no clear incumbent. r/hybridathlete + r/Hyrox + r/tacticalbarbell are all small enough that one good post moves the needle.
- **WTP**: TrainingPeaks proves $20/mo subscription-pay at scale; $40/yr undercuts by 80% and pitches as "stop paying TrainingPeaks."

**Pricing**: $40/yr base + $99 lifetime option. Lifetime captures the cash-conscious "buy once" buyer; yearly captures the subscription-tolerant.

**Path A vs B**: **Path B**. Build the planner, ship in 2-4 weeks. Coach becomes a $10/mo Pro upsell at month 6-12.

**Primary distribution channel**: ONE YouTube creator integration with Fergus Crawley (free Pro + $1-3K + script), PLUS a Beehiiv newsletter started in parallel ("Weekly Hybrid Programming Notes"). r/hybridathlete + r/Hyrox + r/tacticalbarbell as ambient supporting channels.

**30 / 60 / 90 day execution plan**:

- **Days 1-30**: Ship the Apple Health integration (workouts, HRV, body comp, sleep). Build concurrent training calendar (lift + run as siblings). Audit coach.db; add HYROX-specific movements (sled push, BBJ, ski erg, sandbag carry). Bundle Alex Viada / Fergus-Crawley-style hybrid templates (3-5 templates). Set up Beehiiv newsletter; first issue published end of day 30.
- **Days 31-60**: Ship event countdown + static taper logic. Ship CSV export to TrainingPeaks-compatible format. Onboard first 10 users from inner circle as polish-testers. Publish weekly newsletter issues. Start commenting genuinely on r/hybridathlete + r/Hyrox + r/tacticalbarbell.
- **Days 61-90**: Reach out to Fergus Crawley with a "I built this, free Pro for you, would you try it" pitch — be the user who has built the tool, not a transactional sponsor. Publish a "I built an app that programs my long run + squats on the same week" post on r/hybridathlete with screenshots. Post the same content on r/Hyrox tied to a HYROX-prep narrative. Newsletter at 200-500 subscribers by day 90.

**Unit economics at $40/yr**:
- Annual gross per sub: $40 - 30% Apple = $28 net Year 1
- Coach cost: $0 (Path B)
- **100% gross margin**
- Renewal at year 2: $40 - 15% Apple (post Year 1 reduction) = $34 net
- At 3,000 active subs: $84k Year 1 → $102k Year 2 (renewals). $120k ARR target hit by year 2 organic compounding.

**Top risk to monitor**: HYROX Train (official app) shipping a credible product. If they nail HYROX-specific programming, the wedge narrows. Mitigation: positioning is hybrid-athlete-first (year-round, multi-event), not HYROX-prep-first.

---

### #2: tacticalbarbell (Path B, $40/yr + $99 lifetime)

**Why it ranks high**: Strongest product-fit alignment of any niche (the 167-routine substrate + structured-template culture is *exactly* what TB practitioners want), highest conversion rate forecast (12-18% trial→paid), and Wilbur's engineer-respects-the-method framing matches the culture perfectly.

**Pricing**: $40/yr base + $99 lifetime. The MTI $30/mo precedent + spreadsheet-tolerant culture absorbs both pricing tiers cleanly.

**Path A vs B**: **Path B**. The TB community values "owning the tool" over "renting the AI." Coach is an optional $10/mo selection-prep-week add-on at month 6-12.

**Primary distribution channel**: r/tacticalbarbell subreddit infiltration (small sub, high-engagement, one good post moves the needle) PLUS the same "Weekly Hybrid Programming Notes" newsletter started for hybrid-hyrox (audience overlap is substantial — same newsletter, same product, doubles addressable). A small TB-aligned YouTube creator (Garage Gym Athlete / Jerred Moon ~80K, or a smaller TB-regular) as amplifier.

**30 / 60 / 90 day execution plan**:

- **Days 1-30**: Audit / build TB-canonical templates in coach.db (Operator, Fighter, Zulu, Velocity, Mass). Build PFT/CFT/PRT/PAST/CPAT calculator. Ship ruck-logging UI. Don't post on r/tacticalbarbell yet.
- **Days 31-60**: Ship conditioning calendar (lift + E/HICs/LSS as siblings — note: shares engineering with hybrid-hyrox concurrent calendar). Soft-launch to inner circle. Publish 4 weekly issues of "Weekly Hybrid Programming Notes" newsletter (covers TB + general hybrid). Start commenting on r/tacticalbarbell threads with useful content.
- **Days 61-90**: Post "I built a Tactical Barbell app — Operator/Fighter/Zulu rendered properly, PFT calculator built in, $40/yr" on r/tacticalbarbell. Expected reach: top of sub for 2-3 days; 100-300 TestFlight installs. Newsletter cross-pollinates conversions. By day 90: 50-150 paying users.

**Unit economics at $40/yr**: Same as #1 — 100% gross margin (Path B). At 1,000 active subs (75% of credible addressable from TB alone): $28k Year 1 net. Requires combined-niche stack (TB + hybrid + adjacency) to hit $120k ARR.

**Top risk to monitor**: TB niche is small (~41K sub + adjacency = ~10K addressable). Cannot hit $10k MRR from this niche alone — must be combined with hybrid-hyrox as a single product positioning.

---

### #3: powerlifting (Path B, $40/yr + $99 lifetime)

**Why it ranks high**: Strongest WTP signal of any *broad* niche (audience pays $35/mo Juggernaut AI, $150-300/mo coaching), tight product-fit (RPE@X + percentage↔RPE conversion + meet-day taper), and r/powerlifting is large enough (588K) to support $10k MRR from this niche alone if the build delivers.

**Pricing**: $40/yr base + $99 lifetime. The niche pays for coaching at $150-300/mo, so $40/yr reads as "obvious value."

**Path A vs B**: **Path B**, with a caveat — this is the one niche where Path A's product-fit is uniquely powerful (peaking decisions). Even so, ramp + risk dominates: ship Path B, layer the Coach as an opt-in $10/mo "meet prep" tier once the base is paying.

**Primary distribution channel**: ONE YouTube creator integration with Brian Alsruhe (~177K subs, indie-friendly) or Calgary Barbell tier ($1-3K + free Pro). r/powerlifting subreddit infiltration as the supporting channel.

**30 / 60 / 90 day execution plan**:

- **Days 1-30**: Audit coach.db for canonical powerlifting templates (Calgary Barbell 8-week, 5/3/1 BBB, GZCL, nSuns 5/3/1 LP). Label with original sources. Ship RPE↔percentage conversion math. Ship Wilks/IPF GL calculator. Ship attempt-tracker (red/white light) for meet days. Ship OpenPowerlifting-compatible CSV export.
- **Days 31-60**: Inner-circle launch + first 5 unpaid early-tester powerlifters from r/powerlifting daily threads. Post a thoughtful "what I'd want from a meet-prep app" thread on r/powerlifting (no app mention) to gauge audience interest. Refine the build based on feedback.
- **Days 61-90**: Reach out to Brian Alsruhe / Calgary Barbell-tier creator with a "free Pro + I think your audience would like this" pitch. Post a meet-report-with-app-screenshots organic thread on r/powerlifting. By day 90: 100-250 paying users.

**Unit economics at $40/yr**: Same 100% gross margin. At 1,500 active subs (~10% of credible powerlifting addressable): $42k Year 1 net. Stand-alone path to $120k ARR requires 3,000 subs = ~20% of addressable, achievable in 12-18 months.

**Top risk to monitor**: Boostcamp's entrenched template library + the "I already have my Calgary Barbell spreadsheet" stickiness. Mitigation: faithful template rendering + the Wilks/GL calculator + CSV export as the practical wedge.

---

## Final pick — ONE

**Niche**: **hybrid-hyrox** (combined hybrid + HYROX + tactical adjacency).

**Path**: **Path B — programming-first planner.** Coach reserved as a future $10/mo Pro upsell at month 6-12, contingent on observed Coach demand from paying users.

**Pricing**: **$40/yr base + $99 lifetime option**. No monthly tier in v1.

**Primary distribution channel**: **ONE YouTube creator integration with Fergus Crawley** + a **Beehiiv newsletter ("Weekly Hybrid Programming Notes")** started day 1. r/hybridathlete + r/Hyrox + r/tacticalbarbell as ambient supporting channels.

**90-day plan**: as detailed above in the hybrid-hyrox top-3 section.

### Realistic $10k MRR date

Under "someday" timeline, the question becomes: what would have to be true to hit $10k MRR equivalent ($120k ARR)?

**At $40/yr**: 3,000 active yearly subs needed. Conditions:

1. Fergus Crawley integration lands (or equivalent mid-tier hybrid creator) → 200-800 users in the launch month.
2. Newsletter compounds from 0 → 1,500-3,000 subscribers over 12 months at 10-20% trial→paid → 300-600 paid users from newsletter alone.
3. r/hybridathlete + r/Hyrox + r/tacticalbarbell sustained presence (1 useful post per week per sub) compounds to ~500-1,000 paid users over 12 months.
4. TB-niche combined product positioning brings tactical adjacency users (~500 paid over 12 months).
5. Word-of-mouth + Apple search + cross-niche → ~300-500 paid users.

Total: 1,800 - 3,400 paid users by month 12 = **$5k-9.5k MRR equivalent by month 12**, **$10k MRR by month 14-18**.

**Realistic $10k MRR date estimate**: **18 months from product ship** if all four channels (Crawley + newsletter + subreddits + word-of-mouth) compound. **24 months** if only 3 of 4 channels compound (most likely scenario). **Beyond 24 months** if newsletter doesn't grow or no creator integration lands.

**What would have to be true**:
- Fergus Crawley (or equivalent) integrates by month 6.
- Newsletter grows to >1,500 subscribers by month 12.
- Build delivers Apple Health integration + concurrent calendar + HYROX movements without major delays.
- Wilbur posts the founder-build-in-public content consistently (newsletter + TikTok ambient + Reddit) for 12+ months — this is the single biggest unknown given the no-existing-audience starting point.

If Wilbur cannot commit to consistent content output for 12-18 months, the realistic timeline shifts to 30+ months and the strategy collapses. **The audience-from-zero problem is the binding constraint, not the product.**

---

## Fatal-flaw flags

Niches that scored well but have a flaw worth surfacing:

- **xxfitness (3.20)** — addressable size is massive (3M+ subs) and WTP is proven (Sweat $19.99/mo at scale), but founder fit is structurally broken without a credible woman cofounder. Don't pursue without that hire. **Net: drop unless cofounder appears.**

- **renaissance-periodization (3.85)** — highest conversion rate forecast of any niche (RP refugees are *primed*), but Mike Israetel is the gatekeeper and one negative public mention from him closes the niche. Risk concentration is real. **Mitigation: positioning as complementary, not competitor; never directly attack RP app.**

- **naturalbodybuilding (3.20) + jeff-nippard (3.40)** — these double-count with renaissance-periodization (same product build, three distribution lanes). Treating them as separate niches inflates the apparent attractiveness. **Recommendation: collapse into single "science-based hypertrophy" niche with RP as the lead surface.**

- **bodyweightfitness (3.15)** — largest sub by far (4.75M) but the lowest WTP of any niche evaluated. $10k MRR is structurally unreachable from this niche alone due to price ceiling. **Useful as a Path B side wedge at $20 one-time; not a primary niche.**

- **alex-leonidas (3.45)** — strong cultural fit + Path B alignment, but the niche is creator-defined (no large dedicated sub) and audience is anti-subscription. Volume from this niche alone cannot hit $10k MRR. **Useful as feeder distribution to broader natty audience.**

---

## Prerequisite engineering work

Before any of this matters, several pieces of revenue + observability infrastructure must ship. Ordered by dependency + impact:

| # | Work | Est. days | Why first |
|---|---|---|---|
| 1 | **App Store ship** — escape TestFlight; submit to App Store Review | 3-5 days | Nothing else collects revenue. Includes the AI Coach consent + privacy manifest from PLAN-coach.md if Path A; simpler if Path B (no Coach = less reviewer scrutiny). |
| 2 | **IAP / RevenueCat wiring** — yearly + lifetime products + restore-purchases flow | 4-6 days | Path B at $40/yr + $99 lifetime needs IAP. RevenueCat handles cross-device entitlement when accounts ship. |
| 3 | **Analytics — at minimum: install, trial start, conversion, retention** | 2-3 days | Without analytics, no learning loop. Use TelemetryDeck or PostHog (privacy-clean). |
| 4 | **Accounts + cloud sync** — Sign in with Apple + iCloud or Supabase-backed sync | 7-10 days | Without accounts, lifetime purchases tie to device only; bad UX. Also needed for newsletter onboarding-to-app linking. |
| 5 | **CSV export** (per several niche requirements) | 1-2 days | Critical for r/weightroom + r/powerlifting + hybrid-athletes who use TrainingPeaks. |
| 6 | **Apple Health integration** (hybrid-niche requirement) | 7-10 days | Mandatory for hybrid-hyrox niche. Includes HRV, workouts, body comp, cycle (for future xxfitness re-evaluation). |
| 7 | **Concurrent training calendar** (lift days + run days as siblings) | 4-6 days | Hybrid-niche must-build. |
| 8 | **HYROX-specific movements in coach.db** + bundled hybrid templates | 3-5 days | Niche-specific content. |
| 9 | **(IF Path A) Coach cost controls + observability — per-user daily/monthly caps + cost dashboard** | 5-7 days | Currently unenforced. Power users could burn $5-15/mo. Cannot ship Path A without this. |

**Total prerequisite engineering (Path B)**: ~31-47 days = **6-10 weeks** to ship-ready.
**Total prerequisite engineering (Path A)**: ~36-54 days = **7-11 weeks** to ship-ready, plus ongoing Coach cost discipline.

Path B is ~1 week faster to ship-ready and dramatically lower-risk. Confirmed recommendation: **Path B first.**

---

## One-line summary

**Ship Path B (programming planner, $40/yr + $99 lifetime) for the hybrid-athlete niche, starting with App Store + IAP + Apple Health + concurrent calendar work over 6-10 weeks, then Fergus Crawley integration + Beehiiv newsletter + r/hybridathlete subreddit presence as the three compounding channels. Realistic $10k MRR by month 14-18 from product-ship date, contingent on consistent founder content output for 12+ months.**
