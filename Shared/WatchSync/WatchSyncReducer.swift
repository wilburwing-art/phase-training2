// WatchSyncReducer.swift — fold watch events into the phone's session.
//
// PURE. No I/O, no WCSession, no Date(). The phone-side coordinator calls
// `apply` with whatever events arrived, persists the returned state beside
// the active session, and starts rests for the events it reports as applied.
//
// Three rules, each with a test:
//   1. Idempotent on event id. `transferUserInfo` can redeliver; a second
//      delivery changes nothing.
//   2. Ordered by `at`, then id, whatever order they arrived in. A reopen
//      after a complete leaves the set open; the reverse leaves it done.
//   3. The phone wins a conflict. If the phone edited a set after the
//      event's timestamp, the event is consumed and ignored. The ledger of
//      phone edits lives in `WatchSyncState` and the log screen records one
//      whenever it touches a set.
// An event for a different session, an unknown exercise or an unknown set is
// consumed too, so it can never apply later to something it was not about.

import Foundation

struct WatchSyncState: Codable, Equatable {
    /// Which session this state belongs to. Reset when the session changes.
    var sessionStart: Date?
    var appliedEventIds: Set<UUID> = []
    /// Last phone edit per set, keyed by `setKey`.
    var phoneEdits: [String: Date] = [:]

    init(sessionStart: Date? = nil) {
        self.sessionStart = sessionStart
    }

    static func setKey(exerciseId: String, setNum: Int) -> String {
        "\(exerciseId)#\(setNum)"
    }

    /// Record that the phone changed a set. Called by the log screen on every
    /// mutation of that set (done, weight, reps, RPE, RIR).
    mutating func notePhoneEdit(exerciseId: String, setNum: Int, at: Date) {
        let key = Self.setKey(exerciseId: exerciseId, setNum: setNum)
        if let existing = phoneEdits[key], existing >= at { return }
        phoneEdits[key] = at
    }

    /// The state for `session`: this one if it already belongs to it, else a
    /// fresh one. Keeps a previous session's ledger from leaking into the next.
    func matching(_ session: ActiveSession) -> WatchSyncState {
        sessionStart == session.startTime ? self : WatchSyncState(sessionStart: session.startTime)
    }
}

enum WatchSyncReducer {

    struct Outcome: Equatable {
        var session: ActiveSession
        var state: WatchSyncState
        /// Events that changed the session, in the order they were applied.
        /// The coordinator starts a rest for each `setCompleted` here.
        var applied: [WatchSyncEvent]
        /// True once a `sessionEnded` event was applied. The coordinator then
        /// completes the session on the phone.
        var ended: Bool
    }

    static func apply(_ events: [WatchSyncEvent], to session: ActiveSession,
                      state incoming: WatchSyncState) -> Outcome {
        var session = session
        var state = incoming.matching(session)
        var applied: [WatchSyncEvent] = []
        var ended = false

        let ordered = events.sorted {
            $0.at != $1.at ? $0.at < $1.at : $0.id.uuidString < $1.id.uuidString
        }
        for event in ordered {
            guard !state.appliedEventIds.contains(event.id) else { continue }
            state.appliedEventIds.insert(event.id)
            guard event.sessionStart == session.startTime else { continue }

            switch event.kind {
            case .sessionEnded:
                ended = true
                applied.append(event)

            case .watchWorkoutStarted:
                guard session.healthWriter != .watch else { continue }
                session.healthWriter = .watch
                applied.append(event)

            case .setCompleted, .setReopened:
                guard let exerciseId = event.exerciseId, let setNum = event.setNum,
                      let exIdx = session.exercises.firstIndex(where: { $0.id == exerciseId }),
                      let setIdx = session.exercises[exIdx].sets.firstIndex(where: { $0.num == setNum })
                else { continue }
                if let key = event.setKey, let edited = state.phoneEdits[key], edited > event.at {
                    continue
                }
                var set = session.exercises[exIdx].sets[setIdx]
                if case .setCompleted(let weight, let reps) = event.kind {
                    set.done = true
                    if let weight, !weight.isEmpty { set.weight = weight }
                    if let reps, !reps.isEmpty { set.reps = reps }
                } else {
                    set.done = false
                }
                guard set != session.exercises[exIdx].sets[setIdx] else { continue }
                session.exercises[exIdx].sets[setIdx] = set
                applied.append(event)
            }
        }
        return Outcome(session: session, state: state, applied: applied, ended: ended)
    }
}
