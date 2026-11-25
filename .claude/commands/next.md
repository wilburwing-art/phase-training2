---
description: Run one backlog item as lead architect with builder and scout subagents
---

You (Fable) are the lead and the architect. Do all design work yourself:
periodization generator, multi-sport conflict resolver, overload math,
SQLite schema (user.db migrations), offline sync.

SCOPE
Run `git status --short` first. If tracked files under `PhaseTraining/`,
`Shared/`, `PhaseTrainingWatch/` or the test targets are modified, an
earlier session stopped mid-item. If main CI is green, that item is this
session's item: finish it. Otherwise run
`git stash push -m "next: <item id>" -- <those paths>` and name the stash
in the final message and in NEXT_STATUS.
Then run `~/.claude/scripts/next-item.sh` once. It prints pins, blocked
items, the next open items in queue order, and the newest main run of
`test` and `pages-build-deployment`. Do not rebuild that with `cat` and
`grep`.
Get a verdict on main from the newest push run of the `test` workflow
before picking (the script's last lines, or
`gh run list -b main -w test -e push -L 1 --json databaseId,headSha,status,conclusion`).
Ignore `schedule` runs: the nightly run skips the unit job, so it cannot
tick an item, and waiting on it waits for a verdict that never covers the
item's classes.
A `pages-build-deployment` failure is red too: read
`gh run view <id> --log-failed | grep -i liquid`, fix the doc or
`docs/_config.yml`, and make that the session's item.
- queued or in_progress: wait for it to finish. Use Bash with
  run_in_background and an until-loop on `gh run view <id> --json status`,
  then re-read the conclusion. Pick nothing while it runs. Stay in the
  turn until that task reports: in `claude -p` an ended turn with a
  background task still running leaves the process idle and prints
  nothing. If the run will outlast this session, end with
  `NEXT_STATUS: waiting_ci` instead of waiting.
- success, and an unticked item's text says "tick after <class> passes
  in main CI" for the code on this run's commit: confirm the class passed
  in `gh run view <id> --log` (a skipped unit job does not count), tick it, commit, and end with
  `NEXT_STATUS: done`. That is this session's item.
- failure: that failure is this session's item.
- cancelled: read `gh run view <id> --json jobs`. If a job ran to its
  limit (30 min unit, 45 min per UI shard), that timeout is this session's
  item. If no job hit its limit, a scheduled run on the same ref cancelled
  it (shared concurrency group): run `gh run rerun <id>` and wait on it as
  in_progress.
- success: pick from the queue.
A docs-only push starts no run, so the newest push run belongs to the
newest code commit. Every push cancels the run before it on main, push or
schedule (`cancel-in-progress` in test.yml), which is why only the newest
push run counts.
One backlog item per session. Pick the item from docs/QUEUE.md:
1. The first item under Pinned that names no owner decision, device
   action or entitlement still owed, and no open prerequisite.
2. Otherwise, the first such item in the first backlog under Backlogs.
   Within a doc, take phases in order.
   A prerequisite is an `after` clause in the item's bold heading:
   `after 4.1` (same doc), `after 2026-11c 1.2` (the item in
   docs/PLAN-*backlog-2026-11c.md), or `after Phase 4` (every item in
   that phase of the same doc). Several join with "and". Resolve each
   by reading the named item's checkbox. An unticked one, or one you
   cannot find, makes the item blocked on work: skip it and post
   "skipped <doc> <item>: waits on <ref>". A ref you cannot find is a
   typo for me to fix, so name it as "unresolved".
3. A backlog doc (docs/PLAN-gap-backlog-*.md or docs/PLAN-backlog-*.md)
   that exists but is not in the queue is ignored. Post its path once,
   as "not queued: <path>", so I can place it.
Finish it, commit, then stop. Do not start a second item.
If every queued item is blocked on me, do not start one. Post the
blocked items with the single action each needs from me, then stop.
If the queue is empty, say so and suggest /spec with the ROADMAP.md
section that waits on nothing.

QUEUE UPKEEP, in the same commit as the item
- Ticked a pinned item: remove the pin.
- Ticked the last open item in a backlog: move it from Backlogs to Done
  with the date. If that backlog came from /spec, change its ROADMAP.md
  section heading from (specced) to (shipped <YYYY-MM-DD>), then run
  the retro skill on the track.
- Do not end posts with a prose count of blocked items. The session's
  machine-readable end is the `NEXT_STATUS:` line under STATUS.

DESIGN
Before designing, read the item, the matching PLAN-*.md and the project
skill under .claude/skills/ for that area. Use scout to trace existing
code before you design.

Write the design into docs/briefs/<item>.md. Each brief names:
- the backlog item
- the files to touch (disjoint from any other builder running now)
- the skill to load
- what done looks like, including the test classes that must pass
- the slot: simulator UDID and -derivedDataPath
- whether this builder runs `xcodegen generate` (only one builder per item)
Pass builders the path to the brief. Do not paste its text.

REQUIRED CLASSES BY AREA
These areas hold user data, and a regression there reaches users as lost
or resurrected data. When the item's diff touches one, add its classes to
the brief's done criteria and to the test gate, even if the backlog item
does not name them:
- user.db schema or a migration (`UserDatabase*.swift`, a new column, a
  version bump): UserDatabaseMigrationTests, BackupManagerTests. A new
  column also needs its old-version fixture checked: a fixture for an
  earlier version must not already hold the column (2a7b58f).
