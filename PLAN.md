# phase-training2 — TestFlight Plan

Thin vertical slice from `handoff/` → installable iOS app on TestFlight.

## Problem

Ship the 4-screen vertical slice in `handoff/` (sourced from `~/Downloads/design_handoff_training_log/`) as a real iOS app: Start → Log → Complete → History. Hardcoded `upper-1` template. `localStorage`-equivalent persistence. No coach, no charts, no auth, no paywall, no sport DB integration.

## Definition of done

- Repo `~/repos/phase-training2`, pushed to private `wilburwing-art/phase-training2`.
- iOS app installable via TestFlight on Wilbur's iPhone.
- All 4 screens pixel-faithful to `handoff/`: dark `#0A0B0D`, electric lime `#D4FF3D`, Space Grotesk + JetBrains Mono + Inter fonts.
- One full workout loggable end-to-end: start → 6 exercises logged with rest timer → complete → appears in History → "Previous" column populated on next session.
- Active session survives app kill (resumes on cold launch).

## Out of scope

- Auth, accounts, paywall, sync, networked anything.
- Multiple workout templates (just `upper-1` from handoff).
- The `phase-training/` SQLite adaptive-coach DB. Future integration.
- Charts, progress screens, settings, coach, onboarding.
- Android, watchOS, iPad-specific layouts.
- Push notifications, HealthKit, Apple Watch rest timer.

## Stack decision: native SwiftUI

- TestFlight = iOS, native is the no-friction path.
- React Native / Capacitor / PWA all add build complexity for a 4-screen app.
- SwiftData for persistence (Apple's `localStorage` analog; clean fit for the prototype's two-key model).
- iOS 17+ deployment target (unlocks SwiftData; Wilbur is on a modern phone).
- `xcodegen` for project generation (declarative `Project.yml` → `.xcodeproj`) so multi-agent work doesn't fight an Xcode GUI.

If hedging for Android later matters, switch to React Native or Flutter (+1-2 days, worse iOS feel).

## Defaults being taken

| Decision | Default |
|---|---|
| App name | "Phase Training" |
| Bundle id | `art.wilburwing.phasetraining2` |
| Min iOS | 17.0 |
| Persistence | SwiftData (`ActiveSession` + `SavedSession`) |
| Fonts | Bundled `.ttf` (Space Grotesk, JetBrains Mono, Inter — all OFL) |
| Analytics | None for the slice |
| Crash reporting | None for the slice |
| App Store Connect screenshots | Placeholder for first TestFlight; finalize before App Store submission |
| Apple Developer Program | Confirmed active by Wilbur |

## Phases

### Phase 0 — Bootstrap (0.5 day, orchestrator)

- `mkdir ~/repos/phase-training2`, `git init`, copy `handoff/` into repo.
- `Project.yml` for xcodegen (target `PhaseTraining`, bundle `art.wilburwing.phasetraining2`, iOS 17, SwiftUI).
- Stub `PhaseTrainingApp.swift`, `ContentView.swift` so `xcodegen generate` succeeds.
- `.gitignore` for Xcode (`xcuserdata`, `*.xcuserstate`, `DerivedData`, `.build`).
- `README.md` with build instructions.
- Initial commit, create GitHub `wilburwing-art/phase-training2` (private), push.

### Phase 1 — Design system (0.5 day, agent `systems`)

- `Theme.swift`: all 14 color tokens from `handoff/README.md` lines 228-247 as `Color` extensions.
- `Typography.swift`: `Font` extensions for Display L/M/S, Body, Mono L/M/S/XS, Micro per `handoff/README.md` lines 248-260.
- Bundle 3 font families into `Resources/Fonts/`, register in `Info.plist` (`UIAppFonts`).
- `StyleGuidePreview.swift`: SwiftUI preview that renders every token (port of `hd-style.jsx`). Proves the system before screen work.

### Phase 2 — Data layer (0.5 day, agent `data`) — parallel with Phase 1

Translate `handoff/proto/data.jsx` lines 1-99 to Swift:

- `WorkoutTemplate`, `ExerciseTemplate` structs (hardcoded `upper-1` only).
- `@Model` types: `ActiveSession`, `SavedSession`, `LoggedExercise`, `LoggedSet`.
- `SessionStore`: `createSession`, `getPreviousSession`, `saveActive`, `clearActive`, `saveCompleted`, `sessionStats`.
- Two SwiftData containers: active session (single row, replaces `pt_active_session`), saved sessions (array, replaces `pt_sessions`).
- Unit tests against the prototype's behavior (use `XCTest`).

