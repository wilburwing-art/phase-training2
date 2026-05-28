# Strategy Assessment

**App:** Phase Training (iOS, SwiftUI) — periodization lifting app whose differentiator is the **"hybrid-athlete support-role"** framing: it builds a lifting plan *in support of* a primary sport (climb/ski/run), with onboarding-driven constraints (injury, equipment, season), a deterministic rules-based `WorkoutGenerator` over a 551-exercise / 148-routine `coach.db`, and an LLM coach (Claude Sonnet 4.6 via Cloudflare AI Gateway, consent-gated).

**Build state (verified against code, not just plans):** v1.1.0 build 110, on TestFlight. Far past PLAN.md's "thin 4-screen slice." Shipped: 5-tab shell, 12-screen onboarding, rules planner + `PlanDiff`/preview/apply, `TrainingMemory` + soreness/feedback loops, weekly check-in, deterministic generator with LLM-strategy override, coach chat with tool-calls, eval-rig grading harness, image-quality pass done. **No StoreKit / IAP / paywall code exists anywhere** (verified — `grep` for StoreKit/RevenueCat/Product returns nothing; "subscription" hits are Combine). The coach is wired and billing-ready; the *business* is not.

---

## Competitive landscape (re-verified 2026-05-26)

| App | What it does | Price (2026) | Touches "lift in support of a sport"? |
|---|---|---|---|
| **Fitbod** | ML-generated lifting workouts, recovery/equipment-aware, 1000+ exercises, video | $15.99/mo, $95.99/yr | No — pure aesthetic/strength gym app |
| **Hevy** | Best-in-class logger + social; **AI "Hevy Trainer" launched Feb 2026** (generates/progresses programs, free) | Free; Pro $2.99–5.99/mo | No — logger-first; AI is generic programming |
| **Boostcamp** | 70+ canon programs (5/3/1, PPL, nSuns), templated | Free (core) | No — templates, no sport context |
| **Juggernaut AI** | Autoregulated periodization, powerlifting-centric | $34.99/mo, $349.99/yr | No — peaking for the platform lifts |
| **RP Hypertrophy** | Volume-landmark hypertrophy autoregulation | $34.99/mo, ~$225–300/yr | No — bodybuilding |
| **TrainHeroic / Bridge** | Coach→athlete marketplace; buy a coach's program | Athlete free (coach-paid); programs $15–40/mo | Partially — *human* coaches sell sport programs; not an algo |
| **MacroFactor** (Stronger By Science) | Smart macro tracker; **Workouts module launching Jan 2026** | $5.99–11.99/mo | TBD — credible heavyweight entering algo-lifting |
| **Edge / HYBRD / HYBRID** | **Hybrid = strength + endurance** (run-and-lift), wearable-synced, social | ~$10–20/mo | **Adjacent, not the niche** — run+lift, *not* lift-supports-climb/ski |
| **Ray** | **Voice AI coach that talks you through the workout** (TTS, rep-counting CV) | $19.99/mo | No — general |
| **Forge / Bloom (Beebo) / F/AI** | **LLM chat coaches** — conversational plan edits, 24/7 chat | varies; ~$15–20/mo | No — general fitness |

### Verdict on the niche
**The exact lane — "periodized lifting whose explicit job is to support a primary non-gym sport (climbing, skiing, running as the *sport*, not as cardio)" — is still essentially open.** Nobody verified above frames lifting as a *support role* with season-phase (pre/in/off) awareness around a sport calendar. BUT the moat narrowed sharply since the owner's 2026-04-24 notes:

1. **"Hybrid athlete" got crowded.** Edge ("only app built ground-up for multi-discipline"), HYBRD, and HYBRID all grew in 2025-2026 — but all three are **strength + endurance** (the run-and-lift influencer archetype). They do *not* cover climbing/skiing or the support-role framing. The *term* is taken; the *specific positioning* is not. Don't market as "hybrid athlete app" — you'll lose the SEO/category fight. Market as "strength training that serves your sport."
2. **The AI-chat-coach is no longer a differentiator.** As of 2025-2026, Forge, Bloom/Beebo (CHI 2026 best-paper), and F/AI all ship LLM chat coaches; Hevy added AI programming free in Feb 2026. An LLM coach is now table stakes, not a wedge. The wedge is *what the coach is grounded in* — the sport-support model + structured `TrainingMemory` + deterministic generator the LLM only edits. That grounding is real and rare.
3. **Voice coaching already exists and is reviewed well** (Ray, $19.99/mo, "best for voice coaching during the workout"). This directly pre-empts the ROADMAP.md voice bet.
4. **A heavyweight is entering.** MacroFactor (Greg Nuckols / Stronger By Science) ships Workouts in Jan 2026 — the most credible algorithmic-programming team in the space, with an existing paying nutrition base to cross-sell.