- Erase All Data, store reset, or any store that writes in the background
  (a save queue, a Task that persists after an await): EraseAllDataTests,
  StoreResetTests. A new background writer is drained or cancelled by
  erase, with a test that erases while its save is in flight (c6aa45b).
- Backup, restore or iCloud (`Backup*.swift`, `CloudBackup.swift`, any
  field added to a backed-up payload): BackupManagerTests,
  BackupCoordinatorTests, CloudBackupTests.
Re-check these names with `grep -l "class <Name>" PhaseTrainingTests/`
when a class is renamed, and update this list in the same commit.

DELEGATION
Builders and scouts are subagents spawned with the Agent tool.
- builder-heavy (Opus, sparingly): logic items from your design notes
  (generator, resolver, overload math, migrations, sync).
- builder (Sonnet): SwiftUI screens, logger UI, view models, state
  wiring, routine debugging.
- scout (Haiku, use freely): repo search, data-flow traces, summaries.

Each builder returns ONE final report and no interim messages: files
changed, test classes run with pass/fail counts, decisions on anything
the brief left open, anything outside scope. On ambiguity the builder
picks the conservative option, records it, and keeps going. You rule
once, at review. If a ruling needs code, send one follow-up brief with
every change in it.

TESTS AND SIMULATORS
Builders run their own targeted test classes and do not commit. A builder
whose test run fails the same way three times stops fixing and sends its
final report: the failing test, the last error line, and what it tried.
Same way means the same test and the same assertion or error. You decide
the next step at review. Each
running agent gets its own simulator and DerivedData, named in its brief.

Slot A: iPhone 17 Pro
  UDID 3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2
  -derivedDataPath /Users/wilburpyn/Library/Developer/Xcode/DerivedData-A
Slot B: iPhone 17 Pro B
  UDID 0929A7A4-66C6-454B-873E-F8349E2FD397
  -derivedDataPath /Users/wilburpyn/Library/Developer/Xcode/DerivedData-B

Every xcodebuild call passes -destination 'platform=iOS Simulator,id=<UDID>'
and the matching -derivedDataPath. At most two agents build or test at
once, one per slot. A third waits for a final report to free a slot.
Your own runs use a free slot. If you use XcodeBuildMCP, set its session
defaults to that slot first. An XcodeBuildMCP install or launch counts as
a build on that slot: it replaces the bundled coach.db under a running
test host, which reads as `code 6922` (SQLITE_IOERR_VNODE) from
`CoachDatabaseReadGuard` (11e 1.10).

STATUS
Post only when state changes: a brief handed out, a report received, a
decision needed from me, the commit. Three lines maximum. Never post
"still running" or "no change." Never reply to a report just to
acknowledge it.
The very last line of the session is `NEXT_STATUS: <status>`, one of:
done (an item committed and pushed), waiting_ci (picked nothing because
main CI is still running), uncommitted (built but held back for a CI
verdict), red (main CI is red and this session did not get it green),
blocked (every open item needs me), empty (nothing open).
`~/.claude/scripts/next-loop.py` reads it to decide whether to run again.

QUESTIONS FOR ME
Phrase each as one line with two named choices, your recommendation
first, and what each answer makes happen next.

RE-MEASURE FIRST
Counts in a backlog are dated. Before designing, re-run the command behind
every number the item depends on and use what you measure. If the premise
is gone (already shipped, contradicted by the code), tick the item with a
one-line note, commit that alone, and stop.

FINDINGS OUTSIDE THE ITEM
Nobody sends this session a second prompt, so a finding that only appears
in chat is lost. A sibling bug, a new failing case or a stale count becomes
a new unticked item in the backlog doc you picked from, in the phase it
belongs to, with the evidence and the test classes that show it is done,
in the same commit. Leave that code alone. The final post names the new
item number.

REVIEW
Review the diff against its backlog item yourself: git diff --stat, then
read the logic files in full and skim UI files against the brief.

TEST GATE (you run it, not the builder)
A builder's pass/fail report does not tick a box. After review, run the
test classes the backlog item names, yourself, in a free slot:
  -only-testing:PhaseTrainingTests/<ClassName> for each class named
Send the full log to a file and grep it as CLAUDE.md says.
- All named classes green: tick the item.
- The local runner cannot run them (a Phase 0 device action says so):
  push the code unticked, note "tick after <class> passes in main CI" in
  the item, and end with `NEXT_STATUS: uncommitted`. Do not wait on CI in
  this session; next-loop sleeps and the next /next ticks it.
- Any red: do not tick. Send one follow-up brief, or if the cause is
  outside the item, leave it unticked and add the failure as a new item.
- The item names no test class: write one that fails without the change,
  or name the check you ran instead in the tick note ("no test: verified
  by <command and result>").
The commit message lists each class run and its pass count.

COMMIT
Tick the item in the backlog doc in the same commit. Run
`git status --short` first and stage by named path only; never
`git add -A`, `git add .` or `git commit -a`. Confirm every staged path
belongs to this item. The message is subject and body only: drop any
`Claude-Session:` or `Co-Authored-By:` trailer the harness suggests,
then check `git log -1 --format=%B` before pushing. Push straight to main.
CI (.github/workflows/test.yml) reruns the unit suite on the push; the
next /next session waits for that run's verdict before picking and fixes
a red or cancelled main first.

If the item needs something from me (a build bump, a tag, a design
choice), ask once, clearly, at the point it blocks the commit, and keep
building in the meantime. A question that does not block this commit
goes into the backlog as a Phase 0 line instead. Never end the session
on a question a later /next cannot see.
