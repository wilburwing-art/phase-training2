import SwiftUI

// Typography tokens for Phase Training.
// Source of truth: handoff/README.md Design Tokens table (lines 251-259).
//
// Three families:
//   - Space Grotesk: display / headings
//   - Inter:         body
//   - JetBrains Mono: numeric readouts, micro-labels
//
// Font.custom does not apply CSS-style tracking. For styles that need
// non-zero tracking (Display L/M/S, Display 16, Micro), call the
// returned font with the matching `Text.tracking(...)` modifier (see
// `Text.styled(_:)` below). Tracking values are em-relative in the
// spec; SwiftUI's `tracking` is in points, so we convert by size.

private enum FontName {
    static let spaceGroteskRegular  = "SpaceGrotesk-Regular"
    static let spaceGroteskMedium   = "SpaceGrotesk-Medium"
    static let spaceGroteskSemiBold = "SpaceGrotesk-SemiBold"
    static let inter                = "Inter-Regular"
    static let monoRegular          = "JetBrainsMono-Regular"
    static let monoMedium           = "JetBrainsMono-Medium"
    static let monoSemiBold         = "JetBrainsMono-SemiBold"
}

extension Font {
    // MARK: Display (Space Grotesk, weight 600)
    static let displayL = Font.custom(FontName.spaceGroteskSemiBold, size: 34) // tracking -0.03em
    static let displayM = Font.custom(FontName.spaceGroteskSemiBold, size: 26) // tracking -0.03em
    static let displayS = Font.custom(FontName.spaceGroteskSemiBold, size: 16) // tracking -0.02em

    // MARK: Body (Inter)
    static let body = Font.custom(FontName.inter, size: 13)

    // MARK: Mono (JetBrains Mono)
    static let monoL  = Font.custom(FontName.monoSemiBold, size: 22)   // weight 600, tracking -0.02em
    static let monoM  = Font.custom(FontName.monoMedium,   size: 17)   // weight 500
    static let monoS  = Font.custom(FontName.monoMedium,   size: 13.5) // weight 500
    static let monoXS = Font.custom(FontName.monoRegular,  size: 11)   // weight 400
    static let micro  = Font.custom(FontName.monoMedium,   size: 10)   // weight 500, tracking 0.14em, uppercase
}

// MARK: - Type styles with tracking
//
// SwiftUI's `Text.tracking(_:)` takes points, not em. Convert each
// em-relative tracking value at apply time.

enum TypeStyle {
    case displayL, displayM, displayS
    case body
    case monoL, monoM, monoS, monoXS
    case micro

    var font: Font {
        switch self {
        case .displayL: return .displayL
        case .displayM: return .displayM
        case .displayS: return .displayS
        case .body:     return .body
        case .monoL:    return .monoL
        case .monoM:    return .monoM
        case .monoS:    return .monoS
        case .monoXS:   return .monoXS
        case .micro:    return .micro
        }
    }

    /// Tracking in points (em ratio × size).
    var tracking: CGFloat {
        switch self {
        case .displayL: return -0.03 * 34
        case .displayM: return -0.03 * 26
        case .displayS: return -0.02 * 16
        case .monoL:    return -0.02 * 22
        case .micro:    return  0.14 * 10
        default:        return 0
        }
    }

    /// Whether the style is upper-cased in the spec (Micro labels).
    ///
    /// Spec metadata only — `styled(_:)` cannot apply it: it returns `Text`,
    /// and `textCase(_:)` is a View-only modifier. Uppercasing is the
    /// CALLER's job (hand-`.uppercased()` strings or a view-level
    /// `.textCase(.uppercase)`); StyleGuidePreview reads this flag to
    /// uppercase its samples the same way.
    var isUppercase: Bool { self == .micro }
}

extension Text {
    /// Apply a Phase Training type style: font + tracking. Casing is NOT
    /// applied here (see `isUppercase`) — `.micro` callers own it.
    func styled(_ style: TypeStyle) -> Text {
        self.font(style.font).tracking(style.tracking)
    }
}

extension View {
    /// View-level convenience for non-Text containers (e.g. TextField placeholders).
    func styled(_ style: TypeStyle) -> some View {
        self.font(style.font).tracking(style.tracking)
    }
}
