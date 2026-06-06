// BackupManager.swift — single-file export + restore of the user's data.
//
// Bridges every Codable store under a versioned envelope so a user who
// switches phones (or loses one) can recover their training history, custom
// workouts, profile, plan, and overrides. Not a sync mechanism — that needs
// CloudKit — but it gets the user off "lose phone = lose everything".
//
// Export goes through the system share sheet (Profile screen). Restore goes
// through a file importer that reads the JSON and overwrites each store.
// Restore is destructive on purpose — partial merges across multiple devices
// would be its own design.

import Foundation

struct BackupEnvelope: Codable {
    static let currentSchemaVersion = 1
    /// TrainingMemory's schema version in the running app. Pinned into each
    /// export (`memorySchemaVersion`) so a later restore can tell when a
    /// backup predates fields the current memory schema carries.
    static let currentMemorySchemaVersion = TrainingMemory().schemaVersion

    var schemaVersion: Int = BackupEnvelope.currentSchemaVersion
    /// `TrainingMemory.schemaVersion` of the embedded memory at export time.
    /// Optional so backups written before this field existed still decode;
    /// `isMemorySchemaStale` falls back to the payload's own version.
    var memorySchemaVersion: Int? = nil
    var exportedAt: Date

    var memory: TrainingMemory?
    var savedSessions: [SavedSession]
    var activeSession: ActiveSession?
    var customRoutines: [CustomRoutine]
    var plan: WeekPlan?
    var overrides: WeekOverrides?
    var reminderEnabled: Bool

    /// True when the embedded memory predates the app's current
    /// TrainingMemory schema — fields added since were decoded as defaults,
    /// not real values. Informational only: stale backups still restore
    /// (TrainingMemory's tolerant decoder guarantees that); callers can
    /// surface a "backup is from an older version" notice off this.
    var isMemorySchemaStale: Bool {
        guard let memory else { return false }
        return (memorySchemaVersion ?? memory.schemaVersion) < Self.currentMemorySchemaVersion
    }
}

enum BackupError: Error, LocalizedError {
    /// Which slice of the restore failed to land. Raw value is the
    /// user-facing name, matching the export copy ("profile, plan, sessions,
    /// and custom workouts").
    enum RestorePhase: String {
        case routines = "custom workouts"
        case sessions = "workout history"
        case settingsAndMemory = "profile and plan"
    }

    case encode(Error)
    case decode(Error)
    case write(Error)
    case read(Error)
    case schemaUnsupported(Int)
    case restoreIncomplete(RestorePhase)

    var errorDescription: String? {
        switch self {
        case .encode(let e):           return "Couldn't pack your data: \(e.localizedDescription)"
        case .decode(let e):           return "Backup file is unreadable: \(e.localizedDescription)"
        case .write(let e):            return "Couldn't write the file: \(e.localizedDescription)"
        case .read(let e):             return "Couldn't read the file: \(e.localizedDescription)"
        case .schemaUnsupported(let v): return "Backup is from a newer version (schema \(v)). Update the app and try again."
        case .restoreIncomplete(let phase):
            return "Restore couldn't save your \(phase.rawValue), so your previous data was kept."
        }
    }
}

enum BackupManager {

    // MARK: - Encode

    /// Build an envelope. Memory / active session / plan / overrides /
    /// reminder live in UserDefaults; saved sessions + custom routines live
    /// in `user.db` (UserDatabase) since the SQLite migration.
    ///
    /// Read order matters: SQLite reads happen first (each is internally
    /// locked by UserDatabase), then UserDefaults reads happen in a tight
    /// block at the end. This minimizes the window where a concurrent write
    /// to one store could tear the snapshot across the two. There's no
    /// cross-store transaction available on iOS, so this is the best we can
    /// do without taking an app-wide write-pause lock.
    static func snapshot(defaults: UserDefaults = .standard,
                         userDB: UserDatabase = .defaultStore()) -> BackupEnvelope {
        let exportedAt = Date()
        // 1. SQLite first (bigger, slower, internally locked).
        let savedSessions = userDB.listSavedSessions()
        let customRoutines = userDB.listRoutines()
        // 2. UserDefaults last, back-to-back.
        let memory: TrainingMemory? = decodeIfPresent(defaults: defaults, key: "pt_training_memory")
        let activeSession: ActiveSession? = decodeIfPresent(defaults: defaults, key: "pt_active_session")
        let plan: WeekPlan? = decodeIfPresent(defaults: defaults, key: "pt_week_plan")
        let overrides: WeekOverrides? = decodeIfPresent(defaults: defaults, key: "pt_week_overrides")
        let reminderEnabled = defaults.bool(forKey: "pt_weekly_reminder_enabled")
        return BackupEnvelope(
            memorySchemaVersion: memory?.schemaVersion,
            exportedAt: exportedAt,
            memory: memory,
            savedSessions: savedSessions,
            activeSession: activeSession,
            customRoutines: customRoutines,
            plan: plan,
            overrides: overrides,
            reminderEnabled: reminderEnabled
        )
    }

    /// Encode the envelope as pretty JSON suitable for a .json file.
    static func encode(_ envelope: BackupEnvelope) throws -> Data {
        do {
            return try jsonEncoder().encode(envelope)
        } catch {
            throw BackupError.encode(error)
        }
    }

