// ExercisePickerSheet.swift — searchable picker over coach.db exercises.
//
// Build 76 reorganization: primary filter is a horizontal-scrolling chip
// strip of muscle buckets (Chest / Back / Shoulders / ...) which matches
// how lifters mentally locate exercises. Modality, difficulty, environment,
// compound/iso, and movement category (Push/Pull/Legs/Core/Conditioning)
// are demoted to an "All filters" button that opens ExerciseFilterSheet.
//
// Used by:
//  - DayWorkoutPreviewSheet (swap an exercise → opens with the source
//    exercise's primary muscle bucket pre-selected via initialBucket)
//  - CustomRoutineEditSheet (add an exercise to a custom routine)
//  - LibraryScreen Exercises segment (when wired)

import SwiftUI

struct ExercisePickerSheet: View {
    let title: String
    /// Pre-select a muscle bucket when the sheet opens. Used by the
    /// swap-from-preview flow to narrow the picker to the same body area as
    /// the source exercise — saves the user from re-finding "ok I'm swapping
    /// a chest move, so show me chest."
    var initialBucket: MuscleBucket? = nil
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var filters = ExerciseFilters()
    @State private var detailExercise: Exercise? = nil
    @State private var showingFilterSheet = false

    private var results: [Exercise] {
        CoachDatabase.shared.listExercises(
            search: query.isEmpty ? nil : query,
            muscleSlugs: filters.bucket?.memberSlugs ?? [],
            patternSlugs: filters.category?.memberPatternSlugs ?? [],
            modality: filters.modality,
            difficulty: filters.difficulty,
            environment: filters.environment,
            compoundOnly: filters.compoundOnly
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    muscleBucketChips
                    filterBar
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if results.isEmpty {
                                Text("No exercises match these filters.")
                                    .font(.monoXS)
                                    .foregroundStyle(Color.ink3)
                                    .padding(.top, 40)
                            } else {
                                ForEach(results) { ex in row(ex) }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
            }
            .sheet(isPresented: $showingFilterSheet) {
                ExerciseFilterSheet(filters: $filters)
            }
        }
        .presentationBackground(Color.bg)
        .onAppear { filters.bucket = initialBucket }
    }

    // MARK: - Pieces

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.ink3)
            TextField("", text: $query,
                      prompt: Text("Search exercises").foregroundColor(Color.ink3))
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

    private var muscleBucketChips: some View {
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
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Button {
                showingFilterSheet = true
            } label: {
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

            Text("\(results.count) \(results.count == 1 ? "exercise" : "exercises")")
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
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

    private func row(_ ex: Exercise) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                onPick(ex)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ex.name)
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    Text(metaLine(ex))
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    detailExercise = ex
                } label: {
                    Label("Show details", systemImage: "info.circle")
                }
            }

            Button {
                detailExercise = ex
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 36, height: 36)
                    .background(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show details for \(ex.name)")
        }
    }

    private func metaLine(_ ex: Exercise) -> String {
        var parts: [String] = []
        if ex.modalityLabel != "—" { parts.append(ex.modalityLabel) }
        if ex.difficultyLabel != "—" { parts.append(ex.difficultyLabel) }
        return parts.joined(separator: " · ")
    }
}
