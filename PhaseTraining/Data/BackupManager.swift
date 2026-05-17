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

    var schemaVersion: Int = BackupEnvelope.currentSchemaVersion
    var exportedAt: Date

    var memory: TrainingMemory?
    var savedSessions: [SavedSession]
    var activeSession: ActiveSession?
    var customRoutines: [CustomRoutine]
    var plan: WeekPlan?
    var overrides: WeekOverrides?
    var reminderEnabled: Bool
}

enum BackupError: Error, LocalizedError {
    case encode(Error)
    case decode(Error)
    case write(Error)
    case read(Error)
    case schemaUnsupported(Int)

    var errorDescription: String? {
        switch self {
        case .encode(let e):           return "Couldn't pack your data: \(e.localizedDescription)"
        case .decode(let e):           return "Backup file is unreadable: \(e.localizedDescription)"
        case .write(let e):            return "Couldn't write the file: \(e.localizedDescription)"
        case .read(let e):             return "Couldn't read the file: \(e.localizedDescription)"
        case .schemaUnsupported(let v): return "Backup is from a newer version (schema \(v)). Update the app and try again."
        }
    }
}

enum BackupManager {

    // MARK: - Encode

    /// Build an envelope by reading every UserDefaults-backed store.
    static func snapshot(defaults: UserDefaults = .standard) -> BackupEnvelope {
        BackupEnvelope(
            exportedAt: Date(),
            memory: decodeIfPresent(defaults: defaults, key: "pt_training_memory"),
            savedSessions: decodeIfPresent(defaults: defaults, key: "pt_sessions") ?? [],
            activeSession: decodeIfPresent(defaults: defaults, key: "pt_active_session"),
            customRoutines: decodeIfPresent(defaults: defaults, key: "pt_custom_routines") ?? [],
            plan: decodeIfPresent(defaults: defaults, key: "pt_week_plan"),
            overrides: decodeIfPresent(defaults: defaults, key: "pt_week_overrides"),
            reminderEnabled: defaults.bool(forKey: "pt_weekly_reminder_enabled")
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
    static func restore(_ envelope: BackupEnvelope, into defaults: UserDefaults) throws {
        try encodeAndWrite(envelope.memory, defaults: defaults, key: "pt_training_memory")
        try encodeAndWrite(envelope.savedSessions, defaults: defaults, key: "pt_sessions")
        try encodeAndWrite(envelope.activeSession, defaults: defaults, key: "pt_active_session")
        try encodeAndWrite(envelope.customRoutines, defaults: defaults, key: "pt_custom_routines")
        try encodeAndWrite(envelope.plan, defaults: defaults, key: "pt_week_plan")
        try encodeAndWrite(envelope.overrides, defaults: defaults, key: "pt_week_overrides")
        defaults.set(envelope.reminderEnabled, forKey: "pt_weekly_reminder_enabled")
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
