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

    @EnvironmentObject private var memoryStore: MemoryStore

    // Phase 3 CSV import state.
    @State private var presentingCSVPicker = false
    @State private var csvImporting = false
    @State private var csvError: String?
    @State private var csvSummary: (count: Int, oldest: Date?, newest: Date?, perSource: [String: Int])?
    @State private var lastImport: WorkoutCSVImporter.Result?
    /// Read live, so matching a name in the Unmatched sheet moves it.
    @State private var unmatched: (names: Int, sets: Int, ignoredSets: Int) = (0, 0, 0)
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
            // Nothing to check until something is imported.
            if (csvSummary?.count ?? 0) > 0 {
                HistoryCheckRow()
                UnmatchedNamesRow()
            }

            Button {
                csvError = nil
                presentingCSVPicker = true
            } label: {
                Text(csvImporting ? "Importing…" : "Import CSV")
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
            Text("Fitbod, Hevy and Strong exports. We only read the file; nothing is uploaded.")
                .font(.caption)
                .foregroundColor(.ink2)
        }
        .onAppear { refreshCSVSummary() }
        .onReceive(NotificationCenter.default.publisher(for: .importedSetsDidChange).receive(on: RunLoop.main)) { _ in
            refreshCSVSummary()
        }
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
            // Sets marked "Not a lift" were never lifts, so they leave the total.
            Text(Self.matchLine(totalSets: s.count - unmatched.ignoredSets, unmatchedSets: unmatched.sets,
                                unmatchedNames: unmatched.names))
                .font(.caption)
                .foregroundColor(.ink2)
                .accessibilityIdentifier("csv-match-line")
            ForEach(s.perSource.sorted(by: { $0.value > $1.value }), id: \.key) { entry in
                HStack {
                    Text(prettySource(entry.key)).font(.caption).foregroundColor(.ink)
                    Spacer()
                    // One source: its count is the headline above, so don't repeat it.
                    if s.perSource.count > 1 {
                        Text("\(entry.value)").font(.caption.monospaced()).foregroundColor(.ink2)
                    }
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
            Text("Last import: read \(result.setsInserted) sets")
                .font(.caption)
                .foregroundColor(.ink)
            if result.workoutsInserted > 0 {
                Text("\(result.workoutsInserted) cardio \(result.workoutsInserted == 1 ? "session" : "sessions") went to Workout history at the top of this screen")
                    .font(.caption2)
                    .foregroundColor(.ink2)
            }
            if let note = result.unitNote {
                Text(note)
                    .font(.caption2)
                    .foregroundColor(.ink2)
                    .accessibilityIdentifier("csv-unit-note")
            }
            if result.warmupsSkipped > 0 {
                Text("Skipped \(result.warmupsSkipped) warmup \(result.warmupsSkipped == 1 ? "row" : "rows")")
                    .font(.caption2)
                    .foregroundColor(.ink2)
            }
            ForEach(Array(result.unitCorrections.enumerated()), id: \.offset) { _, fix in
                Text("Some workouts \(Self.dateFormatter.string(from: fix.from)) → \(Self.dateFormatter.string(from: fix.through)) looked like pounds entered in kg mode: converted \(fix.correctedSets) sets")
                    .font(.caption2)
                    .foregroundColor(.ink2)
                    .accessibilityIdentifier("csv-unit-correction")
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
            // Grouped by reason: 57 lines of "Plank: no reps logged" read as
            // one fact, and a line number is nothing the user can act on.
            if !result.parseErrors.isEmpty {
                let reasons = Self.groupedReasons(result.parseErrors.map(\.reason))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(result.parseErrors.count) \(result.parseErrors.count == 1 ? "row" : "rows") skipped")
                        .font(.caption2)
                        .foregroundColor(.ink2)
                    ForEach(reasons.prefix(3), id: \.reason) { r in
                        Text(r.count == 1 ? r.reason : "\(r.reason) (\(r.count) rows)")
                            .font(.caption2)
                            .foregroundColor(.ink3)
                            .lineLimit(2)
                    }
                    if reasons.count > 3 {
                        Text("…and \(reasons.count - 3) more")
                            .font(.caption2)
                            .foregroundColor(.ink3)
                    }
                }
                .accessibilityIdentifier("csv-skipped-rows")
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
        case "strongCSV": return "Strong CSV"
        default: return raw
        }
    }

    /// Sets, not names: one unmatched name can carry 50 sets and another 1,
    /// so the set share is what tells you how much of your history counts.
    static func matchLine(totalSets: Int, unmatchedSets: Int, unmatchedNames: Int) -> String {
        guard totalSets > 0 else { return "" }
        let matched = max(0, totalSets - unmatchedSets)
        // Floor, so a few stragglers never round up to 100%.
        let pct = Int((Double(matched) / Double(totalSets) * 100).rounded(.down))
        let left = unmatchedNames == 0 ? "every name matched"
            : unmatchedNames == 1 ? "1 name left to match" : "\(unmatchedNames) names left to match"
        return "\(pct)% of sets count toward suggestions · \(left)"
    }

    /// Distinct skip reasons, most frequent first.
    static func groupedReasons(_ reasons: [String]) -> [(reason: String, count: Int)] {
        Dictionary(grouping: reasons, by: { $0 })
            .map { (reason: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.reason < $1.reason }
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
                let result = try await WorkoutCSVImporter.import(url: url, fallbackImperial: memoryStore.memory.usesImperial)
                lastImport = result
                refreshCSVSummary()
                // Retires the "Past workouts" row in Finish setup.
                if result.setsInserted > 0 { memoryStore.update { $0.markStated(.history) } }
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
        let names = UserDatabase.shared.unmatchedImportNames()
        let ignored = UserDatabase.shared.ignoredImportNames()
        unmatched = (names.count, names.reduce(0) { $0 + $1.sets }, ignored.reduce(0) { $0 + $1.sets })
    }

    private func deleteSource(rawValue: String) {
        guard let src = ImportSource(rawValue: rawValue) else { return }
        UserDatabase.shared.deleteImports(source: src)
        refreshCSVSummary()
        onImportedWorkoutsChanged()
    }
}
