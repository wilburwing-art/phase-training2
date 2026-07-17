//
//  RepelicanView.swift
//  PhaseTraining
//
//  The Repelican — the app mascot. A workout pelican (front-facing
//  double-biceps flex) rendered natively so its `bulk` stays a live value:
//  one character, one scalar 0…1 driving torso width, arm thickness, and the
//  flex bump. See MASCOT.md for the concept; handoff/mascot/generate.mjs is
//  the parametric SVG source this geometry mirrors.
//
//  Rendered with Canvas (multicolor) and conformed to Animatable so a bulk
//  change (e.g. a training-phase transition) morphs Lean → Swole instead of
//  snapping. Identity colors bind to Theme.swift tokens: feathers = ink,
//  bill + feet = danger, headband + wristbands = accent. Dark-ground only.
//
//  Usage rule (see MASCOT.md): render at ≥ 64 pt, never in scrolling list
//  rows — live vector at tiny sizes was blurry/CPU-hot for the muscle chips.
//

import SwiftUI

// MARK: - Mascot view

/// The Repelican, drawn at an arbitrary `bulk` (0 = Lean, 1 = Swole).
///
/// ```swift
/// RepelicanView(build: .athletic).frame(width: 96, height: 110)
/// RepelicanView(bulk: physiqueBulk).frame(width: 72, height: 82)
/// ```
struct RepelicanView: View, Animatable {

    /// 0 = Lean … 1 = Swole. Clamped at draw time.
    var bulk: Double

    init(bulk: Double) { self.bulk = bulk }
    init(build: RepelicanBuild) { self.bulk = build.bulk }

    /// Interpolating `bulk` is what makes a phase transition morph the
    /// physique rather than cut to it.
    var animatableData: Double {
        get { bulk }
        set { bulk = newValue }
    }

    var body: some View {
        Canvas { context, size in
            Self.paint(&context, size: size, bulk: min(1, max(0, bulk)))
        }
        .aspectRatio(260.0 / 300.0, contentMode: .fit)
        .accessibilityLabel("The Repelican mascot")
    }

    // MARK: Drawing (mirrors handoff/mascot/generate.mjs)

