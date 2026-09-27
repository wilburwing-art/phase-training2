# Build 146: the watch (4a companion + 4b labeled motion)

Written 2026-09-27. Track 4 of `PLAN-next-gen.md`, target mid-November. Wilbur said yes on
2026-09-26 to the app writing workouts to Apple Health, on the condition that it creates
no duplicate data.

## Problem

Logging happens on the phone, one set at a time, between sets. That friction is why the
"did" tier is thin, and every model the app has (3b, the twin, PatternEngine, FormModel)
reads that tier. Separately, 4c's motion classifier needs labeled reps that nobody
collects today. A watch that logs sets also knows which exercise every rep belongs to, so
the labeling clock starts the day the watch ships.

## Done means

1. A lifter starts today's session on the phone or the watch, marks sets done, and runs
   the rest timer on the watch. The phone's log matches, set for set, with no manual
   reconciliation, including after a set logged while the phone was out of range.
2. Each session appears in Apple Health exactly once, with heart rate, as a Traditional
   Strength Training workout, and the app's own import never shows it back to the user as
   an outside activity.
3. Every completed set on the watch stores a labeled motion window (exercise, set, reps,
   start and end) on device, within a stated storage cap.
4. TestFlight build 146 installs the watch app from the phone with no manual signing
   step, through the existing tag-driven release.
5. Tests cover the sync reducer, the Health dedupe rules and the motion labeling. Watch UI
   gets a manual check list, since XCUITest on watchOS is thin.

## Out of scope

- 4c, the classifier. 146 only collects.
- Complications, Smart Stack widgets, Live Activities.
- Editing weights or exercises on the watch beyond nudging the planned weight and reps.
  Swaps, adds and notes stay on the phone.
- A standalone watch app that works with no iPhone app installed.
- Uploading motion data anywhere.

## Found while scoping (settle before code)

- **The app's own filter will not catch the watch's workouts.** The watch app has its own
  bundle id (`com.phasetraining.app.watchkitapp`), so a phone-side `HKSource.default()`
  check misses every workout the watch saves. The import has to exclude by a metadata key
  the app writes (below), with the bundle-id prefix as a second guard.
- **Signing covers one profile.** `release.yml` installs one App Store provisioning
  profile from `BUILD_PROVISION_PROFILE_BASE64`. A watch target needs its own App ID with
  the HealthKit capability and its own App Store profile, installed and mapped in
  `ExportOptions.plist`. Creating those is Wilbur's (developer portal), and the workflow
  change is mine.
- **The shipped usage string says the app never writes.** `NSHealthUpdateUsageDescription`
  in `Project.yml` reads "PhaseTraining does not write to Apple Health", and
  `docs/privacy.md` says the same. Both change in 146, in the same commit as the first
  write.

## Design

### Who owns what

The phone stays the source of truth for the session (`SessionStore.saveActive` and
`saveCompleted`). The watch holds a mirror and sends events; it never writes the
`SavedSession`.

- Phone to watch: today's planned session and the active session's state, through
  `WCSession.updateApplicationContext` (latest state wins, delivered when reachable).
- Watch to phone: small events (`setCompleted`, `setUndone`, `restStarted`,
  `sessionStarted`, `sessionEnded`), each with a UUID and a timestamp, through
  `transferUserInfo`, which queues across disconnects and delivers in order.
- A pure reducer on the phone applies events to `ActiveSession`. It is idempotent on event
  UUIDs, so a redelivered event does nothing, and a phone edit to the same set wins over an
  older watch event by timestamp. This reducer is where most of the tests live.

### Apple Health, written once

- The watch runs `HKWorkoutSession` plus `HKLiveWorkoutBuilder`
  (`.traditionalStrengthTraining`) for every watch-driven session. That keeps the watch app
  alive through rests, collects heart rate and energy, and saves the workout.
- **One writer per session.** If a watch workout session ran, the watch saves. If the
  session was logged on the phone alone, the phone saves at `saveCompleted`. Never both.
- Every saved workout carries `HKMetadataKeySyncIdentifier` = `pt-session-<startTime epoch
  ms>` (the `SavedSession` id already derives from `startTime`) and
  `HKMetadataKeySyncVersion` = 1, plus a custom key `pt_session` holding the same id. A
  retry or a re-save replaces the earlier copy in Health instead of adding another.
  **To verify in step 0:** whether HealthKit dedupes on the sync identifier across two
  sources (watch app and phone app) or only within one. If only within one, the
  one-writer rule is the whole guarantee, and a test pins it.
