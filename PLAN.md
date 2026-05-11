# phase-training2 — TestFlight Plan (v2, agent-ready)

Thin vertical slice from `handoff/` → installable iOS app on TestFlight.

## Problem

Ship the 4-screen vertical slice in `handoff/` (sourced from `~/Downloads/design_handoff_training_log/`) as a real iOS app: Start → Log → Complete → History. Hardcoded `upper-1` template. `localStorage`-equivalent persistence. No coach, no charts, no auth, no paywall, no sport DB integration.

## Definition of done

- Repo `~/repos/phase-training2`, pushed to private `wilburwing-art/phase-training2`.
- iOS app installable via TestFlight on Wilbur's iPhone.
- All 4 screens pixel-faithful to `handoff/`: dark `#0A0B0D`, electric lime `#D4FF3D`, Space Grotesk + JetBrains Mono + Inter fonts.
- One full workout loggable end-to-end: start → 6 exercises logged with rest timer → complete → appears in History → "Previous" column populated on next session.
- Active session survives app kill (resumes on cold launch).
- PR detection on Complete screen working (compares max weight per exercise to previous session, per `handoff/proto/complete.jsx:11-19`).

## Out of scope

- Auth, accounts, paywall, sync, networked anything.
- Multiple workout templates (just `upper-1` from handoff).
- The `phase-training/` SQLite adaptive-coach DB. Future integration.
- Charts, progress screens, settings, coach, onboarding.
- Android, watchOS, iPad-specific layouts.
- Push notifications, HealthKit, Apple Watch rest timer.
- UI snapshot tests, Playwright/XCUITest. Unit tests on data layer only.

## Locked decisions

| Decision | Value | Rationale |
|---|---|---|
| Stack | Native SwiftUI | TestFlight = iOS; no-friction path. |
| Project generation | `xcodegen` (declarative `Project.yml`) | Multi-agent work doesn't fight an Xcode GUI. |
| Persistence | `UserDefaults` + `Codable` | Two-key model too small to justify SwiftData macros. ~0.5 day saved. |
| Routing | `@State currentScreen: Screen` enum, single root view | Matches `proto/app.jsx`; simplest for 4 screens. |
| Rest timer state | View-local `@State` in `LogScreen` | Doesn't survive backgrounding for v1 — acceptable. |
| Min iOS | 17.0 | Modern phone, no compatibility burden. |
| Bundle id | `art.wilburwing.phasetraining` (no `2` suffix) | No existing App Store record at that id; the repo name `-2` is git noise, not product noise. |
| App display name | "Phase Training" | — |
| Apple Developer Team | `A2Z2RXR65P` | Lives in `Project.yml` `DEVELOPMENT_TEAM`. |
| Fonts | Space Grotesk, Inter, JetBrains Mono — bundled `.ttf` from Google Fonts (OFL) | Phase 1 agent fetches and registers. |
| Crash reporting / analytics | None | Out of scope for slice. |
| Phase 3 integration protocol | Each screen agent owns exactly one file under `Screens/`. Orchestrator owns `App.swift` routing. No branches; direct edits to `main`. | Minimizes merge surface to one file (orchestrator-owned). |

## Verification commands (agents reference these)

```bash
# Project regen after Project.yml edits
cd ~/repos/phase-training2 && xcodegen generate

# Build for simulator (lightweight, primary check)
xcodebuild -scheme PhaseTraining \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug build | xcbeautify

# Run data-layer unit tests
xcodebuild -scheme PhaseTraining \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test | xcbeautify

# Archive (Phase 5 only)
xcodebuild -scheme PhaseTraining -configuration Release \
  -archivePath build/PhaseTraining.xcarchive archive
```

`xcbeautify` optional. If absent, raw `xcodebuild` output is fine.

## Phases

### Phase 0 — Bootstrap (orchestrator; ~70% complete)

**Done:**
- `~/repos/phase-training2/` created, `git init`, `handoff/` copied in.
- `.gitignore`, `README.md`, `PLAN.md` committed.

