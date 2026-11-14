import SwiftUI
import UIKit
import XCTest
@testable import PhaseTraining

final class ThemeContrastTests: XCTestCase {
    private func luminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func test_lineStrongClearsThreeToOneOnEveryFill() {
        for (name, fill) in [("bg", Color.bg), ("surface", Color.surface), ("elevated", Color.elevated)] {
            XCTAssertGreaterThanOrEqual(contrast(.lineStrong, fill), 3.0, "lineStrong on \(name)")
        }
    }

    func test_lineStrongStaysBelowBodyTextInk() {
        XCTAssertLessThan(contrast(.lineStrong, .bg), contrast(.ink3, .bg))
    }
}
