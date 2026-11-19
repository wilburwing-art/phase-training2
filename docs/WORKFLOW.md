# How work moves through this repo

Three levels of detail on `/roadmap`, `/spec`, `/gaps`, `/next` and `/retro`.
The command files in `.claude/commands/` are the source of truth and win over
the copies in `~/.claude/commands/`. Update this doc when they change.

## Level 1: one sentence each

- **`/roadmap`**: writes an idea into `ROADMAP.md`.
- **`/spec`**: turns one roadmap section into a plan plus a list of tasks.
- **`/gaps`**: audits the app and writes a list of tasks to fix what it finds.
- **`/next`**: does the next task on the list, commits it, and stops.
- **`/retro`**: reviews recent sessions and proposes fixes to the commands themselves. Runs weekly, Monday 08:00.

```
idea ──/roadmap──> ROADMAP.md ──/spec──> PLAN-<track>.md + backlog ─┐
                                                                    ├─> docs/QUEUE.md ──/next──> commit
app code ──/gaps──────────────────────────> gap backlog ────────────┘
```

## Level 2: the files each command touches

| Command | Reads | Writes | Commits |
|---|---|---|---|
| `/roadmap <idea>` | ROADMAP.md, PLAN files, backlogs (to catch duplicates) | A `## Name (not specced)` section, or one added bullet | `ROADMAP.md` only |
| `/spec <section>` | The roadmap section, PLAN-next-gen.md, project skills | `PLAN-<track>.md`, `docs/PLAN-backlog-<YYYY-MM>-<track>.md`, a pointer line in ROADMAP, a line added to QUEUE | All 4 together |
| `/gaps [lens]` | The code, through 8 lenses (feature, signals, competitive, reach, screens, accessibility, generator, coverage) | `docs/PLAN-gap-backlog-<YYYY-MM>[b,c..].md`, a line added to QUEUE | Both |
| `/next` | `docs/QUEUE.md` | Code, `docs/briefs/<item>.md`, the item's checkbox, queue upkeep | Item, tick and queue together |
| `/retro` | The last `/next`, `/gaps` and `/spec` transcripts, git history | `docs/retro/<date>.md` | Edits nothing else |

**How `/next` picks from `docs/QUEUE.md`:**
1. A red main CI run is the item.
2. Otherwise, a **Pinned** item (3 max) that is not waiting on the owner.
3. Otherwise, the first open item in the first doc under **Backlogs**, phases in order.
4. A backlog doc missing from QUEUE is ignored and reported as `not queued: <path>`.

The current order lives in `docs/QUEUE.md`. Reorder it by hand.

## Level 3: the rules inside each step

**`/roadmap` (Sonnet, scribe)**
- Gives each idea one outcome: COVERED, EXTENDS, NEW or SHELVED. A keyword match alone does not count as a duplicate; it reads each hit.
- Asks the owner nothing. Missing detail goes under "Open questions", 3 max. Numbers the owner did not give are marked unverified.
- A conflict with a standing rule (written programs first, readiness under Progress) becomes the section's first open question.
- With no argument, lists every section and recommends "spec next: <name>".

**`/spec` (Fable, architect)**
- Asks every owner decision first, as one-line either/or questions in one message, and waits for the answers before writing the spec.
- Phase 0 of the backlog records the answers with the date.
- Build items run 2 to 10 h each, in dependency order. Each names:
  - its files and types (traced by a Haiku scout)
  - the skill to load
  - the test classes that prove it done
  - builder or builder-heavy
- Replaces the ROADMAP section body with a pointer and marks the heading `(specced)`.

**`/gaps` (Fable, lead)**
- One Haiku scout per lens, at most 2 simulator users at once.
- Every finding is checked at the cited code (`verify-audit-claim-before-implementing`, `ios-audit-finding-false-positives`).
- Drops anything shipped or already in an earlier gap backlog, ticked or open.
- Open gap items cap at 30 across queued gap backlogs. Survivors past the cap go under `## Not scheduled`.
- Reports produced and surviving counts per lens. Blocked items carry "(owner decision)" in their own text so `/next` skips them.

**`/next` (Fable, lead, one item per session)**
1. Checks main CI, then picks from QUEUE. If every item is blocked on the owner, lists the one action each needs and stops.
2. Reads the item, its PLAN and the area skill; a scout traces the code.
3. Writes `docs/briefs/<item>.md`: files (no overlap with other running builders), skill, done criteria, simulator slot, and who runs `xcodegen`.
4. Delegates:
   - **builder** (Sonnet) for UI and wiring.
   - **builder-heavy** (Opus, sparingly) for the generator, overload math, migrations and sync.

   Each builder runs its own tests, does not commit, and sends one final report.
5. Simulator slots: A `3CF80E1F…` with `DerivedData-A`, B `0929A7A4…` with `DerivedData-B`. At most 2 builds at once.
6. Reviews the diff (logic files read in full), runs the item's named test classes itself, ticks the checkbox only when they pass, and pushes to main.
7. Queue upkeep goes in the same commit:
   - removes the pin
   - moves a fully ticked backlog to Done
   - for a backlog from `/spec`, changes the ROADMAP heading to `(shipped <date>)` and runs `/retro`
8. Every post ends with `<n> queued items blocked on you`.

**`/retro`** looks for:
- lost findings
- questions the owner never answered
- rule leaks (trailers, dashes, `git add -A`)
- skipped verification
- expensive sessions
- drift between what sessions did and what the commands say
