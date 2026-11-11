---
name: phase-training2-long-branch-merge-checks
description: Checks to run before trusting a merge of main into a long-lived phase-training2 feature branch (weeks behind, 100+ commits). Trigger on "merge main into my branch", "resolve conflicts", a branch whose merge-base is weeks old, or a build after such a merge failing with hundreds of "cannot find type" / "is ambiguous for type lookup" errors.
---

# Long-lived branch merge checks (phase-training2)

Found 2026-11-10 on `weekly-coach/goal-templates`. Its merge-base was 2026-09-10,
so the merge pulled in 206 commits from main. The merge commit `eb672c7` was
labeled "resolve conflicts" and built with 332 errors.

## 1. Conflicted files truncated or resolved to the stale side

Run this check for every Swift file. Compare each file's line count to main's
version and flag files with no trailing newline:

```sh
for f in $(git ls-files '*.swift'); do
  [ -n "$(tail -c1 "$f")" ] && echo "$f $(wc -l <"$f") vs main $(git show "MERGE^2:$f" 2>/dev/null | wc -l)"
done
```

In this case the check flagged `TrainingMemory.swift` (371 lines vs 975 on main).
The lost lines defined `Sport`, `SeasonPhase`, `Gender` and `Equipment`, so most
of the 332 errors came from that one file. `ProgressScreen.swift`,
`ProgressScreen+ExerciseCards.swift` and `UserDatabase+Sessions.swift` were also
cut short.

## 2. Types main moved to `Shared/`

`ActiveSession` and `SavedSession` moved to `Shared/Models/SessionModels.swift`
for the watch (PLAN-watch.md). If the branch's copy in `PhaseTraining/Data/Session.swift`
survives the merge, every use reports "ambiguous for type lookup". Keep only
main's copy, then re-apply the branch's added fields to it.

## 3. SQLite migration version collision

Each entry in `UserDatabase.migrations` is `(version, statements)`, stamped
with `PRAGMA user_version`. Main was already at v5 or later. The branch also
added a migration numbered v2. Installed builds are already past v2, so they
never run the branch's v2, and the new column (`session_tags`) is never
created. Renumber the branch's migration to the next free version and
update `UserDatabaseMigrationTests`.

Any new `ALTER TABLE ... ADD COLUMN` migration also breaks the upgrade
fixtures. `ExploreSessionTests.test_migration_v1FileGainsTheTable_andKeepsItsData`
and `SessionExerciseHintsPersistenceTests.test_v6File_upgrades_...` open a fresh
DB (which already has every column), DROP each later column, then stamp an old
`user_version`. If the fixture doesn't also drop the new column, the ALTER fails
with "migration vN failed". Add a `DROP COLUMN` line to both fixtures. v8
(`session_tags`) shipped in build 169 without this and went unnoticed, because
the release workflow does not run unit tests. Run `PhaseTrainingTests` in full
before tagging.

## 4. Duplicate methods across extension files

Main splits screens into `+Cards` extension files. When a method was moved
into an extension file and the old copy was also kept, the build fails with
"invalid redeclaration". In this case it was `loadSkiSeason()`, defined in
both `ProgressScreen.swift` and `ProgressScreen+SkiCards.swift`.

## Replay notes (verified 2026-11-10, goals landed as d2340e9)

- On each conflict, `git checkout --ours` (main's side), then re-apply only the
  feature's added lines. Read `git show <sha> -- <file>` for what those are.
- A field added to `Shared/Models/SessionModels.swift` `SavedSession` needs a
  tolerant `init(from:)` in a same-file extension. Synthesized Codable throws on
  a missing non-optional key, and putting the init in an extension keeps the
  memberwise init that the watch uses.
- Main was at migration v7, so the branch's v2 became v8. Main's migration tests
  assert `latestSchemaVersion`, so take main's copy of the test file.
- Sport logs on ProgressScreen come from the `sportLogStore` environment object,
  not `planStore.sportLogStore`.
- Skip a branch commit that main already made independently (`--skip`).
- A PreToolUse hook blocks `git branch -D`. Hand the force-deletes to the user
  as a `!` command.

## Prefer replaying over patching

If any of checks 1 to 4 finds a problem, do not fix the merge commit file by
file. Branch from current main and cherry-pick the feature commits onto it.
Renumber the migration, build with XcodeBuildMCP `build_sim`, then run the
feature's test classes.

## Before any push to main: run the two CI setup lints locally

`.github/actions/ios-setup/action.yml` runs two checks before it builds, and a
failure there ends both the unit and UI jobs in about 20 seconds with no test
output (2026-11-11: an 18-commit push failed this way).

```bash
bash scripts/db/verify_coachdb_sync.sh      # refuses uncommitted db/source edits
bash scripts/quality/verify_font_tokens.sh  # any .font(.custom( outside Theme/Typography.swift
```

The font lint failure was a September line, and the scheduled run on the
previous commit was already red on it, so check `gh run list --branch main
--workflow test --limit 3` for a red baseline before blaming your own diff.
