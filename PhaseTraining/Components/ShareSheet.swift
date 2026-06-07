// ShareSheet.swift — UIActivityViewController bridge.
//
// Lifted out of ProfileScreen.swift (architecture item 11) so other screens
// can present the system share sheet without importing the Profile file.

import SwiftUI

/// Thin UIActivityViewController wrapper so the Profile screen can present
/// the system share sheet for the export file URL. SwiftUI has ShareLink
/// but the file-URL ergonomics + iPad popover behavior are still cleaner
/// via the UIKit bridge.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
