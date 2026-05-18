// View+Keyboard.swift — global keyboard dismissal helper.
//
// `.toolbar { ToolbarItemGroup(placement: .keyboard) { ... } }` only renders
// inside a NavigationStack/NavigationView, which our tab-content screens
// don't have. So tapping a TextField with .numberPad / .decimalPad leaves
// no return key and no Done toolbar — the keyboard is stuck open.
//
// `hideKeyboard()` sends `resignFirstResponder` up the responder chain;
// SwiftUI's @FocusState bindings see it and clear automatically, which
// triggers our commit-on-blur logic.

import SwiftUI
import UIKit

extension View {
    /// Dismiss any focused TextField on the screen. Bridges UIKit's
    /// responder chain so it works regardless of which @FocusState owns
    /// the focused field — no coordination between parent + child views
    /// required.
    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}
