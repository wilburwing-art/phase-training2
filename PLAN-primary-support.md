# PLAN — Primary/Support model (two-sport de-confliction)

Status: vision locked 2026-07-13. This is the launch differentiator and the Pro gate.

- **Phase 1 (done 2026-07-13)** — models + SupportScheduler + rules table:
  `Data/SportSeason/SupportPattern.swift`, `SupportScheduler.swift`,
  `PhaseTrainingTests/SupportSchedulerTest.swift`.
- **Phase 2 wiring (done 2026-07-14)** — the pattern now reflows a REAL week:
  `TrainingMemory.supportPattern` (Codable + in planInputsHash),
  `SupportScheduler.deconflictInPlace` (fixed-weekday, lighten-only app entry),
  `Planner.applySupportPattern` (step 6.6; supersedes the crude
  `applySecondarySportPromotion` for the support sport). Lightened lift days +
  stamped support days write into `generatedReason`, which WeekScreen already
  renders — so the "why it moved" surfacing is free. 24 support tests + 112
  affected-suite tests green.
- **Phase 2 UI (done 2026-07-14)** — `SupportSportEditorSheet` (Profile →
  "Support sport" row): None/Climbing enable, discipline chips (sport/boulder/
  trad-alpine), a 7-weekday × magnitude grid, all store-derived like
  SeasonsEditorSheet. `SupportSportUITests` drives it end-to-end + screenshots
  (green, verified visually). Row summary "Climbing · N days".
  Remaining polish: gate the row to ski/snow-primary users (currently shown to
  all); dedicated week-view badges beyond the reason text.
- **Follow-up** — consolidate: once the SupportPattern UI ships, deprecate the
  crude `applySecondarySportPromotion` placeholder path entirely.

## Problem

For a high-level two-sport athlete, "what season is it?" has no single answer. Sport A's
off-season overlaps Sport B's in-season: a splitboarder who climbs hard spends June–October
needing an off-season *build* for snow while carrying real in-season *load* from rock. Every
competitor (TrainingPeaks, MTI, Uphill Athlete, all authored plans) assumes one sport's
calendar, so the athlete either gets buried (build ignores climbing load) or shows up to
winter untrained (abandons the build). The 2026-04-24 competitive scan found this framing
replicated nowhere; it still isn't.

The engine shares the flaw today: `AthleteState` (Data/SportSeason/AthleteState.swift:41)
carries exactly one `season: SeasonPhase`. Two concurrent phases are unrepresentable.

## Vision (locked decisions)

1. **Exactly 2 sports, asymmetric roles.** Primary gets the periodized plan. Support is
   in-season and gets NO plan — it enters as a **declared weekly pattern** ("climb Tue/Thu,
   alpine day Sat"), each day tagged light/medium/big. No Strava/calendar import in v1.
2. **Wedge market: splitboard/ski primary + climbing support.** Primary variants:
   `.backcountry`, `.skimo`, `.inbounds`. Support variants: `.sportRoute`, `.boulder`,
   `.tradAlpine`. Conflict rules authored from the owner's real experience (shralpinism),
   not guessed generics. Other combos later.
3. **Pro gate.** Support-sport de-confliction IS the Pro subscription feature (existing
   PhaseTraining.storekit). Authored spines sold as IAP become support-aware when Pro.
4. **No open generation re-opened.** The engine's new job is *de-confliction, not
   generation*: place/adjust the primary plan's sessions around declared support load.
   Adaptive layer stays parked. The layer must work for generated weeks now AND authored
   spines (shralpinism import) later — design it against `[GeneratedWorkout]`, not against
   the generator.

## Done means

- Onboarding lets the user pick a primary sport (gets phases) and optionally a support
  sport with a weekly pattern (day + light/medium/big).
- A generated week places nothing that collides: no heavy lower-body session within 48h
  before a `big` support day; intensity sessions land furthest from big support days;
  support days consume fatigue budget (extend `enforceFatigueCap`); collision weeks
  downgrade via `lighten()` rather than skip.
- Editing a support day re-flows the week deterministically (same djb2 seeding discipline).
- Non-Pro users see the support-sport UI teased but gated.
- `SeasonFidelityTest` extended with two-sport fixtures: splitboard-offseason ×
  climb-inseason week asserts every rule above.

## Implementation sketch (anchored to current types)

- New value types in `Data/SportSeason/`: `SupportPattern` (weekday → `SupportMagnitude`
  light/medium/big) and `SupportDay`. `AthleteState` gains `support: SupportPattern?`;
  `season` stays primary-only.
- New `SupportScheduler` (sibling to `SportSeasonGenerator`): takes
  `[GeneratedWorkout]` + `SupportPattern` → day-assigned, adjusted week. Rules table
  keyed by (primary `SportVariant`, support `SportVariant`, `SupportMagnitude`) —
  PhaseRule.swift's variant `switch` (lines ~198–212) is the pattern to follow.
- Fatigue: give each `SupportMagnitude` a `fatigueCost` so support days flow through the
  existing `enforceFatigueCap` accounting instead of a parallel budget.
- Onboarding: extend `OnboardingSportsScreen` with role selection + pattern picker.
- Out of the generator's way: `generateWeek` unchanged; scheduling is a pure post-pass.

## Out of scope (v1)

3+ sports · dual-primary · Strava/calendar import · prescribed support maintenance
sessions · adaptive/readiness layer (parked) · coach features · generic sport combos
beyond ski/board × climb.

## Sequence to ship

1. Models + `SupportScheduler` + rules table + tests (pure Swift, no UI).
2. Onboarding + week-view surfacing (badge support days, show why a session moved —
   explainability sells the feature).
3. Pro gate wiring.
4. TestFlight build; App Store copy leads with "the only training app that knows you
   have two sports."

## Executing-session notes

- New .swift files register in `Project.yml` (XcodeGen; pbxproj is gitignored) — see
  skill `phase-training2-gitignored-pbxproj`.
- Read skills `phase-training-season-aware-generator-reuse-map`,
  `phase-training-season-engine-add-a-sport`, and
  `phase-training-season-generator-engine-pitfalls` before touching the engine.
- Per `phase-training-overrides-persist-intent-not-output`: persist the declared
  `SupportPattern` (intent), never the scheduled week (output) — re-derive on regen.
- Test invariants by behavior, not canonical exercise names
  (`phase-training-test-by-coverage-not-canonical-name`); add metamorphic cases via
  `phase-training-generator-invariant-metamorphic-test` (e.g. upgrading a support day
  light→big must never move intensity CLOSER to it).