Net: the niche is defensible **only** if positioned tightly around the sport-support angle and shipped before the category consolidates. The generic "AI lifting coach" framing is already lapped.

---

## Path to MRR

**Reality check:** solo-built, pre-revenue, on TestFlight, no paywall code. The gap to MRR is App Store submission + a StoreKit paywall, not more features.

### Pricing model — **freemium with a subscription paywall on the AI coach**
The deterministic generator, planner, logging, library, and onboarding are *already a complete free app* (no per-user marginal cost). The LLM coach is the only feature with real COGS, and it's the obvious premium hook. Gate it.

- **Free tier:** full logging, rules-based generated weekly plan, manual plan editing, routine library, sport-season planning. (This alone competes with Hevy free / Boostcamp.)
- **Pro ($9.99/mo, $59.99/yr):** the LLM coach — chat, proactive insights, tool-call plan/workout edits, day recaps. Price **below** Juggernaut/RP ($35) and at/under the Fitbod ($16) line, slightly above Hevy. $59.99/yr is the conversion workhorse.

### Coach unit economics (the load-bearing math)
Config: Sonnet 4.6 default, Haiku 4.5 fallback, prompt cache on system+memory (≥1024 tok), 1024 max output, soft cap 50 turns/day. Sonnet 4.6 ≈ $3/$15 per M tokens (in/out); cache hits ~90% cheaper on the cached prefix.

- Per turn (cached system+memory ~4k cached, ~1k fresh input, ~700 output): ≈ **$0.012–0.02/turn**.
- The owner's PLAN-coach target is **≤ $0.05/user/month** at expected <5 turns/day; realistic *active* users will run higher. Model a heavy user at 15 turns/day × 30 = 450 turns × $0.015 ≈ **$6.75/mo COGS** — that's the worst case the soft/hard cap (50/100) exists to bound.
- Blended across a realistic distribution (most users <5 turns/day, a tail at 15+): expect **$0.50–2.00/user/mo** COGS for active Pro subscribers.
- At **$9.99/mo gross → ~$7/mo net** after Apple's 30% (15% after year 1 / Small Business Program). Even a heavy-user worst case ($6.75 COGS) stays roughly breakeven; the median Pro user is **~85%+ gross margin**. **The economics work** — the cost-cap design already protects the downside. The risk is *free riders running up the bill before converting*, so: **the coach must be behind the paywall, not free-trial-unlimited.** Give a hard free allowance (e.g. 10 lifetime coach turns) to demonstrate value, then paywall.

### Conversion assumptions
Fitness freemium converts ~2–5% of actives to paid. At $60/yr net ~$42 (post-Apple), **1,000 MAU → ~30 Pro → ~$1,260 MRR-equivalent/yr ≈ $105 MRR.** MRR is a distribution game; the first job is *getting to the store and instrumenting conversion*, not optimizing price.

### Smallest shippable monetizable slice
**Ship the current build to the public App Store with a StoreKit 2 paywall that gates only the LLM coach.** Everything else is done. That is the entire MVP-to-revenue path. Concretely: (1) add a `StoreKit 2` `Product` + paywall sheet on the coach-consent step, (2) 10-turn free allowance then paywall, (3) App Store review submission (privacy manifest + 5.1.2(i) disclosure already specced in PLAN-coach). Do **not** build new features for this. Use RevenueCat only if cross-platform later; raw StoreKit 2 is enough solo.

---

## Roadmap pressure-test (sequencing verdict)

Two things are queued: **ROADMAP.md voice coach** and **PLAN-image-quality.md** (525-image vision triage). Both are the wrong next bet.

