# Mountain-athlete niche briefs (T3-1, item 9 of the 2026-09-05 work plan)

Seven briefs, one per community the app's ten plannable sports actually live
in, written under the rule the first ten briefs lacked: every audience figure
read from the page that states it, with URL and date, or marked as an
estimate with its basis. STRATEGY.md found the first round's figures off by up
to 137 percent; these are checked by `validate_brief.py` (headings, dashes,
sourcing, no dated launch plan), calibrated against the old reference brief it
correctly fails.

Filed, not acted on. Pricing and the gate are deferred (decisions 5c, 5d), so
no brief ends in a launch plan and the STRATEGY.md ranking is not redone here.
That is the owner-led next step.

## The shape of the set, read across the seven

Three communities carry the money and the fit: **climbing** (largest and most
crowded, eight priced competitors, the app's most-built sport), **hiking and
thru-hiking** (largest raw audience, one direct competitor in Chase Mountains,
a bodyweight tier already shipped), and **alpinism plus skimo** together (the
highest spend, the only app whitespace, and too small alone). Resort ski and
snowboard has the biggest subreddits and no training community at all; trail
running has a product-fit gap the app has to close before it can be pitched.
This is the material for the owner-led ranking, not the ranking.

## What the round found

| brief | headline audience (read) | closest competitor and price | the finding |
|---|---|---|---|
| ski-and-snowboard | r/skiing 949,599; r/snowboarding 978,811 (frontpagemetrics, 2026-09-05) | Uphill Athlete library $29/mo; MTI ski plan $55 | **No anchor creator and no training-focused community exist.** The big subreddits are gear and trip reports. Weakest distribution story in the set. |
| mountain-biking | r/MTB 454,000 (thehiveindex, synced 2026-09-02); every YouTube count an estimate | TrainerRoad $17.45/mo; MTI MTB plans $49 to $69; bikejames.com $97 | Strongest hard WTP signal read anywhere: average trail bike $6,210 (Singletracks, 2026-03). Audience table weak because Reddit and YouTube blocked direct fetch. |
| hiking-and-thru-hiking | r/hiking 2.6M; r/Ultralight 955K; r/AppalachianTrail ~190K; r/PacificCrestTrail 87K (thehiveindex, 2026-09-05) | **Chase Mountains, $14.99/mo or $34.99 once (App Store); $189 to $249 programs** | Closest direct competitor in the set: same knees-and-descent durability pitch, same audience. r/backpacking excluded: it is the international-travel subreddit. ATC 2025: 2,187 northbound starters, 834 finishers. |
| trail-and-ultra-running | r/trailrunning 482K; r/ultrarunning 128K (thehiveindex); WSER 2026 lottery 11,335 entrants | **Vert.run $9.90/mo, already bundles strength**; Uphill Athlete coaching $399/mo; Runna $9.99 to $19.99 | Product-fit gap verified in the repo: `trail-running` has one WeeklyShape (`maintenance`) and Primary/Support de-confliction is gated to ski slugs (`Planner.swift:835`), so a runner cannot keep an external run plan and take only the strength side. Filed R3-16. |
| alpinism-and-mountaineering | r/Mountaineering 312,000; r/alpinism 108,000 (gummysearch, 2026-08/09); AAC 26,000+ members | Uphill Athlete 24-week plan $99, groups from $53/mo; MTI $35/mo; Evoke $65 to $75 | **Highest spend in the set** (Denali guided $12,250 to $13,500; NOLS course $6,650) and the smallest funnel: roughly $1,500 to $4,700 MRR alone. Reads as a feeder into a combined mountain positioning with skimo, not a standalone pick. Founder fit is an open question, scoped honestly. |
| climbing | r/climbing 1.6M; r/bouldering 488K; r/climbharder 188K (gummysearch, synced 2026-08-31 to 09-03); 5.6M US indoor climbers 2021 (Climbing Business Journal) | Lattice $29.99/mo or $149.99/yr; Crimpd $4.99/mo; Climbstrong $12/mo, coaching $215 to $425/mo; Hooper's Beta coaching $250 to $350/mo | The most-built sport in the app and the most crowded field in the set: eight priced competitors, Crimpd citing 200+ workouts. The brief's product-fit numbers were re-derived at merge from the shipped `PhaseTraining/Resources/coach.db` (12 categories, 54 exercises, 13 routines, 27 injury rows, 29-movement pool); its author had read `db/coach.db`, a stale dev copy in the tree that predates today's injury rows. |
| ski-mountaineering-and-splitboard | r/Backcountry 226,043 (reddit about.json, 2026-09-05); r/skimo 1,580; r/splitboarding 834; r/Skitouring 768; no training creator, Cody Townsend 163K is adventure media | Uphill Athlete skimo plans $89; Evoke Endurance plans $55 to $60, coaching $350/mo; MTI ski plan $55; **zero fitness apps in an App Store search of the keyword space** | The one community in the set with genuine app whitespace and the smallest ceiling: cannot clear $10k MRR alone at $40/yr. Its author caught and discarded a fabricated figure, a search summary's "$29/mo Uphill Athlete coaching" that traced to unrelated Gumroad listings. Reads as one half of a combined mountain positioning with alpinism. |

## A stale copy in the tree

`db/coach.db` is a gitignored dev by-product (`.gitignore:50-52` says so and
names `PhaseTraining/Resources/coach.db` as the bundled database), but it sits
under a directory called `db/` with the right filename, and one brief's author
read it and reported 47 exercises and 11 injury rows where the shipped file
holds 54 and 27. Not a repo defect, a trap for readers: any agent or script
grounding a claim in "the database" must read
`PhaseTraining/Resources/coach.db`. Filed as R3-17 as a one-line rule for the
agent contracts, since deleting another session's ignored local file is not
mine to do.

## What could not be read anywhere, and is marked as an estimate in every brief

Every YouTube subscriber count (channel pages render nothing to a fetch,
Social Blade blocks); reddit.com itself (mirrors used, with their sync date);
Pinkbike, Trailforks, Physiopedia, Mayo Clinic (403); image-based pricing
pages (Zwift, Fitbod). The competitor price tables are the reliable half of
every brief.
