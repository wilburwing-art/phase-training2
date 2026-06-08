// HealthWorkoutSyncSection.swift — workout-sync section of the Health &
// Imports screen. Extracted from HealthImportsScreen; owns the sync
// lifecycle state (spinner, error, summary, debug readiness) so nothing
// is threaded down from the parent shell.
//
// LAZY AUTHORIZATION — the system HK auth dialog is requested when the
// user taps "Sync from Health" the first time, NOT during onboarding.
// Skipping HK entirely is fully supported: the rest of the app sees zero
// imported workouts, GeneratorContext computes readinessScore from native
// sessions + sport logs only (or returns neutral 0.5 if even those are
// empty), and no generator behavior changes.

import SwiftUI

struct HealthWorkoutSyncSection: View {
    @EnvironmentObject private var store: MemoryStore
    @EnvironmentObject private var sessionStore: SessionStore

    let importer: HealthKitImporter

    /// Bumped by the parent when another section (CSV import) writes to
    /// imported_workouts so the summary here stays fresh.
    let refreshToken: Int

    // Lifecycle state — survives only as long as the sheet is open.
    @State private var syncing = false
    @State private var lastError: String?
    @State private var summary: (count: Int, oldest: Date?, newest: Date?, lastImported: Date?)?
    @State private var debugReadiness: ReadinessSignal?
    /// Set once a sync completes. Lets the empty state distinguish "you
    /// haven't synced yet" from "synced, but Health returned nothing" — the
    /// latter usually means read access is off (HK won't tell us directly).
    @State private var didAttemptSync = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            headerSection
            statusSection
            syncSection
            if let err = lastError {
                errorSection(message: err)
            }
            #if DEBUG
            if let breakdown = debugReadiness {
                debugReadinessSection(signal: breakdown)
            }
            #endif
        }
        .onAppear { refreshSummary() }
        .onChange(of: refreshToken) { _, _ in refreshSummary() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workout history")
                .font(.title3.bold())
                .foregroundColor(.ink)
            Text("Read recent workouts from the Health app to help us match the workouts we generate to how active you've actually been. Read-only — we never write to Health.")
                .font(.subheadline)
                .foregroundColor(.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STATUS")
                .font(.caption.bold())
                .foregroundColor(.ink2)
            if let s = summary, s.count > 0 {
                rangeRow(s: s)
            } else if didAttemptSync {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No workouts came back from Health.")
                        .font(.subheadline)
                        .foregroundColor(.ink2)
                    Text("If you expected some, check Settings → Health → Data Access & Devices → Phase Training and turn on Workouts.")
                        .font(.caption)
                        .foregroundColor(.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No imported workouts yet.")
                    .font(.subheadline)
                    .foregroundColor(.ink2)
            }
        }
    }

    private func rangeRow(s: (count: Int, oldest: Date?, newest: Date?, lastImported: Date?)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(s.count) workout\(s.count == 1 ? "" : "s") imported")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.ink)
            if let oldest = s.oldest, let newest = s.newest {
                Text("Range: \(short(oldest)) – \(short(newest))")
                    .font(.caption)
                    .foregroundColor(.ink2)
            }
            if let last = s.lastImported {
                Text("Last sync: \(short(last))")
                    .font(.caption)
                    .foregroundColor(.ink2)
            }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: syncTapped) {
                HStack {
                    if syncing {
                        ProgressView().tint(.accentInk)
                    } else {
                        Image(systemName: "heart.text.square")
                    }
                    Text(syncing ? "Syncing…" : "Sync from Health")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accent)
                .foregroundColor(.accentInk)
                .cornerRadius(10)
            }
            .disabled(syncing)
            Text("Pulls your last 28 days of workouts. You'll see Apple's permission prompt the first time.")
                .font(.caption)
                .foregroundColor(.ink2)
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

    #if DEBUG
    private func debugReadinessSection(signal: ReadinessSignal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("READINESS (DEBUG)")
                .font(.caption.bold())
                .foregroundColor(.ink2)
            Text("score = \(String(format: "%.2f", signal.score))")
                .font(.caption.monospaced())
                .foregroundColor(.ink)
            Text("density = \(String(format: "%.2f", signal.breakdown.density))   recency = \(String(format: "%.2f", signal.breakdown.recency))   trend = \(String(format: "%.2f", signal.breakdown.trend))")
                .font(.caption.monospaced())
                .foregroundColor(.ink2)
        }
    }
    #endif

    // MARK: - Actions

    private func syncTapped() {
        syncing = true
        lastError = nil
        Task { @MainActor in
            defer { syncing = false }
            do {
                // Request auth (idempotent after first grant; surfaces the
                // system dialog on first call). We treat success here as
                // "user saw the prompt"; whether they granted is observed
                // by checking the row count after the fetch.
                _ = try await importer.requestAuthorization()
                let imported = try await importer.recentWorkouts(days: 28)
                UserDatabase.shared.insertImportedWorkouts(imported)
                didAttemptSync = true
                refreshSummary()
            } catch {
                lastError = "\(error)"
            }
        }
    }

    private func refreshSummary() {
        summary = UserDatabase.shared.importedWorkoutSummary()
        #if DEBUG
        // Recompute readiness off the same window — read-only diagnostic.
        let memory = store.memory
        let profile = DemographicProfile.from(memory)
        let imported = UserDatabase.shared.recentImportedWorkouts(within: 28)
        let context = GeneratorContext.from(
            sessions: sessionStore.savedSessions,
            soreness: memory.soreness,
            feedback: memory.feedback,
            importedWorkouts: imported,
            cohort: profile.eraCohort
        )
        if context.hasReadinessData {
            debugReadiness = ReadinessSignal(score: context.readinessScore, breakdown: context.readinessBreakdown)
        } else {
            debugReadiness = nil
        }
        #endif
    }

    private func short(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}
