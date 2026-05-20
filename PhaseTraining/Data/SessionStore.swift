// SessionStore.swift — saved-history persistence + active-session helpers.
//
// Saved sessions live in `user.db` via UserDatabase (sessions →
// session_exercises → session_sets, indexed on template_id and exercise
// name). The hot autosave path for the in-flight session stays on
// `pt_active_session` in UserDefaults — atomic JSON replace is fine there
// and we don't want SQLite write amplification on every keystroke.
//
// On first launch after this build, any pre-existing `pt_sessions`
// UserDefaults JSON blob is imported into user.db and the key is cleared.

import Foundation
import Combine

final class SessionStore: ObservableObject {
    private static let activeKey = "pt_active_session"
    private static let legacySavedKey = "pt_sessions"
    private static let savedMigrationFlag = "pt_sessions_migrated_v1"

    @Published var savedSessions: [SavedSession]
    @Published var active: ActiveSession?

    private let defaults: UserDefaults
    private let userDB: UserDatabase

    init(defaults: UserDefaults = .standard, userDB: UserDatabase? = nil) {
        self.defaults = defaults
        let resolvedDB = userDB ?? UserDatabase.defaultStore()
        self.userDB = resolvedDB

        Self.migrateLegacySessionsIfNeeded(defaults: defaults, userDB: resolvedDB)
        self.savedSessions = resolvedDB.listSavedSessions()

        if let data = defaults.data(forKey: Self.activeKey),
           let session = try? Self.decoder().decode(ActiveSession.self, from: data) {
            self.active = session
        } else {
            self.active = nil
        }

        // Inactivity-reminder lifecycle on launch: if an active session was
        // restored, start the 30-min clock fresh. Otherwise drop any stale
        // scheduled notification left over from a previous run.
        if active != nil {
            InactivityReminderScheduler.scheduleForActiveSession()
        } else {
            InactivityReminderScheduler.cancel()
        }
    }

    // MARK: - One-shot legacy migration

    /// Imports the old UserDefaults JSON blob into UserDatabase on first
    /// launch of the SQLite-backed sessions build. Guarded by a flag so
    /// reruns are no-ops. The legacy UserDefaults key is removed after a
    /// successful import.
    private static func migrateLegacySessionsIfNeeded(defaults: UserDefaults, userDB: UserDatabase) {
        if defaults.bool(forKey: savedMigrationFlag) { return }
        defer { defaults.set(true, forKey: savedMigrationFlag) }

        guard let data = defaults.data(forKey: legacySavedKey) else { return }
        guard let legacy = try? decoder().decode([SavedSession].self, from: data) else { return }

        for session in legacy {
            userDB.saveSession(session)
        }
        defaults.removeObject(forKey: legacySavedKey)
    }

    // MARK: - Codec

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    // MARK: - Active session (UserDefaults; hot autosave path)

    func loadActive() -> ActiveSession? {
        guard let data = defaults.data(forKey: Self.activeKey) else { return nil }
        return try? Self.decoder().decode(ActiveSession.self, from: data)
    }

    func saveActive(_ session: ActiveSession) {
        active = session
        if let data = try? Self.encoder().encode(session) {
            defaults.set(data, forKey: Self.activeKey)
        }
        // Reset the "forgot to finish" reminder clock on every mutation.
        // The 30-min trigger fires only if no further activity follows.
        InactivityReminderScheduler.scheduleForActiveSession()
    }

    func clearActive() {
        active = nil
        defaults.removeObject(forKey: Self.activeKey)
        InactivityReminderScheduler.cancel()
    }

    // MARK: - Saved sessions (SQLite via UserDatabase)

    /// Replaces the entire saved-history list. Used by Backup restore.
    func saveAll(_ sessions: [SavedSession]) {
        userDB.clearAllSessions()
        for session in sessions {
            userDB.saveSession(session)
        }
        savedSessions = userDB.listSavedSessions()
    }