    private static func paint(_ context: inout GraphicsContext, size: CGSize, bulk b: Double) {
        // Draw through a local copy so the nested helpers below capture a plain
        // `var`, not the inout parameter. A GraphicsContext copy shares the same
        // drawing surface (this is the standard Canvas clip pattern), so every
        // fill/stroke still lands on screen.
        var ctx = context

        // Design space is 260×300; scale-to-fit, centered.
        let s = min(size.width / 260, size.height / 300)
        ctx.translateBy(x: (size.width - 260 * s) / 2, y: (size.height - 300 * s) / 2)
        ctx.scaleBy(x: s, y: s)

        // Identity colors = brand tokens; shades are derived tints (see MASCOT.md).
        let feather = Color.ink
        let shade   = Color(red: 0xDE / 255, green: 0xDE / 255, blue: 0xD6 / 255)
        let deep    = Color(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xBD / 255)
        let coral   = Color.danger
        let coralDk = Color(red: 0xE2 / 255, green: 0x4A / 255, blue: 0x2C / 255)
        let pouch   = Color(red: 0xFF / 255, green: 0x8A / 255, blue: 0x6E / 255)
        let accent  = Color.accent
        let accentDk = Color.accentDim
        let eye     = Color(red: 0x14 / 255, green: 0x16 / 255, blue: 0x1A / 255)

        let cx = 130.0
        let bodyRX = 34 + b * 20
        let bodyCY = 206.0
        let bodyRY = 60 + b * 6
        let limb   = 8 + b * 8
        let bicep  = 8 + b * 17
        let headR  = 34.0
        let headCY = 90.0
        let shoulderY = 170.0

        let sh   = CGPoint(x: cx - bodyRX * 0.62, y: shoulderY)
        let el   = CGPoint(x: cx - (bodyRX + limb + 22), y: shoulderY - 12)
        let fist = CGPoint(x: cx - (headR - 4), y: 78)
        let wri  = CGPoint(x: el.x * 0.35 + fist.x * 0.65, y: el.y * 0.35 + fist.y * 0.65)

        func mir(_ p: CGPoint) -> CGPoint { CGPoint(x: 2 * cx - p.x, y: p.y) }
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
            CGRect(x: x, y: y, width: w, height: h)
        }
        func dot(_ c: CGPoint, _ r: Double, _ color: Color) {
            ctx.fill(Path(ellipseIn: rect(c.x - r, c.y - r, 2 * r, 2 * r)), with: .color(color))
        }
        func seg(_ a: CGPoint, _ c: CGPoint, _ w: Double, _ color: Color) {
            var p = Path(); p.move(to: a); p.addLine(to: c)
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round))
        }
        func ring(_ c: CGPoint, _ r: Double, _ w: Double, _ color: Color) {
            ctx.stroke(Path(ellipseIn: rect(c.x - r, c.y - r, 2 * r, 2 * r)),
                       with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round))
        }
        func quad(_ pts: [(CGPoint, CGPoint)], from start: CGPoint) -> Path {
            var p = Path(); p.move(to: start)
            for (end, control) in pts { p.addQuadCurve(to: end, control: control) }
            p.closeSubpath(); return p
        }

        // Energy ticks (Swole only) — drawn behind the body.
        if b > 0.75 {
            for sgn in [-1.0, 1.0] {
                let gx = cx + sgn * (bodyRX + limb + 30)
                seg(CGPoint(x: gx, y: 126), CGPoint(x: gx + sgn * 10, y: 126), 3, accent.opacity(0.9))
                seg(CGPoint(x: gx - sgn * 2, y: 140), CGPoint(x: gx + sgn * 12, y: 140), 3, accent.opacity(0.9))
            }
        }

        // Feet
        ctx.fill(quad([(CGPoint(x: 88, y: 282), CGPoint(x: 90, y: 268)),
                       (CGPoint(x: 118, y: 280), CGPoint(x: 106, y: 288)),
                       (CGPoint(x: 106, y: 262), CGPoint(x: 122, y: 270))],
                      from: CGPoint(x: 106, y: 262)), with: .color(coral))
        ctx.fill(quad([(CGPoint(x: 172, y: 282), CGPoint(x: 170, y: 268)),
                       (CGPoint(x: 142, y: 280), CGPoint(x: 154, y: 288)),
                       (CGPoint(x: 154, y: 262), CGPoint(x: 138, y: 270))],
                      from: CGPoint(x: 154, y: 262)), with: .color(coral))
        ctx.fill(Path(roundedRect: rect(106, 248, 9, 20), cornerRadius: 4), with: .color(coralDk))
        ctx.fill(Path(roundedRect: rect(145, 248, 9, 20), cornerRadius: 4), with: .color(coralDk))

        // Torso
        let torsoRect = rect(cx - bodyRX, bodyCY - bodyRY, 2 * bodyRX, 2 * bodyRY)
        ctx.fill(Path(ellipseIn: torsoRect),
                 with: .linearGradient(Gradient(colors: [feather, deep]),
                                       startPoint: CGPoint(x: cx, y: bodyCY - bodyRY),
                                       endPoint: CGPoint(x: cx, y: bodyCY + bodyRY)))
        ctx.stroke(Path(ellipseIn: torsoRect), with: .color(deep), lineWidth: 2)

        // Chest / pec definition
        var chest = Path()
        chest.move(to: CGPoint(x: cx, y: 168))
        chest.addQuadCurve(to: CGPoint(x: cx, y: 168 + 44 + b * 16),
                           control: CGPoint(x: cx, y: 168 + 28 + b * 14))
        ctx.stroke(chest, with: .color(deep.opacity(0.55)), lineWidth: 2)
        if b > 0.4 {
            var pecL = Path()
            pecL.move(to: CGPoint(x: cx - bodyRX * 0.5, y: 176))
            pecL.addQuadCurve(to: CGPoint(x: cx - bodyRX * 0.5, y: 202 + b * 10),
                              control: CGPoint(x: cx, y: 186 + b * 10))
            ctx.stroke(pecL, with: .color(deep.opacity(0.4)), lineWidth: 2)
            var pecR = Path()
            pecR.move(to: CGPoint(x: cx + bodyRX * 0.5, y: 176))
            pecR.addQuadCurve(to: CGPoint(x: cx + bodyRX * 0.5, y: 202 + b * 10),
                              control: CGPoint(x: cx, y: 186 + b * 10))
            ctx.stroke(pecR, with: .color(deep.opacity(0.4)), lineWidth: 2)
        }

        // Arms (upper + fore), mirrored
        seg(sh, el, limb * 2, shade);          seg(mir(sh), mir(el), limb * 2, shade)
        seg(el, fist, limb * 2, shade);        seg(mir(el), mir(fist), limb * 2, shade)
        // Bicep flex bumps
        let bl = CGPoint(x: el.x + limb * 0.3, y: el.y - limb * 0.2)
        dot(bl, bicep, feather); dot(mir(bl), bicep, feather)
        if b > 0.4 {
            var defL = Path()
            defL.move(to: CGPoint(x: el.x - bicep * 0.5, y: el.y - bicep * 0.6))
            defL.addQuadCurve(to: CGPoint(x: el.x + bicep * 0.5, y: el.y - bicep * 0.4),
                              control: CGPoint(x: el.x, y: el.y - bicep))
            ctx.stroke(defL, with: .color(deep.opacity(0.5)), lineWidth: 2)
            var defR = Path()
            let elR = mir(el)
            defR.move(to: CGPoint(x: elR.x + bicep * 0.5, y: elR.y - bicep * 0.6))
            defR.addQuadCurve(to: CGPoint(x: elR.x - bicep * 0.5, y: elR.y - bicep * 0.4),
                              control: CGPoint(x: elR.x, y: elR.y - bicep))
            ctx.stroke(defR, with: .color(deep.opacity(0.5)), lineWidth: 2)
        }
        // Fists + wristbands
        dot(fist, limb + 2, shade); dot(mir(fist), limb + 2, shade)
        ring(wri, limb + 1, 6, accent); ring(mir(wri), limb + 1, 6, accent)

        // Head
        let headRect = rect(cx - headR, headCY - headR, 2 * headR, 2 * headR)
        ctx.fill(Path(ellipseIn: headRect),
                 with: .linearGradient(Gradient(colors: [feather, deep]),
                                       startPoint: CGPoint(x: cx, y: headCY - headR),
                                       endPoint: CGPoint(x: cx, y: headCY + headR)))
        ctx.stroke(Path(ellipseIn: headRect), with: .color(deep), lineWidth: 2)

        // Headband — a strip clipped to the head circle so it hugs the edges.
        var bandCtx = ctx
        bandCtx.clip(to: Path(ellipseIn: headRect))
        bandCtx.fill(Path(rect(cx - headR, headCY - 14, 2 * headR, 13)), with: .color(accent))
        bandCtx.fill(Path(rect(cx - headR, headCY - 3, 2 * headR, 3)), with: .color(accentDk.opacity(0.6)))
        // Headband tail
        ctx.fill(quad([(CGPoint(x: 188, y: 102), CGPoint(x: 178, y: 88)),
                       (CGPoint(x: 168, y: 104), CGPoint(x: 174, y: 100)),
                       (CGPoint(x: 158, y: 86), CGPoint(x: 170, y: 94))],
                      from: CGPoint(x: 158, y: 86)), with: .color(accent))

        // Eyes
        dot(CGPoint(x: cx - 12, y: headCY + 3), 7, .white)
        dot(CGPoint(x: cx + 12, y: headCY + 3), 7, .white)
        dot(CGPoint(x: cx - 10, y: headCY + 4), 3.4, eye)
        dot(CGPoint(x: cx + 14, y: headCY + 4), 3.4, eye)
        dot(CGPoint(x: cx - 11, y: headCY + 2.4), 1.2, accent)
        dot(CGPoint(x: cx + 13, y: headCY + 2.4), 1.2, accent)

        // Bill + pouch (fixed — the face doesn't bulk)
        let bill = quad([(CGPoint(x: 144, y: 102), CGPoint(x: 130, y: 108)),
                         (CGPoint(x: 142, y: 138), CGPoint(x: 150, y: 122)),
                         (CGPoint(x: 118, y: 138), CGPoint(x: 130, y: 148)),
                         (CGPoint(x: 116, y: 102), CGPoint(x: 110, y: 122))],
                        from: CGPoint(x: 116, y: 102))
        ctx.fill(bill, with: .color(coral))
        ctx.stroke(bill, with: .color(coralDk), lineWidth: 2)
        ctx.fill(quad([(CGPoint(x: 139, y: 112), CGPoint(x: 130, y: 118)),
                       (CGPoint(x: 136, y: 134), CGPoint(x: 141, y: 124)),
                       (CGPoint(x: 124, y: 134), CGPoint(x: 130, y: 140)),
                       (CGPoint(x: 121, y: 112), CGPoint(x: 119, y: 124))],
                      from: CGPoint(x: 121, y: 112)), with: .color(pouch))
        dot(CGPoint(x: 130, y: 148), 3, coralDk)
    }
}

