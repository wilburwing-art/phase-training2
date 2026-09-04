//
//  KettleView.swift
//  PhaseTraining
//
//  Kettle — the app's mascot: an anthropomorphized kettlebell in the
//  cream-lime-coral family. Cast-iron bell body =
//  ink, handle = accent lime, feet = coral. Rendered natively (Canvas) and
//  animated with TimelineView so the five motion loops run with no image
//  weight. See MASCOT2.md; handoff/mascot2/generate.mjs is the parametric SVG
//  source these poses mirror.
//
//  Five seamless loops, each a periodic function of time (no seams):
//    flex · stretch · snowboard · climb · bike
//
//  Usage rule (see MASCOT2.md): render at ≥ 64 pt, never in scrolling list
//  rows. Honors Reduce Motion (falls back to a still).
//

import SwiftUI

// MARK: - Poses

enum KettlePose: String, CaseIterable, Identifiable {
    case flex, stretch, snowboard, climb, bike
    var id: String { rawValue }

    var label: String {
        switch self {
        case .flex:      return "Flex"
        case .stretch:   return "Stretch"
        case .snowboard: return "Snowboard"
        case .climb:     return "Climb"
        case .bike:      return "Bike"
        }
    }

    /// Loop length in seconds. The motion is periodic over this, so the loop
    /// is seamless.
    var period: Double {
        switch self {
        case .flex:      return 1.1
        case .stretch:   return 3.0
        case .snowboard: return 1.7
        case .climb:     return 2.4
        case .bike:      return 1.0
        }
    }

    /// Pick the loop that matches a user's sport slug (Sport.slug). Sports the
    /// app doesn't have a loop for fall back to the flex idle.
    static func forSport(_ slug: String?) -> KettlePose {
        switch slug {
        case "climbing", "bouldering", "sport-climbing":
            return .climb
        case "cycling", "mountain-biking", "road-cycling":
            return .bike
        case "snowboarding", "splitboarding", "alpine-skiing",
             "ski-mountaineering", "snow-sports":
            return .snowboard
        default:
            return .flex
        }
    }
}

// MARK: - View

/// The Kettle mascot. Animates its `pose` loop via TimelineView; pass
/// `animated: false` (or turn on Reduce Motion) for a static rest frame.
///
/// ```swift
/// KettleView(pose: .flex).frame(width: 96, height: 120)
/// KettleView(pose: KettlePose.forSport(sport?.slug)).frame(width: 72, height: 90)
/// ```
struct KettleView: View {
    var pose: KettlePose
    var animated: Bool = true
    /// Loop time to hold when not animating (Reduce Motion included). 0 is the
    /// rest frame; `period / 2` is the far end of every loop's cosine.
    var frozenAt: TimeInterval = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation) { timeline in
                    canvas(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(at: frozenAt)
            }
        }
        .aspectRatio(160.0 / 200.0, contentMode: .fit)
        .accessibilityLabel("Kettle mascot, \(pose.label.lowercased())")
    }

    private func canvas(at t: TimeInterval) -> some View {
        Canvas { context, size in
            KettleRenderer.paint(&context, size: size, pose: pose, t: t)
        }
    }
}

// MARK: - Renderer (mirrors handoff/mascot2/generate.mjs)

private enum KettleRenderer {

    // Palette: identity = brand tokens; the rest are derived tints (see MASCOT2.md).
    static let feather = Color.ink
    static let shade   = Color(red: 0xDE / 255, green: 0xDE / 255, blue: 0xD6 / 255)
    static let deep    = Color(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xBD / 255)
    static let coral   = Color.danger
    static let coralDk = Color(red: 0xE2 / 255, green: 0x4A / 255, blue: 0x2C / 255)
    static let accent  = Color.accent
    static let eye     = Color(red: 0x14 / 255, green: 0x16 / 255, blue: 0x1A / 255)

    static let TAU = 2 * Double.pi

    static func paint(_ context: inout GraphicsContext, size: CGSize, pose: KettlePose, t: TimeInterval) {
        var base = context
        // Design space 160×200; scale-to-fit, centered.
        let s = min(size.width / 160, size.height / 200)
        base.translateBy(x: (size.width - 160 * s) / 2, y: (size.height - 200 * s) / 2)
        base.scaleBy(x: s, y: s)

        switch pose {
        case .flex:      drawFlex(base, t)
        case .stretch:   drawStretch(base, t)
        case .snowboard: drawSnow(base, t)
        case .climb:     drawClimb(base, t)
        case .bike:      drawBike(base, t)
        }
    }

