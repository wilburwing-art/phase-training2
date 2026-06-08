// LibraryScreen.swift — browse the bundled coach.db catalog.
//
// Two segments:
//   - Exercises: 7-tile LazyVGrid landing (LibraryTile cases). Tap a tile to
//     push LibraryMuscleScreen, which owns search + secondary filters scoped
//     to that muscle group. Replaces the prior chip-strip + flat 551-row
//     list, which was a clutter firehose. Custom workouts stay flat
//     (Workouts segment) per intent — they're user-built, scrolled
//     deliberately, not browsed.
//   - Routines:  custom routines list + manual-build CTA (coach-driven
//                generation lives behind the bubble, not here).
//
// Reads CoachDatabase.listExercises / listRoutines / goalCounts. Pure read
// view — picking a row opens a detail sheet; no mutations.

import SwiftUI

struct LibraryScreen: View {
    enum Segment: String, CaseIterable, Hashable {
        case exercises, routines  // raw value kept as "routines" to avoid a UserDefaults / state migration; UI label is "Workouts".

        var label: String {
            switch self {
            case .exercises: return String(localized: "Exercises", comment: "Library tab")
            case .routines:  return String(localized: "Workouts", comment: "Library tab")
            }
        }
    }

    @EnvironmentObject private var customStore: CustomRoutineStore
    @EnvironmentObject private var memoryStore: MemoryStore

    @State private var segment: Segment = .exercises
    @State private var query: String = ""
    @State private var detailExercise: Exercise? = nil
    @State private var editingRoutine: CustomRoutine? = nil
    /// Bundled stock workouts from coach.db (`routines` table). Loaded once
    /// on appear and cached — `listRoutines()` is heavier than the audit
    /// expects when fired on every render. Tap a row → read-only preview.
    @State private var stockRoutines: [BundledRoutineRow] = []
    @State private var previewingStock: BundledRoutineRow? = nil
    /// Unfiltered catalog exercise count for the eyebrow trailing slot.
    /// Cached once on appear like `stockRoutines` — the count is a full
    /// 551-row catalog query and the bundled catalog never changes
    /// mid-session.
    @State private var exerciseCount: Int = 0

