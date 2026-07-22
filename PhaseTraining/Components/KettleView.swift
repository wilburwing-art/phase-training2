// KettleView.swift — "Mr Kettle", the moment mascot.
//
// The Repelican's sibling: a kettlebell character in the same cream + lime +
// coral family, but where the Repelican is the always-on phase avatar, Mr
// Kettle is a MOMENT mascot — he appears at a beat, animates a loop, and he's
// gone. Bell = a friendly face-on-a-belly (Color.ink), handle = a lime arch
// (Color.accent) that doubles as flexing arms, coral feet (Color.danger).
//
// Rendered with a SwiftUI Canvas driven by TimelineView's clock, so each loop
// is a continuous sine/cosine — seamless, no jump at the loop point, zero image
// weight. Still (rest frame) under Reduce Motion. Brand tokens only.
//
// First beat shipped: .flex on session complete (see CompleteScreen). Stretch
// (rest days) and Snowboard (sport days) are authored the same way as
// fast-follows — the loop enum + clock are already here.

import SwiftUI

/// Which looping motion Mr Kettle is playing, and its period.
enum KettleLoop: String, CaseIterable, Identifiable {
    case flex, stretch, snowboard
    var id: String { rawValue }

    /// Seconds per loop cycle — matches the concept sheet timings.
    var period: Double {
        switch self {
        case .flex:      return 1.1
        case .stretch:   return 3.0
        case .snowboard: return 1.7
        }
    }
}

