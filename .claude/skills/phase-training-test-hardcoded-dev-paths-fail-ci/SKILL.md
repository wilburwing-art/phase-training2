---
name: phase-training-test-hardcoded-dev-paths-fail-ci
description: >
  phase-training-family test suites contain dev-only tests that write to or read
  from hardcoded /Users/wilburpyn/... absolute paths (eval-rig workout exports,
  Fitbod CSV imports). On a CI runner home is /Users/runner, so the path is
  absent: a `try?` createDirectory silently no-ops and the next file write dies
  with `NSCocoaErrorDomain Code=4 … mktemp failed … errno Optional(2)` (ENOENT).
  Fix is XCTSkipUnless on the path's existence, NOT deleting the test.
when-to-use: >
  A phase-training / phase-training-design / workout-plan CI `test` job fails with
  mktemp / errno 2 / NSCocoaErrorDomain Code=4, or a test name like
  test_export_batch_* / *Fitbod* / *eval-rig* fails only on CI (passes locally).
  Also proactively when adding a test that writes into ~/repos/eval-rig or reads
  ~/Downloads. Pairs with [[ci-red-attribute-before-blaming-merge]] (diagnosis)
  and [[read-branch-files-via-worktree]] (sandbox log extraction).
---

# Hardcoded dev-machine paths in phase-training tests → CI mktemp ENOENT

## What happened (2026-05-31, phase-training2)
`EvalRigExportSmokeTest.test_export_batch_older_male_bodybuilding_upper_push` and
`…_gen_z_science_based_upper_push` failed on every CI run (not just the latest —
they were red on the 2026-05-29 runs too). Root cause:

```swift
let outDir = URL(fileURLWithPath: "/Users/wilburpyn/repos/eval-rig/workouts/\(batchDir)")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) // no-ops on CI
try data.write(to: url, options: .atomic)  // .atomic → mktemp in a missing dir → errno 2
```
The file header literally said "Skip in CI; this is a development-time tool" — but
nothing skipped it. These dump batches into the sibling eval-rig repo for grading.

## The fix (matches the repo's own FitbodRealCSVSmokeTests convention)
Guard at the top of the test/helper, before any work:
```swift
let evalRigRoot = "/Users/wilburpyn/repos/eval-rig/workouts"
try XCTSkipUnless(
    FileManager.default.fileExists(atPath: evalRigRoot),
    "eval-rig workouts dir not present — dev-only batch export, skipping")
```
Do NOT delete the test — it's a real dev tool on the author's machine. Skip,
don't gate. `XCTSkip*` reports as "skipped" (yellow), not failure.

## Known hardcoded paths in the suite (audit these when CI is red)
`git grep -n "/Users/wilburpyn" -- 'PhaseTrainingTests/*.swift' 'PhaseTrainingUITests/*.swift'`
- `EvalRigExportSmokeTest.swift` → eval-rig/workouts (write) — fixed
- `FitbodRealCSVSmokeTests.swift` → ~/Downloads/FitBodWorkoutExport.csv (read) —
  already guarded with XCTSkip + FITBOD_CSV_PATH env fallback (the template to copy)

## The other half of a red phase-training run is usually a flake
XCUITests on iOS 26 fresh-boot CI runners flake (Menu accessibility, picker-row
taps under idle-wait). The file already disables ~5 via
`try XCTSkipIf(true, "Disabled until iOS 26 fresh-boot XCUITest flake is resolved")`.
A test green on the PR-branch run but red post-merge = flake; skip it the same way.

## Sandbox gotchas seen here
`gh run view --job <id> --log | grep` returns mangled/empty in this sandbox —
redirect to a repo file and open with Read. zsh ate `--include=*.swift` globs —
use `git grep -- '*.swift'` instead. `.derived/` is gitignored Xcode DerivedData.
