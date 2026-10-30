// PastWorkoutsSheet.swift — the "Past workouts" row of Finish setup.
//
// The same CSV import Health & Imports hosts, opened from the setup checklist
// so a new user meets it without hunting through Profile. "Starting fresh"
// answers the row for someone with nothing to bring.

import SwiftUI

struct PastWorkoutsSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Bring your history from another app and weight suggestions start from what you've already lifted.")
                            .styled(.body)
                            .foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        CSVImportSection(onImportedWorkoutsChanged: {})
                        if !store.memory.isStated(.history) {
                            Button {
                                store.update { $0.markStated(.history) }
                                dismiss()
                            } label: {
                                Text("Starting fresh")
                                    .styled(.monoS)
                                    .foregroundStyle(Color.ink2)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("past-workouts-starting-fresh")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Past workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }
}
