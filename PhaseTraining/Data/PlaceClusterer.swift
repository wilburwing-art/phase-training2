// PlaceClusterer.swift — 3c capture slice: where sessions start, grouped into
// places, offline and on device.
//
// SessionPlacePoint is one coarse fix taken when a workout starts
// (SessionLocationCapture), already rounded to 3 decimal places (about 100 m)
// before it is stored. PlaceClusterer groups those points into places: a point
// joins the nearest place whose centroid is within `radiusMeters` (haversine),
// otherwise it starts a new one. Points are visited oldest first with a fixed
// tie-break, so the same log always yields the same places.
//
// Capture and store only. Nothing reads the places yet (the 3c reader, home gym
// and equipment-aware swaps, waits until places have accrued). Nothing here
// leaves the device or enters the coach snapshot.

import Foundation

struct SessionPlacePoint: Codable, Equatable, Identifiable {
    /// Same id SavedSession uses: the session's startTime in seconds since 1970.
    var sessionId: TimeInterval
    /// When the fix was taken.
    var capturedAt: Date
    /// Rounded to 3 decimal places (about 100 m) before storage.
    var latitude: Double
    var longitude: Double
    /// Meters, as CoreLocation reported it for the unrounded fix.
    var horizontalAccuracy: Double

    var id: TimeInterval { sessionId }

    /// Build a stored point, rounding the coordinates. Callers never store
    /// the raw fix.
    static func coarse(sessionId: TimeInterval, capturedAt: Date,
                       latitude: Double, longitude: Double,
                       horizontalAccuracy: Double) -> SessionPlacePoint {
        SessionPlacePoint(sessionId: sessionId, capturedAt: capturedAt,
                          latitude: round3(latitude), longitude: round3(longitude),
                          horizontalAccuracy: horizontalAccuracy.rounded())
    }

    static func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
}

struct TrainingPlace: Equatable, Identifiable {
    /// Position in the clusterer's output (0 = most visited).
    var id: Int
    var latitude: Double
    var longitude: Double
    var visitCount: Int
    var firstSeen: Date
    var lastSeen: Date
    var sessionIds: [TimeInterval]
}

enum PlaceClusterer {

    static let defaultRadiusMeters: Double = 150
    /// A fix vaguer than this says little about which place it was (iOS
    /// "approximate location" reports kilometers). Skipped, not stored apart.
    static let defaultMaxAccuracyMeters: Double = 1_000

    static func cluster(_ points: [SessionPlacePoint],
                        radiusMeters: Double = defaultRadiusMeters,
                        maxAccuracyMeters: Double = defaultMaxAccuracyMeters) -> [TrainingPlace] {
        let usable = points
            .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= maxAccuracyMeters }
            .sorted { ($0.capturedAt, $0.sessionId) < ($1.capturedAt, $1.sessionId) }

        var groups: [[SessionPlacePoint]] = []
        var centroids: [(lat: Double, lon: Double)] = []
        for p in usable {
            var best: Int?
            var bestDistance = Double.infinity
            for (i, c) in centroids.enumerated() {
                let d = haversineMeters(lat1: p.latitude, lon1: p.longitude, lat2: c.lat, lon2: c.lon)
                // Strict < keeps the earliest place on an exact tie.
                if d <= radiusMeters && d < bestDistance {
                    best = i
                    bestDistance = d
                }
            }
            if let i = best {
                groups[i].append(p)
                let n = Double(groups[i].count)
                centroids[i] = (groups[i].reduce(0) { $0 + $1.latitude } / n,
                                groups[i].reduce(0) { $0 + $1.longitude } / n)
            } else {
                groups.append([p])
                centroids.append((p.latitude, p.longitude))
            }
        }

        let places = groups.enumerated().map { i, members in
            TrainingPlace(id: 0,
                          latitude: centroids[i].lat,
                          longitude: centroids[i].lon,
                          visitCount: members.count,
                          firstSeen: members.first!.capturedAt,
                          lastSeen: members.last!.capturedAt,
                          sessionIds: members.map(\.sessionId))
        }
        // Most visited first; an older place wins a tie.
        return places
            .sorted { ($1.visitCount, $0.firstSeen.timeIntervalSince1970) < ($0.visitCount, $1.firstSeen.timeIntervalSince1970) }
            .enumerated()
            .map { i, place in
                var p = place
                p.id = i
                return p
            }
    }

    /// Great-circle distance in meters.
    static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}
