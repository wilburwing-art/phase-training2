---
description: Read the last /next, /gaps and /spec sessions and propose edits to this repo's commands
argument-hint: [number of sessions, default 5; add "scheduled" for the weekly unattended run]
---

Review how the one-item-per-session loop has been running in this repo and
propose fixes to the commands themselves. Write no product code.

INPUT
$ARGUMENTS: a session count (default 5), optionally followed by
"scheduled". A scheduled run is unattended: write the report to
docs/retro/<YYYY-MM-DD>.md, edit nothing else, commit nothing.

STEP 1: MEASURE
One call each, from the repo root:
- `python3 ~/.claude/scripts/next-transcripts.py . <N> /next`
- `python3 ~/.claude/scripts/next-transcripts.py . 3 /gaps`
- `python3 ~/.claude/scripts/next-transcripts.py . 3 /spec`
- `git log -<N*2> --format='%h %ad %s%n%b' --date=format:'%m-%d %H:%M'`
- `gh run list -b main -L 10`
- `grep -cE '^\s*- \[ \]' docs/PLAN-gap-backlog-*.md docs/PLAN-backlog-*.md`
Read `.claude/commands/next.md`, `gaps.md`, `spec.md`, `roadmap.md`,
docs/QUEUE.md and the `## Workflow` block in CLAUDE.md. Do not open the
raw transcripts unless a summary line needs it to settle a finding.

STEP 2: CHECK EACH OF THESE AGAINST THE EVIDENCE
1. Lost findings: every "not fixed", "separately", "left it", "also found"
   or new failure named in a final message. Grep the backlog files for it.
   A finding with no backlog item is lost.
2. Waiting on the owner: every Phase 0 or "(owner decision)" line still
   open in a queued backlog, with the date its doc was added
   (`git log --diff-filter=A --format=%ad --date=short -- <doc>`) and how
   many build items it blocks. Also final messages that end on a question.
3. Queue drift: did each /next commit take the item docs/QUEUE.md order
   says it should? Name any commit that skipped ahead.
4. Test gate: did each ticked item's commit list the test classes run and
   their pass counts? Did any tick land while main CI was red?
5. Gap load: open gap items against the cap of 30 in gaps.md.
6. Rule leaks: commit trailers (`Claude-Session:`, `Co-Authored-By:`),
   em or en dashes in commit text, `git add -A`, a commit holding paths
   outside its item.
7. Cost outliers: sessions far above the median in turns, cache reads or
   minutes. Name what they spent the extra turns on, and whether a
   Sonnet lead would have done (UI or wiring item, no design).
8. Command drift: anything a session did that contradicts the repo
   commands, or that they leave unstated.
Drop any finding you cannot point at with a session id, a commit hash or
a `file:line`. If nothing changed since the last report in docs/retro/,
say "no change" with the baseline line and stop.

STEP 3: REPORT
Ranked by cost to the owner, at most five findings. Each: what happened,
the evidence, and the exact edit that fixes it (which file and the text to
add or change). Then one baseline line: median minutes, turns, output
tokens and cache reads per /next session, so the next retro can compare.
Then the owner-decision list from check 2, oldest first, one line each.

Apply nothing in this step. Interactive runs end with: reply "apply" with
the finding numbers to make the edits. When told to apply, edit the
files, test any script change on this repo, commit by named path, and say
what changed in three lines.
