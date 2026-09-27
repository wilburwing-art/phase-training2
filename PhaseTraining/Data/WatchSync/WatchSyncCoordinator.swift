// WatchSyncCoordinator.swift — the phone side of the watch link (PLAN-watch.md, step 1).
//
// Owns the WCSession on the phone. Two jobs:
//   - Out: whenever the active session changes, push the whole thing to the
//     watch as application context (latest wins, delivered when reachable).
//   - In: fold each event the watch sends through `WatchSyncReducer`, save
//     the result through `SessionStore.saveActive` so every phone reader
//     (LogScreen, autosave, the reminder clock) sees it, and complete the
//     session when the watch ended it.
//
// The phone-edit ledger is filled by diffing: every change to the active
// session that this coordinator did not make itself marks the sets that
// differ as edited now. The first sight of a session records nothing, so
// events queued while the phone app was closed still apply when it opens.
//
// `WatchSyncState` is persisted in UserDefaults beside the active session so
// a redelivered event stays a no-op across launches.

import Foundation
import Combine
import OSLog
import WatchConnectivity

final class WatchSyncCoordinator: NSObject, ObservableObject {

    static let stateKey = "pt_watch_sync_state"

    private let store: SessionStore
    private let planStore: PlanStore
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var lastKnown: ActiveSession?
    private var applyingWatchEvents = false
    private(set) var state: WatchSyncState

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

    init(store: SessionStore, planStore: PlanStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.planStore = planStore
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.stateKey),
           let saved = try? Self.decoder.decode(WatchSyncState.self, from: data) {
            state = saved
        } else {
            state = WatchSyncState()
        }
        super.init()
        lastKnown = store.active
        // No receive(on:): @Published delivers synchronously on assignment, and
        // `applyingWatchEvents` relies on seeing the store's change inline.
        store.$active
            .dropFirst()
            .sink { [weak self] in self?.activeChanged($0) }
            .store(in: &cancellables)
        // Today's planned session rides along in the context, so a plan
        // change (regeneration, an override) reaches the watch too.
        planStore.$plan
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.store.active == nil else { return }
                self.pushContext(nil)
            }
            .store(in: &cancellables)
        MotionStore.shared.prune()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Out

    private func activeChanged(_ session: ActiveSession?) {
        defer { lastKnown = session }
        if !applyingWatchEvents, let session,
           let before = lastKnown, before.startTime == session.startTime {
            var next = state.matching(session)
            let now = Date()
            for ex in session.exercises {
                let previous = before.exercises.first { $0.id == ex.id }?.sets ?? []
                for set in ex.sets where previous.first(where: { $0.num == set.num }) != set {
                    next.notePhoneEdit(exerciseId: ex.id, setNum: set.num, at: now)
                }
            }
            persist(next)
        }
        pushContext(session)
    }

    private func pushContext(_ session: ActiveSession?) {
        guard WCSession.isSupported() else { return }
        let wc = WCSession.default
        guard wc.activationState == .activated, wc.isPaired, wc.isWatchAppInstalled else {
            Self.log.notice("context not pushed: state \(wc.activationState.rawValue) paired \(wc.isPaired) installed \(wc.isWatchAppInstalled)")
            return
        }
        let context = WatchSyncContext(activeSession: session,
                                       plannedSession: session == nil ? plannedSessionForToday() : nil,
                                       sentAt: Date())
        guard let data = try? Self.encoder.encode(context) else { return }
        do {
            try wc.updateApplicationContext(["context": data])
            Self.log.notice("context pushed: \(session?.name ?? "none", privacy: .public), \(data.count) bytes")
        } catch {
            Self.log.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let log = Logger(subsystem: "com.phasetraining.app", category: "watch-sync")

    /// Today's lift or mobility session as the plan shows it, unstarted.
    private func plannedSessionForToday() -> ActiveSession? {
        guard let template = planStore.plan?.today()?.workoutTemplate else { return nil }
        return store.createSession(from: template)
    }

    // MARK: - In

    /// Fold events from the watch into the active session. Main thread.
    func apply(_ events: [WatchSyncEvent]) {
        guard let active = store.active else {
            // Nothing in progress: a start from the watch is adopted as is,
            // with the watch's start time, so its set events line up.
            // Anything else has nothing to apply to.
            for event in events {
                if case .sessionStarted(let session) = event.kind, store.active == nil {
                    Self.log.notice("session started from the watch: \(session.name, privacy: .public)")
                    store.saveActive(session)
                    state = WatchSyncState(sessionStart: session.startTime)
                    state.appliedEventIds.insert(event.id)
                    persist(state)
                } else {
                    Self.log.notice("event dropped: no active session")
                }
            }
            return
        }
        let outcome = WatchSyncReducer.apply(events, to: active, state: state)
        Self.log.notice("events applied: \(outcome.applied.count) of \(events.count), ended \(outcome.ended)")
        persist(outcome.state)
        if outcome.session != active {
            // LogScreen sees this through `store.$active` and starts the rest
            // for any set that became done without one of its own taps.
            applyingWatchEvents = true
            store.saveActive(outcome.session)
            applyingWatchEvents = false
        }
        if outcome.ended {
            store.saveCompleted(outcome.session, feel: nil, note: nil)
        }
    }

    private func persist(_ next: WatchSyncState) {
        guard next != state else { return }
        state = next
        if let data = try? Self.encoder.encode(next) {
            defaults.set(data, forKey: Self.stateKey)
        }
    }
}

extension WatchSyncCoordinator: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async { self.pushContext(self.store.active) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // The user switched watches. Activate again for the new one.
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.pushContext(self.store.active) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        // The phone app can activate before the watch is reachable (seen on
        // paired simulators: activation reported paired and installed, yet
        // nothing arrived). Re-push whenever the link comes up.
        DispatchQueue.main.async { self.pushContext(self.store.active) }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // A labeled motion window (PLAN-watch.md, step 3). The system deletes
        // the received file once this returns, so it is moved synchronously.
        guard let sessionId = file.metadata?["sessionId"] as? String,
              let fileName = file.metadata?["fileName"] as? String else {
            Self.log.error("file without motion metadata: \(file.fileURL.lastPathComponent, privacy: .public)")
            return
        }
        do {
            try MotionStore.shared.store(fileAt: file.fileURL, sessionId: sessionId, fileName: fileName)
            Self.log.notice("motion stored: \(sessionId, privacy: .public)/\(fileName, privacy: .public)")
        } catch {
            Self.log.error("motion store failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // The watch sends this way while reachable; the same payload as a
        // queued transfer, so both land in `apply`.
        self.session(session, didReceiveUserInfo: message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["event"] as? Data,
              let event = try? Self.decoder.decode(WatchSyncEvent.self, from: data) else {
            Self.log.error("userInfo without a decodable event: \(userInfo.keys.joined(separator: ","), privacy: .public)")
            return
        }
        Self.log.notice("event received: \(String(describing: event.kind), privacy: .public) set \(event.setNum ?? -1)")
        DispatchQueue.main.async { self.apply([event]) }
    }
}
