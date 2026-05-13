// ExercisePickerScreen.swift — Browse 711 exercises from coach.db.
// Reference: design handoff exercise-picker.jsx (variation A).
// Two modes:
//   .add               — multi-select, returns selected ids on confirm
//   .replace(rowIndex) — single-select, commits on tap
// Tap the info chevron on a row to push ExerciseDetail without selecting.

import SwiftUI

enum ExercisePickerMode: Equatable {
    case add
    case replace(rowIndex: Int)

    var title: String {
        switch self {
        case .add:     return "Add exercise"
        case .replace: return "Replace exercise"
        }
    }

    var isReplace: Bool { if case .replace = self { return true } else { return false } }
}

struct ExercisePickerScreen: View {
    let mode: ExercisePickerMode
    let onCancel: () -> Void
    let onConfirm: ([Exercise]) -> Void
    let onPreview: (Exercise) -> Void

    @State private var search: String = ""
    @State private var modalityFilter: String? = nil
    @State private var selected: Set<Int> = []

    private var results: [Exercise] {
        CoachDatabase.shared.listExercises(
            search: search.isEmpty ? nil : search,
            modality: modalityFilter
        )
    }

    private var grouped: [(String, [Exercise])] {
        Dictionary(grouping: results, by: { String($0.name.first ?? "·").uppercased() })
            .sorted { $0.key < $1.key }
    }

    private var topModalities: [(String, Int)] {
        Array(CoachDatabase.shared.modalityCounts().prefix(6))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        searchField
                            .padding(.horizontal, 20)
                            .padding(.top, 14)

                        chipScroller
                            .padding(.top, 12)

                        if results.isEmpty {
                            empty
                                .padding(.top, 60)
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(grouped, id: \.0) { letter, exercises in
                                sectionHeader(letter, count: exercises.count)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 18)
                                    .padding(.bottom, 6)
                                ForEach(exercises) { ex in
                                    row(ex)
                                        .padding(.horizontal, 20)
                                }
                            }
                        }

                        Spacer().frame(height: 140)
                    }
                }
            }

            confirmBar
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .foregroundStyle(Color.ink)
        .preferredColorScheme(.dark)
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.custom("SpaceGrotesk-Medium", size: 15))
                        .foregroundStyle(Color.ink)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(mode.title)
                    .font(.custom("SpaceGrotesk-SemiBold", size: 17))
                    .foregroundStyle(Color.ink)
                Spacer()
                Text("\(results.count)")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Rectangle().fill(Color.line).frame(height: 0.5)
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.ink3)
            TextField("", text: $search,
                      prompt: Text("Search 711 exercises…").foregroundColor(Color.ink3))
                .font(.custom("Inter-Regular", size: 15))
                .foregroundStyle(Color.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Chips

    private var chipScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", count: 711, active: modalityFilter == nil) {
                    modalityFilter = nil
                }
                ForEach(topModalities, id: \.0) { m, n in
                    chip(m.replacingOccurrences(of: "_", with: " ").capitalized,
                         count: n,
                         active: modalityFilter == m) {
                        modalityFilter = (modalityFilter == m) ? nil : m
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chip(_ label: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.custom("Inter-Regular", size: 13))
                    .fontWeight(active ? .semibold : .regular)
                Text("\(count)")
                    .font(.custom("JetBrainsMono-Regular", size: 10))
                    .foregroundStyle(active ? Color.accentInk.opacity(0.55) : Color.ink3)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(active ? Color.accent : Color.surface)
            .foregroundStyle(active ? Color.accentInk : Color.ink)
            .overlay(Capsule().stroke(active ? Color.accent : Color.line, lineWidth: 0.5))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section header

    private func sectionHeader(_ letter: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(letter)
                .font(.custom("SpaceGrotesk-SemiBold", size: 22))
                .tracking(-0.02 * 22)
                .foregroundStyle(Color.ink)
            Text("\(count) \(count == 1 ? "exercise" : "exercises")")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Spacer()
        }
    }

    // MARK: - Row

    private func row(_ ex: Exercise) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { onPreview(ex) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(ex.name)
                        .font(.custom("SpaceGrotesk-SemiBold", size: 16))
                        .tracking(-0.01 * 16)
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(rowSubtitle(ex))
                        .font(.custom("JetBrainsMono-Regular", size: 10))
                        .tracking(0.04 * 10)
                        .foregroundStyle(Color.ink3)
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            toggleButton(for: ex)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.line).frame(height: 0.5)
        }
    }

    private func rowSubtitle(_ ex: Exercise) -> String {
        [ex.modalityLabel, ex.difficultyLabel, ex.environment?.capitalized]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func toggleButton(for ex: Exercise) -> some View {
        let isSelected = selected.contains(ex.id)
        return Button {
            switch mode {
            case .add:
                if isSelected { selected.remove(ex.id) } else { selected.insert(ex.id) }
            case .replace:
                onConfirm([ex])
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accent : Color.clear)
                    .frame(width: 28, height: 28)
                Circle()
                    .stroke(isSelected ? Color.accent : Color.ink3, lineWidth: 1.5)
                    .frame(width: 28, height: 28)
                Image(systemName: isSelected ? "checkmark" : "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isSelected ? Color.accentInk : Color.ink2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confirm bar

    @ViewBuilder
    private var confirmBar: some View {
        if case .add = mode, !selected.isEmpty {
            let picked = results.filter { selected.contains($0.id) }
            Button {
                onConfirm(picked)
            } label: {
                HStack(spacing: 6) {
                    Text("Add \(selected.count) exercise\(selected.count == 1 ? "" : "s")")
                        .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.accentInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty

    private var empty: some View {
        VStack(spacing: 8) {
            Text("No matches")
                .font(.custom("SpaceGrotesk-SemiBold", size: 18))
                .foregroundStyle(Color.ink)
            Text("Try a shorter search or clear the filter.")
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink2)
        }
    }
}
