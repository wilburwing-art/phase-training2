// LibraryScreen.swift — browse the bundled coach.db catalog.
//
// Restores the browse surface retired in Phase 11: a tab that lets the user
// explore the exercise + routine library directly instead of only seeing
// them through generated workouts. Two segments:
//   - Exercises: name-LIKE search + modality chip filter, opens detail
//   - Routines:  goal chip filter + name search, opens a routine detail
//
// Reads CoachDatabase.listExercises / listRoutines / modalityCounts /
// goalCounts. Pure read view — picking a row opens a detail sheet; no
// mutations.

import SwiftUI

struct LibraryScreen: View {
    enum Segment: String, CaseIterable, Hashable {
        case exercises, routines

        var label: String {
            switch self {
            case .exercises: return "Exercises"
            case .routines:  return "Routines"
            }
        }
    }

    @State private var segment: Segment = .exercises
    @State private var query: String = ""
    @State private var modality: String? = nil
    @State private var goal: String? = nil
    @State private var detailExercise: Exercise? = nil
    @State private var detailRoutine: Routine? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    segmentControl
                    searchBar
                    filterChips
                    list
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
            }
            .sheet(item: $detailRoutine) { routine in
                RoutineDetailSheet(routine: routine)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Segment control

    private var segmentControl: some View {
        HStack(spacing: 6) {
            ForEach(Segment.allCases, id: \.self) { seg in
                Button {
                    segment = seg
                    query = ""
                    modality = nil
                    goal = nil
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

    // MARK: - Filter chips

    @ViewBuilder
    private var filterChips: some View {
        switch segment {
        case .exercises:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", selected: modality == nil) { modality = nil }
                    ForEach(CoachDatabase.shared.modalityCounts(), id: \.modality) { mod, count in
                        chip("\(formatTag(mod)) · \(count)", selected: modality == mod) {
                            modality = mod
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        case .routines:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", selected: goal == nil) { goal = nil }
                    ForEach(CoachDatabase.shared.goalCounts(), id: \.goal) { g, count in
                        chip("\(formatTag(g)) · \(count)", selected: goal == g) {
                            goal = g
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
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

    private func formatTag(_ s: String) -> String {
        s.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        switch segment {
        case .exercises:
            let rows = CoachDatabase.shared.listExercises(
                search: query.isEmpty ? nil : query,
                modality: modality
            )
            if rows.isEmpty {
                emptyState
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
            let rows = CoachDatabase.shared.listRoutines(
                search: query.isEmpty ? nil : query,
                goal: goal
            )
            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(rows) { r in
                            routineRow(r)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var emptyState: some View {
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

    private func routineRow(_ r: Routine) -> some View {
        Button {
            detailRoutine = r
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.name)
                        .styled(.displayS)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    Text(routineMeta(r))
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

    private func routineMeta(_ r: Routine) -> String {
        var parts: [String] = []
        if let g = r.goal, !g.isEmpty { parts.append(formatTag(g)) }
        parts.append("\(r.exerciseCount) movements")
        if let d = r.durationMinutes { parts.append("~\(d) min") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - RoutineDetailSheet

struct RoutineDetailSheet: View {
    let routine: Routine
    @Environment(\.dismiss) private var dismiss
    @State private var detailExercise: Exercise? = nil

    private var exercises: [RoutineExercise] {
        CoachDatabase.shared.exercises(forRoutineId: routine.id)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if let desc = routine.description, !desc.isEmpty {
                            Text(desc)
                                .styled(.body)
                                .foregroundStyle(Color.ink2)
                        }
                        Text("EXERCISES (\(exercises.count))")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                            .padding(.top, 4)
                        VStack(spacing: 8) {
                            ForEach(exercises) { rex in
                                row(rex)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
            }
        }
        .presentationBackground(Color.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(routine.name)
                .styled(.displayM)
                .foregroundStyle(Color.ink)
            Text(metaLine)
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let g = routine.goal {
            parts.append(g.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        if let d = routine.difficulty {
            parts.append(d.capitalized)
        }
        if let mins = routine.durationMinutes {
            parts.append("~\(mins) min")
        }
        return parts.joined(separator: " · ")
    }

    private func row(_ rex: RoutineExercise) -> some View {
        Button {
            detailExercise = CoachDatabase.shared.exercise(id: rex.exerciseId)
        } label: {
            HStack(spacing: 12) {
                Text("\(rex.position)")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .frame(width: 18, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rex.name)
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                    if let line = setsLine(rex), !line.isEmpty {
                        Text(line)
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
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

    private func setsLine(_ rex: RoutineExercise) -> String? {
        var parts: [String] = []
        if let s = rex.sets, let r = rex.reps {
            parts.append("\(s) × \(r)")
        } else if let s = rex.sets {
            parts.append("\(s) sets")
        } else if let r = rex.reps {
            parts.append(r)
        }
        if let rest = rex.rest, !rest.isEmpty {
            parts.append("rest \(rest)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
