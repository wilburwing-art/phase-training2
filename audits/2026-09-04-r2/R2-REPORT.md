# Second pass, all 13 lenses — 2026-09-04

Re-run against current `main` after 7 Tier 0 and 10 Tier 1 items landed. One
section per lens. Where a lens found nothing new, it says so in a line rather
than restating the first pass.

**Method note.** The generator sections are measured, not reasoned:
`SeasonFidelityTest` was re-run and `/tmp/season-fidelity/report.md` re-read, so
every number below is from this session. Structural sections (niches,
competitors, pricing) were re-checked against the code and found unchanged.

---

## 01 — Coaching quality: the largest change in the suite

Re-measured from the fresh dump. Ski off-season, the phase the first pass used
as its worked example:

| | 2026-09-03 | 2026-09-04 |
|---|---|---|
| exercises per session | 4 | **5** |
| session length | ~33 min (target 50-75) | **~36-48 min** |
| fatigue used / cap | 11 / 24 | **10-18 / 24** |
| demands realized non-zero | 4 of 8 | **8 of 8** |
| sessions 1 and 3 | identical | **different** |

**F1 closed.** `targetMovementCount` rounds instead of truncating.

**F2 closed, and this is the one that mattered.** Slots are apportioned across
the whole week and dealt per session (`weekSlots`), so the quantisation floor is
1/(perSession x sessionsInWeek) rather than 1/perSession. `power` (0.10),
`legEndurance` (0.05), `prehab` (0.05) and `hipLateral` (0.05) all realize
non-zero now. Those last two are the demands the off-season objective's "fix
imbalances" actually depends on, and they had been rounding to zero in every
session.

**F3 closed.** The three off-season sessions now open with Lateral Lunge, Split
Squat Jump and Broad Jump respectively. Nordic Hamstring Curl is in all three
deliberately: `guaranteeSignature` keeps the sport-defining demand in every
session, which is why realized `eccentricLeg` sits at 0.20 against a 0.10 target.
That over-representation is intended and the fidelity check now models it.

**F4 mostly closed.** ~47 min against a 50-75 band is a near miss rather than the
17-minute shortfall it was. The residue is the estimator disagreement the first
pass flagged: `targetMovementCount` budgets 11 min per movement while `assemble`
measures ~8.25. Left alone on purpose; reconciling them moves every phase and is
its own change.

**F6 improved.** The maintenance session went from ~8 min of four single sets to
~13-19 min with a real compound in it.

**F5 still open.** Ski off-season is still entirely lower body and trunk. That is
the pool and the rule, not the allocator, and no amount of re-allocation adds a
pulling movement that the 44-row ski pool's demand weights never ask for.

**F7, F8, F9 unchanged.** The climbing hypertrophy/strength contradiction, three
hangboard sessions a week, and the four unreachable `aerobicUphill` movements are
all as first reported.

**F11 half closed.** `strategy` reaches the season engine now (see 04). `context`
still does not: readiness and soreness scaling live in `makePickedRow`, which
only the custom-routine re-prescription path uses.

**F10 was refuted** during the fix pass and is corrected in place in the first
pass's document.

### New this pass

**R2-01 (high, safety) — the injury filter could push a session under the
movement floor.** T0-1 filters contraindicated exercises *after* the selector
picks a routine, and `AuthoredRoutine.workout` only rejected the empty case. So
a 3-movement routine with one contraindicated lift became a 2-movement session,
under the floor T1-9 had just established. Measured against the shipped db:
four selectable routines drop below 3 for some injury, and one is reachable from
a plannable sport (`Cyclist In-Season Maintenance`, 3 movements, via
mountain-biking, for lumbar-disc-herniation). Fixed by filtering for viability in
the **selector** rather than at build time, so a routine rejected for this user
is skipped and the next one is offered; rejecting at build time would drop an
authored-only sport through to the empty "no supported sport" workout. Regression
test added.

**R2-02 (medium, quality) — primary-demand match now outranks recency in slot
filling.** Found by a test failing for a good reason. Once T1-3 made low-weight
demands reachable, `test_check7_rotation_preserves_coverage` caught that a
rotation could drop `hipLateral` entirely: the ski pool has exactly one
hipLateral-primary movement, and when it was recently used the slot went to a
movement that merely *lists* the demand. Rotation should vary which movement
serves a demand, never whether it is served. Also added scarcest-demand-first
slot ordering so a one-candidate demand is not consumed by a six-candidate one.

---

## 02 — Niche teardown: unchanged

Nothing in this pass touched scope. `SportCatalog.isPlannable` still admits the
same ten mountain sports, the ten niche briefs are still gym-strength
communities, HYROX still has no slug, and the routine library is still 113 with
107 unattributed. F1 through F8 stand as written. This is Tier 3 work (T3-1) and
an owner decision, not a defect.