struct KettleView: View {
    var loop: KettleLoop = .flex
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                // Still rest frame — no clock, no motion.
                Canvas { ctx, size in Self.paint(&ctx, size: size, loop: loop, phase: 0) }
            } else {
                TimelineView(.animation) { timeline in
                    let secs = timeline.date.timeIntervalSinceReferenceDate
                    let phase = (secs.truncatingRemainder(dividingBy: loop.period)) / loop.period
                    Canvas { ctx, size in Self.paint(&ctx, size: size, loop: loop, phase: phase) }
                }
            }
        }
        .aspectRatio(200.0 / 240.0, contentMode: .fit)
        .accessibilityLabel("Mr Kettle mascot")
    }

    // MARK: - Drawing (design space 200×240, scale-to-fit centered)

    private static func paint(_ context: inout GraphicsContext, size: CGSize, loop: KettleLoop, phase: Double) {
        var ctx = context
        let s = min(size.width / 200, size.height / 240)
        ctx.translateBy(x: (size.width - 200 * s) / 2, y: (size.height - 240 * s) / 2)
        ctx.scaleBy(x: s, y: s)

        // Brand tokens + derived shades (mirrors MASCOT.md palette).
        let cream = Color.ink
        let shade = Color(red: 0xDE / 255, green: 0xDE / 255, blue: 0xD6 / 255)
        let lime  = Color.accent
        let limeDk = Color.accentDim
        let coral = Color.danger
        let coralDk = Color(red: 0xE2 / 255, green: 0x4A / 255, blue: 0x2C / 255)
        let eye   = Color(red: 0x14 / 255, green: 0x16 / 255, blue: 0x1A / 255)

        // Flex pulse: one squeeze per cycle, peaking at mid-phase. Only .flex
        // drives motion for now; stretch / snowboard render the rest frame until
        // their loops are authored.
        let f = (loop == .flex) ? pow(sin(phase * .pi), 1.5) : 0.0

        // The whole body rises on the squeeze.
        ctx.translateBy(x: 0, y: -5 * f)

        let cx = 100.0

        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
            CGRect(x: x, y: y, width: w, height: h)
        }
        func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Path {
            Path(ellipseIn: rect(x - rx, y - ry, 2 * rx, 2 * ry))
        }
        func dot(_ x: Double, _ y: Double, _ r: Double, _ c: Color) {
            ctx.fill(ellipse(x, y, r, r), with: .color(c))
        }
        func seg(_ a: CGPoint, _ b: CGPoint, _ w: Double, _ c: Color) {
            var p = Path(); p.move(to: a); p.addLine(to: b)
            ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round))
        }

        // Energy ticks (behind the body) — flare out on the squeeze.
        if f > 0.2 {
            for sgn in [-1.0, 1.0] {
                let gx = cx + sgn * 68
                let len = 6.0 + 12 * f
                seg(CGPoint(x: gx, y: 78), CGPoint(x: gx + sgn * len, y: 74), 3, lime.opacity(0.85 * f))
                seg(CGPoint(x: gx + sgn * 3, y: 96), CGPoint(x: gx + sgn * (len + 4), y: 96), 3, lime.opacity(0.85 * f))
                seg(CGPoint(x: gx, y: 114), CGPoint(x: gx + sgn * len, y: 118), 3, lime.opacity(0.85 * f))
            }
        }

        // Handle — a lime arch that doubles as flexing arms. On the squeeze it
        // pulls in, rises, and thickens (the bicep bump).
        let apexY = 60.0 - 12 * f
        let inset = 6.0 * f
        let hw = 15.0 + 7 * f
        let lx = cx - 32 + inset
        let rx = cx + 32 - inset
        var handle = Path()
        handle.move(to: CGPoint(x: lx, y: 96))
        handle.addQuadCurve(to: CGPoint(x: lx - 2, y: apexY + 6), control: CGPoint(x: lx - 6, y: 72))
        handle.addQuadCurve(to: CGPoint(x: rx + 2, y: apexY + 6), control: CGPoint(x: cx, y: apexY - 10))
        handle.addQuadCurve(to: CGPoint(x: rx, y: 96), control: CGPoint(x: rx + 6, y: 72))
        ctx.stroke(handle, with: .color(lime),
                   style: StrokeStyle(lineWidth: hw, lineCap: .round, lineJoin: .round))
        ctx.stroke(handle, with: .color(limeDk.opacity(0.5)),
                   style: StrokeStyle(lineWidth: max(2, hw * 0.28), lineCap: .round, lineJoin: .round))

        // Feet (coral) — planted below the bell.
        for sgn in [-1.0, 1.0] {
            let fx = cx + sgn * 26
            ctx.fill(ellipse(fx, 214, 20, 12), with: .color(coral))
            ctx.fill(ellipse(fx, 218, 20, 8), with: .color(coralDk.opacity(0.5)))
        }

        // Bell body (cream) with a soft lower shade for volume.
        let bellCY = 148.0, bellRX = 60.0, bellRY = 64.0
        ctx.fill(ellipse(cx, bellCY, bellRX, bellRY), with: .color(cream))
        ctx.fill(ellipse(cx, bellCY + 20, bellRX * 0.82, bellRY * 0.5), with: .color(shade.opacity(0.7)))
        // Neck collar where the handle meets the bell.
        ctx.fill(ellipse(cx, 96, 30, 12), with: .color(shade))

        // Face — eyes + a mouth that opens at the flex peak.
        dot(cx - 22, bellCY - 4, 6.5, eye)
        dot(cx + 22, bellCY - 4, 6.5, eye)
        // tiny cheek highlights on the squeeze
        if f > 0.4 {
            dot(cx - 36, bellCY + 8, 4, coral.opacity(0.5 * f))
            dot(cx + 36, bellCY + 8, 4, coral.opacity(0.5 * f))
        }
        let mouthCY = bellCY + 26
        if f < 0.25 {
            // Resting smile.
            var m = Path()
            m.move(to: CGPoint(x: cx - 14, y: mouthCY))
            m.addQuadCurve(to: CGPoint(x: cx + 14, y: mouthCY), control: CGPoint(x: cx, y: mouthCY + 9))
            ctx.stroke(m, with: .color(eye), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        } else {
            // Open "hup!" mouth on the squeeze.
            let mh = 4.0 + 14 * f
            ctx.fill(ellipse(cx, mouthCY + mh * 0.3, 9 + 3 * f, mh), with: .color(eye))
        }
    }
}

#Preview("Loops") {
    HStack(spacing: 16) {
        ForEach(KettleLoop.allCases) { loop in
            VStack {
                KettleView(loop: loop).frame(width: 90, height: 108)
                Text(loop.rawValue).font(.caption).foregroundStyle(Color.ink2)
            }
        }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.bg)
    .preferredColorScheme(.dark)
}
