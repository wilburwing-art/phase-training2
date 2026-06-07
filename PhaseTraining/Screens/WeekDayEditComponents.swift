// WeekDayEditComponents.swift — picker + row components for WeekDayEditSheet.
//
// LiftFocusPickerSheet, FocusChip, and ActionRow. LiftFocusPickerSheet and
// ActionRow are internal because WeekDayEditSheet references them cross-file;
// FocusChip is only used by LiftFocusPickerSheet so it stays private.

import SwiftUI

// MARK: - LiftFocusPickerSheet
//
// PR 6 — small sheet with a 2×3 chip grid of LiftFocus options. Tap a
// chip → onPick fires and the sheet dismisses. Current selection (if
// any) is highlighted.

struct LiftFocusPickerSheet: View {
    let current: LiftFocus?
    let onPick: (LiftFocus) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text("PICK A FOCUS")
                        .styled(.micro)
                        .foregroundStyle(Color.accent)
                    Text("What kind of lift day?")
                        .font(.custom("SpaceGrotesk-SemiBold", size: 24))
                        .tracking(-0.025 * 24)
                        .foregroundStyle(Color.ink)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 10) {
                        ForEach(LiftFocus.allCases, id: \.self) { focus in
                            FocusChip(
                                label: focus.label,
                                isSelected: focus == current,
                                action: { onPick(focus) }
                            )
                            .accessibilityIdentifier("focus-chip-\(focus.rawValue)")
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ink2)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.bg)
    }
}

private struct FocusChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .styled(.body)
                .foregroundStyle(isSelected ? Color.accentInk : Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSelected ? Color.accent : Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.clear : Color.line, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ActionRow

struct ActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(destructive ? Color.danger : Color.accent)
                    .frame(width: 24, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .styled(.displayS)
                        .foregroundStyle(destructive ? Color.danger : Color.ink)
                    Text(subtitle)
                        .styled(.body)
                        .foregroundStyle(Color.ink3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink3)
            }
            .padding(14)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
