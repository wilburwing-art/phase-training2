// WatchSyncEvent.swift — what the watch tells the phone (PLAN-watch.md, step 1).
//
// Compiled into BOTH the iOS app and the watch app. Foundation only.
//
// The phone owns the session. The watch never writes a SavedSession; it sends
// small events, each with its own id and timestamp, and the phone folds them
// into the ActiveSession through `WatchSyncReducer`. Events travel by
// `WCSession.transferUserInfo`, which queues across disconnects and delivers
// in order, so an event logged with the phone in a locker arrives later and
// still applies. Sets are addressed by exercise id and set number, never by
// index: the phone can add, swap or reorder exercises while the watch holds
// an older mirror.

import Foundation

struct WatchSyncEvent: Codable, Equatable, Identifiable {
    enum Kind: Codable, Equatable {
        /// A set was marked done on the watch. `weight` and `reps` carry the
        /// watch's nudged values when the lifter changed them; nil leaves the
        /// phone's values alone.
        case setCompleted(weight: String?, reps: String?)
        case setReopened
        /// The lifter started today's planned session on the watch (the phone
        /// may be out of range). Carries the whole session, with the watch's
        /// start time; the phone adopts it if nothing is already in progress.
        case sessionStarted(ActiveSession)
        /// The watch started an HKWorkoutSession for this session, so the
        /// watch saves the workout to Health and the phone must not.
        case watchWorkoutStarted
        /// The lifter ended the session on the watch. The phone completes it.
        case sessionEnded
    }

    let id: UUID
    /// `ActiveSession.startTime` of the session this event belongs to. An
    /// event for any other session is stale and is dropped.
    let sessionStart: Date
    /// `LoggedExercise.id`; nil for session-level events.
    let exerciseId: String?
    /// `LoggedSet.num`; nil for session-level events.
    let setNum: Int?
    let kind: Kind
    /// When the event happened on the watch. Ordering and the phone-edit rule
    /// read this, so the watch sets it from its own clock at the tap.
    let at: Date

    init(id: UUID = UUID(), sessionStart: Date, exerciseId: String? = nil, setNum: Int? = nil,
         kind: Kind, at: Date) {
        self.id = id
        self.sessionStart = sessionStart
        self.exerciseId = exerciseId
        self.setNum = setNum
        self.kind = kind
        self.at = at
    }

    /// Key for the phone-edit ledger: one entry per set.
    var setKey: String? {
        guard let exerciseId, let setNum else { return nil }
        return WatchSyncState.setKey(exerciseId: exerciseId, setNum: setNum)
    }
}

/// What the phone sends the watch: the whole active session, latest wins.
/// Travels by `WCSession.updateApplicationContext`, which keeps only the
/// newest value and delivers it when the watch is next reachable. Nil means
/// nothing is in progress.
struct WatchSyncContext: Codable, Equatable {
    var activeSession: ActiveSession?
    /// Today's planned session, built but not started, when nothing is in
    /// progress. The watch offers to start it. Its `startTime` is
    /// meaningless until the watch replaces it at the tap.
    var plannedSession: ActiveSession? = nil
    var sentAt: Date
}
