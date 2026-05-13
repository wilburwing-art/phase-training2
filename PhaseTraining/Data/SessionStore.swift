// SessionStore.swift — UserDefaults-backed persistence + state helpers.
// Ports `handoff/proto/data.jsx` localStorage layer + createSession / sessionStats helpers.

import Foundation
import Combine

final class SessionStore: ObservableObject {
    private static let activeKey = "pt_active_session"
    private static let savedKey  = "pt_sessions"

    @Published var savedSessions: [SavedSession]
    @Published var active: ActiveSession?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        if let data = defaults.data(forKey: Self.savedKey),
           let sessions = try? decoder.decode([SavedSession].self, from: data) {
            self.savedSessions = sessions
        } else {
            self.savedSessions = []
        }

        if let data = defaults.data(forKey: Self.activeKey),
           let session = try? decoder.decode(ActiveSession.self, from: data) {
            self.active = session
        } else {
            self.active = nil
        }
    }

    // MARK: - Encoder/decoder

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    // MARK: - Raw load/save (mirror data.jsx helpers)

    func loadSaved() -> [SavedSession] {
        guard let data = defaults.data(forKey: Self.savedKey) else { return [] }
        return (try? decoder().decode([SavedSession].self, from: data)) ?? []
    }

    func saveAll(_ sessions: [SavedSession]) {
        savedSessions = sessions
        if let data = try? encoder().encode(sessions) {
            defaults.set(data, forKey: Self.savedKey)
        }
    }

    func loadActive() -> ActiveSession? {
        guard let data = defaults.data(forKey: Self.activeKey) else { return nil }
        return try? decoder().decode(ActiveSession.self, from: data)
    }

    func saveActive(_ session: ActiveSession) {
        active = session
        if let data = try? encoder().encode(session) {
            defaults.set(data, forKey: Self.activeKey)
        }
    }

    func clearActive() {
        active = nil
        defaults.removeObject(forKey: Self.activeKey)
    }

    // MARK: - History rollover

    /// Newest saved session matching `templateId`, or nil. Mirrors `data.jsx:45-48`.
    func getPreviousSession(templateId: String) -> SavedSession? {
        return loadSaved()
            .filter { $0.templateId == templateId }
            .sorted { $0.startTime > $1.startTime }
            .first
    }

    /// Build a fresh ActiveSession from the named template, pulling prior set
    /// weight + reps forward when available. Mirrors `data.jsx:51-77`.
    func createSession(templateId: String) -> ActiveSession {
        guard let tmpl = WorkoutTemplate.byId(templateId) else {
            // Match prototype semantics: caller assumes template exists.
            // Returning an empty session keeps the type total; upstream is hardcoded to upper-1.
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

        let prev = getPreviousSession(templateId: templateId)

        let exercises: [LoggedExercise] = tmpl.exercises.map { ex in
            let prevEx = prev?.exercises.first(where: { $0.id == ex.id })
            let sets: [LoggedSet] = (0..<ex.targetSets).map { i in
                let prevSet: LoggedSet? = (prevEx?.sets.indices.contains(i) ?? false) ? prevEx?.sets[i] : nil
                return LoggedSet(
                    num: i + 1,
                    weight: prevSet.map { $0.weight } ?? "",
                    reps:   prevSet.map { $0.reps   } ?? String(ex.targetReps),
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
                prevSets: prevEx?.sets ?? []
            )
        }

        return ActiveSession(
            templateId: templateId,
            name: tmpl.name,
            category: tmpl.category,
            startTime: Date(),
            exercises: exercises,
            feel: nil,
            note: nil
        )
    }

    /// Build a fresh ActiveSession from an ad-hoc template (e.g. one assembled
    /// from coach.db). Same prev-pull semantics as the templateId path.
    func createSession(from tmpl: WorkoutTemplate) -> ActiveSession {
        let prev = getPreviousSession(templateId: tmpl.id)
        let exercises: [LoggedExercise] = tmpl.exercises.map { ex in
            let prevEx = prev?.exercises.first(where: { $0.id == ex.id })
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
                prevSets: prevEx?.sets ?? []
            )
        }
        return ActiveSession(
            templateId: tmpl.id,
            name: tmpl.name,
            category: tmpl.category,
            startTime: Date(),
            exercises: exercises,
            feel: nil,
            note: nil
        )
    }

    /// Persist a completed session: prepend to savedSessions, clear active.
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
        var next = loadSaved()
        next.insert(saved, at: 0)
        saveAll(next)
        clearActive()
        return saved
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
