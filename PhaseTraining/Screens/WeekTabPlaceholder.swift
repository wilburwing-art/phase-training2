import SwiftUI

struct WeekTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(
            eyebrow: "WEEK",
            title: "Your training week.",
            subtitle: "Coming in Phase 10 — rules-based plan over 7 days."
        )
    }
}

#Preview { WeekTabPlaceholder() }
