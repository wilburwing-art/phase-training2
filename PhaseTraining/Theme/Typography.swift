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

// MARK: - Per-style spec

/// One row per style: font name, size, em-relative tracking. Both `font`
/// and `tracking` derive from the same row, so a size change can never
/// leave tracking computed against a stale size.
private struct TypeSpec {
    let fontName: String
    let size: CGFloat
    let trackingEm: CGFloat
    /// The system text style this size scales WITH. `Font.custom(_:size:)`
    /// alone is fixed-size and ignores Dynamic Type entirely; this table was
    /// the app's only source of sizes, so a user on the largest accessibility
    /// setting got 13pt body copy and 10pt labels (T2-1). `relativeTo:` scales
    /// `size` by the ratio of the style's current size to its default, so every
    /// design size below is unchanged at the default setting and grows from
    /// there.
    let relativeTo: Font.TextStyle

    var font: Font { Font.custom(fontName, size: size, relativeTo: relativeTo) }

    /// Tracking in points (em ratio × size).
    var tracking: CGFloat { trackingEm * size }
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

    private var spec: TypeSpec {
        switch self {
        // Display (Space Grotesk, weight 600)
        // The `relativeTo:` style is chosen so its DEFAULT size matches the
        // design size as closely as possible, which keeps the scale curve
        // proportional (largeTitle 34, title 28, title2 22, headline 17,
        // body 17, footnote 13, caption2 11).
        case .displayL: return TypeSpec(fontName: FontName.spaceGroteskSemiBold, size: 34,   trackingEm: -0.03, relativeTo: .largeTitle)
        case .displayM: return TypeSpec(fontName: FontName.spaceGroteskSemiBold, size: 26,   trackingEm: -0.03, relativeTo: .title)
        case .displayS: return TypeSpec(fontName: FontName.spaceGroteskSemiBold, size: 16,   trackingEm: -0.02, relativeTo: .headline)
        // Body (Inter)
        case .body:     return TypeSpec(fontName: FontName.inter,                size: 13,   trackingEm: 0,     relativeTo: .footnote)
        // Mono (JetBrains Mono)
        case .monoL:    return TypeSpec(fontName: FontName.monoSemiBold,         size: 22,   trackingEm: -0.02, relativeTo: .title2)    // weight 600
        case .monoM:    return TypeSpec(fontName: FontName.monoMedium,           size: 17,   trackingEm: 0,     relativeTo: .body)      // weight 500
        case .monoS:    return TypeSpec(fontName: FontName.monoMedium,           size: 13.5, trackingEm: 0,     relativeTo: .footnote)  // weight 500
        case .monoXS:   return TypeSpec(fontName: FontName.monoRegular,          size: 11,   trackingEm: 0,     relativeTo: .caption2)  // weight 400
        case .micro:    return TypeSpec(fontName: FontName.monoMedium,           size: 10,   trackingEm: 0.14,  relativeTo: .caption2)  // weight 500, uppercase
        }
    }

    var font: Font { spec.font }

    /// The system text style this style scales with. Exposed so a test can
    /// assert every style is wired to Dynamic Type (T2-8); a case that ever
    /// drops back to a fixed `Font.custom(_:size:)` would have to remove it
    /// from the table, which the test would catch.
    var relativeTo: Font.TextStyle { spec.relativeTo }

    /// The design size at the default content size category.
    var designSize: CGFloat { spec.size }

    /// Tracking in points (em ratio × size).
    var tracking: CGFloat { spec.tracking }

    /// Whether the style is upper-cased in the spec (Micro labels).
    ///
    /// Spec metadata only — `styled(_:)` cannot apply it: it returns `Text`,
    /// and `textCase(_:)` is a View-only modifier. Uppercasing is the
    /// CALLER's job (hand-`.uppercased()` strings or a view-level
    /// `.textCase(.uppercase)`); StyleGuidePreview reads this flag to
    /// uppercase its samples the same way.
    var isUppercase: Bool { self == .micro }
}

// Font statics derived from the TypeSpec table above (sizes live there only).
extension Font {
    // MARK: Display (Space Grotesk, weight 600)
    static let displayL = TypeStyle.displayL.font
    static let displayM = TypeStyle.displayM.font
    static let displayS = TypeStyle.displayS.font

    // MARK: Body (Inter)
    static let body = TypeStyle.body.font

    // MARK: Mono (JetBrains Mono)
    static let monoL  = TypeStyle.monoL.font
    static let monoM  = TypeStyle.monoM.font
    static let monoS  = TypeStyle.monoS.font
    static let monoXS = TypeStyle.monoXS.font
    static let micro  = TypeStyle.micro.font
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
