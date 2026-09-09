// SetupChecklistSheet.swift — the permanent "what's still a guess" list.
//
// This is what replaced the questionnaire. Onboarding used to walk every
// plan-shaping field once, in a modal the user never saw again; now the gate
// asks sport + season and this list carries the rest, forever. A user on day
// one and a user in month three hit the same surface, and every row opens the
// same Profile editor the Week-tab assumption chips do.
//
// Deliberately NOT a first-run-only nag: it stays reachable from Profile after
// everything is stated, showing an all-set state, because "what is this plan
// actually built on" is a fair question at any point, not just at install.

import SwiftUI

struct SetupChecklistSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var editing: ProfileField?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        VStack(spacing: 8) {
                            ForEach(ProfileField.allCases) { field in
                                row(field)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Plan setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .sheet(item: $editing) { field in
            ProfileFieldEditorHost(field: field)
                .environmentObject(store)
        }
    }

    private var intro: some View {
        let remaining = store.memory.assumedFields.count
        return Text(remaining == 0
                    ? "Every input below is one you set. Nothing here is a guess."
                    : "Your week is built on these. \(remaining) of them we guessed — set them and the plan gets closer.")
            .styled(.body)
            .foregroundStyle(Color.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ field: ProfileField) -> some View {
        let stated = store.memory.isStated(field)
        return Button {
            editing = field
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: stated ? "checkmark.circle.fill" : field.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(stated ? Color.ok : Color.ink3)
                    .frame(width: 24)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(field.label)
                            .styled(.displayS)
                            .foregroundStyle(Color.ink)
                        if !stated {
                            Text("ASSUMED")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.elevated)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(store.memory.assumptionSummary(for: field))
                        .font(.monoXS)
                        .foregroundStyle(Color.ink2)
                    Text(field.whyItMatters)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink3)
                    .padding(.top, 4)
            }
            .padding(14)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("setup-checklist-row-\(field.rawValue)")
    }
}
