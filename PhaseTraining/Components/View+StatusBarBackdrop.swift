// View+StatusBarBackdrop.swift — keeps scrolled content out from under the clock.
//
// The tab screens have no navigation bar, so a ScrollView's content draws
// into the status-bar strip once scrolled and the time sits on top of card
// text (Progress and Profile, gap analysis 2026-10-31). A zero-height view
// pinned to the top edge that ignores the top safe area grows to exactly the
// status bar's height, so the strip is painted in the screen's background.

import SwiftUI

extension View {
    func statusBarBackdrop(_ color: Color = .bg) -> some View {
        overlay(alignment: .top) {
            color
                .ignoresSafeArea(edges: .top)
                .frame(height: 0)
                .allowsHitTesting(false)
        }
    }
}
