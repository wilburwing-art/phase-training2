// HealthImportsScreen.swift — Phase 2 Settings → Health & Imports
// subscreen. Presented from ProfileScreen's APP section as a sheet so
// it composes with the existing Settings row pattern.
//
// LAZY AUTHORIZATION — the system HK auth dialog is requested when the
// user taps "Sync from Health" the first time, NOT during onboarding.
// Skipping HK entirely is fully supported: the rest of the app sees zero
// imported workouts, GeneratorContext computes readinessScore from native
// sessions + sport logs only (or returns neutral 0.5 if even those are
// empty), and no generator behavior changes.
//
// What this screen shows:
//   - Auth status row (system-level status is opaque for reads; we only
//     surface "have we asked yet" + "did the last sync return rows").
//   - Last sync summary (count + date range + last-synced-at).
//   - "Sync from Health" primary CTA.
//   - Phase 3 CSV import placeholder section (disabled in v1).
//   - Debug-only readiness breakdown (only when DEBUG and we have data).

import SwiftUI

struct HealthImportsScreen: View {
    @EnvironmentObject private var store: MemoryStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    // Lifecycle state — survives only as long as the sheet is open.
    @State private var syncing = false
    @State private var lastError: String?
    @State private var summary: (count: Int, oldest: Date?, newest: Date?, lastImported: Date?)?
    @State private var debugReadiness: ReadinessSignal?

    // Build 103 — body-metrics sync state. Separate flow from workouts so
    // the auth dialog is granular (users can grant workouts but not body
    // composition, or vice versa).
    @State private var bodyMetricsSyncing = false
    @State private var lastBodyMetricsSummary: BodyMetricsSyncSummary?
    @State private var bodyMetricsError: String?

    // Phase 3 CSV import state.
    @State private var presentingCSVPicker = false
    @State private var csvImporting = false
    @State private var csvError: String?
    @State private var csvSummary: (count: Int, oldest: Date?, newest: Date?, perSource: [String: Int])?
    @State private var lastImport: WorkoutCSVImporter.Result?

    private let importer = HealthKitImporter()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        headerSection
                        statusSection
                        syncSection
                        if let err = lastError {
                            errorSection(message: err)
                        }
                        bodyMetricsSection
                        if let err = bodyMetricsError {
                            errorSection(message: err)
                        }
                        csvImportSection
                        #if DEBUG
                        if let breakdown = debugReadiness {
                            debugReadinessSection(signal: breakdown)
                        }
                        #endif
                        Spacer().frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
            }
            .navigationTitle("Health & Imports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                refreshSummary()
                refreshCSVSummary()
            }
            .fileImporter(
                isPresented: $presentingCSVPicker,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleCSVPick(result)
            }
        }
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

    private var csvImportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FROM A CSV")
                .font(.caption.bold())
                .foregroundColor(.ink2)

            if let s = csvSummary, s.count > 0 {
                csvSummaryBlock(s: s)
            }
            if let last = lastImport {
                csvLastImportBlock(result: last)
            }

            Button {
                csvError = nil
                presentingCSVPicker = true
            } label: {
                Text(csvImporting ? "Importing…" : "Import Fitbod CSV")
                    .font(.subheadline.bold())
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
            .disabled(csvImporting)

            if let err = csvError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Hevy and Strava export support arrives in a follow-up. We only read the file — we don't upload anything.")
                .font(.caption)
                .foregroundColor(.ink2)
        }
    }

    private func csvSummaryBlock(s: (count: Int, oldest: Date?, newest: Date?, perSource: [String: Int])) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(s.count) sets in your import history")
                .font(.subheadline)
                .foregroundColor(.ink)
            if let oldest = s.oldest, let newest = s.newest {
                Text("\(Self.dateFormatter.string(from: oldest)) → \(Self.dateFormatter.string(from: newest))")
                    .font(.caption)
                    .foregroundColor(.ink2)
            }
            ForEach(s.perSource.sorted(by: { $0.value > $1.value }), id: \.key) { entry in
                HStack {
                    Text(prettySource(entry.key)).font(.caption).foregroundColor(.ink)
                    Spacer()
                    Text("\(entry.value)").font(.caption.monospaced()).foregroundColor(.ink2)
                    Button(role: .destructive) {
                        deleteSource(rawValue: entry.key)
                    } label: {
                        Text("Delete").font(.caption)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.surface)
        .cornerRadius(8)
    }

    private func csvLastImportBlock(result: WorkoutCSVImporter.Result) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last import: \(result.setsInserted) sets, \(result.workoutsInserted) cardio rows")
                .font(.caption)
                .foregroundColor(.ink)
            Text("Matched \(Int(result.nameMatchRate * 100))% of exercise names to the catalog")
                .font(.caption2)
                .foregroundColor(.ink2)
            if !result.topExercises.isEmpty {
                Text("Top: " + result.topExercises.map { "\($0.name) (\($0.sets))" }.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundColor(.ink2)
                    .lineLimit(2)
            }
            if !result.parseErrors.isEmpty {
                Text("\(result.parseErrors.count) rows skipped (see Xcode console for details)")
                    .font(.caption2)
                    .foregroundColor(.ink2)
            }
        }
        .padding(8)
        .background(Color.surface.opacity(0.6))
        .cornerRadius(6)
    }

    private func prettySource(_ raw: String) -> String {
        switch raw {
        case "healthKit": return "Apple Health"
        case "fitbodCSV": return "Fitbod CSV"
        case "hevyCSV": return "Hevy CSV"
        case "stravaCSV": return "Strava CSV"
        default: return raw
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

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
                refreshSummary()
            } catch {
                lastError = "\(error)"
            }
        }
    }

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
                bodyMetricsError = "\(error)"
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

    // MARK: - Phase 3 CSV actions

    private func handleCSVPick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            runCSVImport(url: url)
        case .failure(let err):
            csvError = err.localizedDescription
        }
    }

    private func runCSVImport(url: URL) {
        csvImporting = true
        csvError = nil
        Task { @MainActor in
            defer { csvImporting = false }
            // .fileImporter URLs are security-scoped. iOS docs say balance
            // start/stop and check the return; the file picker for our own
            // sandboxed Documents would work without it but the system
            // share path needs it.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let result = try await WorkoutCSVImporter.import(url: url)
                lastImport = result
                refreshCSVSummary()
                // Also refresh the HK summary in case the importer wrote
                // cardio rows to imported_workouts (Fitbod cardio path).
                refreshSummary()
            } catch {
                csvError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }
    }

    private func refreshCSVSummary() {
        csvSummary = UserDatabase.shared.importedSetsSummary()
    }

    private func deleteSource(rawValue: String) {
        guard let src = ImportSource(rawValue: rawValue) else { return }
        UserDatabase.shared.deleteImports(source: src)
        refreshCSVSummary()
        refreshSummary()
    }
}