// MARK: - Named builds

/// The three reference physiques. `bulk` is the single knob behind each.
enum RepelicanBuild: String, CaseIterable, Identifiable {
    case lean, athletic, swole
    var id: String { rawValue }

    var bulk: Double {
        switch self {
        case .lean:     return 0.0
        case .athletic: return 0.55
        case .swole:    return 1.0
        }
    }

    var label: String {
        switch self {
        case .lean:     return "Lean"
        case .athletic: return "Athletic"
        case .swole:    return "Swole"
        }
    }
}

// MARK: - Phase → physique mapping

/// Maps a training phase to the mascot's `bulk`, so the Repelican's build
/// reflects the block the user is in (see MASCOT.md). Pure — unit-tested in
/// RepelicanTests. No new persistence; callers feed it values already on
/// TrainingMemory.
enum RepelicanPhysique {

    /// Endurance disciplines from `Sport.catalog` — these peak *lean*, so the
    /// mascot never bulks up for them.
    static let enduranceSlugs: Set<String> = [
        "running", "cycling", "swimming", "rowing",
        "paddle-sports", "stand-up-paddleboarding", "obstacle-course-racing",
        "triathlon"
    ]

    static func isEndurance(_ sport: Sport?) -> Bool {
        guard let sport else { return false }
        return enduranceSlugs.contains(sport.slug)
    }