    func deleteSession(id: TimeInterval) {
        userDB.deleteSession(startTime: Date(timeIntervalSince1970: id))
        savedSessions = userDB.listSavedSessions()
    }

    /// Upsert one already-saved session with edits (weight / reps / rpe /
    /// done) intact. UserDatabase.saveSession is upsert-by-start_time so
    /// the row is replaced in place; the @Published list is refreshed so
    /// SwiftUI rebinds. Used by HistoryScreen's set-level edit flow.
    func updateSession(_ session: SavedSession) {
        userDB.saveSession(session)
        savedSessions = userDB.listSavedSessions()
    }

    func clearSavedSessions() {
        userDB.clearAllSessions()
        savedSessions = []
    }

    // MARK: - Phase 13f: coach workout-diff applies to a live session
    //
    // If the user has already started today's workout, the coach's swap/
    // adjust operations must rebuild the ActiveSession too — otherwise the
    // user keeps logging against the old exercises until they restart.
    //
    // Rules:
    //   - Match exercises by case-insensitive name (same key the diff used).
    //   - For matched exercises, preserve LoggedSets (especially done=true).
    //     Update targetSets / targetReps / rest only.
    //   - For new exercises (swap targets), build a fresh LoggedExercise.
    //   - For removed exercises (swap sources without a match): drop them
    //     UNLESS the user had logged sets there. If they had logged work,
    //     keep the exercise in the session so they don't lose history.

    /// Returns true if the diff applied to the active session, false if no
    /// active session existed.
    @discardableResult
    func applyWorkoutDiffToActiveSession(_ diff: WorkoutDiff) -> Bool {
        guard var current = active else { return false }

        var existing: [String: LoggedExercise] = [:]
        for ex in current.exercises {
            existing[ex.name.lowercased()] = ex
        }

        var rebuilt: [LoggedExercise] = []
        var consumedNames = Set<String>()

        for gex in diff.after.exercises {
            let key = gex.name.lowercased()
            consumedNames.insert(key)

            if let prior = existing[key] {
                let reps = Int(gex.reps.prefix(while: { $0.isNumber })) ?? prior.targetReps
                var updated = prior
                updated.targetSets = max(1, gex.sets)
                updated.targetReps = reps
                updated.rest = gex.restSeconds
                while updated.sets.count < updated.targetSets {
                    updated.sets.append(LoggedSet(num: updated.sets.count + 1, weight: "", reps: "", rpe: "", done: false))
                }
                rebuilt.append(updated)
            } else {
                let reps = Int(gex.reps.prefix(while: { $0.isNumber })) ?? 8
                let target = max(1, gex.sets)
                let sets = (0..<target).map { i in
                    LoggedSet(num: i + 1, weight: "", reps: "", rpe: "", done: false)
                }
                rebuilt.append(LoggedExercise(
                    id: "gex-\(gex.id)",
                    name: gex.name,
                    type: nil,
                    unit: "lbs",
                    targetSets: target,
                    targetReps: reps,
                    rest: gex.restSeconds,
                    sets: sets,
                    prevSets: []
                ))
            }
        }

        for (key, ex) in existing where !consumedNames.contains(key) {
            let hadWork = ex.sets.contains(where: { $0.done })
            if hadWork { rebuilt.append(ex) }
        }

        current.exercises = rebuilt
        current.name = diff.after.title
        saveActive(current)
        return true
    }

    // MARK: - History rollover

    /// Newest saved session matching `templateId`, or nil. Indexed query in
    /// UserDatabase (template_id, start_time DESC) — replaces an O(N) scan.
    func getPreviousSession(templateId: String) -> SavedSession? {
        return userDB.previousSession(templateId: templateId)
    }

