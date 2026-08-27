// CSVImportSection.swift — Phase 3 CSV import section of the Health &
// Imports screen. Extracted from HealthImportsScreen; owns the picker /
// import / summary state. The `.fileImporter` lives here too so the
// presentation binding never leaves the section.

import SwiftUI

struct CSVImportSection: View {
    /// Called when an import or delete touches imported_workouts (the
    /// Fitbod cardio path writes there) so the workout-sync section can
    /// refresh its summary.
    let onImportedWorkoutsChanged: () -> Void

    // Phase 3 CSV import state.
    @State private var presentingCSVPicker = false
    @State private var csvImporting = false
    @State private var csvError: String?
    @State private var csvSummary: (count: Int, oldest: Date?, newest: Date?, perSource: [String: Int])?
    @State private var lastImport: WorkoutCSVImporter.Result?
    /// Pending per-source delete, held until the user confirms. Deleting an
    /// import source drops every set that came from it — the data behind
    /// priorBest and lifetime peaks — and there is no undo, so this follows
    /// the confirmed-destructive pattern the erase-all and restore paths use.
    @State private var pendingDelete: (source: String, count: Int)?

    var body: some View {
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

            // Was "arrives in a follow-up", which reads as imminent for
            // something with no parser written (T2-6). Say what's true today.
            Text("Fitbod exports only for now. We only read the file — we don't upload anything.")
                .font(.caption)
                .foregroundColor(.ink2)
        }
        .onAppear { refreshCSVSummary() }
        .fileImporter(
            isPresented: $presentingCSVPicker,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleCSVPick(result)
        }
        .confirmationDialog(
            pendingDelete.map { "Delete \($0.count) sets from \(prettySource($0.source))?" } ?? "",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pending = pendingDelete {
                Button("Delete \(pending.count) sets", role: .destructive) {
                    deleteSource(rawValue: pending.source)
                    pendingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This permanently removes that imported history, including the sets behind your lifetime bests. It can't be undone.")
        }
    }

    // MARK: - Blocks

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
                        pendingDelete = (source: entry.key, count: entry.value)
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
            // "Read" not "imported": the count is rows parsed, and the table
            // is INSERT OR REPLACE, so re-importing the same file shows the
            // same number with zero net-new rows.
            Text("Last import: read \(result.setsInserted) sets · \(result.workoutsInserted) cardio rows")
                .font(.caption)
                .foregroundColor(.ink)
            Text("Matched \(Int(result.nameMatchRate * 100))% of exercise names to the catalog")
                .font(.caption2)
                .foregroundColor(.ink2)
            if result.warmupsSkipped > 0 {
                Text("Skipped \(result.warmupsSkipped) warmup \(result.warmupsSkipped == 1 ? "row" : "rows")")
                    .font(.caption2)
                    .foregroundColor(.ink2)
            }
            if !result.topExercises.isEmpty {
                Text("Top: " + result.topExercises.map { "\($0.name) (\($0.sets))" }.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundColor(.ink2)
                    .lineLimit(2)
            }
            // The reasons were carried all the way from FitbodCSVParser through
            // WorkoutCSVImporter into this view and then used only for
            // `.count`, under a message pointing at an Xcode console that
            // nothing ever writes to — a grep for print/os_log/Logger across
            // Imports/, HealthImports/ and Health/ returns zero hits. Show them.
            if !result.parseErrors.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(result.parseErrors.count) \(result.parseErrors.count == 1 ? "row" : "rows") skipped")
                        .font(.caption2)
                        .foregroundColor(.ink2)
                    ForEach(Array(result.parseErrors.prefix(3).enumerated()), id: \.offset) { _, err in
                        Text("Line \(err.line): \(err.reason)")
                            .font(.caption2)
                            .foregroundColor(.ink3)
                            .lineLimit(2)
                    }
                    if result.parseErrors.count > 3 {
                        Text("…and \(result.parseErrors.count - 3) more")
                            .font(.caption2)
                            .foregroundColor(.ink3)
                    }
                }
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
                onImportedWorkoutsChanged()
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
        onImportedWorkoutsChanged()
    }
}
