# Brief: weekly iCloud Drive backup write (slot A)

## Backlog item

`docs/PLAN-gap-backlog-2026-11b.md`, Phase 7 (Data row): "Last exported" plus a nudge, then a weekly iCloud Drive write. The Data row half is done. This brief is the iCloud write. Owner decided 2026-11-15 to add the entitlement and build it; the portal container `iCloud.com.phasetraining.app` and the regenerated profile exist.

## Skill

None for this area. Read `PhaseTraining/Data/BackupCoordinator.swift` (`BackupStatus`) and `PhaseTraining/Data/BackupManager.swift` (`snapshot`, `encode`) first. Read `phase-training-wipe-spans-userdefaults-and-sqlite` (skill) before touching erase.

## Problem

A lifter who never taps Export loses every workout when the phone dies. The app should write a full backup to the app's iCloud Drive container once a week without a tap.

## Design (fixed)

1. **New file `PhaseTraining/Data/CloudBackup.swift`**, an `enum CloudBackup`:
   - `static let containerID = "iCloud.com.phasetraining.app"`
   - `static let lastWriteKey = "pt_last_icloud_backup_at"` (a `pt_` key, so erase clears it)
   - `static let interval: TimeInterval = 7 * 86_400`
   - `static let fileName = "phasetraining-backup.json"` (one file, overwritten each week)
   - `static func lastWrite(defaults:) -> Date?`
   - `static func isDue(lastWrite: Date?, now: Date) -> Bool`: true when nil or `now - lastWrite >= interval`
   - `static func write(envelope: BackupEnvelope, to containerRoot: URL, now: Date, defaults: UserDefaults) throws`: creates `<containerRoot>/Documents` if missing, writes `BackupManager.encode(envelope)` atomically to `Documents/phasetraining-backup.json`, then stamps `lastWriteKey`. The stamp is set only after the write succeeds.
   - `static func runIfDue(defaults:userDB:now:containerURL:) async`: returns at once when not due. Resolves the container with `containerURL` (default closure `{ FileManager.default.url(forUbiquityContainerIdentifier: containerID) }`) on a detached background task, never on the main thread. A nil container (signed out of iCloud, iCloud Drive off) returns with no write and no stamp, so the next launch tries again. Takes the snapshot with `BackupManager.snapshot(defaults:userDB:)` and calls `write`. A thrown error is logged with `os.Logger` and not stamped.
2. **Trigger.** In `PhaseTraining/App/PhaseTrainingApp.swift`, inside the existing `.onChange(of: scenePhase)` `.active` branch, add one `Task { await CloudBackup.runIfDue() }` guarded by `memory.isOnboarded`, next to the Physiology capture block. No new UI.
3. **Entitlements** (`PhaseTraining/PhaseTraining.entitlements`): add
   - `com.apple.developer.icloud-container-identifiers` = [`iCloud.com.phasetraining.app`]
   - `com.apple.developer.icloud-services` = [`CloudKit`]
   - `com.apple.developer.ubiquity-container-identifiers` = [`iCloud.com.phasetraining.app`]
   Do not touch the watch or widget entitlements.
4. **Files app visibility.** In `PhaseTraining/Info.plist` add `NSUbiquitousContainers` with the container id as key and `NSUbiquitousContainerIsDocumentScopePublic` = true, `NSUbiquitousContainerName` = "Phase Training", `NSUbiquitousContainerSupportedFolderLevels` = "None". If `PhaseTraining/Info.plist` is generated from `Project.yml` `info.properties`, put the keys there instead and say so.
5. **Data row.** Leave `BackupStatus` and the row text unchanged. The row keeps reading the manual export date.
6. **Erase.** `MemoryStore.wipeAllUserData` already removes `pt_` keys, so the stamp clears. Do not delete the iCloud file.

## Files to touch

- `PhaseTraining/Data/CloudBackup.swift` (new)
- `PhaseTrainingTests/CloudBackupTests.swift` (new)
- `PhaseTraining/App/PhaseTrainingApp.swift` (one block)
- `PhaseTraining/PhaseTraining.entitlements`
- `PhaseTraining/Info.plist` or `Project.yml` (`info.properties` for the app target)
- `docs/PLAN-gap-backlog-2026-11b.md` is mine; do not edit it.

## Done looks like

- `CloudBackupTests` passes with these cases: nil last write is due; 6 days is not due; 7 days is due; `write` into a temp directory produces `Documents/phasetraining-backup.json` that `BackupManager.decode` accepts and stamps the key; a `write` into an unwritable path throws and leaves the key unset; `runIfDue` with a `containerURL` returning nil writes nothing and leaves the key unset; `runIfDue` with a temp-directory container writes and stamps; a second `runIfDue` right after does not rewrite (compare file modification date). Use an isolated `UserDefaults(suiteName:)` and a temp `UserDatabase`, following `BackupCoordinatorTests`.
- `BackupCoordinatorTests` still passes.
- `xcodebuild build` for the `PhaseTraining` scheme succeeds with the entitlements change (Debug, simulator).
- Report whether the simulator build accepted the iCloud entitlement keys.

## Slot

Slot A. Simulator UDID `3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2`, `-derivedDataPath /Users/wilburpyn/Library/Developer/Xcode/DerivedData-A`. Every xcodebuild call passes `-destination 'platform=iOS Simulator,id=3CF80E1F-2A07-4F8E-9BA9-DD0A021241B2'`. Run one test class at a time with `-only-testing:PhaseTrainingTests/<Class>`; send the full log to a file and grep it with `grep -nE "failed \(|with [1-9][0-9]* (test )?failure|error:" <log>`.

## xcodegen

This builder runs `xcodegen generate` once, after adding the two new Swift files.

## Rules

Do not commit. Return one final report: files changed, test classes run with pass/fail counts, decisions on anything left open, anything outside scope. On ambiguity pick the conservative option and record it.
