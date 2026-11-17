// CloudBackup.swift — a full backup written to the app's iCloud Drive
// container once a week, without a tap.
//
// One file, overwritten each week. The write date lives in UserDefaults under
// a `pt_` key, so "Erase all data" clears it. Erase does not touch the iCloud
// file. The Profile Data row keeps reading the manual export date
// (`BackupStatus`).

import Foundation
import os

enum CloudBackup {
    static let containerID = "iCloud.com.phasetraining.app"
    static let lastWriteKey = "pt_last_icloud_backup_at"
    static let interval: TimeInterval = 7 * 86_400
    static let fileName = "phasetraining-backup.json"

    private static let log = Logger(subsystem: "com.phasetraining.app", category: "CloudBackup")

    static func lastWrite(defaults: UserDefaults = .standard) -> Date? {
        guard let stamp = defaults.object(forKey: lastWriteKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: stamp)
    }

    static func isDue(lastWrite: Date?, now: Date = Date()) -> Bool {
        guard let lastWrite else { return true }
        return now.timeIntervalSince(lastWrite) >= interval
    }

    /// Writes the envelope to `<containerRoot>/Documents/phasetraining-backup.json`
    /// and stamps `lastWriteKey` only after the write succeeds.
    static func write(envelope: BackupEnvelope,
                      to containerRoot: URL,
                      now: Date = Date(),
                      defaults: UserDefaults = .standard) throws {
        let data = try BackupManager.encode(envelope)
        let documents = containerRoot.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try data.write(to: documents.appendingPathComponent(fileName), options: [.atomic])
        defaults.set(now.timeIntervalSince1970, forKey: lastWriteKey)
    }

    /// Weekly write. Returns at once when not due. A nil container (signed out
    /// of iCloud, iCloud Drive off) writes nothing and stamps nothing, so the
    /// next launch tries again.
    static func runIfDue(
        defaults: UserDefaults = .standard,
        userDB: UserDatabase = .defaultStore(),
        now: Date = Date(),
        containerURL: @escaping @Sendable () -> URL? = {
            FileManager.default.url(forUbiquityContainerIdentifier: CloudBackup.containerID)
        }
    ) async {
        guard isDue(lastWrite: lastWrite(defaults: defaults), now: now) else { return }
        // Resolving the container can block on iCloud, so it stays off the main thread.
        let root = await Task.detached(priority: .utility) { containerURL() }.value
        guard let root else { return }
        let envelope = BackupManager.snapshot(defaults: defaults, userDB: userDB)
        do {
            try write(envelope: envelope, to: root, now: now, defaults: defaults)
        } catch {
            log.error("iCloud backup write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
