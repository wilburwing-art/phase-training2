// SessionReuse.swift: run a finished session again, keep it as a saved
// workout, and find it in History.
//
// Pure value transforms over `SavedSession`, so History and Complete share
// one definition and the tests need no store.

import Foundation

extension SavedSession {
    /// The exercises worth carrying forward: the ones with at least one
    /// completed set. A session saved with nothing ticked keeps every row,
    /// so an abandoned plan can still be repeated as written.
    var reusableExercises: [LoggedExercise] {
        let done = exercises.filter { ex in ex.sets.contains { $0.done } }
        return done.isEmpty ? exercises : done
    }

    /// The session as a template to start again. Keeps the template and
    /// exercise ids, so the new session pulls its previous sets the same way
    /// a second run of the original plan would.
    func repeatTemplate() -> WorkoutTemplate {
        WorkoutTemplate(
            id: templateId,
            name: name,
            category: category,
            exercises: reusableExercises.map { ex in
                ExerciseTemplate(
                    id: ex.id,
                    name: ex.name,
                    type: ex.type,
                    unit: ex.unit,
                    targetSets: ex.workingSetCount,
                    targetReps: ex.repsToCarry,
                    rest: ex.rest,
                    rpe: ex.rpe,
                    tempo: ex.tempo,
                    supersetGroup: ex.supersetGroup,
                    repsLabel: ex.repsLabel
                )
            }
        )
    }

    /// The session as a saved workout for the Library. `exerciseId` resolves
    /// an id from an exercise name (catalog, or negative for a custom
    /// exercise); an unmatched name stores 0, which still runs as a session
    /// and only loses substitutes and the image.
    func asCustomRoutine(named routineName: String? = nil,
                         now: Date = Date(),
                         exerciseId: (String) -> Int?) -> CustomRoutine {
        let trimmed = (routineName ?? name).trimmingCharacters(in: .whitespacesAndNewlines)
        return CustomRoutine(
            id: UUID().uuidString,
            name: trimmed.isEmpty ? "Saved workout" : trimmed,
            exercises: reusableExercises.enumerated().map { idx, ex in
                CustomRoutineExercise(
                    id: UUID().uuidString,
                    exerciseId: exerciseId(ex.name) ?? 0,
                    name: ex.name,
                    position: idx + 1,
                    sets: ex.workingSetCount,
                    reps: ex.repsLabel ?? String(ex.repsToCarry),
                    rest: "\(ex.rest)s",
                    notes: nil,
                    supersetGroup: ex.supersetGroup
                )
            },
            createdAt: now
        )
    }
}

extension LoggedExercise {
    /// Completed working sets, or the planned count when none were ticked.
    var workingSetCount: Int {
        let done = sets.filter { $0.done && $0.countsForStrength }.count
        return done > 0 ? done : max(1, targetSets)
    }

    /// Reps for the next run: what the first completed working set logged,
    /// which for a freestyle row is the only real number there is. A row
    /// with a written prescription ("8s hold") keeps its planned count.
    var repsToCarry: Int {
        if repsLabel != nil { return targetReps }
        let first = sets.first { $0.done && $0.countsForStrength }
        return first?.repsValue.flatMap { $0 > 0 ? $0 : nil } ?? targetReps
    }
}

/// Exercise id for an exercise name, exact match ignoring case, for writing
/// `CustomRoutineExercise.exerciseId`: the catalog id first, then the user's
/// custom exercise as `-rowId` (read from the same store as
/// `ExerciseLookupCache`). Nil when neither matches.
enum ExerciseNameLookup {
    static func anyId(_ name: String) -> Int? {
        CoachDatabase.shared
            .listExercises(search: name)
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
            ?? ExerciseLookupCache.shared.userDB?.userExercise(named: name)?.exercise.id
    }
}

/// Search text and tag filter for the History list.
struct HistoryFilter: Equatable {
    var query: String = ""
    var tags: Set<SessionTag> = []

    var isActive: Bool { !terms.isEmpty || !tags.isEmpty }

    /// Lowercased words of the query. Every word has to appear somewhere in
    /// the session, so "squat march" narrows instead of widening.
    private var terms: [String] {
        query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    func matches(_ session: SavedSession, calendar: Calendar = .current) -> Bool {
        if !tags.isEmpty {
            let have = Set(session.sessionTags)
            guard tags.allSatisfy({ have.contains($0.rawValue) }) else { return false }
        }
        let words = terms
        guard !words.isEmpty else { return true }
        let haystack = Self.searchText(session, calendar: calendar)
        return words.allSatisfy { haystack.contains($0) }
    }

    func apply(to sessions: [SavedSession], calendar: Calendar = .current) -> [SavedSession] {
        isActive ? sessions.filter { matches($0, calendar: calendar) } : sessions
    }

    /// Everything a person might type to find a session: its name, the
    /// exercise names, the session note, per-exercise notes, tag labels and
    /// the month and year it happened ("march 2026").
    static func searchText(_ session: SavedSession, calendar: Calendar = .current) -> String {
        var parts: [String] = [session.name, session.category]
        if let note = session.note { parts.append(note) }
        for ex in session.exercises {
            parts.append(ex.name)
            if let note = ex.note { parts.append(note) }
        }
        parts += session.sessionTags.compactMap { SessionTag(rawValue: $0)?.label }
        let comps = calendar.dateComponents([.year, .month], from: session.startTime)
        if let month = comps.month, let year = comps.year,
           calendar.monthSymbols.indices.contains(month - 1) {
            parts.append(calendar.monthSymbols[month - 1])
            parts.append(String(year))
        }
        return parts.joined(separator: "\n").lowercased()
    }

    /// Tags that occur in the list, in declaration order. The chip row shows
    /// only these, so nobody taps a filter that can only return nothing.
    static func tagsPresent(in sessions: [SavedSession]) -> [SessionTag] {
        let raw = Set(sessions.flatMap(\.sessionTags))
        return SessionTag.allCases.filter { raw.contains($0.rawValue) }
    }
}