---

## 03 — Safety: the headline finding is closed

**F1 closed and verified by mutation.** `AuthoredRoutine.workout` now takes a
required `profile` and filters `excludedExerciseIds`. With the filter removed the
new invariant fails on `Weighted Pull-Up` and `Hangboard Repeaters (7/3
Protocol)` for a climber with a declared finger-pulley injury, which is exactly
the case F2 named.

**F2 closed** by the same change, plus R2-01 above for the floor interaction.

**F4 closed.** Disclaimer on the onboarding welcome and in the injury editor.

**F5 half closed.** The strategy half is wired (04 F1); the readiness and
soreness half is not, and the app still asks for a soreness check-in that changes
nothing in either live generator. That is the largest remaining safety-adjacent
gap and it is not on the current backlog as its own item.

**F3 open, and deliberately not auto-fixed.** 42 of 56 declarable injuries still
have no contraindication mapping, including meniscus tear, three stress
fractures, and shoulder dislocation. **This should not be filled by a model.**
Each row asserts that a specific exercise is unsafe for a specific injury, it is
the one table in this app whose errors hurt people, and the existing 39 rows
appear to be researched. The mechanical part that IS safe to do: surface the gap
in the UI, so a user declaring meniscus tear is told the app has no exercise
filter for it rather than being shown a filtering promise that does nothing for
them. Recorded as T1-5's revised scope.

**F6, F7 open.** Unconditional 2.5% progression with no autoregulation, and the
name-keyed prior-best lookup.

---

## 04 — Coach red-team

**F1 closed.** `strategy` now reaches `SportSeasonGenerator.generateSession`.
Honestly scoped: intensity bias applies to sets, and the per-exercise RPE, tempo
and target-weight overrides apply by name. `emphasizePatterns` and
`deprioritizePatterns` are movement-pattern slugs with no demand equivalent and
are still ignored **deliberately**, rather than mapped by guesswork. So the Coach
Request screen's billed call now changes the workout it explains.

**F2 closed.** The swap resolves `toName` through `ExerciseLookupCache`, keeps a
real `exerciseId` (so injury contraindications can match it), takes identity from
the new movement, keeps the dose, and drops `notes`/`rpe`/`tempo` — `notes`
above all, because it could carry a load target computed from the replaced lift's
history.

**F6 closed** as a consequence of F1: `build_workout` is no longer a tool whose
output the generator discards.

**F3 open.** Both tools still match exercises by display name, and a partial
proposal can still apply the changes that resolved while silently dropping the
rest.

**F4, F5 unchanged.** The medical boundary is still one prompt line, though the
app now has a disclaimer behind it. The gateway token rotation is still external
and still open from T0-1.

---

## 05 — Cold-install funnel

**F1, F2 closed.** The full UI target passes: **42 tests, 0 failures**, and all
13 tap-budget flows land on reference. That is the first green UI suite since at
least 2026-08-29.

**F3 closed.** Baseline updated to 13, and `discard-workout` to 4 after T0-3's
Finish-confirm walk.

**F4 partly addressed.** The welcome screen's step count is honest now ("Nine
quick questions"), but eraAffinity is still step 8 of 11 and consent is still a
required decision before any value is shown. Both are placement questions and
remain open.

**F6 open.** Ten questions still precede the first thing worth seeing, though
what arrives after them is materially better than it was (01).

---

## 06 — Lifecycle

**F1 closed.** `needsRegeneration` has a date term, `planCoversCurrentWeek` is
the predicate, and `refreshForCurrentWeek` runs on every foreground: snapshot the
outgoing week, prefer a plan the Weekly Check-In staged, otherwise generate.
Skipped mid-session so a day rollover during a workout cannot reroll the template
under the user. **Not runtime-confirmed** — the fix is unit-covered and the
simulator clock was not moved forward eight days. Worth doing before shipping.

**F2 closed.** `deloadAware` resolves the mesocycle status and swaps the phase
rule for a deloaded one, which re-resolves every `DemandScheme`, so sets, reps
and RPE all lighten rather than one number. Week 4 of a 4-week block now
prescribes strictly fewer total sets than week 1, and weeks 1 and 2 are
identical, both pinned by new tests.

**F5 improved by F1.** The missed-workout machinery is still behind the weekly
check-in, but the check-in's staged plan is now promoted on foreground rather
than only via a notification deep link.

**F3 open.** Still nothing brings a lapsed user back; the weekly reminder is
still off by default.

**F6 closed.** The five-test start/finish cluster is resolved, and one of its
three causes was a real bug (T0-3).

---

## 07 — Accessibility

