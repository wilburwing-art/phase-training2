---
name: phase-training-xcodebuild-test-failed-grep-full-log
description: When `xcodebuild test` on a phase-training-family iOS app prints `** TEST FAILED **` but a `tail` of the output shows the UITest target with "0 failures", the real failures are in the earlier-printed PhaseTrainingTests UNIT target and scrolled off. Also covers a run where ZERO tests executed because the test host could not launch — typically because the session was driving the same simulator with simctl at the time. Don't trust the tail — capture the full log to a file and grep it. Also covers the missing-iPhone-16-simulator destination gotcha and the ProfileFieldCoverage "new TrainingMemory field needs a probe" unit gate. Trigger when a phase-training / phase-training2 / workout-plan `xcodebuild test` run is red but the visible summary looks green, or when picking a simulator destination for these repos.
when-to-use: Running `xcodebuild test` for a phase-training-family scheme and the result is `** TEST FAILED **` despite the tail showing a passing suite, or choosing a `-destination` and `iPhone 16` isn't installed.
---

# phase-training2: TEST FAILED but the tail looks green

## What actually happened
`xcodebuild test -scheme PhaseTraining` ended in `** TEST FAILED **`, but `... 2>&1 | tail`
showed the `PhaseTrainingUITests` target with **29 executed, 0 failures**. The failures were
real — they were just in the `PhaseTrainingTests` *unit* target, whose suite summaries print
BEFORE the UITest target and scroll out of a `tail` window. `tail` lies here.

## The recipe
1. Run xcodegen first (pbxproj is gitignored/generated): `xcodegen generate`
2. **No `iPhone 16` simulator is installed.** `-destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'`
   errors with "Unable to find a device". Use what's present — `name=iPhone 17,OS=26.4.1` — or list
   them: the error output itself prints every available destination. Don't keep retrying iPhone 16.
3. Capture the WHOLE log, then grep — never diagnose from `tail`:
   ```
   xcodebuild test -scheme PhaseTraining -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' 2>&1 > /tmp/pt_test.log
   grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" /tmp/pt_test.log
   ```
   That surfaces the exact `Test Case '...' failed` lines + file:line of each `XCTAssert`.

## The inverse: a huge failure COUNT with no per-assertion detail = simulator flake

2026-08-25, mid-Tier-2. A run reported **"972 tests, 153 failures"** — and the
grep above came back completely empty: no `: error:`, no `Test Case '...'
failed`, nothing. The only anomaly anywhere in the log was
`IOSurfaceClientSetSurfaceNotify failed e00002c7`. Two clean re-runs gave 972 /
0 failures / `** TEST SUCCEEDED **`.

**A real failure always leaves a trail.** 153 failures with zero
`Test Case ... failed` lines is arithmetically impossible for genuine
assertions — it's the simulator dying and the harness attributing it to the
tests. So:

- The grep returning NOTHING on a red run is itself the diagnosis. Don't start
  bisecting your diff; the failure isn't in it.
- Confirm at the suite level, which is the field that actually reflects
  reality: `grep -E "\*\* TEST (SUCCEEDED|FAILED) \*\*" /tmp/pt_test.log`
- Re-run before believing either verdict, and re-run **twice** before committing
  on the strength of a green that followed a red — one clean run after a flake
  is not evidence of stability.
- Tell the user the run flaked rather than quietly re-running until green. A
  suppressed red is indistinguishable from a suppressed regression.

This is the mirror image of the section above: there, `tail` hid real failures;
here, the summary count invented failures that were never there. Both mean the
same thing — **the count is not the evidence, the per-assertion lines are.**

### …but assertion lines are NOT proof it's real either (correction, 2026-08-26)

The rule above, taken literally, would have sent me bisecting a clean diff the
very next day. A run reported **67 failures with 20 genuine
`Test Case ... failed` lines** — so by "lines present ⇒ real", it was mine. It
wasn't. Every one of the 20 read:

```
XCTUnwrap failed: expected non-nil value of type "Exercise"
  - coach.db must have horizontal-push exercises
```

That's the **bundled catalog not loading into the test host** — a resource
failure that trips a shared precondition in ~20 tests at once. Two re-runs on
the byte-identical tree: 972 / 0 / `** TEST SUCCEEDED **`.

So this suite has **two** distinct flake shapes, and the count/lines heuristic
separates only the first:

| Shape | Count | Assertion lines | Tell |
|---|---|---|---|
| Simulator death | large (153) | **none** | `IOSurfaceClientSetSurfaceNotify` |
| Bundle/catalog not loaded | medium (67) | ~20, **all identical** | every message is a *resource precondition* (`coach.db must have…`), not business logic |
| Test host never launched | **zero** (`Executed` absent) | none | `Failed to send signal 19 to process`, `IDELaunchReport ... Finished with error` — usually self-inflicted, see below |
| Real regression | usually small | varied | messages differ, and they name YOUR behavior |

**Read what the assertions say, not just that they exist.** If they all fail on
the same fixture/resource precondition and none names logic you touched, it's
infrastructure — re-run before diagnosing. If the messages are varied and
describe behavior, it's yours: fix it, don't re-run for a green (that happened
too, same day — 8 failures across 5 tests from a constant-vs-parameter gate,
genuinely mine, fixed properly).

## Don't touch the simulator while a test run is in flight (2026-08-29)

`** TEST FAILED **` with **no `Executed N tests` line anywhere in the log** and:

```
DTServiceHub - Error resuming pid NNNNN 'Failed to send signal 19 to process NNNNN: 3'
IDELaunchReport: ...:Launch PhaseTrainingTests Finished with error
```

Zero tests ran. The test host could not launch, because the same session was
running `xcrun simctl terminate/install/launch` against the SAME simulator to
grab screenshots while `xcodebuild test` was starting up. Self-inflicted, and it
reads exactly like a red suite.

- **The tell is the absence of `Executed`**, not the error text. Every other
  shape in the table above still reports a count. `grep -c "Executed [0-9]* test"`
  returning 0 on a red run means nothing was measured at all.
- Serialize sim work: finish the test run, THEN screenshot. Or point the test at
  a different `-destination` than the one you are driving by hand.
- Never report this as a failure or as a pass. Nothing was measured; re-run
  clean and report the re-run.

The same collision corrupts the reverse direction: a `simctl install` landing
mid-test can leave the wrong binary installed for later manual checks.

## Known failure shapes in this repo
- **Compile gate before any test runs:** a `@ViewBuilder func -> some View` called with `if let x = f()`
  fails as "initializer for conditional binding must have Optional type, not 'some View'". The builder
  already emits `EmptyView` for its nil case — call it directly, drop the `if let`. (Hit in `LogScreen.swift`.)
- **`ProfileFieldCoverageTests.test_everyTrainingMemoryFieldHasAProbe`:** any new `TrainingMemory` field
  fails this unless you either (a) wire it into `planInputsHash` + `CoachContext.snapshot` and add a probe
  with both mutators, or (b) add a probe with nil mutators + a `skipReason`. The test message spells out both.
- **`PlateMathTests`:** assertions encode a specific plate inventory; if the `imperial`/`metric` set changes
  (e.g. a 1.25 plate drops), `achieved`/`remainder` drift and the test goes red against the new inventory.
