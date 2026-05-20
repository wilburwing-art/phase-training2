// DataEditorSheet.swift — backup export / restore entry rows.
//
// Lifted out of ProfileScreen as part of the Option-C condense pass. The
// actual fileImporter / ShareSheet / alerts still live on ProfileScreen
// (the parent owns the iOS-level presentation surfaces — this sheet just
// fires callbacks that flip flags on the parent).

import SwiftUI

struct DataEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onExport: () -> Void
    var onImport: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("DATA")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        Button(action: {
                            onExport()
                            dismiss()
                        }) {
                            dataRow(icon: "square.and.arrow.up",
                                    title: "Export backup",
                                    subtitle: "Save a JSON file with your profile, plan, sessions, and custom workouts.")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile-export")

                        Button(action: {
                            onImport()
                            dismiss()
                        }) {
                            dataRow(icon: "square.and.arrow.down",
                                    title: "Restore from backup",
                                    subtitle: "Replace everything on this device with a backup file. Restart after to refresh.")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile-import")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Data")
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
    }

    private func dataRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                Text(subtitle)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ink3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
