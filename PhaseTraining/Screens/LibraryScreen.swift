// LibraryScreen.swift — browse the bundled coach.db catalog.
//
// Restores the browse surface retired in Phase 11: a tab that lets the user
// explore the exercise + routine library directly instead of only seeing
// them through generated workouts. Two segments:
//   - Exercises: muscle-bucket chip strip (primary) + "All filters" sheet
//     for movement category / modality / difficulty / environment /
//     compound-vs-iso. Mirrors ExercisePickerSheet.
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
    @State private var filters = ExerciseFilters()
    @State private var showingFilterSheet = false
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
                    segmentControl
                    if showSearchBar {
                        searchBar
                    }
                    if segment == .routines {
                        createCustomCTA
                    }
                    if segment == .exercises {
                        filterChips
                    }
                    list
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
            }
            .sheet(item: $editingRoutine) { routine in
                CustomRoutineEditSheet(routine: routine)
            }
            .sheet(isPresented: $showingFilterSheet) {
                ExerciseFilterSheet(filters: $filters)
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Hide search until exercise browsing has hundreds of rows (always) or
    /// the user has built up enough custom routines for filtering to matter.
    private var showSearchBar: Bool {
        switch segment {
        case .exercises: return true
        case .routines:  return customStore.routines.count >= Self.routineSearchThreshold
        }
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
                    filters = ExerciseFilters()
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

    // MARK: - Filter chips (exercises segment only)

    @ViewBuilder
    private var filterChips: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", selected: filters.bucket == nil) { filters.bucket = nil }
                    ForEach(MuscleBucket.allCases) { bucket in
                        chip(bucket.label, selected: filters.bucket == bucket) {
                            filters.bucket = (filters.bucket == bucket) ? nil : bucket
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            allFiltersBar
        }
    }

    private var allFiltersBar: some View {
        HStack(spacing: 12) {
            Button { showingFilterSheet = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 12, weight: .medium))
                    Text(filters.secondaryCount > 0 ? "All filters (\(filters.secondaryCount))" : "All filters")
                        .styled(.micro)
                }
                .foregroundStyle(filters.secondaryCount > 0 ? Color.accentInk : Color.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(filters.secondaryCount > 0 ? Color.accent : Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(filters.secondaryCount > 0 ? Color.clear : Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .styled(.micro)
                .foregroundStyle(selected ? Color.accentInk : Color.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? Color.accent : Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.clear : Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        switch segment {
        case .exercises:
            let rows = CoachDatabase.shared.listExercises(
                search: query.isEmpty ? nil : query,
                muscleSlugs: filters.bucket?.memberSlugs ?? [],
                patternSlugs: filters.category?.memberPatternSlugs ?? [],
                modality: filters.modality,
                difficulty: filters.difficulty,
                environment: filters.environment,
                compoundOnly: filters.compoundOnly,
                userSportSlugs: filters.hideOtherSports
                    ? memoryStore.memory.sports.map(\.slug)
                    : []
            )
            if rows.isEmpty {
                searchEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(rows) { ex in
                            exerciseRow(ex)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }

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
                            customRow(c)
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

    private func exerciseRow(_ ex: Exercise) -> some View {
        Button {
            detailExercise = ex
        } label: {
            HStack(spacing: 12) {
                ExerciseThumbnail(urlString: ex.thumbnailURL ?? ex.imageURL, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ex.name)
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    Text(metaLine(ex))
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink3)
            }
            .padding(14)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func metaLine(_ ex: Exercise) -> String {
        var parts: [String] = []
        if ex.modalityLabel != "—" { parts.append(ex.modalityLabel) }
        if ex.difficultyLabel != "—" { parts.append(ex.difficultyLabel) }
        if ex.isCompound { parts.append("Compound") }
        return parts.joined(separator: " · ")
    }

    /// One of the user's saved CustomRoutines. Tap → CustomRoutineEditSheet.
    /// Mirrors the row style used in OverrideTodaySheet.
    private func customRow(_ c: CustomRoutine) -> some View {
        Button {
            editingRoutine = c
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .frame(width: 24, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name.isEmpty ? "Untitled workout" : c.name)
                        .styled(.displayS)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(customSubtitle(c))
                        .styled(.body)
                        .foregroundStyle(Color.ink3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink3)
            }
            .padding(14)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func customSubtitle(_ c: CustomRoutine) -> String {
        let count = c.exercises.count
        return count == 1 ? "1 movement" : "\(count) movements"
    }

}
