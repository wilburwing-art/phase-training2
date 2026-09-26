// WorkoutCategoryScreen.swift — drill-down for one Workouts-segment tile.
//
// Two near-identical entry points, one screen:
//   - .sport(WorkoutSportTile): routines linked to a sport via
//     routine_sports/sport_categories (the curated link set, not free-text
//     tags) — "tap Snowboarding → its programs".
//   - .goal(WorkoutGoalTile): routines whose goal matches the tile, with
//     `.other` surfacing the null/unclaimed-goal catch-all.
//
// Shape mirrors LibraryMuscleScreen (search + back header + count badge)
// minus the sub-bucket chips and filter sheet — goal tiles are
// single-member and sport narrowing is the sport itself.

import SwiftUI

struct WorkoutCategoryScreen: View {
    enum Scope: Hashable {
        case sport(WorkoutSportTile)
        case goal(WorkoutGoalTile)
    }

    let scope: Scope

    @EnvironmentObject private var memoryStore: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var previewingStock: BundledRoutineRow? = nil
    /// A3 explore log for this visit. Previews here are read-only, so this
    /// surface records looks, never conversions.
    @State private var recorder = ExploreRecorder(surface: .workoutCategory)
    /// Cached query results — refreshed on appear and on query change,
    /// same pattern as LibraryMuscleScreen.rows.
    @State private var rows: [BundledRoutineRow] = []

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                searchBar
                list
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $previewingStock) { row in
            BundledRoutinePreviewSheet(row: row)
        }
        .onAppear { reloadRows() }
        .onChange(of: query) { _, _ in reloadRows() }
        .onDisappear { recorder.flush() }
        .preferredColorScheme(.dark)
    }

    private var tileName: String {
        switch scope {
        case .sport(let t): return t.name
        case .goal(let t):  return t.label
        }
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
            .accessibilityIdentifier("workout-category-back")

            VStack(alignment: .leading, spacing: 2) {
                Text("LIBRARY · \(tileName.uppercased())")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Text(tileName)
                    .styled(.displayS)
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            Text("\(rows.count) WK")
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
                      prompt: Text("Search \(tileName.lowercased())").foregroundColor(Color.ink3))
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
                    ForEach(rows) { row in
                        ExerciseTile(vm: .init(
                            leading: .icon(systemName: "books.vertical.fill"),
                            title: row.name,
                            meta: metaLine(row),
                            trailing: .chevron,
                            onTap: {
                                recorder.opened(.routine, id: String(row.id), name: row.name)
                                previewingStock = row
                            }
                        ))
                        .accessibilityIdentifier("workout-category-routine-\(row.id)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
    }

    /// Duration / exercise count + difficulty + goal tags. Same shape as
    /// LibraryScreen.stockSubtitle.
    private func metaLine(_ row: BundledRoutineRow) -> String {
        var parts: [String] = []
        if let mins = row.durationMinutes { parts.append("\(mins) min") }
        parts.append("\(row.exerciseCount) ex")
        if let d = row.difficulty, !d.isEmpty { parts.append(d.capitalized) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Data

    private func reloadRows() {
        let search = query.isEmpty ? nil : query
        switch scope {
        case .sport(let tile):
            rows = CoachDatabase.shared.listRoutines(search: search, sportSlug: tile.slug)
        case .goal(let tile):
            // `.other` claims null + unclaimed goals; pass [] for that.
            rows = CoachDatabase.shared.listRoutines(search: search, goals: tile.memberGoals)
        }
        recorder.query(query, results: rows.count)
    }
}
