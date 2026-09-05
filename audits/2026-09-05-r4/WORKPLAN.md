# Work plan for the nine NEXT.md items, 2026-09-05

Sequential, one item at a time, each landed and pushed before the next
starts. Item 1 uses a fan-out inside it, as NEXT.md scoped; everything else
is single-sitting. Work happens in a detached worktree, never in the shared
tree another session is using; each item pushes `HEAD:main` as a
fast-forward and re-fetches before the next.

Acceptance for every item: unit target green via
`scripts/quality/test-summary.sh` (fatal errors and simulator collapse count
as failures), `verify_coachdb_sync.sh` green when `db/source` moved, and the
item's own gate below.

| # | item | shape | gate |
|---|---|---|---|
| 1 | R3-11 twelve injuries, pattern rules **(done 2026-09-05)** | fan-out, 5 agents by region; lead merges | zero `contraindicated`+`rehab_early` clashes; `FilterCompositionTests` extended to the twelve and green; every row's note cites its mechanism |
| 2 | general-fitness bodyweight base + name the last 15 empty days **(done 2026-09-05: 15 -> 0)** | single | one `general-fitness` routine bodyweight-viable under all 5 test injuries; the 15 named by instrumenting the test, fixed or written down as the floor |
| 3 | R3-8 five inert weights | single, owner answers needed | each weight change deletes its `knownInertWeights` line; `test_everyFundedDemandRealizesASlot` green |
| 4 | catalog gaps: Clamshell, Side-Lying Hip Abduction, Bird Dog, Spanish Squat + `rehab_early` rows for epicondylitis, patellar tendinopathy, impingement, plantar fasciitis | single | CHECK pre-flight clean before build; rows sourced; `contradictoryInjuryRoles()` empty |
| 5 | week-shape tests for thru-hiking, mountaineering, trail-running | single | one test per sport asserting the full-gym week's shape across phases |
| 6 | wheel samples differ | single | one assertion: exercise-id sets and titles distinct across a sport's samples |
| 7 | R3-9 per-movement prescription override | single | `SportMovement` carries optional sets/reps/rest; scheme respects it; no-hang pull serves as 3 s pulls; fidelity green |
| 8 | small items R3-12, R3-13, R3-14, 08-23 header | single | estimator parses "min"; routine 70 renamed or re-tagged; PFPS rule scoped; header count fixed |
| 9 | T3-1 mountain-athlete niche briefs | fan-out, one brief per plannable sport | verbatim-or-NOT-ON-PAGE; briefs filed, not acted on (5c) |

## Item 1 contract (the agents read this)

Inputs, all in `<scratchpad>/r3-11/`: `injuries.json` (12 targets with ids),
`exercise-catalog.json` (575 exercises: id, name, movement patterns, primary
muscles, equipment), `movement-patterns.json` (pattern vocabulary with
counts), `existing-rows.json` (every row the 12 already carry, all roles).

Regions: knee (patellar-tendinopathy); shoulder (rotator-cuff-injury,
shoulder-impingement, slap-tear); elbow and wrist (tennis-elbow,
golfers-elbow, wrist-sprain); hip (hip-flexor-strain, hip-labral-tear);
spine and neck (lumbar-disc-herniation, whiplash, stinger-burner).

Each agent writes `<scratchpad>/r3-11/<region>.json`:

    { "rules": [ { "injury_slug": "...", "mechanism": "verbatim sentence from a fetched page",
                   "source_url": "...", "predicate": { "patterns": [...], "name_regex": "...",
                   "exclude_exercise_ids": [...] }, "note": "one line ending 'Sourced (mechanism), unreviewed.'" } ],
      "rehab_early": [ { "injury_slug": "...", "exercise_id": <existing id>, "source_url": "...", "note": "..." } ],
      "research": "which claim came from which URL; what was NOT ON PAGE" }

Hard rules:
1. The predicate is no wider than the mechanism sentence. If the page says
   "thumb movement and wrist deviation", the rule does not say "gripping".
2. `rehab_early` only for a movement the literature names as the treatment
   while symptomatic. `prehab` and `rehab_late` are not "safe now" and are
   not to be added here.
3. Never contraindicate an exercise that already carries `rehab_early` for
   the same injury (`existing-rows.json`); the lead's self-join will reject it.
4. Squat and hinge patterns are contraindicated only with a depth or load
   qualifier the mechanism actually states; a pattern rule cannot see depth.
5. WebFetch: verbatim or NOT ON PAGE. No number that was not read on a page.
6. No em or en dashes. No new exercises (that is item 4).

Lead: apply predicates against the catalog, dedupe, skip existing rows,
pre-flight, rebuild, run the clash query and the full unit target, extend
`FilterCompositionTests.injuries` to include the twelve, measure removed-per-
sport-pool for each injury and report it.
