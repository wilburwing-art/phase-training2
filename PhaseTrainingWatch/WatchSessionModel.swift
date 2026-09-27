// WatchSessionModel.swift — the watch side of the link (PLAN-watch.md, steps 1 and 2).
//
// Holds the mirror of the phone's active session, received as application
// context, and sends events back. Each tap is applied to the mirror at once
// through the same `WatchSyncReducer` the phone uses, so the watch shows the
// set as done before the phone confirms; the phone's next context push
// replaces the mirror wholesale, which is the phone-owns-the-session rule.
//
// Step 2 adds the rest countdown, the weight and rep nudge, and the Health
// workout: "Start on watch" runs an HKWorkoutSession (heart rate, rings) and
// tells the phone the watch will save it. Ending the session on either
// device ends that workout.

import Foundation
import Combine
import OSLog
import WatchConnectivity

@MainActor
final class WatchSessionModel: NSObject, ObservableObject {

    @Published private(set) var active: ActiveSession?
    /// Today's planned session from the phone, offered when nothing is running.
    @Published private(set) var planned: ActiveSession?
    @Published private(set) var reachable = false
    @Published var rest = WatchRestTimer()
    let workout = WatchWorkoutController()

    private var state = WatchSyncState()
    private var cancellables = Set<AnyCancellable>()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
    private static let log = Logger(subsystem: "com.phasetraining.app.watchkitapp", category: "watch-sync")

