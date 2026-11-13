// UnmatchedNamesSheet.swift — match imported names the catalog didn't know.
//
// Sets under an unmatched name keep a nil exercise id, so they never reach
// suggestions, Your strength or PRs by catalog name. Picking an exercise here
// stores the match (import_name_map) and fills those rows; the next re-import
// resolves the same way. "Not a lift" (import_name_ignored) takes a name off
// the list without matching it; its rows keep a nil id.

import SwiftUI

struct UnmatchedNamesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var names: [(name: String, sets: Int)] = []
    @State private var ignored: [(name: String, sets: Int)] = []
    /// Catalog search hits per name, filled off the main thread: 60-odd
    /// searches block the sheet if run inline.
    @State private var suggestions: [String: [Exercise]] = [:]
    @State private var showTail = false
    @State private var matching: MatchTarget?

    private struct MatchTarget: Identifiable {
        let name: String
        var id: String { name }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(names.isEmpty
                             ? (ignored.isEmpty ? "Every imported name matches an exercise." : "Nothing left to match.")
                             : "These names from your import didn't match an exercise, so their sets don't count toward suggestions yet. Tap a guess, pick another, or mark it as not a lift.")
                            .styled(.body)
                            .foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        let split = Self.split(names)
                        LazyVStack(spacing: 0) {
                            ForEach(showTail ? names : split.main, id: \.name) { item in
                                nameRow(item)
                                Rectangle().fill(Color.lineSoft).frame(height: 0.5)
                            }
                        }
                        if !showTail, !split.tail.isEmpty { tailRow(split.tail) }
                        if !ignored.isEmpty { ignoredSection }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Unmatched names")
            .navigationBarTitleDisplayMode(.inline)
            // Opaque bar: rows no longer show through the title as they scroll.
            .toolbarBackground(Color.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
        .task { await loadSuggestions() }
        .sheet(item: $matching) { target in
            ExercisePickerSheet(title: "Match \u{201C}\(target.name)\u{201D}", conversion: .matchImport,
                                includesCustomExercises: false) { exercise in
                match(target.name, to: exercise)
            }
        }
    }

    private func nameRow(_ item: (name: String, sets: Int)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(item.name)
                    .font(.scaled("Inter-Regular", size: 14))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                Spacer(minLength: 6)
                Text(item.sets == 1 ? "1 set" : "\(item.sets) sets")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            // Wraps, so three long catalog names never push past the edge.
            FlowChips {
                ForEach(suggestions[item.name] ?? [], id: \.id) { ex in
                    chip(ex.name, systemImage: "checkmark", prominent: true) { match(item.name, to: ex) }
                        .accessibilityIdentifier("unmatched-suggest-\(item.name)-\(ex.id)")
                }
                chip("Other…", systemImage: "magnifyingglass") { matching = MatchTarget(name: item.name) }
                    .accessibilityIdentifier("unmatched-name-\(item.name)")
                chip("Not a lift", systemImage: "nosign") {
                    UserDatabase.shared.setImportNameIgnored(item.name, true)
                    reload()
                }
                .accessibilityIdentifier("unmatched-ignore-\(item.name)")
            }
        }
        .padding(.vertical, 12)
    }

    /// Names logged for fewer than this many sets are folded into one row.
    static let tailThreshold = 5

    /// The list as shown: names worth matching one by one, and the long tail.
    /// A 64-name import had 44 names under 5 sets, which buried the 20 that
    /// carry most of the history. A short tail (3 names or fewer) stays in the
    /// main list, since folding it would save nothing.
    static func split(_ names: [(name: String, sets: Int)])
        -> (main: [(name: String, sets: Int)], tail: [(name: String, sets: Int)]) {
        let tail = names.filter { $0.sets < tailThreshold }
        guard tail.count > 3 else { return (names, []) }
        return (names.filter { $0.sets >= tailThreshold }, tail)
    }

    private func tailRow(_ tail: [(name: String, sets: Int)]) -> some View {
        let sets = tail.reduce(0) { $0 + $1.sets }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(tail.count) more names with under \(Self.tailThreshold) sets each (\(sets) sets in all)")
                .font(.scaled("Inter-Regular", size: 14))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            FlowChips {
                chip("Show them", systemImage: "chevron.down") { showTail = true }
                    .accessibilityIdentifier("unmatched-tail-show")
                chip("Set all aside", systemImage: "tray.and.arrow.down") {
                    for item in tail { UserDatabase.shared.setImportNameIgnored(item.name, true) }
                    reload()
                }
                .accessibilityIdentifier("unmatched-tail-set-aside")
            }
        }
        .padding(.vertical, 12)
    }

    private var ignoredSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SET ASIDE")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .padding(.top, 10)
            ForEach(ignored, id: \.name) { item in
                HStack {
                    Text(item.name)
                        .font(.scaled("Inter-Regular", size: 14))
                        .foregroundStyle(Color.ink2)
                    Spacer()
                    Button("Undo") {
                        UserDatabase.shared.setImportNameIgnored(item.name, false)
                        reload()
                    }
                    .font(.caption)
                    .foregroundStyle(Color.accent)
                    .accessibilityIdentifier("unmatched-unignore-\(item.name)")
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func chip(_ label: String, systemImage: String, prominent: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(prominent ? Color.ink : Color.ink2)
                .background(prominent ? Color.surface : Color.clear)
                .overlay(Capsule().stroke(Color.lineSoft, lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func match(_ name: String, to exercise: Exercise) {
        UserDatabase.shared.setImportName(name, exerciseId: exercise.id)
        reload()
    }

    private func reload() {
        names = UserDatabase.shared.unmatchedImportNames()
        ignored = UserDatabase.shared.ignoredImportNames()
    }

    private func loadSuggestions() async {
        let pending = names.map(\.name).filter { suggestions[$0] == nil }
        let found = await Task.detached(priority: .userInitiated) {
            Dictionary(uniqueKeysWithValues: pending.map { ($0, Self.suggestions(for: $0)) })
        }.value
        suggestions.merge(found) { old, _ in old }
    }

    /// Up to three catalog guesses: the picker's own search on the raw name.
    /// Measured on a 2016-2025 Fitbod export, about half the unmatched names
    /// get the right exercise in the top three (Decline Push Up → Push-Up,
    /// Elliptical → Elliptical Machine); a wrong guess costs one "Other…" tap.
    nonisolated static func suggestions(for name: String, coach: CoachDatabase = .shared) -> [Exercise] {
        Array(coach.searchExercises(search: name).exercises.prefix(3))
    }
}

/// Lays chips left to right and wraps to a new line when the row is full.
private struct FlowChips: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for (i, x) in zip(row.indices, row.xs) {
                subviews[i].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row { var indices: [Int] = []; var xs: [CGFloat] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            let x = row.indices.isEmpty ? 0 : row.width + spacing
            row.indices.append(i); row.xs.append(x)
            row.width = x + size.width; row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// The one-line entry point under the import section. Hidden when every
/// imported name matched; re-reads on each import change.
struct UnmatchedNamesRow: View {
    @State private var count = 0
    @State private var showing = false

    var body: some View {
        // A VStack, so the reload hooks below still fire while the row is hidden.
        VStack(spacing: 0) {
            if count > 0 {
                Button { showing = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(count == 1 ? "1 name didn't match" : "\(count) names didn't match")
                                .font(.subheadline)
                                .foregroundColor(.ink)
                            Text("Match them so their sets count toward suggestions")
                                .font(.caption)
                                .foregroundColor(.ink2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.ink3)
                    }
                    .padding(12)
                    .background(Color.surface)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("unmatched-names-row")
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .importedSetsDidChange).receive(on: RunLoop.main)) { _ in reload() }
        .sheet(isPresented: $showing, onDismiss: reload) { UnmatchedNamesSheet() }
    }

    private func reload() {
        count = UserDatabase.shared.unmatchedImportNames().count
    }
}
