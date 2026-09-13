// View+SelectAllOnFocus.swift — tap a pre-filled number field and type over it.
//
// The log pre-fills each set's weight and reps from the set above
// (propagateForward), so the common mid-workout edit is "this set is 10 lb
// heavier than the last one": tap the cell, and the number you want to replace
// is already sitting in it.
// UIKit puts the caret where you tapped, so typing 145 into a cell reading 135
// gives you 1**145**35 and a row of backspaces first.
//
// Selecting the whole value on focus turns that into tap-and-type. Tapping an
// already-focused field still places the caret normally (the notification only
// fires when editing BEGINS), so deliberately editing one digit is still one
// extra tap away.
//
// SwiftUI has no select-on-focus and @FocusState hands back no UITextField, so
// this listens for UIKit's begin-editing notification instead. Scope, since the
// notification is global: it applies while the view carrying the modifier is on
// screen, and only to decimal-pad fields — in the log, exactly the weight and
// reps cells.

import SwiftUI
import Combine
import UIKit

extension View {
    /// Select a decimal-pad field's whole value when it takes focus, so the
    /// next keystroke replaces it instead of appending to it.
    func selectsAllOnFocusInNumberFields() -> some View {
        modifier(SelectAllOnFocusInNumberFields())
    }
}

private struct SelectAllOnFocusInNumberFields: ViewModifier {
    /// Gates the global notification to this screen's lifetime. A sheet over
    /// the screen doesn't disappear it — that's deliberate, the number fields
    /// in the log's own sheets (plate calculator) want the same behavior.
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
            .onReceive(NotificationCenter.default.publisher(
                for: UITextField.textDidBeginEditingNotification)
            ) { note in
                guard isOnScreen,
                      let field = note.object as? UITextField,
                      field.keyboardType == .decimalPad,
                      let value = field.text, !value.isEmpty
                else { return }
                // UIKit positions the caret from the tap AFTER posting this,
                // so a selection set here is immediately overwritten. One
                // runloop turn later it sticks.
                DispatchQueue.main.async {
                    guard field.isFirstResponder else { return }
                    // selectedTextRange rather than selectAll(_:) — same
                    // selection, without inviting the edit menu.
                    field.selectedTextRange = field.textRange(
                        from: field.beginningOfDocument,
                        to: field.endOfDocument
                    )
                }
            }
    }
}