**F2 closed.** The check dot draws at 22 and is tappable at 44. No tap budget
moved, so the layout change is contained.

**F4 barely started.** The check dot gained a label ("Complete set 3" / "Set 3
done, tap to undo"). That is 1 of the dozens the logging surface needs.

**F1, F3 open and unchanged.** The type system is still 134 `.custom(_:size:)`
calls with zero `relativeTo:`, and the fixed row frames still have to move with
it. This is the largest untouched item in the whole suite.

---

## 08 — Copy and voice

**F1 closed.** All three false claims are gone, and the pass found a **fourth**
the first pass missed: the paywall feature list carried "Personalized workout
polish on every plan generation", which is literally the refinement pass
`PlanStore+LLMRefinement` disabled itself over.

**F3 open.** The Coach prompt still opens "The user is a busy hybrid athlete",
a persona the app will not accept a sport for.

**F4 partly.** Four prose dashes went with the paywall rewrite; roughly 19
remain.

**F5, F6 unchanged.**

---

## 09 — Paywall: unchanged except the copy

The gates are still both held open, nothing is gated, the Coach is still the
free feature that costs money to run, and no ASC products exist. F3's false
claim is fixed (08 F1); F1, F2, F4-F7 stand. T3-4 is the owner decision.

---

## 10 — Competitors: unchanged

No scope or pricing change this pass. The MTI attribution question (F2) is
untouched and remains the sharpest pre-submission item in Tier 3.

---

## 11 — App Review and privacy

**F1, F2, F3, F5, F6 all closed.** Manifest added with the UserDefaults
required-reason declaration and Health/Fitness data types; the policy rewritten
from the actual 22 context blocks; the promised privacy link wired to a
GitHub Pages URL verified live; the stale header comment corrected; the
disclaimer added.

**F4 was refuted** and is corrected in place: confirming a Health-detected
activity writes a `SportLogEntry`, and sport logs are one of the context blocks,
so the policy sentence the finding wanted to "fix" was accurate.

### New this pass

**R2-03 (medium, discoverability) — raised by Wilbur, not by the first pass.**
Authorization is requested only from two buttons inside Profile -> Health &
Imports; onboarding never mentions Health and nothing else points there. Since
HealthKit will not report a denied read, an ungranted install is
indistinguishable from one with no workouts, so the app cannot detect the gap and
prompt. Everything behind the grant is therefore inert and invisible for anyone
who does not go looking, including the on-open activity detection shipped four
commits before the first pass. Fixed as a state on the existing row rather than a
prompt, which keeps the "never nag someone who has not opted in" property intact.

---

## 12 — Backlog re-verification, applied to this session's own work

Every Tier 0 and Tier 1 claim above was verified against the behaviour, not the
commit. Three things worth recording:

- **Three findings from the first pass were refuted while fixing them**
  (01 F1's mechanism, 01 F10, 11 F4), and one had its severity corrected by an
  order of magnitude (T1-9). All four are corrected in place in the first pass's
  documents rather than deleted.
- **T1-9's severity error has a general shape**: the audit counted over the raw
  `routines` table while the selector already filters on goal and duration. Count
  against what the consumer can reach.
- **The `>= 3` gate broke a test whose comment named the bad row.**
  `testSelectRotatesAcrossMultipleLiftDays` documented "two full-session routines
  (#2, #10)"; #2 is a one-exercise hangboard protocol. The break was the finding.

---

## 13 — Test suite

**F1 closed.** Unit target **1019 passing**, UI target **42 passing, 0
failures**, all tap budgets on reference.

**F3 half closed.** The injury-contraindication invariant — the one deleted with
the legacy engine in `449bd8d` and the one critique 03 F1 needed — exists again
and is mutation-checked. The rest of `GeneratorInvariantTest`'s 486-cell property
grid does not.

**F4 partly closed.** Coverage added where fixes landed (season generator,
authored selector, workout diff). `CoachClient`'s spend ceiling, `RestTimerState`,
`InactivityReminderScheduler` and the four `Mini*DiffCard` views still have none.

**F2 open.** Gate 3 (`wireHistory`) is still unwritten and still the smallest
thing standing between here and the Tier 3 architecture work.

**F5 open as guidance rather than defect**: this session gated on the whole
scheme throughout, which is what the finding asked for.

### New this pass

**R2-04 (low, infrastructure) — the simulator collapse is now a known failure
signature.** Two full-suite runs this session returned 0 passed with every test
carrying `Simulator device failed to launch ... Busy ("Application failed
preflight checks")`, both caused by racing a `simctl shutdown` or a concurrent
`xcodebuild` against the run. Zero code signal, and it reads exactly like a
catastrophic regression. Triage by whether the failures carry an `XCTAssert`.
