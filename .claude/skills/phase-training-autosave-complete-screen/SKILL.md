---
name: phase-training-autosave-complete-screen
description: >
  Moving a phase-training workout's SAVE earlier — e.g. auto-save on
  CompleteScreen.onAppear so "Finish" is the save (no separate Save tap) —
  silently breaks PR detection unless you self-exclude the now-persisted
  session, and flips Discard from "clear active" to "delete a saved row".
  Trigger when changing WHEN/WHERE a logged workout is committed in
  phase-training (CompleteScreen, the Finish→Save→feedback tail, SessionStore.
  saveCompleted), making Finish auto-save, or collapsing the post-workout flow.
when-to-use: >
  Editing the LogScreen Finish → CompleteScreen → Save flow in phase-training /
  phase-training2; auto-saving a workout; "PRs stopped showing after I changed
  save". Skip for unrelated SessionStore work.
---

# Auto-saving a workout in CompleteScreen — the four couplings

`SessionStore.saveCompleted(_:feel:note:)` writes the row, inserts into
`savedSessions`, AND `clearActive()`s, returning the `SavedSession`. Moving that
call from the "Save session" button to `CompleteScreen.onAppear` makes Finish
the save. Done 2026-06-02 (PR #34): full/planned log flows 5→3 taps. Four things
you MUST handle or it breaks subtly:

1. **PR self-exclusion (the silent one).** CompleteScreen's `prs` calls
   `store.personalRecords(in: session.exercises, ...)`. Before auto-save the
   session isn't in user.db yet, so PRs are correct. AFTER auto-save it IS in
   the DB → it beats itself → **zero PRs shown**. Fix: pass
   `excludingSessionId: saved?.startTime.timeIntervalSince1970` (the param
   exists for exactly this; `personalRecords` doc calls it the "post-save call").
2. **Discard becomes a delete, not a clear.** Pre-save Discard just
   `clearActive()`. Post-save the workout is in history, so Discard must
   `store.deleteSession(id: saved.startTime.timeIntervalSince1970)` THEN navigate.
   Set a `discarded` flag first so trailing edits don't re-insert it.
3. **feel/note are captured AFTER save.** They start empty at on-appear save, so
   patch the record in place on change: `var s = saved; s.feel = feel;
   s.note = …; store.updateSession(s); saved = s` (SavedSession.feel/note are
   `var`; updateSession upserts by start_time).
4. **Guard double-save:** `guard saved == nil else { return }` in the on-appear
   save — onAppear can fire more than once.

Side effect: the auto-presented `PostWorkoutFeedbackSheet` (structured
FeedbackEntry → `memory.feedback`, read by the planner) gets unwired if you drop
the Save→feedback chain. `feel`/`note` still persist inline; re-add the sheet as
an OPTIONAL summary entry if the coach needs the difficulty/hurt data.

Tap-budget flows 2/4/8 in TapBudgetTests assert `complete-done` (the renamed
primary) and that Finish lands on the summary — see [[phase-training-tap-budget-is-a-floor]].
