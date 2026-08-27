---
name: phase-training2-gitignored-pbxproj
description: phase-training2 uses XcodeGen — `Project.yml` (capital P, tracked) is the source of truth and `xcodegen generate` produces `PhaseTraining.xcodeproj/project.pbxproj`. The pbxproj is gitignored (`.gitignore` line 20 `*.xcodeproj`). CI runs `xcodegen generate` before `xcodebuild`. Build numbers, new Swift files, and target config all live in `Project.yml`, not pbxproj. Sister repos phase-training and workout-plan track pbxproj directly. Trigger when working in phase-training2 and (a) about to add a new .swift file, (b) bumping the build number for TestFlight, (c) a fresh checkout build fails with missing-symbol errors that grep finds on disk, (d) editing the lowercase `project.yml` and `git add` rejects it as untracked.
when-to-use: phase-training2 only; adding files OR bumping versions OR diagnosing missing-symbol failures on fresh checkout
---

# phase-training2 is XcodeGen-managed

## How it's wired

- `Project.yml` (capital P, tracked) is the source of truth.
- `xcodegen generate` produces `PhaseTraining.xcodeproj/project.pbxproj`.
- `.gitignore` line 20: `*.xcodeproj` — the generated pbxproj never travels.
- `.github/workflows/release.yml` runs `xcodegen generate` immediately after checkout, so CI always builds from `Project.yml`.

## The recurring gotchas

**Build number lives in Project.yml.** Local pbxproj edits (e.g. `sed -i '' 's/CURRENT_PROJECT_VERSION = 106/.../'`) work for local Xcode builds but never reach CI — CI regenerates pbxproj on every run. To bump for TestFlight: edit `Project.yml`'s `CURRENT_PROJECT_VERSION: "N"`, commit, push.

**New .swift files live in Project.yml too.** Don't hand-edit pbxproj via `pbxproj-add-files-by-hand` for production work — XcodeGen picks files up from the `sources:` block (or from filesystem auto-discovery, depending on the target spec). Local hand-edits to pbxproj work until the next `xcodegen generate` blows them away.

**Case-sensitivity trap.** On macOS's default case-insensitive filesystem, `Project.yml` and `project.yml` resolve to the same file. But git is case-sensitive and tracks only `Project.yml`. If you `Read` or `Edit` with lowercase `project.yml`, the change writes correctly but `git add project.yml` errors with "did not match any files." Always use the capital P.

## Verification

```bash
ls Project.yml                                    # capital P, tracked
git ls-files | grep -i project.yml                # expect: Project.yml
grep -n xcodeproj /Users/wilburpyn/repos/phase-training2/.gitignore
# expect: 20:*.xcodeproj
grep CURRENT_PROJECT_VERSION Project.yml          # build number lives here
```

## Bumping for TestFlight

```bash
# Bump Project.yml; commit + push; CI picks up on tag or workflow_dispatch.
sed -i '' 's/CURRENT_PROJECT_VERSION: "106"/CURRENT_PROJECT_VERSION: "107"/' Project.yml
git add Project.yml && git commit -m "build: bump to 107 ..."
git push origin main
gh workflow run release.yml --ref main            # or push tag v1.1.0-107
```

The local pbxproj's CURRENT_PROJECT_VERSION is irrelevant for CI — only matters if you're archiving locally.

## Don't

- Don't `git add -f` the pbxproj — it contradicts the XcodeGen contract and will be stale by next `xcodegen generate`.
- Don't bump `CURRENT_PROJECT_VERSION` in the pbxproj alone and expect TestFlight to see it.
- Don't `Read`/`Edit` `project.yml` (lowercase) and then `git add project.yml` — git won't find it. Use `Project.yml`.
- See also `[[phase-training-xcuitest-recipe]]` for accessibility-identifier conventions and `[[xcodebuildmcp-session-defaults-cross-worktree]]` for the parallel-agent build path.
