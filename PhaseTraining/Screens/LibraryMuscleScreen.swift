// LibraryMuscleScreen.swift — drill-down for one LibraryTile.
//
// Pushed from LibraryScreen's 7-tile landing grid. Pre-scopes the exercise
// list to the tile's muscle buckets so users never see the 551-row catalog
// firehose. Compound tiles (Arms, Hams + Glutes) surface a sub-bucket chip
// row so users can narrow to a single MuscleBucket (Triceps only, Glutes
// only, etc.); single-member tiles skip the chips.
//
// Search bar + "All filters" sheet (modality / difficulty / environment /
// compound-iso) preserved from the prior Library experience — they're now
// the secondary narrowing surface once a tile is selected.

import SwiftUI

struct LibraryMuscleScreen: View {
    let tile: LibraryTile

    @EnvironmentObject private var memoryStore: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var subBucket: MuscleBucket? = nil
    @State private var filters = ExerciseFilters()
    @State private var showingFilterSheet = false
    @State private var detailExercise: Exercise? = nil
    /// Cached catalog query results — refreshed on appear and whenever a
    /// query input (search / sub-bucket / filters) changes, instead of
    /// re-running listExercises on every render. Same caching pattern as
    /// LibraryScreen's stockRoutines/exerciseCount.
    @State private var rows: [Exercise] = []

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                searchBar
                if tile.members.count > 1 {
                    subBucketChips
                }
                allFiltersBar
                list
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $detailExercise) { ex in
            ExerciseDetailSheet(exercise: ex)
        }
        .sheet(isPresented: $showingFilterSheet) {
            ExerciseFilterSheet(filters: $filters)
        }
        .onAppear { reloadRows() }
        .onChange(of: query) { _, _ in reloadRows() }
        .onChange(of: subBucket) { _, _ in reloadRows() }
        .onChange(of: filters) { _, _ in reloadRows() }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.ink2)
                    .frame(width: 32, height: 32)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.line, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library-muscle-back")

            VStack(alignment: .leading, spacing: 2) {
                Text("LIBRARY · \(tile.label.uppercased())")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Text(tile.label)
                    .styled(.displayS)
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            Text("\(rows.count) EX")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.ink3)
            TextField("", text: $query,
                      prompt: Text("Search \(tile.label.lowercased())").foregroundColor(Color.ink3))
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
        .padding(.top, 8)
    }

    // MARK: - Sub-bucket chips (compound tiles only)

    private var subBucketChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: subBucket == nil) { subBucket = nil }
                ForEach(tile.members) { bucket in
                    chip(bucket.label, selected: subBucket == bucket) {
                        subBucket = (subBucket == bucket) ? nil : bucket
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: - All filters bar

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
        .padding(.top, 4)
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
        if rows.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.ink3)
                Text("Nothing matches")
                    .styled(.body)
                    .foregroundStyle(Color.ink2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(rows) { ex in
                        ExerciseTile(vm: .init(
                            leading: .thumb(exerciseID: ex.id, urlString: ex.thumbnailURL ?? ex.imageURL),
                            title: ex.name,
                            meta: ex.metaLabel(),
                            trailing: .chevron,
                            onTap: { detailExercise = ex }
                        ))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Data

    /// Active muscle slugs: the selected sub-bucket if one is picked, otherwise
    /// the full tile membership.
    private var activeMuscleSlugs: [String] {
        if let sub = subBucket { return sub.memberSlugs }
        return tile.memberSlugs
    }

    private func reloadRows() {
        rows = CoachDatabase.shared.listExercises(
            search: query.isEmpty ? nil : query,
            muscleSlugs: activeMuscleSlugs,
            patternSlugs: filters.category?.memberPatternSlugs ?? [],
            modality: filters.modality,
            difficulty: filters.difficulty,
            environment: filters.environment,
            compoundOnly: filters.compoundOnly,
            userSportSlugs: filters.hideOtherSports
                ? memoryStore.memory.sports.map(\.slug)
                : []
        )
    }
}