    /// `bulk` for a phase. Off-season ramps up over its weeks ("build the
    /// engine"); pre-season/maintenance sit balanced; in-season and event
    /// prep trend lean. Endurance-primary athletes are scaled leaner
    /// throughout.
    static func bulk(phase: SeasonPhase, weekInPhase: Int?, primaryIsEndurance: Bool) -> Double {
        let base: Double
        switch phase {
        case .offSeason:
            let w = max(1, weekInPhase ?? 1)
            base = min(0.8, 0.4 + 0.1 * Double(w - 1))
        case .preSeason:   base = 0.55
        case .inSeason:    base = 0.35
        case .eventPrep:   base = 0.25
        case .maintenance: base = 0.55
        }
        let adjusted = primaryIsEndurance ? base * 0.6 : base
        return min(1, max(0, adjusted))
    }
}

// MARK: - Preview

#Preview("Three builds") {
    HStack(spacing: 12) {
        ForEach(RepelicanBuild.allCases) { build in
            VStack(spacing: 8) {
                RepelicanView(build: build)
                    .frame(width: 96, height: 110)
                Text(build.label).styled(.micro).foregroundStyle(Color.ink3)
            }
        }
    }
    .padding(24)
    .background(Color.bg)
    .preferredColorScheme(.dark)
}

private struct RepelicanSliderPreview: View {
    @State private var bulk = 0.55
    var body: some View {
        VStack(spacing: 20) {
            RepelicanView(bulk: bulk)
                .frame(width: 160, height: 190)
            Slider(value: $bulk, in: 0...1)
                .tint(Color.accent)
            Text(String(format: "bulk %.2f", bulk))
                .styled(.monoS).foregroundStyle(Color.ink2)
        }
        .padding(32)
        .background(Color.bg)
    }
}

#Preview("Bulk slider") {
    RepelicanSliderPreview().preferredColorScheme(.dark)
}
