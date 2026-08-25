// BodyMetricsSyncSection.swift — body-metrics sync section of the
// Health & Imports screen. Extracted from HealthImportsScreen; owns its
// sync state. Separate flow from workouts so the auth dialog is granular
// (users can grant workouts but not body composition, or vice versa).

import SwiftUI

struct BodyMetricsSyncSection: View {
    @EnvironmentObject private var store: MemoryStore

    let importer: HealthKitImporter

    // Build 103 — body-metrics sync state. Separate flow from workouts so
    // the auth dialog is granular (users can grant workouts but not body
    // composition, or vice versa).
    @State private var bodyMetricsSyncing = false
    @State private var lastBodyMetricsSummary: BodyMetricsSyncSummary?
    @State private var bodyMetricsError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            bodyMetricsSection
            if let err = bodyMetricsError {
                errorSection(message: err)
            }
        }
    }

    // MARK: - Sections

    /// Build 103 — body-metrics sync section. Mirrors the workout sync
    /// UX but with its own primary CTA + status row. Granular auth — a
    /// user can grant workouts but skip body composition (or vice
    /// versa); HK's per-type prompt makes that the natural flow.
    private var bodyMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BODY METRICS")
                .font(.caption.bold())
                .foregroundColor(.ink2)
            if let s = lastBodyMetricsSummary {
                bodyMetricsSummaryRow(s: s)
            } else if !store.memory.bodyWeightLog.isEmpty || !store.memory.bodyCompositionLog.isEmpty {
                Text("\(store.memory.bodyWeightLog.count) weight · \(store.memory.bodyCompositionLog.count) composition entries on file.")
                    .font(.caption)
                    .foregroundColor(.ink2)
            } else {
                Text("Pull weight + body-fat % + lean mass from Health.")
                    .font(.caption)
                    .foregroundColor(.ink2)
            }
            Button(action: syncBodyMetricsTapped) {
                HStack {
                    if bodyMetricsSyncing {
                        ProgressView().tint(.ink)
                    } else {
                        Image(systemName: "scalemass")
                    }
                    Text(bodyMetricsSyncing ? "Syncing…" : "Sync body metrics from Health")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.surface)
                .foregroundColor(.ink)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.lineSoft, lineWidth: 1)
                )
            }
            .disabled(bodyMetricsSyncing)
            Text("Last 365 days. Existing log entries within a minute of an HK sample are kept — we don't double-log.")
                .font(.caption)
                .foregroundColor(.ink3)
        }
    }

    private func bodyMetricsSummaryRow(s: BodyMetricsSyncSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Imported \(s.addedWeightEntries) weight · \(s.addedCompositionEntries) composition entr\(s.addedCompositionEntries == 1 ? "y" : "ies")")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.ink)
            if s.skippedDuplicateSamples > 0 {
                Text("Skipped \(s.skippedDuplicateSamples) already-logged entr\(s.skippedDuplicateSamples == 1 ? "y" : "ies").")
                    .font(.caption)
                    .foregroundColor(.ink3)
            }
            if let newest = s.newestSampleAt {
                Text("Newest from Health: \(short(newest))")
                    .font(.caption)
                    .foregroundColor(.ink2)
            }
        }
    }

    private func errorSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sync error")
                .font(.subheadline.bold())
                .foregroundColor(.ink)
            Text(message)
                .font(.caption)
                .foregroundColor(.ink2)
        }
        .padding(12)
        .background(Color.surface)
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func syncBodyMetricsTapped() {
        bodyMetricsSyncing = true
        bodyMetricsError = nil
        Task { @MainActor in
            defer { bodyMetricsSyncing = false }
            do {
                _ = try await importer.requestBodyMetricsAuthorization()
                let samples = try await importer.recentBodyMetrics(days: 365)
                // Seed any onboarding / About-You scalar into the log FIRST so
                // it participates in the date comparison. Otherwise an older HK
                // sample would clobber a manually-set weight that has no log
                // entry to compete with.
                store.update { $0.backfillBodyWeightLogFromScalar() }
                let merged = BodyMetricsMerger.merge(
                    weightLog: store.memory.bodyWeightLog,
                    compositionLog: store.memory.bodyCompositionLog,
                    samples: samples
                )
                store.update { mem in
                    mem.bodyWeightLog = merged.weight
                    mem.bodyCompositionLog = merged.composition
                    // Mirror to whatever is genuinely newest by date — an older
                    // imported sample no longer overwrites a fresher logged
                    // weight, and the scalar is never nulled.
                    mem.remirrorWeightFromLog()
                }
                lastBodyMetricsSummary = merged.summary
            } catch {
                // LocalizedError first, like CSVImportSection. Raw interpolation
                // surfaced HKError as `Error Domain=com.apple.healthkit Code=5
                // "Authorization not determined" UserInfo={...}` under a heading
                // that just said "Sync error".
                bodyMetricsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func short(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}
