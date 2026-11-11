// SkiReadinessTest.swift — one pre-season ski fitness check.
//
// Four field tests a skier can run in a garage: a wall sit held to failure,
// single-leg balance with the eyes closed, two-footed lateral hops over a
// line in 30 seconds, and a standing broad jump. Every metric is optional so
// a partial test still logs. Stored in TrainingMemory beside the max-hang
// tests; the Progress card compares the latest test with the one before.
// There is no score or pass mark: the app has no verified norms to grade by.

import Foundation

struct SkiReadinessTest: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var wallSitSeconds: Int?
    /// Eyes closed, seconds until the lifted foot touches down, capped at 60.
    var balanceLeftSeconds: Int?
    var balanceRightSeconds: Int?
    var lateralHops30s: Int?
    var broadJumpCm: Double?

    static let balanceCapSeconds = 60

    var isEmpty: Bool {
        wallSitSeconds == nil && balanceLeftSeconds == nil && balanceRightSeconds == nil
            && lateralHops30s == nil && broadJumpCm == nil
    }

    /// One row on the Progress card.
    enum Metric: String, CaseIterable {
        case wallSit, balanceLeft, balanceRight, lateralHops, broadJump

        var label: String {
            switch self {
            case .wallSit: return "Wall sit"
            case .balanceLeft: return "Balance, left"
            case .balanceRight: return "Balance, right"
            case .lateralHops: return "Lateral hops"
            case .broadJump: return "Broad jump"
            }
        }
    }

    func value(_ metric: Metric) -> Double? {
        switch metric {
        case .wallSit: return wallSitSeconds.map(Double.init)
        case .balanceLeft: return balanceLeftSeconds.map(Double.init)
        case .balanceRight: return balanceRightSeconds.map(Double.init)
        case .lateralHops: return lateralHops30s.map(Double.init)
        case .broadJump: return broadJumpCm
        }
    }

    /// "90s", "38 in 30s", "7 ft 2 in" / "218 cm".
    func label(_ metric: Metric, imperial: Bool) -> String? {
        guard let v = value(metric) else { return nil }
        switch metric {
        case .wallSit, .balanceLeft, .balanceRight: return "\(Int(v))s"
        case .lateralHops: return "\(Int(v)) in 30s"
        case .broadJump: return Self.distanceLabel(cm: v, imperial: imperial)
        }
    }

    /// The change from `previous` to this test, only when both carry the
    /// metric: "+6s", "-2", "+3 in" / "+8 cm". Nil when either side is missing.
    func deltaLabel(_ metric: Metric, from previous: SkiReadinessTest, imperial: Bool) -> String? {
        guard let now = value(metric), let then = previous.value(metric) else { return nil }
        let d = now - then
        let sign = d > 0 ? "+" : (d < 0 ? "-" : "±")
        switch metric {
        case .wallSit, .balanceLeft, .balanceRight: return "\(sign)\(Int(abs(d)))s"
        case .lateralHops: return "\(sign)\(Int(abs(d)))"
        case .broadJump:
            return imperial
                ? "\(sign)\(Int((abs(d) / BodyMetrics.cmPerInch).rounded())) in"
                : "\(sign)\(Int(abs(d).rounded())) cm"
        }
    }

    static func distanceLabel(cm: Double, imperial: Bool) -> String {
        guard imperial else { return "\(Int(cm.rounded())) cm" }
        let (feet, inches) = BodyMetrics.cmToFeetInches(Int(cm.rounded()))
        return "\(feet) ft \(inches) in"
    }
}

extension TrainingMemory {
    /// True for a lifter who skis or rides, the audience for the ski cards.
    var skis: Bool {
        sports.contains { SportProfile.of($0.slug).isSki }
    }
}
