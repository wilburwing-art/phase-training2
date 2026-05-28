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
            case .exercises: return "Exercises"
            case .routines:  return "Workouts"
            }
        }
    }

    @EnvironmentObject private var customStore: CustomRoutineStore
    @EnvironmentObject private var memoryStore: MemoryStore

    @State private var segment: Segment = .exercises
    @State private var query: String = ""
    @State private var detailExercise: Exercise? = nil
    @State private var editingRoutine: CustomRoutine? = nil

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
        }
        .preferredColorScheme(.dark)
    }

    /// Counts for the eyebrow trailing slot — exercise total comes from the
    /// catalog, workout count comes from CustomRoutineStore. Format:
    /// "<n> EX · <n> WORKOUTS" (UI glossary uses "Workouts" not "Routines").
    private var libraryEyebrowTrailing: String {
        let exCount = CoachDatabase.shared.listExercises(
            search: nil,
            muscleSlugs: [],
            patternSlugs: [],
            modality: nil,
            difficulty: nil,
            environment: nil,
            compoundOnly: false,
            userSportSlugs: []
        ).count
        let routineCount = customStore.routines.count
        return "\(exCount) EX · \(routineCount) WORKOUTS"
    }

    /// Search only matters on the Workouts segment once the user has enough
    /// custom routines to justify filtering. Exercises now lands on a 7-tile
    /// grid; search lives inside LibraryMuscleScreen scoped to one tile.
    private var showSearchBar: Bool {
        customStore.routines.count >= Self.routineSearchThreshold
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
            let filtered = query.isEmpty
                ? allCustoms
                : allCustoms.filter { $0.name.localizedCaseInsensitiveContains(query) }
            if allCustoms.isEmpty {
                routinesEmptyState
            } else if filtered.isEmpty {
                searchEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { c in
                            ExerciseTile(vm: .init(
                                leading: .icon(systemName: "figure.strengthtraining.traditional"),
                                title: c.name.isEmpty ? "Untitled workout" : c.name,
                                meta: customSubtitle(c),
                                trailing: .chevron,
                                onTap: { editingRoutine = c }
                            ))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }
        }
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

    private func metaLine(_ ex: Exercise) -> String {
        var parts: [String] = []
        if ex.modalityLabel != "—" { parts.append(ex.modalityLabel) }
        if ex.difficultyLabel != "—" { parts.append(ex.difficultyLabel) }
        if ex.isCompound { parts.append("Compound") }
        return parts.joined(separator: " · ")
    }

    private func customSubtitle(_ c: CustomRoutine) -> String {
        let count = c.exercises.count
        return count == 1 ? "1 movement" : "\(count) movements"
    }

}