**Remaining (orchestrator finishes before fan-out):**
- Write `Project.yml` (`PhaseTraining` target, iOS 17, bundle `art.wilburwing.phasetraining`, team `A2Z2RXR65P`, SwiftUI).
- Stub `PhaseTraining/App/PhaseTrainingApp.swift` + `PhaseTraining/App/ContentView.swift` so `xcodegen generate` succeeds and project opens in Xcode.
- Stub `PhaseTraining/Info.plist` (empty `UIAppFonts` array — Phase 1 fills).
- Run `xcodegen generate`, verify `xcodebuild build` succeeds.
- Create GitHub `wilburwing-art/phase-training2` (private), push.

**Acceptance:** `xcodegen generate && xcodebuild -scheme PhaseTraining -destination 'platform=iOS Simulator,name=iPhone 15' build` succeeds on an empty SwiftUI app.

### Phase 1 — Design system (agent `systems`) — parallel with Phase 2

**Tasks:**
1. Fetch Google Fonts (all OFL):
   - Space Grotesk (weights 400, 500, 600) → `PhaseTraining/Resources/Fonts/SpaceGrotesk-{Regular,Medium,SemiBold}.ttf`
   - Inter (weights 400) → `Inter-Regular.ttf`
   - JetBrains Mono (weights 400, 500, 600) → `JetBrainsMono-{Regular,Medium,SemiBold}.ttf`
   - Download from `https://fonts.google.com/download?family=...` or use `curl` against the static font URLs on `fonts.gstatic.com`. Add to `Project.yml` resources.
2. Register fonts in `Info.plist` `UIAppFonts` array.
3. Write `PhaseTraining/Theme/Theme.swift`: all 14 color tokens from `handoff/README.md:232-246` as `extension Color` static members (`Color.bg`, `Color.surface`, `Color.elevated`, `Color.line`, `Color.lineSoft`, `Color.ink`, `Color.ink2`, `Color.ink3`, `Color.accent`, `Color.accentInk`, `Color.accentDim`, `Color.accentWash`, `Color.accentBorder`, `Color.ok`, `Color.danger`).
4. Write `PhaseTraining/Theme/Typography.swift`: `Font` extensions for all 9 type styles from `handoff/README.md:251-259` (`Font.displayL`, `Font.displayM`, `Font.displayS`, `Font.body`, `Font.monoL`, `Font.monoM`, `Font.monoS`, `Font.monoXS`, `Font.micro`). Apply size, weight, and kerning per spec.
5. Write `PhaseTraining/Theme/StyleGuidePreview.swift`: SwiftUI `#Preview` rendering every color swatch + every type style. Port of `handoff/hd-style.jsx`. Used as visual smoke test.

**Acceptance:**
- `xcodebuild build` succeeds.
- Opening `StyleGuidePreview.swift` in Xcode shows all 14 colors and all 9 type styles with custom fonts rendering (not system fallback). Visual confirmation via Xcode Preview.

### Phase 2 — Data layer (agent `data`) — parallel with Phase 1

Translate `handoff/proto/data.jsx` (98 lines) to Swift.

**Tasks:**
1. Write `PhaseTraining/Data/WorkoutTemplate.swift`:
   - `struct WorkoutTemplate: Identifiable, Codable` with id, name, category, exercises.
   - `struct ExerciseTemplate: Identifiable, Codable` with id, name, type (optional), unit, targetSets, targetReps, rest.
   - Static constant `WorkoutTemplate.upper1` matching `data.jsx:4-17` exactly (6 exercises: Bench, Pull Up, OHP, Incline Row, Skullcrusher, Face Pull).
