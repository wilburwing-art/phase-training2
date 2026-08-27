---
name: pocock-skills-on-phase-training-ios
description: How to run Matt Pocock's engineering skills (/tdd, /improve-codebase-architecture, /grill-me, /setup-matt-pocock-skills) inside phase-training / phase-training2 / workout-plan without hitting iOS-specific frictions that break Pocock's default test loop and new-file flow. Trigger when the user wants to invoke any of those slash commands inside a phase-training-family iOS repo, OR when starting a TDD / refactor / architecture-audit task in one of those repos.
---

# Pocock skills on phase-training-family iOS

`/grill-me`, `/tdd`, and `/improve-codebase-architecture` assume a generic codebase. In phase-training / phase-training2 they hit three frictions you must wire around on turn 1.

## Quick start (no setup)

`/grill-me` works out of the box. Use it before any "let's add X" — but let the `phase-training-feature-gap-checklist` skill fire first to check whether X is already shipped.

`/tdd` works out of the box IF you tell it two things on turn 1:

1. **Test command is `mcp__XcodeBuildMCP__test_sim`**, not `swift test`. Pocock's red-green loop assumes a generic test runner; it has no idea about XcodeBuildMCP.
2. **After writing any new test file, hand off to the `pbxproj-add-files-by-hand` skill before re-running the test loop.** phase-training-family pbxproj is hand-managed (not synchronized folders, not XcodeGen-synced), so a freshly-written .swift test file does NOT compile into the test target until you add four entries to project.pbxproj. Pocock's `/tdd` will write the file, run the loop, see "cannot find type X in scope," and spin.

## Full setup (one-time, unlocks `/improve-codebase-architecture`)

Run `/setup-matt-pocock-skills` in the repo. It scaffolds `AGENTS.md`, `docs/agents/`, `CONTEXT.md`. Paste the domain glossary (exercise, set, modality, sport_relevance, muscle_group, phase, block, workout, plan) into `CONTEXT.md` — `/improve-codebase-architecture` reads it to ground its recommendations.

## Predicted high-value finding for /improve-codebase-architecture

The first deepening candidate it should surface is the **catalog-messy inverse-deep-module**: phase-training-family SQLite has rich relational tag tables (`exercise_sport_relevance`, `muscle_groups`, etc.) populated but unused by Swift/UI code. That's data without an interface — the OPPOSITE of a deep module. The fix is one query module that exposes the tags through a simple API, NOT pruning the tables. Cross-reference `catalog-messy-diagnose-before-cleanup` skill before acting on this finding.

## Don't dual-fire

`/grill-me` and `phase-training-feature-gap-checklist` both try to scope feature requests. Run feature-gap-audit FIRST (it checks shipped state via the standard fitness-app foundations checklist); only fire `/grill-me` after if a real gap exists. Otherwise you'll grill on a feature that already ships.
