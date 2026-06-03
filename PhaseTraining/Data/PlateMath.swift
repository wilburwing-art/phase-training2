// PlateMath.swift — barbell plate-stack math.
//
// Pure value-only helpers. Used by PlateCalculatorSheet for rendering and by
// tests for verification. Kept out of the SwiftUI view so the math doesn't
// depend on @State / @Environment and can be unit-tested directly.

import Foundation

enum PlateMath {

    /// One denomination + how many of it sit on a single side of the bar.
    struct Row: Equatable {
        let plate: Double
        let count: Int
    }

    /// Greedy plate allocation result. `achieved` is the total weight the
    /// stack actually adds up to (bar + both sides); `remainder` is what we
    /// couldn't make with the available denominations (in the target's unit,
    /// total — not per side).
    struct Result: Equatable {
        let perSide: [Row]
        let achieved: Double
        let remainder: Double
    }

    /// Standard plate set per unit system. Hard-coded to what most gyms
    /// stock — imperial defaults to the IPF-ish 45/35/25/10/5/2.5 lb set,
    /// metric defaults to the IWF 25/20/15/10/5/2.5/1.25 kg set.
    static func standardPlates(imperial: Bool) -> [Double] {
        imperial
            ? [45, 35, 25, 10, 5, 2.5]
            : [25, 20, 15, 10, 5, 2.5, 1.25]
    }

    /// Greedy biggest-plate-first allocation. Returns nil when the target
    /// is below the bar — the UI surfaces an explicit error in that case.
    /// Remainder is total (both sides combined) so the read-out "1 lb short"
    /// matches what the user can actually feel on the bar.
    static func calculate(target: Double, bar: Double, plates: [Double]) -> Result? {
        guard target >= bar else { return nil }
        let perSideTarget = (target - bar) / 2
        var remaining = perSideTarget
        var rows: [Row] = []
        for plate in plates {
            // Cap at a sane upper count — pathological inputs (e.g. 0.0001 lb
            // plates) shouldn't allocate a millions-long array; 50/side is
            // already absurd for any real loadout. Clamp as a Double BEFORE
            // the Int() conversion: a huge pasted target (raw > Int.max) would
            // otherwise trap on Int(_:) before the min(...) cap could run.
            let raw = remaining / plate
            let count = max(0, Int(min(raw, 50) + 1e-9))
            if count > 0 {
                rows.append(Row(plate: plate, count: count))
                remaining -= Double(count) * plate
            }
        }
        let achievedPerSide = perSideTarget - remaining
        return Result(
            perSide: rows,
            achieved: bar + achievedPerSide * 2,
            remainder: remaining * 2
        )
    }
}
