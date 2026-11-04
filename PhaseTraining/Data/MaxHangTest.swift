// MaxHangTest.swift — one max-hang test: added load on a 20mm edge for 10s.
//
// The standard finger-strength benchmark climbing apps track, expressed as a
// share of body weight so it compares across a weight change. Stored in
// TrainingMemory beside the body-weight log. The latest test sets the added
// load on the two hangboard protocols Lattice publishes a figure for
// (`HangboardLoad`), prefilled when a session starts.

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

/// Added load on a hangboard exercise from the latest max-hang test.
///
/// Source, read verbatim from Lattice Training's "Testing & Training Rung
/// Instructions" (latticetraining.com, 2018): "Maximal total loading = Body
/// weight + additional weight"; maximal strength is "6 x 10 second dead hangs
/// @ 85% of maximal total loading"; anaerobic capacity is "6 sets of 5 (7
/// seconds on 3 seconds off) @ 80% of maximal total loading". Lattice's test
/// is a 7s hang and this app's is 10s, so 85% of a 10s max is slightly
/// conservative. No other hangboard exercise gets a load: Lattice gives no
/// figure for one-arm, density or 10/5 repeaters, and none is invented here.
enum HangboardLoad {
    struct Prescription: Equatable {
        /// Added load in lb (weight fields are lb app-wide). Negative means
        /// assistance: take that much off with a pulley or the feet.
        let addedLb: Double
        /// Share of tested total load, 0.85 or 0.80.
        let intensity: Double

        var percentLabel: String { "\(Int((intensity * 100).rounded()))% of your test" }
    }

    /// Catalog name (lowercased) to share of maximal total loading.
    static let intensities: [String: Double] = [
        "hangboard max hang (20mm edge)": 0.85,
        "hangboard repeaters (7/3 protocol)": 0.80,
    ]

    /// Nil without a test, without a body weight, or for an exercise Lattice
    /// gives no figure for. Uses the test's ratio against today's body
    /// weight, so a weigh-in since the test moves the load with it.
    static func prescription(forExerciseNamed name: String, memory: TrainingMemory) -> Prescription? {
        guard let intensity = intensities[name.lowercased()],
              let test = memory.maxHangTests.max(by: { $0.date < $1.date }),
              test.ratio > 0,
              let body = memory.currentBodyKg, body > 0 else { return nil }
        let addedKg = intensity * test.ratio * body - body
        let lb = (addedKg / BodyMetrics.kgPerLb / 2.5).rounded() * 2.5
        return Prescription(addedLb: lb == 0 ? 0 : lb, intensity: intensity)
    }
}
