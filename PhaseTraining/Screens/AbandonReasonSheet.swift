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
    let onConfirm: (AbandonReason, String?) -> Void
    let onCancel: () -> Void

    @State private var reason: AbandonReason?
    @State private var note: String = ""
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
                                        .font(.system(size: 14, weight: .bold))
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
                                    .stroke(reason == r ? Color.accentBorder : Color.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("abandon-reason-\(r.rawValue)")
                    }
                }
                .padding(.horizontal, 20)

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
                            .stroke(Color.line, lineWidth: 1)
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
                        dismiss()
                        onConfirm(reason, trimmed.isEmpty ? nil : trimmed)
                    }
                    .disabled(reason == nil)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    AbandonReasonSheet(
        completionSummary: "3 of 12 sets logged",
        onConfirm: { _, _ in },
        onCancel: {}
    )
}