- `HealthKitImporter` drops any workout carrying `pt_session` or coming from a bundle id
  starting `com.phasetraining.app`, before import, activity detection or readiness see it.
  `buildLoadEvents` already takes the largest source per day, so load was never
  double-counted; this closes the "log this outside workout?" and readiness-event paths.
- Starting Apple's own Workout app for the same session still makes two workouts from two
  apps. The app cannot prevent that. The watch's start screen says so once.

### Labeled motion (4b)

- While a set is active, the watch records accelerometer and device motion, ideally
  through `CMBatchedSensorManager` (watchOS 10, only during a workout session). **To verify
  in step 0:** the sample rates it actually delivers on current hardware, and whether any
  permission prompt appears.
- Each set's window is saved with its label: exercise id and name, set index, planned and
  logged reps and weight, set start and end, and the device model. Stored on the watch,
  moved to the phone with `transferFile`, kept in the phone's Application Support
  directory.
- **Size (estimate, from arithmetic, not measured):** 6 axes at 50 Hz as 16-bit values for
  a 40-second set is about 24 KB. At 20 sets a session and 3 sessions a week, that is about
  75 MB a year. At the full 200 Hz it would be about 300 MB a year. Step 3 measures the
  real figure.
- Excluded from the app's backup file and never uploaded. It stays on device, so the App
  Store privacy label does not change for it.

## Steps

0. **Spike (2 days).** Empty watch target through xcodegen, built in CI on a watchOS
   simulator. Answer the two "to verify" questions on a real watch: sync-identifier
   dedupe across sources, and batched sensor rates. Write the answers here before step 1.
   *Started 2026-09-27:* `PhaseTrainingWatch` target in `Project.yml`, embedded by xcodegen
   (the pbxproj carries an "Embed Watch Content" phase), compiles against
   `watchsimulator26.4`. Xcode refuses to build the iOS scheme at all unless the watchOS
   simulator runtime is installed (`xcodebuild -downloadPlatform watchOS`); the macos-26
   runner ships watchOS 26.4 simulators, so CI is unaffected. The two real-watch checks
   are still open.
1. **Sync (1 week).** Message types, the pure reducer, the phone's `WCSession`
   delegate, today's session pushed to the watch. Tests: reducer idempotence, ordering,
   out-of-range queueing, phone-edit-wins.
2. **Watch logging and Health (1.5 weeks).** Set list, done taps, weight and rep nudge,
   rest timer with haptic, `HKWorkoutSession` lifecycle, save with sync metadata. Phone
   saves for phone-only sessions. Importer exclusion. Usage string and `docs/privacy.md`
   rewritten in the same commit. Tests: one-writer rule, importer exclusion by metadata
   and by bundle prefix.
3. **Labeled motion (1 week).** Recording per set, labeling, transfer, storage cap,
   backup exclusion, a DEBUG count on the Signals sheet. Measure the real bytes per set.
4. **Release (3 days).** Second profile secret and `ExportOptions.plist` mapping in
   `release.yml`, watch app icon, manual check list on a real watch, tag
   `v1.1.0-build146`.

About 4 weeks of build, in line with Track 4's estimate for 4a plus 4b.

## Decisions (Wilbur, 2026-09-27: deferred to the recommendations, so all three are as recommended)

1. **Can a session start on the watch with the phone out of range?** Recommended: yes, for
   today's planned session only. The watch queues the events and the phone applies them
   when it is back. The alternative requires the phone for every start, which is simpler
   but fails the gym-locker case.
2. **Should phone-only sessions also go to Apple Health?** Recommended: yes, so Health
   shows every session whether or not the watch was worn. It is the same write grant.
3. **Motion storage cap.** Recommended: keep 12 months or 200 MB, whichever comes first,
   oldest dropped first.

## Needs Wilbur in the developer portal (before step 4)

- A new App ID `com.phasetraining.app.watchkitapp` with HealthKit enabled.
- An App Store provisioning profile for it, base64-encoded into a new repo secret
  `BUILD_WATCH_PROVISION_PROFILE_BASE64`. The `web-automation` route can do the portal
  clicks if you would rather not.
