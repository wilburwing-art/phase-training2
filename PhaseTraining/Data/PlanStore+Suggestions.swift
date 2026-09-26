// PlanStore+Suggestions.swift — A4: gather PatternEngine inputs, apply or
// dismiss a suggestion. Every accept goes through a seam that already exists:
// MemoryStore.update for sessionMinutes and exerciseAffinities, and
// CustomRoutineStore.save for a saved routine.

import Foundation

extension PlanStore {

    /// Suggestions for the weekly check-in. Empty when the stores are not
    /// wired yet (the check-in is only reachable after they are).
    func currentSuggestions(now: Date = Date()) -> [Suggestion] {
        guard let memory = memoryStore?.memory else { return [] }
        let since = now.addingTimeInterval(-Double(PatternEngine.windowDays) * 86_400)
        let input = PatternEngine.Inputs(
            outcomes: dayOutcomes,
            abandoned: abandonedWorkouts,
            explore: exploreSessionsSince(since),
            sessionMinutes: memory.sessionMinutes,
            affinities: memory.exerciseAffinities,
            savedRoutineNames: Set(customStore?.routines.map(\.name) ?? []),
            decisions: memory.suggestionDecisions)
        return PatternEngine.suggestions(input, now: now)
    }

    /// Perform the accept and record it. Returns false when the action could
    /// not be carried out (e.g. the bundled routine has no rows), in which
    /// case nothing is recorded and the card stays.
    @discardableResult
    func acceptSuggestion(_ s: Suggestion, now: Date = Date()) -> Bool {
        guard let memoryStore else { return false }
        switch s.action {
        case .setSessionMinutes(let minutes):
            // statedFields is left alone: `.availability` also covers lift
            // days, which this accept says nothing about.
            memoryStore.update { $0.sessionMinutes = minutes }
        case .sinkExercise(let name):
            let sink = AthleteState.affinitySinkThreshold
            memoryStore.update { m in
                // Fold any case variants into the one key, then sink it.
                let variants = m.exerciseAffinities.keys.filter { $0.lowercased() == name.lowercased() }
                for key in variants { m.exerciseAffinities[key] = nil }
                m.exerciseAffinities[name] = sink
            }
        case .saveRoutine(let routineId, let name):
            let rows = CoachDatabase.shared.exercises(forRoutineId: routineId)
            guard !rows.isEmpty, let customStore else { return false }
            customStore.save(CustomRoutine.from(bundledName: name, exercises: rows, now: now))
        }
        record(s, accepted: true, now: now)
        return true
    }

    func dismissSuggestion(_ s: Suggestion, now: Date = Date()) {
        record(s, accepted: false, now: now)
    }

    private func record(_ s: Suggestion, accepted: Bool, now: Date) {
        memoryStore?.update { m in
            m.suggestionDecisions.append(SuggestionDecision(suggestionId: s.id, accepted: accepted, at: now))
            m.suggestionDecisions = SuggestionDecision.prune(m.suggestionDecisions, now: now)
        }
    }
}
