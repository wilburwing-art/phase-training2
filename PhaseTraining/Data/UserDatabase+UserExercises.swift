// UserDatabase+UserExercises.swift — exercises the user creates for lifts the
// catalog lacks.
//
// A custom exercise surfaces as an `Exercise` whose id is the NEGATIVE of its
// row id: positive is catalog, 0 is "unresolved", negative is custom. Only the
// picker (`ExerciseSearch.run`) and display resolution (`ExerciseLookupCache`)
// read this table. `CoachDatabase` stays catalog-only, which is what keeps the
// generator, the season engine and authored routines from ever picking one.
//
// Logged sessions, History, PRs and CSV export are keyed by name, so a custom
// exercise may not share a name (or alias) with the catalog, and there is no
// rename: either would merge or detach name-keyed history.

import Foundation
import SQLite3

struct UserExercise: Codable, Identifiable, Equatable {
    /// user.db row id, positive. Never reissued after a delete.
    var id: Int64
    var name: String
    /// `MuscleBucket.rawValue`, or nil when the user picked none.
    var muscleBucket: String?
    var notes: String?
    var createdAt: Date

    var exercise: Exercise {
        Exercise(id: -Int(id), name: name, slug: "custom-\(id)", description: notes,
                 instructions: nil, cues: [], difficulty: nil, modality: nil, environment: nil,
                 isCompound: false, isUnilateral: false,
                 defaultSets: nil, defaultReps: nil, defaultRest: nil, defaultDuration: nil,
                 regression: nil, progression: nil,
                 imageURL: nil, thumbnailURL: nil, videoURL: nil, sourceVideoAttribution: nil)
    }
}

enum UserExerciseError: Error, Equatable {
    case emptyName, nameTaken, storeUnavailable
}

extension Exercise {
    /// True for an exercise from user.db (`UserExercise.exercise`).
    var isCustom: Bool { id < 0 }
}

extension UserDatabase {

    private static let userExerciseColumns = "id, name, muscle_bucket, notes, created_at"

    func listUserExercises() -> [UserExercise] { withLock {
        guard let db else { return [] }
        let sql = "SELECT \(Self.userExerciseColumns) FROM user_exercises ORDER BY name COLLATE NOCASE"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [UserExercise] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(userExerciseRow(stmt)) }
        return out
    } }

    /// Exact name match, ignoring case and surrounding whitespace.
    func userExercise(named name: String) -> UserExercise? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return withLock { () -> UserExercise? in
            guard let db else { return nil }
            let sql = "SELECT \(Self.userExerciseColumns) FROM user_exercises WHERE name = ? COLLATE NOCASE"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, trimmed, -1, SQLITE_TRANSIENT_USER)
            return sqlite3_step(stmt) == SQLITE_ROW ? userExerciseRow(stmt) : nil
        }
    }

    func userExercise(id: Int64) -> UserExercise? { withLock {
        guard let db else { return nil }
        let sql = "SELECT \(Self.userExerciseColumns) FROM user_exercises WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        return sqlite3_step(stmt) == SQLITE_ROW ? userExerciseRow(stmt) : nil
    } }

    /// Create a custom exercise. The name is trimmed and must not match an
    /// existing custom exercise or anything the catalog resolves (name, slug or
    /// alias), since history and PRs are keyed by name.
    func createUserExercise(name: String,
                            muscleBucket: MuscleBucket?,
                            notes: String?,
                            catalog: CoachDatabase = .shared) -> Result<UserExercise, UserExerciseError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyName) }
        guard db != nil, unavailableReason == nil else { return .failure(.storeUnavailable) }
        let catalogHit = catalog.listExercises(search: trimmed)
            .contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
            || catalog.exerciseId(forImportName: trimmed) != nil
        guard !catalogHit, userExercise(named: trimmed) == nil else { return .failure(.nameTaken) }

        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedNotes = (trimmedNotes?.isEmpty ?? true) ? nil : trimmedNotes
        // Whole seconds: an integral Double converts to and from Date exactly,
        // so the returned value equals a later read and a backup round trip.
        let createdAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let result: Result<UserExercise, UserExerciseError> = withLock {
            guard let db else { return .failure(.storeUnavailable) }
            let sql = "INSERT INTO user_exercises(name, muscle_bucket, notes, created_at) VALUES (?, ?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return .failure(.storeUnavailable) }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, trimmed, -1, SQLITE_TRANSIENT_USER)
            bindOptionalText(stmt, 2, muscleBucket?.rawValue)
            bindOptionalText(stmt, 3, storedNotes)
            sqlite3_bind_double(stmt, 4, createdAt.timeIntervalSince1970)
            switch sqlite3_step(stmt) {
            case SQLITE_DONE:
                return .success(UserExercise(id: sqlite3_last_insert_rowid(db), name: trimmed,
                                             muscleBucket: muscleBucket?.rawValue, notes: storedNotes,
                                             createdAt: createdAt))
            case SQLITE_CONSTRAINT:
                // The UNIQUE NOCASE index caught a name another writer added
                // between the check above and this insert.
                return .failure(.nameTaken)
            default:
                return .failure(.storeUnavailable)
            }
        }
        if case .success = result { ExerciseLookupCache.shared.reset() }
        return result
    }

    /// Hard delete. Sessions and saved routines keep the name string, so
    /// History and PRs under that name are unchanged.
    func deleteUserExercise(id: Int64) {
        withLock {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM user_exercises WHERE id = ?", -1, &stmt, nil) == SQLITE_OK
            else { return }
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        ExerciseLookupCache.shared.reset()
    }

    /// Restore path: insert with the row's original id, so saved routines that
    /// reference `-id` still point at the same exercise. Does not reset
    /// `ExerciseLookupCache`: the restore resets it once after the whole loop.
    func insertUserExercise(_ ex: UserExercise) {
        withLock {
            guard let db else { return }
            let sql = "INSERT INTO user_exercises(\(Self.userExerciseColumns)) VALUES (?, ?, ?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_int64(stmt, 1, ex.id)
            sqlite3_bind_text(stmt, 2, ex.name, -1, SQLITE_TRANSIENT_USER)
            bindOptionalText(stmt, 3, ex.muscleBucket)
            bindOptionalText(stmt, 4, ex.notes)
            sqlite3_bind_double(stmt, 5, ex.createdAt.timeIntervalSince1970)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func clearUserExercises() {
        withLock {
            guard let db else { return }
            sqlite3_exec(db, "DELETE FROM user_exercises", nil, nil, nil)
        }
        ExerciseLookupCache.shared.reset()
    }

    func userExerciseCount() -> Int { withLock { countLocked(table: "user_exercises") } }

    // MARK: - Row helpers

    private func userExerciseRow(_ stmt: OpaquePointer?) -> UserExercise {
        UserExercise(id: sqlite3_column_int64(stmt, 0),
                     name: text(stmt, 1) ?? "",
                     muscleBucket: text(stmt, 2),
                     notes: text(stmt, 3),
                     createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)))
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let value { sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT_USER) }
        else { sqlite3_bind_null(stmt, idx) }
    }
}
