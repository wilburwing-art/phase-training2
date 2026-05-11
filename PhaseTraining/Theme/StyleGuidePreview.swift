import SwiftUI

// Visual smoke test for the design system: every color token and every
// type style, rendered in one preview. Ported from `handoff/hd-style.jsx`.
//
// To use: open this file in Xcode, hit the canvas; verify all 14 colors
// and 9 type styles render with custom fonts (not system fallback).

struct StyleGuidePreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                colors
                typography
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .background(Color.bg.ignoresSafeArea())
    }

    // MARK: Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PHASE TRAINING / STYLE")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .textCase(.uppercase)
            Text("Design system")
                .styled(.displayL)
                .foregroundStyle(Color.ink)
            Text("Modern athletic — near-black, electric-lime accent, technical sans.")
                .styled(.body)
                .foregroundStyle(Color.ink2)
        }
    }

    // MARK: Colors
    private struct Swatch: Identifiable {
        let id = UUID()
        let name: String
        let hex: String
        let color: Color
        let inkOnTop: Color
    }

    private var swatches: [Swatch] {
        [
            .init(name: "bg",            hex: "#0A0B0D",   color: .bg,          inkOnTop: .ink),
            .init(name: "surface",       hex: "#14161A",   color: .surface,     inkOnTop: .ink),
            .init(name: "elevated",      hex: "#1C1F24",   color: .elevated,    inkOnTop: .ink),
            .init(name: "line",          hex: "#2A2E35",   color: .line,        inkOnTop: .ink),
            .init(name: "lineSoft",      hex: "#1F2229",   color: .lineSoft,    inkOnTop: .ink),
            .init(name: "ink",           hex: "#F5F5F0",   color: .ink,         inkOnTop: .bg),
            .init(name: "ink2",          hex: "#B5B7BD",   color: .ink2,        inkOnTop: .bg),
            .init(name: "ink3",          hex: "#7A7D85",   color: .ink3,        inkOnTop: .bg),
            .init(name: "accent",        hex: "#D4FF3D",   color: .accent,      inkOnTop: .accentInk),
            .init(name: "accentInk",     hex: "#0A0B0D",   color: .accentInk,   inkOnTop: .ink),
            .init(name: "accentDim",     hex: "#8FA82A",   color: .accentDim,   inkOnTop: .bg),
            .init(name: "accentWash",    hex: "4% lime",   color: .accentWash,  inkOnTop: .ink),
            .init(name: "accentBorder",  hex: "30% lime",  color: .accentBorder,inkOnTop: .ink),
            .init(name: "ok",            hex: "#6BE89A",   color: .ok,          inkOnTop: .bg),
            .init(name: "danger",        hex: "#FF6B4A",   color: .danger,      inkOnTop: .ink),
        ]
    }

    private var colors: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Colors")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .textCase(.uppercase)

            let columns = [GridItem(.adaptive(minimum: 140), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(swatches) { sw in
                    swatchCard(sw)
                }
            }
        }
    }

    private func swatchCard(_ sw: Swatch) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(sw.color)
                .frame(height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.line, lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(sw.name).styled(.monoS).foregroundStyle(Color.ink)
                Text(sw.hex).styled(.monoXS).foregroundStyle(Color.ink3)
            }
            .padding(.top, 8)
        }
    }

    // MARK: Typography
    private struct TypeRow: Identifiable {
        let id = UUID()
        let label: String
        let sample: String
        let style: TypeStyle
    }

    private var typeRows: [TypeRow] {
        [
            .init(label: "displayL  Space Grotesk 34 / 600 / -0.03em",  sample: "Phase Training",    style: .displayL),
            .init(label: "displayM  Space Grotesk 26 / 600 / -0.03em",  sample: "Upper Body",        style: .displayM),
            .init(label: "displayS  Space Grotesk 16 / 600 / -0.02em",  sample: "Bench Press",       style: .displayS),
            .init(label: "body      Inter 13 / 400",                    sample: "Push the bar.",     style: .body),
            .init(label: "monoL     JetBrains Mono 22 / 600 / -0.02em", sample: "01:23",             style: .monoL),
            .init(label: "monoM     JetBrains Mono 17 / 500",           sample: "00:42",             style: .monoM),
            .init(label: "monoS     JetBrains Mono 13.5 / 500",         sample: "135 × 5 @ RPE 7",   style: .monoS),
            .init(label: "monoXS    JetBrains Mono 11 / 400",           sample: "prev 130 × 5",      style: .monoXS),
            .init(label: "micro     JetBrains Mono 10 / 500 / 0.14em",  sample: "ELAPSED",           style: .micro),
        ]
    }

    private var typography: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Typography")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(typeRows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.label)
                            .styled(.monoXS)
                            .foregroundStyle(Color.ink3)
                        if row.style.isUppercase {
                            Text(row.sample.uppercased())
                                .styled(row.style)
                                .foregroundStyle(Color.ink)
                        } else {
                            Text(row.sample)
                                .styled(row.style)
                                .foregroundStyle(Color.ink)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.line, lineWidth: 0.5)
                    )
                }
            }
        }
    }
}

#Preview("Style Guide") {
    StyleGuidePreview()
        .preferredColorScheme(.dark)
}
