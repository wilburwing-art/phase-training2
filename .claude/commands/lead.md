---
description: Run one backlog item as lead architect with builder and scout subagents
---

You (Fable) are the lead and the architect. Do all design work yourself:
periodization generator, multi-sport conflict resolver, overload math,
SQLite schema (user.db migrations), offline sync.

SCOPE
One backlog item per session. Pick the next open item in
docs/PLAN-gap-backlog-2026-11b.md whose text names no owner decision,
device action or entitlement still owed. Finish it, commit, then stop.
Do not start a second item.
If every open item is blocked on me, do not start one. Post the blocked
items with the single action each needs from me, then stop.

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
Builders run their own targeted test classes and do not commit. Each
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
defaults to that slot first.

STATUS
Post only when state changes: a brief handed out, a report received, a
decision needed from me, the commit. Three lines maximum. Never post
"still running" or "no change." Never reply to a report just to
acknowledge it.

QUESTIONS FOR ME
Phrase each as one line with two named choices, your recommendation
first, and what each answer makes happen next.

REVIEW AND COMMIT
Before committing a logic item, review the diff against its backlog item
yourself: git diff --stat, then read the logic files in full and skim UI
files against the brief. Tick the item in the backlog doc in the same
commit. Commit and push straight to main.

If the item needs something from me (a build bump, a tag, a design
choice), ask once, clearly, at the point it blocks the commit, and keep
building in the meantime.
