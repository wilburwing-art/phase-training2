// WatchSessionModel.swift — the watch side of the link (PLAN-watch.md, step 1).
//
// Holds the mirror of the phone's active session, received as application
// context, and sends events back with `transferUserInfo`, which queues while
// the phone is out of range. Each tap is applied to the mirror at once through
// the same `WatchSyncReducer` the phone uses, so the watch shows the set as
// done before the phone confirms; the phone's next context push replaces the
// mirror wholesale, which is the phone-owns-the-session rule in action.

import Foundation
import Combine
import OSLog
import WatchConnectivity

final class WatchSessionModel: NSObject, ObservableObject {

    @Published private(set) var active: ActiveSession?
    @Published private(set) var reachable = false

    private var state = WatchSyncState()

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

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Taps

    func toggle(exerciseId: String, setNum: Int) {
        guard let active,
              let set = active.exercises.first(where: { $0.id == exerciseId })?.sets.first(where: { $0.num == setNum })
        else { return }
        let kind: WatchSyncEvent.Kind = set.done ? .setReopened : .setCompleted(weight: nil, reps: nil)
        send(WatchSyncEvent(sessionStart: active.startTime, exerciseId: exerciseId, setNum: setNum,
                            kind: kind, at: Date()))
    }

    func endSession() {
        guard let active else { return }
        send(WatchSyncEvent(sessionStart: active.startTime, kind: .sessionEnded, at: Date()))
        self.active = nil
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

    private static let log = Logger(subsystem: "com.phasetraining.app.watchkitapp", category: "watch-sync")

    // MARK: - Context

    private func read(_ context: [String: Any]) {
        guard let data = context["context"] as? Data,
              let decoded = try? Self.decoder.decode(WatchSyncContext.self, from: data) else { return }
        active = decoded.activeSession
        if let session = decoded.activeSession { state = state.matching(session) }
        Self.log.notice("context read: \(decoded.activeSession?.name ?? "none", privacy: .public), args \(ProcessInfo.processInfo.arguments.joined(separator: " "), privacy: .public)")
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

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async {
            self.reachable = session.isReachable
            self.read(session.receivedApplicationContext)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.reachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.read(applicationContext) }
    }
}
