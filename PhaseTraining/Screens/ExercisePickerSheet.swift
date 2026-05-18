// ExercisePickerSheet.swift — searchable picker over coach.db exercises.
//
// Reusable pick UI backed by CoachDatabase.listExercises. Search by name
// (server-side LIKE), optional modality filter, info button per row that
// opens ExerciseDetailSheet so the user can vet before picking. The same
// component is used by the custom-routine edit sheet (add exercise) and
// will back the browse entry point in the upcoming library tab.

import SwiftUI

struct ExercisePickerSheet: View {
    let title: String
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var modality: String? = nil
    @State private var detailExercise: Exercise? = nil

    private var results: [Exercise] {
        CoachDatabase.shared.listExercises(
            search: query.isEmpty ? nil : query,
            modality: modality
        )
    }

    private var modalities: [(modality: String, count: Int)] {
        CoachDatabase.shared.modalityCounts()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    modalityChips
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(results) { ex in
                                row(ex)
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
        }
        .presentationBackground(Color.bg)
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

    private var modalityChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: modality == nil) { modality = nil }
                ForEach(modalities, id: \.modality) { mod, _ in
                    chip(label(for: mod), selected: modality == mod) {
                        modality = mod
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
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

    private func label(for modality: String) -> String {
        modality.replacingOccurrences(of: "_", with: " ").capitalized
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
