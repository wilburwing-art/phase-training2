---
name: phase-training-wipe-spans-userdefaults-and-sqlite
description: In phase-training2 (and family), user data lives in TWO storage layers — UserDefaults under `pt_*` keys AND the on-disk SQLite `UserDatabase` (saved sessions, custom routines, imported history, which migrated out of UserDefaults). Any "erase all my data" / full reset / backup / `--ui-test-reset` feature MUST clear BOTH layers; a UserDefaults-only wipe silently leaves all workout history on disk. The canonical wipe should sweep the `pt_` prefix (a hand-kept key list bit-rots) plus call UserDatabase.wipeAll(). Trigger when building or reviewing a data-deletion / reset / backup path, OR when reviving a stale branch that touches one. Skip for single-key resets.
when-to-use: Implementing/reviewing "erase all data", account-deletion, full reset, backup-restore, or --ui-test-reset in phase-training / phase-training2 / workout-plan. Also fires when a branch that predates ~build-100 needs reviving and touches persistence.
---

# phase-training2: a full wipe spans UserDefaults + SQLite

## The trap (this session)
A "revive the stale privacy branch" ask was NOT a mechanical rebase. The branch
(235 commits behind) implemented "Erase all my data" as a UserDefaults-only wipe
with a hardcoded 6-key `persistedKeys` list. Since it was cut, the data layer
migrated: **saved sessions, custom routines, and imported history now live in a
SQLite `UserDatabase`** (`SessionStore.savedSessions = userDB.listSavedSessions()`,
not UserDefaults). So the branch's wipe would have left all workout history on
disk — a privacy bug worse than no button. The hand-kept key list had also
drifted (missed coach archives, sport logs, plan overrides, reshuffle counters).

**Lesson: before estimating a revive/rebase that touches persistence, audit the
data layer.** `grep -rhoE '"pt_[a-z_]+"'` for UserDefaults keys AND check
`UserDatabase.swift` for `CREATE TABLE` to see what moved to SQLite.

## The correct canonical wipe
One function both the production action and `--ui-test-reset` route through (so
they can't drift):
- **UserDefaults:** sweep by prefix, not a list —
  `for k in defaults.dictionaryRepresentation().keys where k.hasPrefix("pt_") { removeObject }`.
  Rot-proof; covers prefix-keyed archives (`pt_coach_archive_<day>`) and future keys.
  Leaves non-`pt_` (system/SDK) keys alone.
- **SQLite:** add `UserDatabase.wipeAll()` — one transaction DELETEing session_sets,
  session_exercises, sessions, user_routine_exercises, user_routines, imported_sets,
  imported_workouts. (Per-table `clearAll*` helpers already existed; there was no
  all-tables one.)
- Cancel pending local notifications (`pt.weekly_reminder`).
- Callers holding live `@StateObject` stores must also reset in-memory caches
  (`store.reset()`, `sessionStore.clearInMemoryState()`, `customStore.reload()`,
  `planStore.clear()`) so the UI drops to the onboarding cover.

## Gotchas
- `--ui-test-reset` previously wiped only UserDefaults → UI tests could inherit
  prior sessions/routines from SQLite. Route it through the canonical wipe.
- `UserDatabase(path: ":memory:")` is the unit-test idiom; `defaultStore()` returns
  `.shared` in prod, fresh in-memory under UI-test/preview.
- `.derived/` (this repo's DerivedData dir) is NOT in `.gitignore` by default — only
  `DerivedData/` is. `git add -A` will sweep in ~6000 artifact files. Add `.derived/`.
