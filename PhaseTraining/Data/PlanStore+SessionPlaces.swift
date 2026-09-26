// PlanStore+SessionPlaces.swift — 3c capture: persist the coarse point taken
// at each session start. Same shape as the DayOutcome log (dedupe by session
// id, rolling window, UserDefaults JSON), with a 365-day window because places
// are learned from repeat visits. See PlaceClusterer.swift.

import Foundation

extension PlanStore {

    /// Record the point for a just-started session. Idempotent per session id.
    /// Called through `SessionStore.onSessionStarted` → SessionLocationCapture.
    func recordSessionPlace(_ point: SessionPlacePoint, now: Date = Date()) {
        var next = sessionPlaces.filter { $0.sessionId != point.sessionId }
        next.append(point)
        let cutoff = now.addingTimeInterval(-Double(Self.sessionPlacesRetentionDays) * 86_400)
        sessionPlaces = next
            .filter { $0.capturedAt >= cutoff }
            .sorted { $0.capturedAt > $1.capturedAt }
        saveSessionPlaces()
    }

    func saveSessionPlaces() {
        if let data = try? Self.encoder().encode(sessionPlaces) {
            defaults.set(data, forKey: Self.sessionPlacesKey)
        }
    }

    /// Shared by init and reloadFromDefaults (a restore must re-read it, or
    /// the next insert writes the stale in-memory copy over the restored log).
    static func loadSessionPlaces(_ defaults: UserDefaults, today: Date) -> [SessionPlacePoint] {
        let cutoff = today.addingTimeInterval(-Double(sessionPlacesRetentionDays) * 86_400)
        return (decode([SessionPlacePoint].self, defaults, sessionPlacesKey) ?? [])
            .filter { $0.capturedAt >= cutoff }
            .sorted { $0.capturedAt > $1.capturedAt }
    }
}
