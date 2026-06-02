// BodyCompositionEntry.swift — one row in the body-composition time series.
//
// Lives on `TrainingMemory.bodyCompositionLog` (build 103, schemaVersion 7).
// Distinct from `BodyWeightEntry`: body weight is a single scalar (kg);
// composition tracks the two scalars that actually matter for the recomp
// story — body-fat percent and lean / fat-free mass in kg. Either can be
// nil so DEXA / InBody users (BF% + LBM) and home-scale users (BF% only)
// both have a place to record.
//
// Metric storage. Conversions live in BodyMetrics.

import Foundation

struct BodyCompositionEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date
    /// 0.0–60.0 in percent units (NOT decimal — "18.5" means 18.5%).
    /// Nil when the source method only reported lean mass.
    var bodyFatPercent: Double? = nil
    /// Lean / fat-free mass in kg. Nil when the source method only reported
    /// body-fat percent (most consumer scales).
    var leanMassKg: Double? = nil
    /// Free-text — "DEXA scan", "InBody", "calipers", etc.
    var method: String? = nil
    var note: String? = nil

    init(
        id: UUID = UUID(),
        date: Date,
        bodyFatPercent: Double? = nil,
        leanMassKg: Double? = nil,
        method: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.bodyFatPercent = bodyFatPercent
        self.leanMassKg = leanMassKg
        self.method = method
        self.note = note
    }
}
