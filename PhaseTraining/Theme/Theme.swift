import SwiftUI

// Color tokens for Phase Training.
// Source of truth: handoff/README.md Design Tokens table (lines 232-246).
// "Modern athletic": near-black surface, electric-lime accent, paper-white ink.

extension Color {
    // Backgrounds
    static let bg       = Color(red: 0x0A / 255, green: 0x0B / 255, blue: 0x0D / 255) // #0A0B0D
    static let surface  = Color(red: 0x14 / 255, green: 0x16 / 255, blue: 0x1A / 255) // #14161A
    static let elevated = Color(red: 0x1C / 255, green: 0x1F / 255, blue: 0x24 / 255) // #1C1F24

    // Borders / dividers
    static let line     = Color(red: 0x2A / 255, green: 0x2E / 255, blue: 0x35 / 255) // #2A2E35
    static let lineSoft = Color(red: 0x1F / 255, green: 0x22 / 255, blue: 0x29 / 255) // #1F2229

    // Ink (text)
    static let ink  = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF0 / 255) // #F5F5F0
    static let ink2 = Color(red: 0xB5 / 255, green: 0xB7 / 255, blue: 0xBD / 255) // #B5B7BD
    static let ink3 = Color(red: 0x7A / 255, green: 0x7D / 255, blue: 0x85 / 255) // #7A7D85

    // Accent (electric lime)
    static let accent       = Color(red: 0xD4 / 255, green: 0xFF / 255, blue: 0x3D / 255) // #D4FF3D
    static let accentInk    = Color(red: 0x0A / 255, green: 0x0B / 255, blue: 0x0D / 255) // #0A0B0D
    static let accentDim    = Color(red: 0x8F / 255, green: 0xA8 / 255, blue: 0x2A / 255) // #8FA82A
    static let accentWash   = Color(red: 0xD4 / 255, green: 0xFF / 255, blue: 0x3D / 255).opacity(0.04)
    static let accentBorder = Color(red: 0xD4 / 255, green: 0xFF / 255, blue: 0x3D / 255).opacity(0.30)

    // Semantic
    static let ok     = Color(red: 0x6B / 255, green: 0xE8 / 255, blue: 0x9A / 255) // #6BE89A
    static let danger = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x4A / 255) // #FF6B4A
}
