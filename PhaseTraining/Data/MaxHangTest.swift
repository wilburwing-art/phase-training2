// MaxHangTest.swift — one max-hang test: added load on a 20mm edge for 10s.
//
// The standard finger-strength benchmark climbing apps track, expressed as a
// share of body weight so it compares across a weight change. Stored in
// TrainingMemory beside the body-weight log. Nothing prescribes from it yet.

import Foundation

struct MaxHangTest: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date
    /// Load added on top of body weight; negative when assisted (pulley, feet).
    var addedKg: Double
    /// Body weight at the time, so the ratio survives later weigh-ins.
    var bodyKg: Double
    var edgeMm: Int = 20
    var seconds: Int = 10

    /// Total load held, as a share of body weight: 1.0 is a body-weight hang.
    var ratio: Double { bodyKg > 0 ? (bodyKg + addedKg) / bodyKg : 0 }

    /// "132% of body weight".
    var percentLabel: String { "\(Int((ratio * 100).rounded()))% of body weight" }
}

extension TrainingMemory {
    /// Latest logged body weight, else the profile weight; nil with neither.
    var currentBodyKg: Double? {
        bodyWeightLog.max(by: { $0.date < $1.date })?.weightKg ?? weightKg
    }

    /// True for a lifter who climbs, the audience for the finger card.
    var climbs: Bool {
        sports.contains { $0.slug.contains("climb") || $0.slug.contains("boulder") }
    }
}