    // MARK: Transform helpers (GraphicsContext fill/stroke are non-mutating,
    // so contexts can be passed by value; transforms need a var copy.)

    private static func rotated(_ g: GraphicsContext, _ deg: Double, around p: CGPoint) -> GraphicsContext {
        var c = g
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .degrees(deg))
        c.translateBy(x: -p.x, y: -p.y)
        return c
    }
    private static func translated(_ g: GraphicsContext, _ dx: Double, _ dy: Double) -> GraphicsContext {
        var c = g; c.translateBy(x: dx, y: dy); return c
    }
    /// Loop phase 0…1 for time `t` over period `P`.
    private static func ph(_ t: Double, _ P: Double) -> Double {
        let u = t.truncatingRemainder(dividingBy: P) / P
        return u < 0 ? u + 1 : u
    }

    // MARK: Primitives

    private static func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private static func dot(_ g: GraphicsContext, _ x: Double, _ y: Double, _ r: Double, _ c: Color) {
        g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(c))
    }
    private static func seg(_ g: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ w: Double, _ c: Color) {
        var p = Path(); p.move(to: a); p.addLine(to: b)
        g.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round))
    }
    private static func poly(_ g: GraphicsContext, _ pts: [CGPoint], _ w: Double, _ c: Color) {
        var p = Path(); p.move(to: pts[0])
        for i in 1..<pts.count { p.addLine(to: pts[i]) }
        g.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
    private static func arm(_ g: GraphicsContext, _ sh: CGPoint, _ el: CGPoint, _ fi: CGPoint) {
        seg(g, sh, el, 8, shade); seg(g, el, fi, 8, shade); dot(g, fi.x, fi.y, 7, shade)
    }
    private static func shoe(_ g: GraphicsContext, _ ft: CGPoint) {
        var p = Path()
        p.move(to: pt(ft.x - 9, ft.y))
        p.addQuadCurve(to: pt(ft.x - 11, ft.y + 10), control: pt(ft.x - 13, ft.y + 8))
        p.addLine(to: pt(ft.x + 3, ft.y + 10))
        p.addQuadCurve(to: pt(ft.x + 1, ft.y), control: pt(ft.x + 6, ft.y + 4))
        p.closeSubpath()
        g.fill(p, with: .color(coral))
        dot(g, ft.x - 2, ft.y - 1, 3, coralDk)
    }
    private static func face(_ g: GraphicsContext, _ cx: Double, _ cy: Double, _ open: Bool) {
        dot(g, cx - 11, cy, 6.5, .white); dot(g, cx + 11, cy, 6.5, .white)
        dot(g, cx - 9, cy + 1, 3.1, eye); dot(g, cx + 13, cy + 1, 3.1, eye)
        dot(g, cx - 10, cy - 1, 1.1, accent); dot(g, cx + 12, cy - 1, 1.1, accent)
        if open {
            var m = Path()
            m.move(to: pt(cx - 6, cy + 14))
            m.addQuadCurve(to: pt(cx + 6, cy + 14), control: pt(cx, cy + 22))
            m.addQuadCurve(to: pt(cx - 6, cy + 14), control: pt(cx, cy + 11))
            m.closeSubpath()
            g.fill(m, with: .color(coralDk))
        } else {
            var m = Path()
            m.move(to: pt(cx - 7, cy + 13))
            m.addQuadCurve(to: pt(cx + 7, cy + 13), control: pt(cx, cy + 20))
            g.stroke(m, with: .color(eye), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
    }
    /// The kettlebell body: lime handle, cast bell, sheen, face.
    private static func body(_ g: GraphicsContext, _ open: Bool, _ squash: Double) {
        var handle = Path()
        handle.move(to: pt(56, 90))
        handle.addLine(to: pt(56, 66))
        handle.addQuadCurve(to: pt(80, 42), control: pt(56, 42))
        handle.addQuadCurve(to: pt(104, 66), control: pt(104, 42))
        handle.addLine(to: pt(104, 90))
        g.stroke(handle, with: .color(accent), style: StrokeStyle(lineWidth: 12, lineCap: .round))

        var neck = Path()
        neck.move(to: pt(60, 84)); neck.addLine(to: pt(64, 98))
        neck.addLine(to: pt(96, 98)); neck.addLine(to: pt(100, 84)); neck.closeSubpath()
        g.fill(neck, with: .color(feather))

        let rx = 46 * (1 - squash * 0.6), ry = 46 * (1 + squash)
        let bell = Path(ellipseIn: CGRect(x: 80 - rx, y: 124 - ry, width: 2 * rx, height: 2 * ry))
        g.fill(bell, with: .color(feather))
        g.stroke(bell, with: .color(deep), lineWidth: 2)
        g.fill(Path(ellipseIn: CGRect(x: 66 - 15, y: 108 - 11, width: 30, height: 22)),
               with: .color(.white.opacity(0.32)))
        g.stroke(Path(ellipseIn: CGRect(x: 80 - 23, y: 128 - 23, width: 46, height: 46)),
                 with: .color(deep.opacity(0.45)), lineWidth: 1.5)
        face(g, 80, 118, open)
    }

    // MARK: Poses

    private static func drawFlex(_ g: GraphicsContext, _ t: Double) {
        let flex = 0.5 - 0.5 * cos(TAU * ph(t, 1.1))
        let w = translated(g, 0, -2.5 * flex)
        let el = pt(26, 98 - 3 * flex), elR = pt(134, 98 - 3 * flex)
        let fy = 80 - 6 * flex, fx = 50 - 2 * flex
        let op = 0.25 + 0.75 * flex
        seg(w, pt(34 - 3 * flex, 74), pt(27 - 5 * flex, 69), 3, accent.opacity(op))
        seg(w, pt(126 + 3 * flex, 74), pt(133 + 5 * flex, 69), 3, accent.opacity(op))
        body(w, flex > 0.62, 0.04 * flex)
        arm(w, pt(40, 110), el, pt(fx, fy)); arm(w, pt(120, 110), elR, pt(160 - fx, fy))
        dot(w, el.x, el.y, 8 + 6 * flex, shade); dot(w, elR.x, elR.y, 8 + 6 * flex, shade)
        seg(w, pt(66, 152), pt(60, 176), 8, shade); shoe(w, pt(60, 176))
        seg(w, pt(94, 152), pt(100, 176), 8, shade); shoe(w, pt(100, 176))
    }

    private static func drawStretch(_ g: GraphicsContext, _ t: Double) {
        let u = ph(t, 3.0)
        let s = sin(TAU * u), breathe = 0.5 - 0.5 * cos(TAU * u)
        let w = rotated(translated(g, 0, -1.5 * breathe), 7 * s, around: pt(80, 152))
        let reachY = 58 - 3 * breathe
        var arc = Path()
        arc.move(to: pt(52, 52 - 2 * breathe))
        arc.addQuadCurve(to: pt(108, 52 - 2 * breathe), control: pt(80, 40 - 2 * breathe))
        w.stroke(arc, with: .color(Color.accentDim.opacity(0.35 + 0.4 * breathe)),
                 style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4]))
        body(w, false, 0)
        poly(w, [pt(40, 110), pt(58, 80), pt(74, reachY + 3)], 8, shade)
        poly(w, [pt(120, 110), pt(102, 80), pt(86, reachY + 3)], 8, shade)
        dot(w, 80, reachY, 8, shade)
        seg(w, pt(64, 152), pt(56, 176), 8, shade); shoe(w, pt(56, 176))
        seg(w, pt(96, 152), pt(104, 176), 8, shade); shoe(w, pt(104, 176))
    }

    private static func drawSnow(_ g: GraphicsContext, _ t: Double) {
        let u = ph(t, 1.7), c = sin(TAU * u)
        let w = rotated(translated(g, 0, -1.2 * (1 - abs(c))), 5 * c, around: pt(80, 130))
        for i in 0..<6 {
            let f = (u + 0.16 * Double(i)).truncatingRemainder(dividingBy: 1)
            dot(w, 30 - 26 * f, 176 - 12 * f, 2.4 * (1 - f), Color.white.opacity(0.8))
        }
        body(w, abs(c) > 0.6, 0)
        arm(w, pt(40, 110), pt(30, 92), pt(44 - 7 * c, 72 - 2 * c))
        arm(w, pt(120, 110), pt(134, 116), pt(132 + 5 * c, 118 + 9 * c))
        poly(w, [pt(70, 152), pt(62, 166), pt(64, 172)], 8, shade)
        poly(w, [pt(94, 152), pt(102, 166), pt(100, 172)], 8, shade)
        // Board in front, tilted.
        let bd = rotated(w, -12 + 5 * c, around: pt(80, 178))
        bd.fill(Path(roundedRect: CGRect(x: 26, y: 174, width: 108, height: 11), cornerRadius: 5.5), with: .color(accent))
        bd.fill(Path(roundedRect: CGRect(x: 58, y: 169, width: 10, height: 8), cornerRadius: 2), with: .color(coral))
        bd.fill(Path(roundedRect: CGRect(x: 92, y: 169, width: 10, height: 8), cornerRadius: 2), with: .color(coral))
    }

    private static func drawClimb(_ g: GraphicsContext, _ t: Double) {
        let reach = 0.5 - 0.5 * cos(TAU * ph(t, 2.4))
        let G = rotated(g, 7, around: pt(80, 120))
        // Wall holds — fixed, so the reach reads against them.
        dot(G, 46, 56, 7, accent); dot(G, 120, 92, 6, accent); dot(G, 54, 150, 6, accent); dot(G, 40, 104, 5, accent)
        let w = translated(G, 0, -2 * reach)
        let lh = pt(58 + (46 - 58) * reach, 118 + (56 - 118) * reach)
        body(w, false, 0)
        poly(w, [pt(52, 112), pt(45, 90), lh], 8, shade); dot(w, lh.x, lh.y, 7, shade)
        poly(w, [pt(112, 112), pt(118, 100), pt(120, 92)], 8, shade); dot(w, 120, 92, 7, shade)
        poly(w, [pt(70, 152), pt(60, 152 + 7 * (1 - reach)), pt(54, 150)], 8, shade); shoe(w, pt(54, 150))
        poly(w, [pt(92, 152), pt(99, 150), pt(90, 144)], 8, shade)
        if reach > 0.72 {
            let op = 0.6 * (reach - 0.72) / 0.28
            dot(G, 46, 52, 3, Color.white.opacity(op))
            dot(G, 51, 48, 2, Color.white.opacity(op))
            dot(G, 41, 49, 1.6, Color.white.opacity(op))
        }
    }

    private static func drawBike(_ g: GraphicsContext, _ t: Double) {
        let u = ph(t, 1.0), th = TAU * u
        let K = pt(80, 178), rp = 10.0
        let B = pt(38, 176), F = pt(126, 176), S = pt(80, 166), H = pt(116, 150)
        let pedL = pt(K.x + rp * cos(th), K.y + rp * sin(th))
        let pedR = pt(K.x + rp * cos(th + .pi), K.y + rp * sin(th + .pi))
        let w = rotated(translated(g, 0, 1.1 * sin(2 * th)), -4, around: pt(80, 124))

        let sop = 0.3 + 0.4 * abs(sin(th))
        seg(w, pt(8, 120), pt(24, 120), 3, accent.opacity(sop))
        seg(w, pt(4, 134), pt(22, 134), 3, accent.opacity(sop))
        seg(w, pt(10, 148), pt(26, 148), 3, accent.opacity(sop))

        func wheel(_ c: CGPoint, _ a0: Double) {
            w.stroke(Path(ellipseIn: CGRect(x: c.x - 16, y: c.y - 16, width: 32, height: 32)),
                     with: .color(deep), lineWidth: 3)
            for k in 0..<4 {
                let a = a0 + Double(k) * .pi / 4
                seg(w, pt(c.x + 3 * cos(a), c.y + 3 * sin(a)), pt(c.x + 14 * cos(a), c.y + 14 * sin(a)), 1.5, deep)
            }
            dot(w, c.x, c.y, 2.5, accent)
        }
        wheel(B, -th * 1.7); wheel(F, -th * 1.7)
        poly(w, [B, S, H], 3, accent); poly(w, [B, K], 3, accent)
        poly(w, [K, H], 3, accent); poly(w, [S, K], 3, accent); poly(w, [H, F], 3, accent)
        seg(w, H, pt(H.x + 9, H.y - 7), 3, accent)
        dot(w, K.x, K.y, 3, deep)

        body(w, false, 0)
        poly(w, [pt(102, 120), pt(110, 136), pt(H.x - 1, H.y - 2)], 8, shade)
        dot(w, H.x - 1, H.y - 2, 7, shade)
        poly(w, [pt(74, 168), pt(pedL.x - 3, pedL.y - 7), pedL], 8, shade); shoe(w, pedL)
        poly(w, [pt(88, 168), pt(pedR.x + 3, pedR.y - 7), pedR], 8, shade); shoe(w, pedR)
    }
}

// MARK: - Preview

#Preview("Loops") {
    let cols = [GridItem(.adaptive(minimum: 120), spacing: 14)]
    return ScrollView {
        LazyVGrid(columns: cols, spacing: 14) {
            ForEach(KettlePose.allCases) { pose in
                VStack(spacing: 8) {
                    KettleView(pose: pose)
                        .frame(height: 130)
                    Text(pose.label).styled(.micro).foregroundStyle(Color.ink3)
                }
                .padding(8)
            }
        }
        .padding()
    }
    .background(Color.bg)
    .preferredColorScheme(.dark)
}
