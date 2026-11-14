import SwiftUI

/// Dynamic Type for SF Symbols and other system-font glyphs that
/// `Font.system(size:)` would otherwise freeze at their design size.
enum SystemFontScale {
    /// Share of a fixed box's smaller side a glyph may fill.
    static let boxFill: CGFloat = 0.7

    /// `scaled` is the design size after Dynamic Type scaling.
    /// With no box the result is `scaled`. With a box the glyph grows until it
    /// fills `boxFill` of the box, never below its design size and never above
    /// `scaled`.
    static func pointSize(design: CGFloat, scaled: CGFloat, within box: CGFloat?) -> CGFloat {
        guard let box else { return scaled }
        return min(scaled, max(design, box * boxFill))
    }
}

private struct ScaledSystemFontModifier: ViewModifier {
    let design: CGFloat
    let weight: Font.Weight
    let fontDesign: Font.Design
    let box: CGFloat?
    @ScaledMetric private var scaled: CGFloat

    init(size: CGFloat, weight: Font.Weight, fontDesign: Font.Design, box: CGFloat?) {
        self.design = size
        self.weight = weight
        self.fontDesign = fontDesign
        self.box = box
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: ScreenScale.textStyle(for: size))
    }

    func body(content: Content) -> some View {
        content.font(.system(
            size: SystemFontScale.pointSize(design: design, scaled: scaled, within: box),
            weight: weight,
            design: fontDesign
        ))
    }
}

extension View {
    /// Replaces `.font(.system(size:weight:design:))`. Pass `within` with the
    /// smaller fixed side of the box the glyph sits in.
    func scaledSystemFont(_ size: CGFloat,
                          weight: Font.Weight = .regular,
                          design: Font.Design = .default,
                          within box: CGFloat? = nil) -> some View {
        modifier(ScaledSystemFontModifier(size: size, weight: weight, fontDesign: design, box: box))
    }
}
