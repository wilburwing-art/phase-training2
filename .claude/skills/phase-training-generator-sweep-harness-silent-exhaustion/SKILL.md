---
name: phase-training-generator-sweep-harness-silent-exhaustion
description: >
  The phase-training2 generator sweep (GeneratorSweepReportTest /
  scripts/generator-sweep.sh) can INTERMITTENTLY emit a report where most
  variant columns render "0 ex" and the summary fills with ⚠ UNEXPECTED/SCOPE
  flags — this is a flaky empty-catalog read under the xcodebuild runner, NOT a
  WorkoutGenerator regression. A re-run clears it. Trigger when reading sweep
  output with many empty variant days or a wall of anomaly flags, or when the
  test fails with "intermittent empty-catalog flake". Skip for the
  fixed-seed/expectsChange/scope mechanics (that's
  phase-training-generator-sweep-report).
when-to-use: a generator-sweep report whose variants are mostly empty / drowning in anomaly flags, or the test's empty-catalog-flake failure
---

## What it is (verified 2026-06-09)
INTERMITTENT, not deterministic. Run 1 of the sweep produced 213 empty
day-lines (most variants `0 ex`) and ~19 anomaly-flagged variables. An
identical re-run (run 2) was 100% clean: 0 empty day-lines, 2 flags, every
control variant matching baseline. Same code, same commit. So a sweep report
full of empties + UNEXPECTED/SCOPE flags is a FLAKED RUN — re-run before
believing any finding in it.

## Root cause
Transient empty reads from the bundled `coach.db` under the xcodebuild
simulator runner — exactly the "intermittent '0 exercises returned'" symptom
`CoachDatabase.init` documents (and tries to beat with an open+verify retry
loop). It can strike AFTER init's verify passed, mid-run. In a clean run the
catalog reads healthy (`listExercises().count == 572`, `dbOpen == true`
throughout). The connection is fine (single READONLY+FULLMUTEX handle, opened
once, balanced prepare/finalize) — the reads just transiently come back empty.

## The trap that wasted an hour
The report's BASELINE column is captured once early (`baseA.primaryWeek`,
~test:247) while every VARIANT column is generated live later. So during a
flake the baseline stays healthy in every section while live variants go empty,
and the diff then flags those empties as UNEXPECTED (control "moved") / SCOPE.
Do NOT read that as "the generator broke N axes" or "cumulative state
corruption" — I built a whole positional-onset theory off ONE flaky run and it
was wrong. Re-run first; the signature reproduces only ~half the time.

## The fix that landed
`test_generate_sweep_report` now self-guards: after assembling sweeps it counts
empty variant-days and `XCTAssertLessThan(emptyFrac, 0.10, ...)`. A healthy run
is 0% empty; a flake is ~60%. So the flake now FAILS LOUDLY ("intermittent
empty-catalog flake … re-run") instead of writing a green, misleading report.
If you see that assertion fail: just re-run `scripts/generator-sweep.sh`. If the
test passes, the report is trustworthy.

## To diagnose if it ever changes
Temporarily log, in `generateWeek`, a global call counter + `day0 ex count` +
`CoachDatabase.shared.listExercises().count` + `.isOpen`. If catalogCount stays
healthy while day0 goes empty, it's the read flake; if catalogCount drops, the
handle died (different bug). Remove the instrumentation after.
