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
        WCSession.default.transferUserInfo(["event": data])
    }

    // MARK: - Context

    private func read(_ context: [String: Any]) {
        guard let data = context["context"] as? Data,
              let decoded = try? Self.decoder.decode(WatchSyncContext.self, from: data) else { return }
        active = decoded.activeSession
        if let session = decoded.activeSession { state = state.matching(session) }
    }
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
