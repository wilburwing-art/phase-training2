// Motion.swift: one place that decides what Reduce Motion does to an animation.
//
// Under Reduce Motion nothing loops, slides, scales, rotates or springs. A
// short crossfade of opacity or colour stays. Call sites use `withMotion`
// and `.motion(_:_:value:)` instead of the SwiftUI originals. A slide or scale
// `.transition` goes through `Motion.transition(_:reduced:)`.

import SwiftUI
import UIKit

enum Motion {
    enum Kind {
        /// Opacity or colour change. Kept under Reduce Motion.
        case fade
        /// Anything that moves, scales, rotates, springs or resizes. Dropped under Reduce Motion.
        case movement
    }

    /// True when the launch argument `--ui-test-reduce-motion` is present. Read once.
    static let forcedByLaunchArgument: Bool =
        ProcessInfo.processInfo.arguments.contains("--ui-test-reduce-motion")

    /// The setting as seen outside a view body.
    static var systemReduced: Bool {
        UIAccessibility.isReduceMotionEnabled || forcedByLaunchArgument
    }

    /// The setting as seen from a view: the environment value or the launch argument.
    static func isReduced(_ environmentValue: Bool) -> Bool {
        environmentValue || forcedByLaunchArgument
    }

    static func animation(_ animation: Animation, _ kind: Kind, reduced: Bool) -> Animation? {
        switch kind {
        case .fade: return animation
        case .movement: return reduced ? nil : animation
        }
    }

    /// The looping ease used by a pulsing indicator. Pass it as `.movement` so
    /// Reduce Motion drops it.
    static func pulse(duration: TimeInterval) -> Animation {
        .easeInOut(duration: duration).repeatForever(autoreverses: true)
    }

    static func transition(_ full: AnyTransition, reduced: Bool) -> AnyTransition {
        reduced ? .opacity : full
    }
}

@discardableResult
func withMotion<Result>(_ animation: Animation, _ kind: Motion.Kind,
                        _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.animation(animation, kind, reduced: Motion.systemReduced), body)
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let kind: Motion.Kind
    let value: V

    func body(content: Content) -> some View {
        content.animation(
            Motion.animation(animation, kind, reduced: Motion.isReduced(reduceMotion)),
            value: value
        )
    }
}

extension View {
    func motion<V: Equatable>(_ animation: Animation, _ kind: Motion.Kind, value: V) -> some View {
        modifier(MotionModifier(animation: animation, kind: kind, value: value))
    }
}
