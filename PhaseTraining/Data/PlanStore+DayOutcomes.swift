// PlanStore+DayOutcomes.swift — A2: record planned-vs-actual per saved session.
// See DayOutcome.swift for why this is frozen at save time.

import Foundation

extension PlanStore {

    /// Record the outcome of a just-saved session. Idempotent per session id:
    /// a re-record replaces the prior entry. Called once per save through
    /// `SessionStore.onSessionSaved`.
    func recordOutcome(for session: SavedSession, abandoned: Bool, now: Date = Date()) {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: session.startTime)
        let plannedDay = plan?.days.first { cal.isDate($0.date, inSameDayAs: dayStart) }
        let displaced = overrides.displacedPlanByDate?.first {
            cal.isDate($0.key, inSameDayAs: dayStart)
        }?.value
        var outcome = DayOutcome.derive(
            session: session,
            plannedDay: plannedDay,
            displaced: displaced,
            abandoned: abandoned,
            targetMinutes: memoryStore?.memory.sessionMinutes,
            now: now)
        // B1a — shadow twin. History excludes this session; the model adds it
        // back only to read the actual it is scored against.
        let history = TwinInputs.sets(from: (sessionStore?.savedSessions ?? []).filter { $0.id != session.id })
            + TwinInputs.sets(from: importedSetsProvider())
        outcome.twin = TwinInputs.predict(session: session, plannedExercises: outcome.plannedExercises,
                                          history: history)
        insertOutcome(outcome, now: now)
    }

    /// Insert, dedupe by session id, trim to the 90-day window, persist.
    func insertOutcome(_ outcome: DayOutcome, now: Date = Date()) {
        var next = dayOutcomes.filter { $0.sessionId != outcome.sessionId }
        next.append(outcome)
        let cutoff = now.addingTimeInterval(-Double(Self.planOverridesRetentionDays) * 86_400)
        dayOutcomes = next
            .filter { $0.recordedAt >= cutoff }
            .sorted { $0.date > $1.date }
        saveDayOutcomes()
    }

    func saveDayOutcomes() {
        if let data = try? Self.encoder().encode(dayOutcomes) {
            defaults.set(data, forKey: Self.dayOutcomesKey)
        }
    }
}
