// UnmatchedNamesSheet.swift — match imported names the catalog didn't know.
//
// Sets under an unmatched name keep a nil exercise id, so they never reach
// suggestions, Your strength or PRs by catalog name. Picking an exercise here
// stores the match (import_name_map) and fills those rows; the next re-import
// resolves the same way.

import SwiftUI

struct UnmatchedNamesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var names: [(name: String, sets: Int)] = []
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
                             ? "Every imported name matches an exercise."
                             : "These names from your import didn't match an exercise, so their sets don't count toward suggestions yet. Tap one to pick the exercise it is.")
                            .styled(.body)
                            .foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        LazyVStack(spacing: 0) {
                            ForEach(names, id: \.name) { item in
                                Button { matching = MatchTarget(name: item.name) } label: {
                                    HStack(spacing: 10) {
                                        Text(item.name)
                                            .font(.scaled("Inter-Regular", size: 14))
                                            .foregroundStyle(Color.ink)
                                            .lineLimit(2)
                                        Spacer(minLength: 6)
                                        Text(item.sets == 1 ? "1 set" : "\(item.sets) sets")
                                            .font(.monoXS)
                                            .foregroundStyle(Color.ink3)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color.ink3)
                                    }
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("unmatched-name-\(item.name)")
                                Rectangle().fill(Color.lineSoft).frame(height: 0.5)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Unmatched names")
            .navigationBarTitleDisplayMode(.inline)
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
        .sheet(item: $matching) { target in
            ExercisePickerSheet(title: "Match \u{201C}\(target.name)\u{201D}", conversion: .matchImport) { exercise in
                UserDatabase.shared.setImportName(target.name, exerciseId: exercise.id)
                reload()
            }
        }
    }

    private func reload() {
        names = UserDatabase.shared.unmatchedImportNames()
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
