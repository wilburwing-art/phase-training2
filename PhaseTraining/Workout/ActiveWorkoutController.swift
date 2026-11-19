// ActiveWorkoutController.swift — owns the live ActiveSession and its rest
// timer so the log screen, voice and the watch path share one set of rules.
//
// Every mutation lands on `session`; its didSet persists through
// `SessionStore.saveActive` once per change. Rest stays in memory only.

import Foundation
import UIKit

/// The set the lifter should do next.
struct NextUp: Equatable {
    let exIdx: Int
    let setIdx: Int
    let exerciseName: String
    /// 1-based, `setIdx + 1`.
    let setNumber: Int
    /// `sets.count` of the exercise.
    let totalSets: Int
    let targetReps: Int
    /// Weight of the latest done set in this exercise, else this set's own
    /// non-empty weight, else nil.
    let lastWeight: String?
}

@MainActor
final class ActiveWorkoutController: ObservableObject {
    // The log screen binds text fields through `session` and the rest card writes `rest`.
    @Published var session: ActiveSession {
        didSet {
            if session != oldValue { store.saveActive(session) }
        }
    }
    @Published var rest = RestTimerState()

    private let store: SessionStore
    private let suppressAutoRest: Bool
    private let haptic: (UIImpactFeedbackGenerator.FeedbackStyle) -> Void
    private let now: () -> Date

    init(store: SessionStore,
         session: ActiveSession,
         suppressAutoRest: Bool = false,
         haptic: @escaping (UIImpactFeedbackGenerator.FeedbackStyle) -> Void = { UIImpactFeedbackGenerator(style: $0).impactOccurred() },
         now: @escaping () -> Date = Date.init) {
        self.store = store
        self.session = session
        self.suppressAutoRest = suppressAutoRest
        self.haptic = haptic
        self.now = now
    }

    private func contains(exIdx: Int, setIdx: Int) -> Bool {
        session.exercises.indices.contains(exIdx)
            && session.exercises[exIdx].sets.indices.contains(setIdx)
    }

    // MARK: - Sets

    func setRIR(exIdx: Int, setIdx: Int, value: String) {
        guard contains(exIdx: exIdx, setIdx: setIdx) else { return }
        session.exercises[exIdx].sets[setIdx].rir = value
        haptic(.light)
    }

    func toggleSet(exIdx: Int, setIdx: Int) {
        guard contains(exIdx: exIdx, setIdx: setIdx) else { return }
        let wasDone = session.exercises[exIdx].sets[setIdx].done
        session.exercises[exIdx].sets[setIdx].done = !wasDone

        haptic(.light)

        if !wasDone {
            startRestAfterCompleting(exIdx: exIdx, setIdx: setIdx)
        } else if rest.exIdx == exIdx, rest.setIdx == setIdx {
            // Untoggled: clear rest if it was anchored to this set.
            rest.clear()
        }
    }

    /// Write the values the lifter said or typed, then mark the set done.
    /// A nil param keeps the cell's current value. A set that was already done
    /// takes the new values but does not restart rest.
    func logSet(exIdx: Int, setIdx: Int, weight: String?, reps: String?, rpe: String?) {
        guard contains(exIdx: exIdx, setIdx: setIdx) else { return }
        var updated = session
        var set = updated.exercises[exIdx].sets[setIdx]
        let wasDone = set.done
        if let weight { set.weight = weight }
        if let reps { set.reps = reps }
        if let rpe { set.rpe = rpe }
        set.done = true
        updated.exercises[exIdx].sets[setIdx] = set
        session = updated

        guard !wasDone else { return }
        haptic(.light)
        startRestAfterCompleting(exIdx: exIdx, setIdx: setIdx)
    }

    /// The rest that follows a set being marked done. Start it only when this
    /// exercise has more sets to come; the final set of an exercise gets no
    /// rest, since moving to the next exercise is the rest.
    ///
    /// Superset-aware: while a sibling in the group still owes this set index,
    /// skip the rest so the lifter moves to the next member. The rest fires
    /// after the last member of the group completes set `setIdx`.
    func startRestAfterCompleting(exIdx: Int, setIdx: Int) {
        guard contains(exIdx: exIdx, setIdx: setIdx) else { return }
        let ex = session.exercises[exIdx]
        // Any other set still undone, so ticking sets out of order matches
        // the watch's rule rather than keying on the set's position.
        let hasMoreSets = ex.sets.indices.contains { $0 != setIdx && !ex.sets[$0].done }

        if isMidSupersetRound(exIdx: exIdx, setIdx: setIdx) {
            // Clear any pending rest from a prior round so the active band
            // moves cleanly to the next group member.
            rest.clear()
        } else if !suppressAutoRest, hasMoreSets {
            rest.start(exIdx: exIdx, setIdx: setIdx, duration: ex.rest, now: now(),
                       cue: lockedRestEndLine())
        } else {
            // Final set of the exercise: drop any rest still counting down
            // from an earlier set so it doesn't carry into the next exercise.
            rest.clear()
        }
    }

