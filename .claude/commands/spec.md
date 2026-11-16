---
description: Turn one ROADMAP.md section into a spec and backlog items that /next can run
argument-hint: <roadmap section, e.g. "user model" or "voice coach">
---

You (Fable) are the architect. Turn one ROADMAP.md section into a spec and
a backlog phase that /next can run item by item. Write no app code.

INPUT
The section to spec: $ARGUMENTS
If that is empty, list the ROADMAP.md sections with what each waits on
(owner decision, data, another track) and ask which one, as a one-line
question. Then stop.

READ FIRST
- The section in ROADMAP.md, and every PLAN-*.md it names.
- PLAN-next-gen.md for any gate or decision the section sits behind.
- The project skills under .claude/skills/ for the areas it touches.
- Use scout (Haiku) freely to trace existing code, so each item cites the
  files and types it changes.

STANDING RULES TO CHECK AGAINST
Written programs first: the engine ranks, moves and scales authored
sessions and never writes a workout. Readiness is visible to the user on
its own page under Progress; Today does not show it. Decisions already
recorded in ROADMAP.md, PLAN-next-gen.md and the backlog docs stay
settled. Do not ask them again.

OWNER DECISIONS FIRST
List every call only I can make before the spec holds. Phrase each as one
line with two named choices, your recommendation first, and what each
answer makes happen. Ask them all in one message and wait. Do not write
the spec around an unanswered decision.

OUTPUT, after the answers
1. A one-page spec at PLAN-<track>.md in the repo root, in the format of
   the other PLAN files: the problem, each parameter or screen, where its
   data comes from, how often it updates, gates, and what is out of scope.
2. A backlog doc at docs/PLAN-backlog-<YYYY-MM>-<track>.md:
   - Phase 0: the owner decisions with my answers and the date.
   - Build phases in dependency order. Each item is a checkbox with an
     hour estimate, the files and types it touches (from scout's traces),
     the skill to load, and the test classes that show it is done.
   - Size items so one /next session finishes one item (about 2 to 10 h).
     Split anything larger.
   - Mark items that are logic (builder-heavy) or UI and wiring (builder).
3. In ROADMAP.md, replace the section's body with one line pointing to
   the spec and the backlog doc.

Commit the three files together and push to main. Then post the item
count, the total hours, and the first item /next will pick, in three
lines at most.
