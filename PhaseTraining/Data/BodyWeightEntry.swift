// BodyWeightEntry.swift — one row in the body-weight time series.
//
// Lives on `TrainingMemory.bodyWeightLog` (build 103, schemaVersion 7). The
// most recent entry's weight is mirrored onto `TrainingMemory.weightKg` so
// every existing consumer (strength ratios, profile summary, generator) sees
// the latest weight without changing its read path. Older entries power the
// Progress trend card.
//
// Metric storage — same convention as `weightKg`. Rendered through
// `BodyMetrics.formatWeight(kg:imperial:)`.

import Foundation

struct BodyWeightEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var weightKg: Double
    var note: String? = nil

    init(id: UUID = UUID(), date: Date, weightKg: Double, note: String? = nil) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.note = note
    }
}