- **Image-quality cleanup is already substantially done** (git log: builds 938c877→205aa0a landed the L1/L3 triage, 318 suspects, 62 auto-swaps, audit report, build 106). The remaining tail polish is **invisible to a non-user** and moves zero revenue. It's craftsmanship on an app no paying customer has yet opened. **Defer the residual pass indefinitely.**
- **Voice coach is the most expensive, least-validated bet on the board**, and Ray already occupies "voice coaching during the workout" at $19.99/mo with CV rep-counting the solo dev can't match. Voice adds STT/TTS cost, audio-session complexity, and a new App Store surface — for a feature a competitor already ships and that **nobody is paying you for yet.** Building it pre-revenue is optimizing an engine before selling a single ride.

**Verdict: neither. Ship + paywall comes first, unambiguously.** The app is feature-complete enough to charge for; it has no way to charge. Every engineering hour not spent on App Store submission + StoreKit is an hour spent gold-plating a product with zero paying users. Build the paywall, submit to review, get 50 real users, *then* let their behavior — not the roadmap — pick voice vs. anything else. The single most likely outcome of shipping is learning the positioning ("supports your sport") needs to change, which is far cheaper to discover now than after a voice build.

---

## Tiered backlog — GO-TO-MARKET (not code)

### P0 — do first (gate to any revenue)
- **StoreKit 2 paywall gating the LLM coach (10-turn free allowance → Pro).** ~2–3 days. The coach is wired and cost-capped; the only missing piece between the app and MRR is the buy button.
- **Public App Store submission (not just TestFlight).** ~1–2 days + review wait. Privacy manifest + 5.1.2(i) AI disclosure already specced in PLAN-coach; execute it. You cannot earn from TestFlight.
- **Lock positioning copy to "strength training that serves your sport" — drop "hybrid athlete."** ~0.5 day. The hybrid category is now contested (Edge/HYBRD/HYBRID) and means run+lift; your wedge is sport-support (climb/ski). App Store title/subtitle/screenshots must say this, not "AI coach" (lapped) or "hybrid" (taken).

### P1 — fast-follow once live
- **Instrument conversion + coach-turn cost per user.** ~1 day. The PLAN-coach dev menu already logs tokens/turn; surface it as analytics so you can watch COGS vs. the soft cap on real users. You're flying blind on unit economics until real users hit it.
- **Pricing experiment: $9.99/mo vs $59.99/yr emphasis; 7-day trial vs hard allowance.** ~0.5 day config. Sub-Fitbod, sub-Juggernaut pricing; annual is the conversion workhorse.
- **ASO for the open lane: "climbing strength training," "ski prep lifting," "off-season strength plan."** ~1 day. These keywords have no algo-app incumbent — cheaper to rank than "AI workout."

### P2 — only after paying-user signal
- **Voice coach** (ROADMAP.md). Large. Defer until users ask + Pro revenue funds the STT/TTS COGS; Ray already owns the slot, so this needs a sport-support angle to differentiate, not just "voice."
- **Residual image-quality tail pass** (PLAN-image-quality.md). Small but invisible to acquisition; finish only if a paying user complains about a specific wrong image.
- **Eval-rig adapter → public generation-quality claim** (PLAN-eval-rig-adapter.md). Medium. Useful *marketing* proof ("our generator scores X on canonical-program rubrics") once there's an audience to market to — premature now.

---

**Sources:** Fitbod ([apps.apple.com](https://apps.apple.com/us/app/fitbod-gym-fitness-planner/id1041517543), [arvo.guru](https://arvo.guru/vs/fitbod)); Hevy ([prpath.app](https://prpath.app/blog/hevy-app-review-2026.html), [hevy.com/pricing](https://hevy.com/pricing)); Juggernaut/RP/Boostcamp ([juggernautai.app/pricing](https://www.juggernautai.app/pricing), [arvo.guru](https://arvo.guru/vs/juggernaut-ai)); TrainHeroic/MacroFactor/SBS ([coachbox.app](https://coachbox.app/en/compare/trainheroic-pricing), [strongerbyscience.com](https://www.strongerbyscience.com/macrofactor-workouts-survey/)); hybrid apps ([findyouredge.app](https://www.findyouredge.app/news/best-hybrid-workout-apps-2026-comparison), [hybrd.app](https://www.hybrd.app/)); voice + LLM coaches ([rayfit.com](https://www.rayfit.com/blog/2026/02/best-ai-personal-trainer-app/), [forgetrainer.ai](https://forgetrainer.ai/blog/best-ai-personal-trainer-apps-2026), [hai.stanford.edu](https://hai.stanford.edu/news/an-ai-health-coach-could-change-your-mindset)). Verified 2026-05-26.
