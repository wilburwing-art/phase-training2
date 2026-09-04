# 09. Paywall and gate

**Status:** closed 2026-09-03
**Lens:** business

## Question

Is the free tier a complete app or a demo, is the Pro line defensible, and does
the paywall appear at the moment of felt value?

## Depth actually reached

Full. Every entitlement call site was enumerated, both gate switches read, the
StoreKit configuration parsed, and the pricing compared against the strategy
doc. Not covered: an actual purchase run against a sandbox account.

## Findings

### F1 (critical, business) There is no paid feature. Both gates are held open

```swift
// CoachEntitlement.swift:10
// PRODUCT DECISION (2026-06-05): coach ships FREE. The Pro gate is wired at
// every coach surface but held open by `proRequired = false`.

// SupportEntitlement.swift:35
static let proRequired = false
```

Both are deliberate and documented, with a written flip plan on each. The
consequence is still worth stating plainly: **the free tier is the whole app.**
A grep for `freeLimit`, `maxFree`, `trialDays` or `limitReached` returns
nothing. There is no session cap, no history limit, no export gate, no ad. Every
capability, including the LLM coach, is available to a user who pays nothing.

So the question "is the free tier a complete app or a demo" has a third answer:
it is the product, and Pro is currently a button.

### F2 (critical, business) The most expensive feature to run is the free one

The Coach makes Cloudflare AI Gateway calls billed to the developer. T0-1 in the
2026-08-23 backlog established that the gateway token ships inside the IPA and
that the only ceilings are client-side (`CoachConfig.dailyRequestCeiling = 400`,
soft/hard turn caps of 50/100). Revenue against that cost is currently zero by
construction.

`STRATEGY.md:88` predicted this exact shape and recommended against it: "Coach
is a future $10/mo Pro upsell once the base is established, not a v1
requirement", with the stated reason being Coach unit-economics risk. What
shipped is Coach as the flagship, free, unmetered per install, with the external
half of T0-1 still open.

### F3 (high, trust) One of the paywall's two benefit claims is false

`PaywallView.swift:74` is the entire value proposition:

> "The only training app that plans your primary sport around a second one —
> plus an AI coach that personalizes every workout."

- The first half is real. `SupportScheduler`, `SupportPattern` and the
  support-sport reflow exist, and `SupportEntitlement.swift:5-7` names it as
  "potentially the FIRST paid feature". Defensible, and nothing in the
  competitor set does it.
- The second half is not. Per critique 04 F1, seven of nine `GeneratorStrategy`
  fields never reach the generator, and per 08 F2 the sibling refinement path
  was disabled by its own author as "a false product claim". This sentence is
  the paywall version of the claim that got disabled elsewhere.

A user cannot currently act on it (F4), which limits the damage to credibility
rather than money. It should not survive to the day products go live.

### F4 (medium) Nobody can buy anything, and the unconfigured state is handled well

`SubscriptionStore.allProductIDs` holds `com.phasetraining.app.pro_monthly` and
`com.phasetraining.app.pro_yearly`. `PhaseTraining.storekit` defines both at
$6.99/month and $49.99/year, and the scheme wires that file for local runs only
(`Project.yml:25-28`). No App Store Connect products exist, so a live build
falls into `unconfiguredState` and shows "NOT AVAILABLE YET"
(`PaywallView.swift:153-172`).

That state is well handled and the code says why: it used to render build
instructions with backticked Swift symbols to anyone who tapped Upgrade, and the
developer version now lives behind `#if DEBUG`. Good catch, already fixed.

### F5 (high, business) The shipped price shape contradicts the strategy's own reasoning

| | strategy (`STRATEGY.md:105`) | shipped (`PhaseTraining.storekit`) |
|---|---|---|
| yearly | $40 | $49.99 |
| lifetime | $99 | **absent** |
| monthly | not recommended | $6.99 |

The lifetime option is not a detail in that document. It is argued for twice:
the tacticalbarbell brief says the community "values 'owning the tool' over
'renting the AI'" (`STRATEGY.md:134`), and the alex-leonidas entry says that
audience is "anti-subscription" (`:222`). $99 lifetime was the answer to both.

What shipped is subscription-only, with a monthly tier the strategy did not ask
for and no lifetime tier at all. Given critique 02 F2, the niches this was
priced for cannot use the app anyway, so the honest read is that pricing was set
independently of the strategy rather than against it. Worth deciding on purpose.

### F6 (medium) The paywall is reachable from two places and neither is a moment of value

`PaywallView()` is presented from `ProfileScreen.swift:292` and
`CoachSettingsRow.swift:52`. Both are settings surfaces. A user reaches them by
deciding to go looking.

There is no contextual paywall, because there is nothing to gate against (F1).
When `SupportEntitlement.proRequired` flips, the moment of value is obvious and
already built: the user opens `SupportPatternEditor` to declare their second
sport's weekly rhythm, and that is the screen where the pitch lands. Nothing
needs inventing; the flip just needs to route there rather than to Profile.

### F7 (low) The gates are wired correctly for the day they flip

Worth recording, since this is the part most likely to be half-done and is not.
Both entitlements are pure functions parameterized for tests
(`unlocked(pro:requirePro:)`), both read the same mirror
(`CoachEntitlement.proKey`, updated by `SubscriptionStore` on refresh), and
`SupportEntitlement` carries its own switch specifically so support can go paid
while the coach stays free. `SupportEntitlement.swift:31-34` even records where
the revocation must happen on lapse (at the PlanStore boundary, not inside the
pure Planner) and why. There are dedicated tests
(`SupportEntitlementTests`, `CoachEntitlementTests`, `SubscriptionStoreTests`).

## Refuted

- **"A user could buy Pro and receive nothing."** They cannot buy at all: no ASC
  products exist and the paywall renders "NOT AVAILABLE YET". The risk is real
  for the day products are created and should be closed before then, but it is
  not live.
- **"The gates are held open by accident."** They are not. Two dated product
  decisions with written rationale and a flip procedure in each file.

## The decision this critique exists to force

Three things are true at once: the Coach is free and costs real money to run,
the support-sport feature is the documented first paid feature and is also free,
and the paywall claims a Coach capability that does not run. Any two of those
can coexist. All three cannot survive an App Store launch.

The cheapest coherent move is the one the code is already shaped for: flip
`SupportEntitlement.proRequired`, route the paywall from
`SupportPatternEditor`, and rewrite the second half of the paywall sentence to
describe the deterministic planner rather than the coach.