    func addSet(exIdx: Int) {
        guard session.exercises.indices.contains(exIdx) else { return }
        let ex = session.exercises[exIdx]
        let lastSet = ex.sets.last
        let newSet = LoggedSet(
            num: ex.sets.count + 1,
            weight: lastSet?.weight ?? "",
            reps: lastSet?.reps ?? String(ex.targetReps),
            rpe: "",
            done: false
        )
        session.exercises[exIdx].sets.append(newSet)
    }

    /// Re-open a done set so its values can be edited. Keeps the entered
    /// values; clears the rest if it was anchored to this row.
    func reopenSet(exIdx: Int, setIdx: Int) {
        guard contains(exIdx: exIdx, setIdx: setIdx) else { return }
        session.exercises[exIdx].sets[setIdx].done = false
        if rest.exIdx == exIdx, rest.setIdx == setIdx { rest.clear() }
        haptic(.light)
    }

    /// True when this exercise belongs to a superset AND at least one sibling
    /// in the same group still has `set[setIdx]` undone. Siblings with fewer
    /// sets don't gate the rest (their round ended earlier).
    func isMidSupersetRound(exIdx: Int, setIdx: Int) -> Bool {
        guard session.exercises.indices.contains(exIdx) else { return false }
        guard let group = session.exercises[exIdx].supersetGroup else { return false }
        return session.exercises.enumerated().contains { offset, sibling in
            offset != exIdx
                && sibling.supersetGroup == group
                && sibling.sets.indices.contains(setIdx)
                && !sibling.sets[setIdx].done
        }
    }

    // MARK: - Rest

    func skipRest() {
        rest.clear()
    }

    /// Extend (positive) or shorten (negative) the running rest in place.
    /// Shortening to at or under the elapsed time ends the rest. No-op when
    /// no rest is counting down.
    func addRest(seconds: Int) {
        let at = now()
        guard seconds != 0,
              let started = rest.startedAt,
              let duration = rest.duration,
              rest.remaining(at: at) != nil else { return }
        let newDuration = duration + seconds
        if seconds < 0, newDuration <= Int(at.timeIntervalSince(started)) {
            rest.clear()
        } else {
            rest.duration = newDuration
            rest.rescheduleExpiryNotification(now: at, cue: lockedRestEndLine())
        }
    }

    /// Preset pick on the running rest: the new duration runs from now, so a
    /// shorter pick does not land already expired. No-op with no rest.
    func setRestDuration(_ seconds: Int) {
        guard rest.startedAt != nil else { return }
        let at = now()
        rest.duration = seconds
        rest.startedAt = at
        rest.alertFiredFor = at
        rest.rescheduleExpiryNotification(now: at, cue: lockedRestEndLine())
    }

    /// Spoken rest-end line for the lock-screen notification, nil when cues
    /// are off.
    private func lockedRestEndLine() -> String? {
        VoiceCuePlayer.shared.lockedRestEndLine(session: session, next: nextUp())
    }

    // MARK: - Next up

    /// The first exercise (session order) with an undone set. Plain exercise:
    /// its first undone set. Superset member: the lowest set index any member
    /// still owes, served to the first member (session order) owing it.
    func nextUp() -> NextUp? {
        let exercises = session.exercises
        guard let firstIdx = exercises.firstIndex(where: { $0.sets.contains { !$0.done } }) else {
            return nil
        }
        guard let group = exercises[firstIdx].supersetGroup else {
            let setIdx = exercises[firstIdx].sets.firstIndex { !$0.done }!
            return makeNextUp(exIdx: firstIdx, setIdx: setIdx)
        }
        let members = exercises.indices.filter { exercises[$0].supersetGroup == group }
        let roundIdx = members.compactMap { m in exercises[m].sets.firstIndex { !$0.done } }.min()!
        let exIdx = members.first { m in
            exercises[m].sets.indices.contains(roundIdx) && !exercises[m].sets[roundIdx].done
        }!
        return makeNextUp(exIdx: exIdx, setIdx: roundIdx)
    }

    private func makeNextUp(exIdx: Int, setIdx: Int) -> NextUp {
        let ex = session.exercises[exIdx]
        let latestDone = ex.sets.last { $0.done && !Self.isBlank($0.weight) }?.weight
        let own = ex.sets[setIdx].weight
        return NextUp(
            exIdx: exIdx,
            setIdx: setIdx,
            exerciseName: ex.name,
            setNumber: setIdx + 1,
            totalSets: ex.sets.count,
            targetReps: ex.targetReps,
            lastWeight: latestDone ?? (Self.isBlank(own) ? nil : own)
        )
    }

    private static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