    /// Build a fresh ActiveSession from the named template, pulling prior set
    /// weight + reps forward when available. Mirrors `data.jsx:51-77`.
    func createSession(templateId: String) -> ActiveSession {
        guard let tmpl = WorkoutTemplate.byId(templateId) else {
            return ActiveSession(
                templateId: templateId,
                name: "",
                category: "",
                startTime: Date(),
                exercises: [],
                feel: nil,
                note: nil
            )
        }

        return buildSession(templateId: templateId,
                            name: tmpl.name,
                            category: tmpl.category,
                            exercises: tmpl.exercises)
    }

    /// Build a fresh ActiveSession from an ad-hoc template (e.g. one assembled
    /// from coach.db). Same prev-pull semantics as the templateId path.
    func createSession(from tmpl: WorkoutTemplate) -> ActiveSession {
        return buildSession(templateId: tmpl.id,
                            name: tmpl.name,
                            category: tmpl.category,
                            exercises: tmpl.exercises)
    }

    /// Shared session-construction body. Pulls prev autofill in two passes:
    ///
    ///   1. templateId-match — UserDatabase.previousSession on (template_id).
    ///   2. cross-template name match — UserDatabase.mostRecentExerciseByName
    ///      for any exercise that pass 1 didn't fill. Walks the indexed
    ///      (name, session_start DESC) ordering and returns the most recent
    ///      occurrence that has at least one completed set with weight.
    ///
    /// Closes leak #2 from the loop audit: progressive-overload signal flows
    /// even when the workout shape changes week to week. Two indexed lookups
    /// replace an O(N) + O(N×M) pair of cross-session scans.
    private func buildSession(templateId: String,
                              name: String,
                              category: String,
                              exercises: [ExerciseTemplate]) -> ActiveSession {
        let templatePrev = getPreviousSession(templateId: templateId)

        let logged: [LoggedExercise] = exercises.map { ex in
            let templateMatchedEx = templatePrev?.exercises.first(where: { $0.id == ex.id })
            let prevEx = templateMatchedEx ?? userDB.mostRecentExerciseByName(ex.name)

            let sets: [LoggedSet] = (0..<ex.targetSets).map { i in
                let prevSet: LoggedSet? = (prevEx?.sets.indices.contains(i) ?? false) ? prevEx?.sets[i] : nil
                return LoggedSet(
                    num: i + 1,
                    weight: prevSet.map { $0.weight } ?? "",
                    reps: prevSet.map { $0.reps } ?? String(ex.targetReps),
                    rpe: "",
                    done: false
                )
            }
            return LoggedExercise(
                id: ex.id,
                name: ex.name,
                type: ex.type,
                unit: ex.unit,
                targetSets: ex.targetSets,
                targetReps: ex.targetReps,
                rest: ex.rest,
                sets: sets,
                prevSets: prevEx?.sets ?? [],
                rpe: ex.rpe,
                tempo: ex.tempo
            )
        }

        return ActiveSession(
            templateId: templateId,
            name: name,
            category: category,
            startTime: Date(),
            exercises: logged,
            feel: nil,
            note: nil
        )
    }

    /// Persist a completed session: insert into SQLite, prepend to the
    /// @Published cache, clear active.
    @discardableResult
    func saveCompleted(_ active: ActiveSession, feel: String?, note: String?) -> SavedSession {
        let endTime = Date()
        let duration = max(0, Int(endTime.timeIntervalSince(active.startTime)))
        let saved = SavedSession(
            templateId: active.templateId,
            name: active.name,
            category: active.category,
            startTime: active.startTime,
            exercises: active.exercises,
            feel: feel,
            note: note,
            endTime: endTime,
            duration: duration
        )
        userDB.saveSession(saved)
        savedSessions.insert(saved, at: 0)
        clearActive()
        return saved
    }

    // MARK: - PRs (SQL-aggregated)
    //
    // Prior best-weight-per-(exercise,reps) lookup goes through one indexed
    // SQL query (`bestWeightsByExerciseAndReps`), replacing the O(N×M×K)
    // nested walk over savedSessions. The PR-emission loop still runs in
    // Swift — its inputs are either a live ActiveSession's exercises (not
    // in DB yet) or a single SQL fetch of qualifying-set rows.

