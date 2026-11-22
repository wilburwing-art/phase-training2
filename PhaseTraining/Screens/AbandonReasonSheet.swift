// AbandonReasonSheet.swift — PR 9 of the weekly-coach roadmap.
//
// Capture sheet shown when the user taps "Stop early" on LogScreen.
// Picks one typed reason (AbandonReason) plus an optional note (always
// available, not just for "Other" — a pain report like "left knee" is
// exactly what the coach needs later). Confirm records the abandonment
// and ends the session; Cancel returns to the log with nothing lost.
//
// Spec: PLAN-weekly-coach.md §2.3.

import SwiftUI

struct AbandonReasonSheet: View {
    /// Done sets / total sets at the moment the sheet opened, for the
    /// one-line context under the title.
    let completionSummary: String
    /// Reason, trimmed note, and the joints picked for a Pain stop (empty
    /// for every other reason).
    let onConfirm: (AbandonReason, String?, [String]) -> Void
    let onCancel: () -> Void

    @State private var reason: AbandonReason?
    @State private var note: String = ""
    @State private var hurtAreas: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Stopped \(completionSummary). What got in the way?")
                    .styled(.body)
                    .foregroundStyle(Color.ink2)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 14)

                VStack(spacing: 8) {
                    ForEach(AbandonReason.allCases, id: \.self) { r in
                        Button {
                            reason = r
                        } label: {
                            HStack {
                                Text(r.label)
                                    .styled(.body)
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                if reason == r {
                                    Image(systemName: "checkmark")
                                        .scaledSystemFont(14, weight: .bold)
                                        .foregroundStyle(Color.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(reason == r ? Color.surface : Color.bg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(reason == r ? Color.accentBorder : Color.lineStrong, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("abandon-reason-\(r.rawValue)")
                    }
                }
                .padding(.horizontal, 20)

                if reason == .pain {
                    painAreas
                }

                TextField("Add a note (optional)", text: $note, axis: .vertical)
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.lineStrong, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                Spacer()
            }
            .navigationTitle("Stop early")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep going") {
                        dismiss()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard let reason else { return }
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        let areas = reason == .pain ? hurtAreas.sorted() : []
                        dismiss()
                        onConfirm(reason, trimmed.isEmpty ? nil : trimmed, areas)
                    }
                    .disabled(reason == nil)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// 11c 3.2 — where it hurts. Same joints as the post-workout sheet; each
    /// eases the muscles around it on the next session for 36 hours.
    private var painAreas: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHERE DOES IT HURT? (OPTIONAL)")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)],
                      alignment: .leading, spacing: 6) {
                ForEach(FeedbackEntry.hurtAreaOptions, id: \.self) { area in
                    let active = hurtAreas.contains(area)
                    Button {
                        if active { hurtAreas.remove(area) } else { hurtAreas.insert(area) }
                    } label: {
                        Text(area.capitalized)
                            .font(.scaled("JetBrainsMono-Medium", size: 11))
                            .foregroundStyle(active ? Color.accentInk : Color.ink2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(active ? Color.accent : Color.elevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(active ? Color.clear : Color.lineStrong, lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityIdentifier("abandon-hurt-\(area.replacingOccurrences(of: " ", with: "-"))")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}

#Preview {
    AbandonReasonSheet(
        completionSummary: "3 of 12 sets logged",
        onConfirm: { _, _, _ in },
        onCancel: {}
    )
}