    override init() {
        super.init()
        workout.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Taps

    func toggle(exerciseId: String, setNum: Int) {
        guard let set = set(exerciseId, setNum) else { return }
        if set.done {
            send(event(exerciseId, setNum, .setReopened))
            if rest.exerciseId == exerciseId, rest.setNum == setNum { rest.clear() }
        } else {
            complete(exerciseId: exerciseId, setNum: setNum, weight: nil, reps: nil)
        }
    }

    /// Mark a set done with the nudged values from the detail screen. Nil
    /// keeps the phone's value.
    func complete(exerciseId: String, setNum: Int, weight: String?, reps: String?) {
        guard let active, set(exerciseId, setNum) != nil else { return }
        send(event(exerciseId, setNum, .setCompleted(weight: weight, reps: reps)))
        startRest(after: exerciseId, setNum: setNum, in: active)
    }

    /// Start today's planned session here, phone in range or not. The
    /// session is adopted locally at once; the phone takes it when the event
    /// reaches it and pushes the same session back as context.
    func startPlannedSession() {
        guard active == nil, var session = planned else { return }
        session.startTime = Date()
        active = session
        planned = nil
        state = WatchSyncState(sessionStart: session.startTime)
        send(WatchSyncEvent(sessionStart: session.startTime, kind: .sessionStarted(session), at: session.startTime))
    }

    /// Run the Health workout from the watch for the active session.
    func startWorkout() async {
        guard let active, !workout.isRunning else { return }
        guard await workout.requestAuthorization() else { return }
        if await workout.start(appSessionStart: active.startTime) {
            send(WatchSyncEvent(sessionStart: active.startTime, kind: .watchWorkoutStarted, at: Date()))
        }
    }

    func endSession() async {
        guard let active else { return }
        await workout.end()
        send(WatchSyncEvent(sessionStart: active.startTime, kind: .sessionEnded, at: Date()))
        self.active = nil
        rest.clear()
    }

    // MARK: - Rest

    /// Same rule as the phone's log screen, without the superset round-robin:
    /// a rest follows a completed set whenever more work is planned after it.
    private func startRest(after exerciseId: String, setNum: Int, in session: ActiveSession) {
        guard let exIdx = session.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let ex = session.exercises[exIdx]
        let moreSetsHere = ex.sets.contains { $0.num != setNum && !$0.done }
        let moreWorkAfter = session.exercises[(exIdx + 1)...].contains { $0.sets.contains { !$0.done } }
        guard moreSetsHere || moreWorkAfter else { rest.clear(); return }
        rest.start(exerciseId: exerciseId, setNum: setNum, duration: ex.rest)
    }

    // MARK: - Sending

    private func event(_ exerciseId: String, _ setNum: Int, _ kind: WatchSyncEvent.Kind) -> WatchSyncEvent {
        WatchSyncEvent(sessionStart: active?.startTime ?? Date(), exerciseId: exerciseId, setNum: setNum,
                       kind: kind, at: Date())
    }

    private func set(_ exerciseId: String, _ setNum: Int) -> LoggedSet? {
        active?.exercises.first { $0.id == exerciseId }?.sets.first { $0.num == setNum }
    }

    private func send(_ event: WatchSyncEvent) {
        if let active {
            let outcome = WatchSyncReducer.apply([event], to: active, state: state)
            state = outcome.state
            self.active = outcome.session
        }
        guard let data = try? Self.encoder.encode(event) else { return }
        let wc = WCSession.default
        // Reachable: deliver now, and fall back to the queue if that fails.
        // Not reachable: the queue, which survives the phone being away.
        if wc.isReachable {
            wc.sendMessage(["event": data], replyHandler: nil) { error in
                Self.log.error("sendMessage failed, queueing: \(error.localizedDescription, privacy: .public)")
                wc.transferUserInfo(["event": data])
            }
        } else {
            wc.transferUserInfo(["event": data])
        }
        Self.log.notice("event sent: \(String(describing: event.kind), privacy: .public) set \(event.setNum ?? -1), reachable \(wc.isReachable), queued \(wc.outstandingUserInfoTransfers.count)")
    }

    // MARK: - Context

    private func read(_ context: [String: Any]) {
        guard let data = context["context"] as? Data,
              let decoded = try? Self.decoder.decode(WatchSyncContext.self, from: data) else { return }
        let before = active
        // The phone has not adopted a session started here yet: keep ours
        // until the context carries it (same start time) or another one.
        if decoded.activeSession == nil, let mine = before,
           state.sessionStart == mine.startTime, !state.appliedEventIds.isEmpty,
           decoded.sentAt < mine.startTime.addingTimeInterval(120) {
            planned = decoded.plannedSession
            return
        }
        active = decoded.activeSession
        planned = decoded.activeSession == nil ? decoded.plannedSession : nil
        if let session = decoded.activeSession {
            state = state.matching(session)
            // A set the phone just marked done gets its rest here too.
            if let before, before.startTime == session.startTime {
                for ex in session.exercises {
                    let previous = before.exercises.first { $0.id == ex.id }?.sets ?? []
                    for set in ex.sets where set.done && !(previous.first { $0.num == set.num }?.done ?? false) {
                        startRest(after: ex.id, setNum: set.num, in: session)
                    }
                }
            }
        } else {
            // The phone finished or discarded the session: close the workout.
            rest.clear()
            if workout.isRunning { Task { await workout.end() } }
        }
        Self.log.notice("context read: \(decoded.activeSession?.name ?? "none", privacy: .public)")
        #if DEBUG
        // `--watch-test-toggle-set`: mark the first open set once the mirror
        // arrives, so the watch-to-phone path can be checked on paired
        // simulators, which have no UI automation. DEBUG only, like the
        // phone's --seed-* arguments.
        if !didTestToggle, ProcessInfo.processInfo.arguments.contains("--watch-test-toggle-set"),
           let session = decoded.activeSession,
           let ex = session.exercises.first(where: { $0.sets.contains { !$0.done } }),
           let set = ex.sets.first(where: { !$0.done }) {
            didTestToggle = true
            toggle(exerciseId: ex.id, setNum: set.num)
        }
        #endif
    }

    #if DEBUG
    private var didTestToggle = false
    #endif
}

extension WatchSessionModel: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let reachable = session.isReachable
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.reachable = reachable
            self.read(context)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.reachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.read(applicationContext) }
    }
}
