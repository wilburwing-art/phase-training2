---
name: phase-training-fleet-tuning
description: Run, read and tune against the eval-rig synthetic-athlete fleet for phase-training2 (3b likelihood, PatternEngine, twin, 2a counterfactual). Covers the local loop that skips the 40-minute CI run, which knobs the fleet can honestly fit, and the two ways a fleet number looks like evidence when it is not. Trigger on "run the fleet", "tune 3b / PatternEngine / thresholds from the fleet", "fleet report", "sign agreement 0%/100%", or before writing any fitted constant into the app from a fleet sweep.
---

# Fleet tuning (phase-training2 + eval-rig)

## Local loop (minutes, not the 40-minute `fleet.yml` run)
1. eval-rig checkout: `npm ci --ignore-scripts` (Node 26 cannot build better-sqlite3; the fleet code does not need it).
   `npx tsx src/cli.ts fleet simulate -n 50 -w 26 -s <seed> --out <dir>`
2. Replay: `TEST_RUNNER_FLEET_RUN_DIR=<dir> xcodebuild test ... -only-testing:PhaseTrainingTests/FleetReplayTests/testReplayRunDirectory`
   (after `./scripts/generate-coach-secrets.sh && xcodegen generate`). A skip exits 0: count `predictions/*.json`.
3. Score: `npx tsx src/cli.ts fleet score <dir>`. Diff report sections against the previous run to prove "unchanged".
4. Sweep: `FleetLikelihoodSweepTests` (env `FLEET_SWEEP_FIT`, `FLEET_SWEEP_HOLDOUT`, `FLEET_SWEEP_FREEZE`), knobs via `SessionLikelihoodEngine.Params`. About 3 minutes per run.

CI: `fleet.yml` is manual, reads eval-rig through the `EVAL_RIG_DEPLOY_KEY` deploy key, takes `eval_rig_ref`.
`gh run list --commit <sha>` returns nothing in this repo; filter `gh run list --branch main --json headSha` instead.

## What the fleet can and cannot fit
- **Freeze any knob whose truth the simulator plants as a constant.** Every persona has `travel_attendance: 0.2`, so the sweep's travel factor 0.3 just copied that number back. Check `truth` in the athlete files before trusting a fitted value.
- Time-of-day terms cannot be fitted: the replay estimates each day from its start.
- PatternEngine thresholds cannot be fitted from v1 personas: planted habits sit far above every threshold (100% recall, 0 false). Near-threshold personas would only re-plant invented frequencies; use in-app `suggestionDecisions` instead.
- A fitted value at the edge of its grid is not an optimum: widen and re-run.

## Two numbers that are not evidence
- **0% agreement** can be real. Cross-tab app sign against `truthDelta` sign per alternative before calling the scorer broken (2a: move/shorter were exactly baseline on every row).
- **100% agreement** is circular when the app model shares the simulator's constants (`FormModel` uses readiness.ts's 42/7/gain 3). It proves the implementation only; say so wherever the number is written.

Results and shipped values live in PLAN-next-gen.md ("Fleet baseline", "3b tuned", item 4). Readiness split: [[phase-training-personalization-two-axes]].