### Phase 3 — Screens (3-4 days, 4 agents fan out)

Lock `Theme.swift` and `SessionStore` interface before fan-out. Each screen owns one file; orchestrator integrates routing in `App.swift`.

1. **Start** (`screen-start`) — `hd-session-start.jsx`, `proto/start.jsx`. Read-only. Validates fonts, colors, card pattern, "last session" via `getPreviousSession`.
2. **Log** (`screen-log`) — `hd-training-log.jsx`, `proto/log.jsx`. Hardest screen. Sticky header (elapsed timer + progress bar), scrollable exercise blocks, inline number inputs, set check circles, rest timer with +15/skip, "+ Add Set", active-row left border. `TimelineView(.periodic)` for both timers. Auto-save on every change.
3. **Complete** (`screen-complete`) — `hd-session-complete.jsx`, `proto/complete.jsx`. Stat grid, PR detection, feel chips, note textarea, save action.
4. **History** (`screen-history`) — `hd-history.jsx`, `proto/history.jsx`. List with expand/collapse accordion, empty state.

Navigation: `NavigationStack` with `Route` enum, or single `@State currentScreen` (prototype does the latter; fine for the slice).

### Phase 4 — Polish + device test (1 day, orchestrator)

- Active session resume on cold launch (`proto/app.jsx` reference).
- Pulse animation on rest timer dot (`handoff/README.md` line 296).
- Haptic on set-check tap (`UIImpactFeedbackGenerator`).
- App icon (lime "PT" square) and launch screen (`Assets.xcassets`).
- Test on Wilbur's iPhone via Xcode for one real workout. Adjust spacing where mock and reality diverge.

### Phase 5 — TestFlight (0.5 day, orchestrator + human-in-loop signing)

- App Store Connect: create app record (name, bundle id, SKU, Health & Fitness category, age rating, privacy nutrition label — no data collected, easy).
- Xcode: archive, distribute to App Store Connect, wait for processing.
- TestFlight internal tester: add Wilbur, install via TestFlight app (~5-15min after processing).
- External testers / Beta App Review only if needed (~24h).

## Timeline

| Phase | Effort |
|---|---|
| 0 — Bootstrap | 0.5 day |
| 1 — Design system *(parallel with 2)* | 0.5 day |
| 2 — Data layer *(parallel with 1)* | 0.5 day |
| 3 — Screens (4 agents fan out) | 3-4 days wall-clock if parallel, 5-6 serial |
| 4 — Polish + device test | 1 day |
| 5 — TestFlight | 0.5 day |
| **Total** | **6-7 working days** |

## Agent team shape

| Role | Phase | Type | Parallel? |
|---|---|---|---|
| `orchestrator` (this thread) | 0, 4, 5; integration | (me) | — |
| `systems` | 1 | general-purpose | with `data` |
| `data` | 2 | general-purpose | with `systems` |
| `screen-start` | 3 | general-purpose | with 3 siblings |
| `screen-log` | 3 | general-purpose | with 3 siblings |
| `screen-complete` | 3 | general-purpose | with 3 siblings |
| `screen-history` | 3 | general-purpose | with 3 siblings |

Phase 3 fan-out only after `Theme.swift` and `SessionStore` interface are locked, so the shared-surface conflict is just `App.swift`'s screen registration (orchestrator integrates).

## Open questions for review

1. **Native SwiftUI vs React Native** — RN preserves the existing JSX prototype as production code and hedges Android. Worth it?
2. **SwiftData vs UserDefaults** — SwiftData is overkill for two keys but scales to multi-template Phase 2. Or use `Codable` + `UserDefaults` for the slice and refactor when complexity demands?
3. **App identity** — bundle id `art.wilburwing.phasetraining2` collides namespace with the existing `phase-training/` repo. Should the App Store-visible name just be "Phase Training" or signal it's the v2 (`Phase Training 2`, `Phase Log`)?
4. **Multi-agent risk** — 4 parallel screen agents share `Theme.swift` + `SessionStore`. Locking those first is the mitigation, but a single sequential builder might still be lower-risk for a slice this small.
5. **Migration path from `phase-training/`** — should the slice's `WorkoutTemplate` Swift struct be a strict subset of the existing SQLite schema so adaptive-coach migration is mechanical, or punt that alignment to v2?
6. **TestFlight scope** — internal-only (just Wilbur) ships immediately; external testers trigger Beta App Review (~24h). Slice assumes internal-only. Confirm?