    /// Search field only appears once the user has accumulated enough custom
    /// routines to make filtering useful.
    private static let routineSearchThreshold = 5

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    TabHeader(
                        eyebrow: "LIBRARY",
                        eyebrowTrailing: libraryEyebrowTrailing,
                        title: "Library",
                        subtitle: "Browse every exercise and workout."
                    )
                    segmentControl
                    if segment == .routines && showSearchBar {
                        searchBar
                    }
                    if segment == .routines {
                        createCustomCTA
                    }
                    list
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LibraryTile.self) { tile in
                LibraryMuscleScreen(tile: tile)
            }
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
            }
            .sheet(item: $editingRoutine) { routine in
                CustomRoutineEditSheet(routine: routine)
            }
            .sheet(item: $previewingStock) { row in
                BundledRoutinePreviewSheet(row: row)
            }
            .onAppear {
                // Cache the stock routines list once per screen lifetime.
                // The DB query takes a recursive lock; running it on every
                // render of the Workouts segment is unnecessary churn.
                if stockRoutines.isEmpty {
                    stockRoutines = CoachDatabase.shared.listRoutines()
                }
                if exerciseCount == 0 {
                    exerciseCount = CoachDatabase.shared.listExercises(
                        search: nil,
                        muscleSlugs: [],
                        patternSlugs: [],
                        modality: nil,
                        difficulty: nil,
                        environment: nil,
                        compoundOnly: false,
                        userSportSlugs: []
                    ).count
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Counts for the eyebrow trailing slot — exercise total comes from the
    /// catalog (cached in `exerciseCount` on appear), workout count comes
    /// from CustomRoutineStore. Format: "<n> EX · <n> WORKOUTS" (UI glossary
    /// uses "Workouts" not "Routines").
    private var libraryEyebrowTrailing: String {
        let routineCount = customStore.routines.count + stockRoutines.count
        return "\(exerciseCount) EX · \(routineCount) WORKOUTS"
    }

    /// Search appears in Workouts once there's enough to filter — the bundled
    /// stock library (~148 rows) already clears the threshold on its own, so
    /// the bar shows from the first launch when stock is loaded.
    private var showSearchBar: Bool {
        (customStore.routines.count + stockRoutines.count) >= Self.routineSearchThreshold
    }

    // MARK: - Create custom CTA (Routines segment only)

    /// Manual-build entry point. Coach-driven generation lives behind the
    /// floating chat bubble (RootTabView overlay), so the Library CTA owns
    /// the "I'll pick exercises myself" flow exclusively. Tap → fresh empty
    /// CustomRoutine + open the edit sheet, where the user can name it and
    /// add exercises from the picker.
    private var createCustomCTA: some View {
        Button {
            editingRoutine = CustomRoutine.makeBlank()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentInk)
                    .frame(width: 24, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build a workout")
                        .styled(.displayS)
                        .foregroundStyle(Color.accentInk)
                    Text("Pick exercises yourself")
                        .styled(.body)
                        .foregroundStyle(Color.accentInk.opacity(0.7))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentInk.opacity(0.7))
            }
            .padding(14)
            .background(Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-create-custom")
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Segment control

    private var segmentControl: some View {
        HStack(spacing: 6) {
            ForEach(Segment.allCases, id: \.self) { seg in
                Button {
                    segment = seg
                    query = ""
                } label: {
                    Text(seg.label)
                        .styled(.micro)
                        .foregroundStyle(segment == seg ? Color.accentInk : Color.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(segment == seg ? Color.accent : Color.surface)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(segment == seg ? Color.clear : Color.line, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.ink3)
            TextField("", text: $query,
                      prompt: Text("Search \(segment.label.lowercased())").foregroundColor(Color.ink3))
                .styled(.body)
                .foregroundStyle(Color.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Tile grid (Exercises segment)

    /// 7-tile landing for the Exercises segment. Each tile is a
    /// `NavigationLink` carrying a `LibraryTile`; the destination
    /// (`LibraryMuscleScreen`) is registered on the enclosing
    /// `NavigationStack` via `.navigationDestination(for: LibraryTile.self)`.
    private var tileGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(LibraryTile.allCases) { tile in
                    NavigationLink(value: tile) {
                        tileFace(tile)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-tile-\(tile.rawValue)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }

    private func tileFace(_ tile: LibraryTile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: tile.symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.accent)
            Text(tile.label)
                .styled(.displayS)
                .foregroundStyle(Color.ink)
            HStack(spacing: 4) {
                Text("Browse")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        switch segment {
        case .exercises:
            tileGrid

        case .routines:
            let allCustoms = customStore.routines
            let filteredCustoms = query.isEmpty
                ? allCustoms
                : allCustoms.filter { $0.name.localizedCaseInsensitiveContains(query) }
            let filteredStock = query.isEmpty
                ? stockRoutines
                : stockRoutines.filter {
                    $0.name.localizedCaseInsensitiveContains(query)
                        || ($0.description ?? "").localizedCaseInsensitiveContains(query)
                }
            if allCustoms.isEmpty && stockRoutines.isEmpty {
                routinesEmptyState
            } else if filteredCustoms.isEmpty && filteredStock.isEmpty {
                searchEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if !filteredCustoms.isEmpty {
                            workoutsSectionHeader("YOUR WORKOUTS")
                            ForEach(filteredCustoms) { c in
                                ExerciseTile(vm: .init(
                                    leading: .icon(systemName: "figure.strengthtraining.traditional"),
                                    title: c.name.isEmpty ? "Untitled workout" : c.name,
                                    meta: customSubtitle(c),
                                    trailing: .chevron,
                                    onTap: { editingRoutine = c }
                                ))
                            }
                        }
                        if !filteredStock.isEmpty {
                            workoutsSectionHeader("BROWSE LIBRARY")
                                .padding(.top, filteredCustoms.isEmpty ? 0 : 12)
                            ForEach(filteredStock) { row in
                                ExerciseTile(vm: .init(
                                    leading: .icon(systemName: "books.vertical.fill"),
                                    title: row.name,
                                    meta: stockSubtitle(row),
                                    trailing: .chevron,
                                    onTap: { previewingStock = row }
                                ))
                                .accessibilityIdentifier("library-stock-routine-\(row.id)")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    /// Section label between the user's own workouts and the bundled stock
    /// library inside the Workouts segment.
    private func workoutsSectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Spacer()
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    /// Meta line for a stock routine row — duration / exercise count and any
    /// available difficulty + goal tags. Mirrors the shape of customSubtitle.
    private func stockSubtitle(_ row: BundledRoutineRow) -> String {
        var parts: [String] = []
        if let mins = row.durationMinutes { parts.append("\(mins) min") }
        parts.append("\(row.exerciseCount) ex")
        if let d = row.difficulty, !d.isEmpty { parts.append(d.capitalized) }
        if let g = row.goal, !g.isEmpty { parts.append(g.replacingOccurrences(of: "_", with: " ").capitalized) }
        return parts.joined(separator: " · ")
    }

    /// First-time / no-customs state for the Routines segment. CTA above the
    /// list already prompts to create one — this copy reinforces it.
    private var routinesEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 22))
                .foregroundStyle(Color.ink3)
            Text("Saved workouts show up here.")
                .styled(.body)
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
            Text("Tap Build a workout to assemble one.")
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Used by both segments when a search query returns no rows.
    private var searchEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(Color.ink3)
            Text("Nothing matches")
                .styled(.body)
                .foregroundStyle(Color.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func customSubtitle(_ c: CustomRoutine) -> String {
        let count = c.exercises.count
        return count == 1 ? "1 movement" : "\(count) movements"
    }

}

// MARK: - Stock routine read-only preview
//
// Opens when the user taps a row in the new "BROWSE LIBRARY" section of the
// Workouts segment. Read-only by intent — the 148 stock routines shipped in
// coach.db are reference material; the user's own copies live in
// CustomRoutineStore. Loads the routine's exercises on appear (one indexed
// query via CoachDatabase). Forking to a custom is a deliberate follow-up.
private struct BundledRoutinePreviewSheet: View {
    let row: BundledRoutineRow
    @State private var exercises: [RoutineExercise] = []
    @Environment(\.dismiss) private var dismiss

    private var headerMeta: String {
        var parts: [String] = []
        if let mins = row.durationMinutes { parts.append("\(mins) min") }
        parts.append("\(row.exerciseCount) ex")
        if let d = row.difficulty, !d.isEmpty { parts.append(d.capitalized) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.name)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Color.ink)
                            Text(headerMeta)
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                            if let desc = row.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 4)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("EXERCISES")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                            if exercises.isEmpty {
                                Text("Loading…")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.ink3)
                            } else {
                                ForEach(exercises) { ex in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text("\(ex.position + 1)")
                                            .font(.monoXS)
                                            .foregroundStyle(Color.ink3)
                                            .frame(width: 18, alignment: .trailing)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ex.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(Color.ink)
                                            if let line = setRepLine(ex) {
                                                Text(line)
                                                    .font(.monoXS)
                                                    .foregroundStyle(Color.ink3)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.line, lineWidth: 0.5)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
            .onAppear {
                if exercises.isEmpty {
                    exercises = CoachDatabase.shared.exercises(forRoutineId: row.id)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func setRepLine(_ ex: RoutineExercise) -> String? {
        var parts: [String] = []
        if let s = ex.sets { parts.append("\(s) sets") }
        if let r = ex.reps, !r.isEmpty { parts.append(r) }
        if let rest = ex.rest, !rest.isEmpty { parts.append("rest \(rest)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
