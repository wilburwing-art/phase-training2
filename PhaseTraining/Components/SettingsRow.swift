// SettingsRow.swift — Profile-tab "label + value + chevron" row.
//
// First step of the Option-C condense pass: each Profile section becomes a
// single summary row that opens a focused editor sheet on tap. Same shape
// as iOS Settings rows, themed with phase-training tokens.
//
// One row per section. Caller supplies the label + a concise value summary
// + an action. Disabled state is for sections with no editable value (rare).

import SwiftUI

struct SettingsRow: View {
    let label: String
    let value: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accent)
                        .frame(width: 22, alignment: .center)
                }
                Text(label)
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 8)
                Text(value)
                    .styled(.body)
                    .foregroundStyle(Color.ink3)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
