# phase-training2

iOS training app (SwiftUI) with a watchOS companion. Targets: `PhaseTraining`, `PhaseTrainingTests`, `PhaseTrainingUITests`, `PhaseTrainingWatch`, plus `Shared`.

## Build

- XcodeGen project. `Project.yml` (capital P) is the source of truth; `PhaseTraining.xcodeproj` is gitignored and generated.
- Run `xcodegen generate` after adding a Swift file, after `git switch`, and on a fresh checkout.
- Build number is `CURRENT_PROJECT_VERSION` in `Project.yml`. Editing the pbxproj does nothing for CI.

## Test

- Prefer one test class over the full suite: `-only-testing:PhaseTrainingTests/<ClassName>`.
- Send the full log to a file and grep it. A `tail` shows only the UI test target and hides unit failures:
  `grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" <log>`
- No `iPhone 16` simulator is installed. Pick a destination from `xcrun simctl list devices available`.
- Two test runs on one simulator restart each other. Run one at a time.
- `SubscriptionStoreFlowTests` (StoreKit test mode) runs only on the `iPhone 17 Pro iOS 26.2` simulator. On iOS 26.3 to 26.5 it skips (FB22237318).

## Exercise catalog

- `db/coach.db` and `PhaseTraining/Resources/coach.db` are build outputs. Edit `db/source/*.json`, run `python3 scripts/db/build_db.py`, commit the JSON and the regenerated db together.

## Workflow

- Solo repo. Commit and push straight to `main`.
- Project skills under `.claude/skills/` hold the detail for the generator, planner, season engine, coach and watch. Load the matching one before changing those areas.

### Gap lenses

`/gaps` with no argument runs all eight. `/gaps <name>` runs one. All lenses are read-only static passes unless the command column says otherwise. Treat each as a hypothesis source and check findings with `ios-audit-finding-false-positives`.

| Lens | Measures | Command or skill |
|---|---|---|
| feature | Data the app holds against the UI that shows it; missing foundations | `phase-training-feature-gap-checklist`, `feature-gap-audit` |
| signals | Behavior signals captured and which have a reader | `phase-training-behavior-signal-inventory`; grep each signal for a consumer |
| competitive | Features rival apps ship that this app lacks, filtered by the privacy stance in `PLAN-next-gen.md` | `GAP_ANALYSIS.md`, `FUNCTIONAL_GAP_ANALYSIS.md` as a starting inventory, then `WebSearch` |
| reach | Capabilities users cannot find or enable (permissions, settings, entry points, widgets) | read `Info.plist`, `Project.yml`, entry-point views |
| screens | Per-screen critique against one shared rubric | `app-part-by-part-critique`, `phase-training-tab-time-horizon-rule`, `phase-training-tap-budget-is-a-floor` |
| accessibility | Labels, traits, Dynamic Type, announcements, confirm dialogs, watch parity | grep `accessibility`, `UIAccessibility.post`, `isSelected`, `confirmationDialog` under `PhaseTraining/` and `PhaseTrainingWatch/` |
| generator | Session structure, prescription and constraint violations | `phase-training-generator-eval-method-portfolio`, `phase-training-generator-sweep-report` |
| coverage | Types and functions with no test reference | `phase-training-test-by-coverage-not-canonical-name`; grep `PhaseTrainingTests/` per type |

- Backlog location: `docs/PLAN-gap-backlog-<YYYY-MM>.md`, suffix `b`, `c`, `d` for later runs in the month. `/next` picks work from `docs/QUEUE.md` (pins first, then backlogs top to bottom). `/gaps` and `/spec` add new backlogs to its bottom; reorder by hand.
- Blocked markers: an item that needs an owner decision, device action, account, key or entitlement says so in its own text, with "(owner decision)" in the bold title for Phase 0 lines. Work parked for lack of a plan goes under `## Not scheduled`.
- Drop a finding already in any earlier backlog file, ticked or open.
- Open gap items cap at 30 across queued gap backlogs. `/gaps` queues its top-ranked survivors up to the cap; the rest go under `## Not scheduled`.
- `/next` ticks an item only after it runs the item's named test classes itself and they pass. A red main CI run is the next item.
- `/retro` runs weekly (Monday 08:00, launchd `com.wilburwing.phase-training-retro`) and writes `docs/retro/<date>.md`. It edits nothing else.
- Repo commands in `.claude/commands/` win over `~/.claude/commands/`; the home copies defer to them.
- Push straight to `main`, commit the backlog doc by named path.
