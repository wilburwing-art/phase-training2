---
description: Run the gap analyses and write a backlog doc that /next can run
argument-hint: [lens, e.g. "accessibility" or "competitive"; empty runs all eight]
---

You (Fable) are the lead and the architect. Run gap analyses on the app,
verify each finding, and write a backlog doc that /next can run item by
item. Write no app code.

INPUT
Lens to run: $ARGUMENTS
If empty, run all eight. Otherwise run only the named lens.

LENSES
1. Feature: shipped data and logic with no screen (skill phase-training-feature-gap-checklist, then feature-gap-audit).
2. Signals: behavior signals captured but unused (skill phase-training-behavior-signal-inventory).
3. Competitive: what Strong, Hevy, JuggernautAI, Boostcamp and Lattice ship that this app lacks.
4. Reach: first-run and setup paths where a feature exists but the user is never prompted to it.
5. Screen critique: one pass per tab (skill app-part-by-part-critique).
6. Accessibility: contrast, VoiceOver labels, Dynamic Type, tap targets.
7. Generator eval: sweep and invariants (skills phase-training-generator-eval-method-portfolio, phase-training-generator-sweep-report).
8. Coverage: untested logic files, by coverage and not by canonical name (skill phase-training-test-by-coverage-not-canonical-name).

Fan lenses out to scouts (Haiku), one per lens, each returning a ranked
finding list with file and line. Cap at two builders or runners on a
simulator at once, per the slots in /next.

VERIFY BEFORE LISTING
Skills verify-audit-claim-before-implementing and
ios-audit-finding-false-positives apply to every finding. Open the cited
code and confirm it. Drop findings that are already shipped, already in an
earlier docs/PLAN-gap-backlog-*.md (ticked or open), or contradicted by
the code. Record how many findings each lens produced and how many
survived.

STANDING RULES TO CHECK AGAINST
Written programs first: the engine ranks, moves and scales authored
sessions and never writes a workout. Readiness lives under Progress, not
on Today. The one-screen Today rule is dropped. Decisions recorded in
ROADMAP.md, PLAN-next-gen.md and the backlog docs stay settled.

OPEN-ITEM CAP: 30
Count open gap items first, one call:
  grep -cE '^\s*- \[ \]' docs/PLAN-gap-backlog-*.md
summing only the files listed under Backlogs in docs/QUEUE.md. Room =
30 minus that sum. Rank the surviving findings by cost to the user and
queue only the top <room> as build items. Every other survivor goes under
`## Not scheduled` in the same doc, one line each with its evidence, so a
later run can promote it without re-auditing. If room is 0, write no new
doc: post the open count and the top three findings you would have
queued, then stop.

STABILITY
If a finding matches an earlier backlog item or Not scheduled line
(ticked or open), drop it; do not reword it into a new item. If no
finding survives, write no doc and post "no new gaps" with the counts.

OUTPUT
1. docs/PLAN-gap-backlog-<YYYY-MM>[b,c...].md in the format of the existing
   gap backlogs: a short header naming the lenses and the date, then phases
   in dependency order. Each item is a checkbox with an hour estimate, the
   files and types it touches, the skill to load, the test classes that show
   it is done, and logic (builder-heavy) or UI (builder). Size items so one
   /next session finishes one item (about 2 to 10 h). Split anything larger.
2. An item that needs an owner decision, a device action or an entitlement
   says so in its own text, so /next skips it. List those decisions in a
   Phase 0 as one-line choices with two named options, recommendation first.
   An item that needs another item done first puts an `after` clause in
   its bold heading (`after 4.1`, `after 2026-11c 1.2`, `after Phase 4`),
   the form /next resolves. A dependency written only in the item's prose
   is invisible to the pick.
3. Add the doc to the bottom of Backlogs in docs/QUEUE.md. Commit both
   and push to main. Then post the finding counts, the item
   count, the total hours and the first item /next will pick, in three
   lines at most.
