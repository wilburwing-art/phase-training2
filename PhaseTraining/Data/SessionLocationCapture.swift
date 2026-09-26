// SessionLocationCapture.swift — the only CoreLocation code in the app (3c
// capture slice).
//
// One coarse fix (kCLLocationAccuracyHundredMeters, requestLocation) when a
// workout starts, and nothing else: no continuous updates, no background
// location, no geofences. "While using" permission is asked at the first
// session start only, and only if iOS has never been asked; once the user
// declines, nothing is captured and nothing is asked again.
//
// It never blocks the workout. The request is fire-and-forget, gives up after
// `timeout`, and drops a fix that arrives too long after the session began
// (the user may have sat on the permission prompt). The coordinates are
// rounded to ~100 m before the completion sees them (SessionPlacePoint.coarse)
// and are kept on device; nothing here is sent anywhere or reaches the coach.
//
// Must be created and used on the main thread (the manager delivers delegate
// callbacks on the run loop of the thread that created it).

import CoreLocation
import Foundation

final class SessionLocationCapture: NSObject, CLLocationManagerDelegate {

    static let shared = SessionLocationCapture()

    /// Set once the app has put the permission prompt up, so it is never put
    /// up again (iOS would not show it twice anyway; this keeps the intent
    /// explicit and survives a status that reads notDetermined again).
    static let promptedKey = "pt_location_prompted"
    /// How long a requested fix may take before it is abandoned.
    static let timeout: TimeInterval = 20
    /// A fix later than this after the session began no longer says where the
    /// session started.
    static let maxDelayAfterStart: TimeInterval = 10 * 60
    /// A cached fix older than this is not "at session start".
    static let maxFixAge: TimeInterval = 5 * 60

    private let manager = CLLocationManager()
    private let defaults: UserDefaults
    private var pendingSessionId: TimeInterval?
    private var pendingCompletion: ((SessionPlacePoint) -> Void)?
    private var timeoutWork: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Unit tests, SwiftUI previews and UI tests never prompt or capture.
    static var isDisabledForThisProcess: Bool {
        let info = ProcessInfo.processInfo
        if info.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || info.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return info.arguments.contains { $0.hasPrefix("--ui-test") }
    }

    /// Start the one-shot capture for a session that just began. Returns at
    /// once; `completion` runs on the main thread only if a usable fix arrives.
    func captureAtSessionStart(sessionId: TimeInterval,
                               completion: @escaping (SessionPlacePoint) -> Void) {
        guard !Self.isDisabledForThisProcess else { return }
        // A newer session replaces any capture still in flight.
        finish()
        pendingSessionId = sessionId
        pendingCompletion = completion
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            requestFix()
        case .notDetermined:
            guard !defaults.bool(forKey: Self.promptedKey) else { return finish() }
            defaults.set(true, forKey: Self.promptedKey)
            // locationManagerDidChangeAuthorization continues once the user answers.
            manager.requestWhenInUseAuthorization()
        default:
            // Denied or restricted: capture nothing, ask nothing.
            finish()
        }
    }

    private func requestFix() {
        guard let sessionId = pendingSessionId else { return }
        guard Date().timeIntervalSince1970 - sessionId < Self.maxDelayAfterStart else { return finish() }
        timeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingSessionId == sessionId else { return }
            // Cancels an outstanding requestLocation.
            self.manager.stopUpdatingLocation()
            self.finish()
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout, execute: work)
        manager.requestLocation()
    }

    private func finish() {
        timeoutWork?.cancel()
        timeoutWork = nil
        pendingSessionId = nil
        pendingCompletion = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Also called when the manager is created; only act for a pending session.
        guard pendingSessionId != nil, timeoutWork == nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            requestFix()
        case .notDetermined:
            break
        default:
            finish()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let sessionId = pendingSessionId, let completion = pendingCompletion,
              let fix = locations.last else { return }
        finish()
        guard fix.horizontalAccuracy >= 0,
              abs(fix.timestamp.timeIntervalSinceNow) <= Self.maxFixAge else { return }
        completion(.coarse(sessionId: sessionId,
                           capturedAt: fix.timestamp,
                           latitude: fix.coordinate.latitude,
                           longitude: fix.coordinate.longitude,
                           horizontalAccuracy: fix.horizontalAccuracy))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // requestLocation reports one failure and stops; nothing to retry.
        finish()
    }
}
