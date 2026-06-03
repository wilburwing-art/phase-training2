// CardSurface.swift — the shared card chrome.
//
// Surface fill + hairline stroke + rounded clip, in one modifier. The
// body-weight / body-composition / plate-calculator sheets each hand-copied
// this block per section; ProgressScreen kept a private `card(title:)` with
// the same chrome. This is the single source so a design tweak (corner
// radius, surface color, stroke weight) lands in one place.

import SwiftUI

extension View {
    /// Standard card surface used by the logging sheets + Progress cards.
    func cardSurface(cornerRadius: CGFloat = 12, padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