2. Write `PhaseTraining/Data/Session.swift`:
   - `struct LoggedSet: Codable` with `num: Int`, `weight: String`, `reps: String`, `rpe: String`, `done: Bool`. **String for numeric fields** to match prototype's TextField binding semantics.
   - `struct LoggedExercise: Codable, Identifiable` with template fields + `sets: [LoggedSet]` + `prevSets: [LoggedSet]`.
   - `struct ActiveSession: Codable` with `templateId`, `name`, `category`, `startTime: Date`, `exercises: [LoggedExercise]`, optional `feel: String?`, optional `note: String?`.
   - `struct SavedSession: Codable, Identifiable` — same shape plus `endTime: Date`, `duration: Int` (seconds).
3. Write `PhaseTraining/Data/SessionStore.swift`:
   - Class with `@Published` properties for SwiftUI, backed by `UserDefaults.standard`.
   - Keys: `pt_active_session`, `pt_sessions` (match prototype).
   - Methods, all matching `data.jsx`:
     - `loadSessions() -> [SavedSession]`
     - `saveSessions(_:)`
     - `loadActive() -> ActiveSession?`
     - `saveActive(_:)`
     - `clearActive()`
     - `getPreviousSession(templateId:) -> SavedSession?`
     - `createSession(templateId:) -> ActiveSession` — pulls previous set values forward (`data.jsx:51-77`).
     - `sessionStats(_:) -> SessionStats` (returns totalSets, doneSets, avgRpe).
4. Write `PhaseTrainingTests/SessionStoreTests.swift` (XCTest):
   - Test `createSession` produces 6 exercises with correct set counts.
   - Test `createSession` with no prior history leaves weight strings empty and reps strings = target.
   - Test `createSession` with prior history populates weight + reps from previous.
   - Test `sessionStats` math on a hand-built session.
   - Test active-session roundtrip through UserDefaults survives an instance swap.

**Acceptance:** `xcodebuild test` passes all 5 unit tests.

### Phase 3 — Screens (4 agents fan out) — sequential after Phases 1 + 2 land

**Pre-fan-out lock:** Phase 1 and Phase 2 must be merged and `xcodebuild build && xcodebuild test` green. `Theme.swift` and `SessionStore` public API are frozen.

**Integration protocol:** each agent owns exactly the file listed below. No agent touches `App.swift` — orchestrator wires routing after each screen lands.

| Agent | Owns | References |
|---|---|---|
| `screen-start` | `PhaseTraining/Screens/StartScreen.swift` | `handoff/hd-session-start.jsx`, `handoff/proto/start.jsx` |
| `screen-log` | `PhaseTraining/Screens/LogScreen.swift` + `PhaseTraining/Components/RestTimer.swift` | `handoff/hd-training-log.jsx`, `handoff/proto/log.jsx` |
| `screen-complete` | `PhaseTraining/Screens/CompleteScreen.swift` | `handoff/hd-session-complete.jsx`, `handoff/proto/complete.jsx` |
| `screen-history` | `PhaseTraining/Screens/HistoryScreen.swift` | `handoff/hd-history.jsx`, `handoff/proto/history.jsx` |

**Per-screen acceptance:** opens via `#Preview` in Xcode, renders pixel-faithful to JSX reference (margins, colors, typography, layout), all interactions wired to `SessionStore`. `xcodebuild build` green.

**Per-screen specifics:**

- **StartScreen** — `SessionStore.getPreviousSession("upper-1")` drives "last session" card. Start button → `currentScreen = .log`. History button → `currentScreen = .history`.
- **LogScreen** — *hardest*. Sticky header: elapsed `Mono M` timer + progress bar (done sets / total sets). Scrollable `List` of exercises. Each set row: weight `TextField` + reps `TextField` + rpe `TextField` (all `Mono S`, decimal keyboard) + check circle. Toggling check on a non-final set triggers `RestTimer` overlay (counts down from `ex.rest`, +15 button, skip button, pulse-dot animation per `README.md:296`). "+ Add Set" button per exercise. Auto-save to `SessionStore` on every change. Active row has left border `Color.accent`. Use `TimelineView(.periodic(from: .now, by: 1.0))` for elapsed timer + rest timer.
- **CompleteScreen** — Stat grid (sets done / time / avg RPE). PR detection block per `proto/complete.jsx:11-19` (compare max weight per exercise to previous session). Feel chips (HARD / OK / EASY) bound to `session.feel`. Note `TextEditor` bound to `session.note`. Save button → builds `SavedSession`, prepends to `sessions`, calls `clearActive()`, returns to Start.
- **HistoryScreen** — `List(SessionStore.savedSessions)` with disclosure rows (expand/collapse). Empty state message when none. Back button → Start.