    /// Write the envelope to a temp file the share sheet can present. Caller
    /// is responsible for cleanup; the OS prunes tmp eventually anyway.
    @discardableResult
    static func writeTempFile(_ envelope: BackupEnvelope) throws -> URL {
        let data = try encode(envelope)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "phasetraining-backup-\(f.string(from: envelope.exportedAt)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw BackupError.write(error)
        }
        return url
    }

    // MARK: - Decode + restore

    /// Parse a previously-exported envelope from JSON data.
    static func decode(_ data: Data) throws -> BackupEnvelope {
        let envelope: BackupEnvelope
        do {
            envelope = try jsonDecoder().decode(BackupEnvelope.self, from: data)
        } catch {
            throw BackupError.decode(error)
        }
        if envelope.schemaVersion > BackupEnvelope.currentSchemaVersion {
            throw BackupError.schemaUnsupported(envelope.schemaVersion)
        }
        return envelope
    }

    /// Restore destructively into the given UserDefaults. Caller is
    /// responsible for refreshing in-memory stores (drop + recreate, or
    /// reload by hand). For the app, the simplest path is to terminate +
    /// re-launch; for unit tests we re-instantiate stores from the same
    /// defaults to verify the round-trip.
    static func restore(_ envelope: BackupEnvelope,
                        into defaults: UserDefaults,
                        userDB: UserDatabase = .shared) throws {
        // Customs + saved sessions live in user.db. Restore is destructive,
        // but must never be partial: UserDatabase writes swallow SQLite
        // errors, so a failed insert mid-populate would silently leave the
        // store cleared. Capture the prior rows, repopulate, verify every
        // row landed, and put the prior rows back if any didn't — all
        // before a single UserDefaults key is touched, so a failed restore
        // changes nothing.
        let priorRoutines = userDB.listRoutines()
        let priorSessions = userDB.listSavedSessions()
        userDB.clearAll()
        for routine in envelope.customRoutines { userDB.save(routine) }
        userDB.clearAllSessions()
        for session in envelope.savedSessions { userDB.saveSession(session) }
        if userDB.routineCount() != envelope.customRoutines.count {
            rollBack(userDB, routines: priorRoutines, sessions: priorSessions)
            throw BackupError.restoreIncomplete(.routines)
        }
        if userDB.savedSessionCount() != envelope.savedSessions.count {
            rollBack(userDB, routines: priorRoutines, sessions: priorSessions)
            throw BackupError.restoreIncomplete(.sessions)
        }

        // UserDefaults half gets the same all-or-nothing contract: capture
        // every key the restore touches before the first write; if any
        // encode throws mid-sequence, put the captured values back (and undo
        // the already-populated SQLite half) so a failed restore changes
        // nothing.
        let touchedKeys = ["pt_training_memory", "pt_active_session",
                           "pt_week_plan", "pt_week_overrides",
                           "pt_weekly_reminder_enabled",
                           "pt_sessions", "pt_custom_routines"]
        var priorValues: [String: Any] = [:]
        for key in touchedKeys { priorValues[key] = defaults.object(forKey: key) }
        do {
            try encodeAndWrite(envelope.memory, defaults: defaults, key: "pt_training_memory")
            try encodeAndWrite(envelope.activeSession, defaults: defaults, key: "pt_active_session")
            try encodeAndWrite(envelope.plan, defaults: defaults, key: "pt_week_plan")
            try encodeAndWrite(envelope.overrides, defaults: defaults, key: "pt_week_overrides")
            defaults.set(envelope.reminderEnabled, forKey: "pt_weekly_reminder_enabled")
            // Wipe legacy UserDefaults keys so a stale post-migration import
            // path can never resurrect them. Idempotent.
            defaults.removeObject(forKey: "pt_sessions")
            defaults.removeObject(forKey: "pt_custom_routines")
        } catch {
            for key in touchedKeys {
                if let prior = priorValues[key] {
                    defaults.set(prior, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            rollBack(userDB, routines: priorRoutines, sessions: priorSessions)
            throw BackupError.restoreIncomplete(.settingsAndMemory)
        }
    }

    /// Put the prior SQLite rows back after a failed restore. Rollback uses
    /// the same write path as the populate, so a genuinely failing disk can
    /// defeat it too — but envelope rows that can't all land (e.g. colliding
    /// primary keys) leave the prior data intact.
    private static func rollBack(_ userDB: UserDatabase,
                                 routines: [CustomRoutine],
                                 sessions: [SavedSession]) {
        userDB.clearAll()
        for routine in routines { userDB.save(routine) }
        userDB.clearAllSessions()
        for session in sessions { userDB.saveSession(session) }
    }

    // MARK: - Helpers

    private static func decodeIfPresent<T: Decodable>(defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? jsonDecoder().decode(T.self, from: data)
    }

    private static func encodeAndWrite<T: Encodable>(_ value: T?, defaults: UserDefaults, key: String) throws {
        if let value {
            do {
                let data = try jsonEncoder().encode(value)
                defaults.set(data, forKey: key)
            } catch {
                throw BackupError.encode(error)
            }
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func jsonEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func jsonDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