    /// Personal records achieved by `exercises` — completed sets whose weight
    /// at given rep count beats every prior set of the same exercise (matched
    /// by name, ACROSS all templates) in stored history. Used by
    /// CompleteScreen to celebrate before save commits, and by post-save
    /// surfaces.
    ///
    /// `excludingSessionId` lets a post-save call self-exclude when the
    /// current session is already in user.db.
    func personalRecords(in exercises: [LoggedExercise],
                         excludingSessionId: TimeInterval? = nil) -> [PersonalRecord] {
        let best = userDB.bestWeightsByExerciseAndReps(
            excludingSessionStart: excludingSessionId.map { Int64($0) }
        )

        var out: [PersonalRecord] = []
        var emitted: Set<String> = []
        for ex in exercises {
            for set in ex.sets where set.done {
                let reps = Int(set.reps) ?? 0
                let weight = Double(set.weight) ?? 0
                guard reps > 0, weight > 0 else { continue }
                let prior = best[ex.name]?[reps] ?? 0
                guard weight > prior else { continue }
                let key = "\(ex.name)|\(reps)"
                if emitted.contains(key) { continue }
                emitted.insert(key)
                out.append(PersonalRecord(
                    exerciseName: ex.name,
                    reps: reps,
                    weight: weight,
                    previousBest: prior > 0 ? prior : nil,
                    date: Date()
                ))
            }
        }
        return out
    }

    /// All PR events across saved history, newest first. Replays the
    /// running-best walk over a single indexed SQL fetch of qualifying
    /// completed sets (ordered by session_start ASC). One emission per
    /// (exercise, reps) pair per session.
    ///
    /// Used by ProgressScreen's PR feed + per-exercise sparklines.
    func allPersonalRecords() -> [PersonalRecord] {
        let rows = userDB.qualifyingSetsForPRs()
        var best: [String: [Int: Double]] = [:]
        var events: [PersonalRecord] = []
        var currentSession: Int64 = .min
        var emitted: Set<String> = []

        for r in rows {
            if r.sessionStart != currentSession {
                currentSession = r.sessionStart
                emitted = []
            }
            let prior = best[r.name, default: [:]][r.reps] ?? 0
            guard r.weight > prior else { continue }
            let key = "\(r.name)|\(r.reps)"
            if !emitted.contains(key) {
                emitted.insert(key)
                events.append(PersonalRecord(
                    exerciseName: r.name,
                    reps: r.reps,
                    weight: r.weight,
                    previousBest: prior > 0 ? prior : nil,
                    date: Date(timeIntervalSince1970: TimeInterval(r.sessionStart))
                ))
            }
            best[r.name, default: [:]][r.reps] = r.weight
        }
        return events.reversed()
    }

    // MARK: - Stats

    /// Mirrors `data.jsx:80-92` — total/done set counts + 1-decimal avg RPE.
    /// Returns `"—"` for `avgRpe` when no done-set has a numeric RPE.
    func stats(for session: ActiveSession) -> SessionStats {
        var totalSets = 0
        var doneSets = 0
        var totalRpe: Double = 0
        var rpeCount = 0

        for ex in session.exercises {
            for s in ex.sets {
                totalSets += 1
                if s.done {
                    doneSets += 1
                    if !s.rpe.isEmpty, let v = Double(s.rpe), !v.isNaN {
                        totalRpe += v
                        rpeCount += 1
                    }
                }
            }
        }

        let avgRpe: String
        if rpeCount > 0 {
            let avg = totalRpe / Double(rpeCount)
            avgRpe = String(format: "%.1f", avg)
        } else {
            avgRpe = "—"
        }
        return SessionStats(totalSets: totalSets, doneSets: doneSets, avgRpe: avgRpe)
    }
}