### Phase 4 — Polish + device test (orchestrator)

**Tasks:**
- Wire active-session resume on cold launch in `App.swift` (`onAppear`: if `loadActive()` returns non-nil, jump to `.log`).
- Confirm pulse animation on rest timer dot is smooth at 60fps.
- Add `UIImpactFeedbackGenerator(style: .light)` on set-check tap.
- App icon: generate 1024×1024 PNG (lime `#D4FF3D` background, black `PT` in Space Grotesk SemiBold). Tool: Python+PIL one-shot, or `magick convert`. Save to `Assets.xcassets/AppIcon.appiconset`. Use Xcode's automatic icon-set scaling.
- Launch screen: SwiftUI launch screen, lime background, no text. Configured via `Info.plist` `UILaunchScreen`.
- Install on Wilbur's iPhone via Xcode, run one real workout. Note any spacing/padding deltas vs JSX reference, fix.

**Acceptance:** One full workout logged on a physical device. Active session survives an app kill mid-workout. No layout regressions vs JSX mockups.

### Phase 5 — TestFlight (orchestrator + human-in-loop)

**Tasks:**
- App Store Connect: create app record (name "Phase Training", bundle `art.wilburwing.phasetraining`, SKU `phase-training-1`, primary category Health & Fitness, secondary Sports, age rating 4+, privacy nutrition label: "Data Not Collected").
- Xcode → Product → Archive. Distribute to App Store Connect.
- Wait for processing (~10-15min).
- TestFlight: add Wilbur as internal tester (`wilburwing@gmail.com`). Install via TestFlight app on iPhone.

**Acceptance:** Build appears in TestFlight, installs cleanly on device, launches and runs.

## Timeline (revised)

| Phase | Effort (orchestrator + agent wall clock) |
|---|---|
| 0 — Bootstrap (finish) | 0.25 day |
| 1 + 2 — Parallel design system + data layer | 0.5 day |
| 3 — 4 screens parallel | 1.5-2 days (Log dominates) |
| 4 — Polish + device test | 1 day |
| 5 — TestFlight | 0.5 day |
| **Total wall clock** | **~3.5-4.5 days** |

Serial equivalent (no team): 6-7 working days. Parallelism gain: ~2.5 days, paid in integration overhead.

## Team shape

| Role | Phase | Agent type |
|---|---|---|
| `orchestrator` (this thread) | 0 finish, 4, 5; integration of App.swift | (me) |
| `systems` | 1 | general-purpose |
| `data` | 2 | general-purpose |
| `screen-start` | 3 | general-purpose |
| `screen-log` | 3 | general-purpose |
| `screen-complete` | 3 | general-purpose |
| `screen-history` | 3 | general-purpose |

## Risks tracked

| Risk | Mitigation |
|---|---|
| First-time signing for new bundle id fails | Wilbur on standby for one-time Xcode signing prompt; orchestrator drives. |
| Log screen exceeds 2-day budget | Agent reports blockers via SendMessage; orchestrator descopes "+ Add Set" or auto-save aggressiveness if needed. |
| Font fetch fails behind a captcha | Fallback: include TTFs from `/System/Library/Fonts/Supplemental/` lookalikes (Helvetica, SF Mono) and skip custom fonts for slice. Visual regression; cosmetic. |
| Multi-agent integration churn eats the parallelism win | If Phase 3 integration burns >0.5 day, orchestrator absorbs remaining screens solo. |
