---
name: phase-training-watch-companion-map
description: Where the watch companion lives in phase-training2 and the rules it is built on (phone owns the session, one Health writer per session, events keyed by exercise id and set number, motion files on the phone). Trigger on "watch app", "WatchSync", "sessionStarted", "healthWriter", "ptmotion", "build 146", "why did the phone not save the workout", or before touching Shared/, PhaseTrainingWatch/, WatchSyncCoordinator or HealthWorkoutWriter.
---

# The watch companion (build 146, PLAN-watch.md)

## Files
- `Shared/` compiles into BOTH targets, Foundation only: `Models/SessionModels.swift`
  (ActiveSession, LoggedExercise, LoggedSet moved here; the `EquipmentCategory` helper stayed
  in `PhaseTraining/Data/Session.swift`), `WatchSync/` (event contract + pure reducer),
  `Health/HealthWorkoutTag.swift`, `Motion/MotionWindow.swift`.
- Phone: `Data/WatchSync/WatchSyncCoordinator.swift` (WCSession, created in
  `PhaseTrainingApp` `.task`), `Health/HealthWorkoutWriter.swift`, `Data/Motion/MotionStore.swift`.
- Watch: `PhaseTrainingWatch/` (`WatchSessionModel`, `WatchWorkoutController`,
  `WatchRestTimer`, `MotionRecorder`, the SwiftUI in `PhaseTrainingWatchApp.swift`).

## Rules that are not obvious from the code
- **The phone owns the session.** The watch never writes a SavedSession; it sends
  `WatchSyncEvent`s (set completed/reopened, sessionStarted, watchWorkoutStarted,
  sessionEnded), keyed by exercise id + set number, never index. The reducer is idempotent
  on event id, orders by `at`, and a phone edit after the event wins (ledger filled by
  DIFFING `store.$active`; the first sight of a session records nothing, so queued events
  from a closed phone still apply).
- **Stale-session rule:** an event whose `sessionStart` is not the active session's is
  consumed and dropped. A phone-started session beats a watch-started one in flight.
- **One Health writer per session.** `SavedSession.healthWriter` nil/phone means
  `HealthWorkoutWriter` saves at `onSessionSaved`; `.watch` (set by `watchWorkoutStarted`)
  means the watch's `HKWorkoutSession` saves. Both stamp `HKMetadataKeySyncIdentifier` =
  `HealthWorkoutTag.sessionId(for: startTime)` and `pt_session`; the importer drops any
  workout with that tag OR a `com.phasetraining.app` bundle prefix (the watch app's bundle id
  is a suffix, so `HKSource.default()` alone would miss it).
- **Motion** is recorded only while the watch runs the workout, cut per done tap into a
  `.ptmotion` file, moved by `transferFile`, kept in Application Support (outside the
  single-file backup), pruned 12 months / 200 MB, wiped by Erase all my data.
- Both sides log under category `watch-sync` (notice level); DEBUG watch launch flag
  `--watch-test-toggle-set` taps the first open set.

## Release
Watch Release signing is pinned to profile "PhaseTraining Watch App Store"; `release.yml`
installs it from `BUILD_WATCH_PROVISION_PROFILE_BASE64` and fails in words without it.
Bump `CURRENT_PROJECT_VERSION` only in the release PR. Hardware checks still open are
listed under step 0 in PLAN-watch.md; simulators prove phone-to-watch context only (see the
global `watchos-companion-build-and-sim-verify` skill).
