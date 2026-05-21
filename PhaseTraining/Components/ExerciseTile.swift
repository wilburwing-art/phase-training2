// ExerciseTile.swift — the unified exercise row.
//
// One primitive, three slots — [LEADING][CONTENT][TRAILING]. Every screen
// that lists an exercise renders this shape; only the trailing slot varies
// per context (chevron / sets×reps / sparkline / controls / summary /
// duration). Replaces the 7 forked exerciseRow private funcs called out in
// HANDOFF-tile-system.md §1.
//
// Density variants:
//   .catalog (default) — 76pt min height, card chrome (surface + 0.5px line)
//   .compact           — 56pt min height, card chrome
//   .flat              — no chrome, used as a sibling inside TileList
//
// Spec ref: HANDOFF-tile-system.md §1. Tokens come from Theme/Theme.swift
// and Theme/Typography.swift — do not introduce new ones.

import SwiftUI

// MARK: - View model

struct ExerciseTileVM {
    enum Leading {
        case thumb(urlString: String?)
        case index(Int)
        case icon(systemName: String)
        case handle
        case none
    }

    enum Trailing {
        case chevron
        case setsReps(sets: Int, reps: Int, unit: String, lastWeight: Double?)
        case sparkline(points: [Double], pr: Bool)
        case controls(onInfo: () -> Void, onSwap: () -> Void)
        case summary(text: String, rpe: String?, isPR: Bool)
        case duration(String)
        case none
    }

    enum Emphasis { case none, accent }

    var leading: Leading
    var title: String
    var meta: String?
    var trailing: Trailing
    var emphasis: Emphasis = .none
    var onTap: (() -> Void)?
}

// MARK: - Density

enum TileDensity { case catalog, compact, flat }

// MARK: - Tile

struct ExerciseTile: View {
    let vm: ExerciseTileVM
    var density: TileDensity = .catalog

    var body: some View {
        let row = HStack(spacing: 12) {
            leadingView
            VStack(alignment: .leading, spacing: 3) {
                Text(vm.title)
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let meta = vm.meta {
                    Text(meta)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailingView
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(minHeight: minHeight, alignment: .center)
        .background(density == .flat ? Color.clear : surfaceFill)
        .overlay {
            if density != .flat {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 0.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: density == .flat ? 0 : 12))

        if let onTap = vm.onTap {
            Button(action: onTap) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    // MARK: layout tokens
    private var horizontalPadding: CGFloat { density == .flat ? 0 : 14 }
    private var verticalPadding: CGFloat {
        switch density {
        case .catalog: return 12
        case .compact: return 10
        case .flat:    return 0
        }
    }
    private var minHeight: CGFloat {
        switch density {
        case .catalog: return 76
        case .compact: return 56
        case .flat:    return 0
        }
    }
    private var surfaceFill: Color {
        vm.emphasis == .accent ? Color.accentWash : Color.surface
    }
    private var borderColor: Color {
        vm.emphasis == .accent ? Color.accentBorder : Color.line
    }

    // MARK: leading slot
    @ViewBuilder private var leadingView: some View {
        switch vm.leading {
        case .thumb(let url):
            ExerciseThumbnail(urlString: url, size: 48, cornerRadius: 8)

        case .index(let n):
            Text(String(format: "%02d", n))
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .foregroundStyle(Color.ink3)
                .monospacedDigit()
                .frame(width: 18, alignment: .leading)

        case .icon(let systemName):
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.line, lineWidth: 0.5)
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.accent)
            }
            .frame(width: 48, height: 48)

        case .handle:
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.ink3.opacity(0.7))
                .frame(width: 14, alignment: .center)

        case .none:
            EmptyView()
        }
    }

    // MARK: trailing slot
    @ViewBuilder private var trailingView: some View {
        switch vm.trailing {
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ink3)
                .padding(.leading, 4)

        case .setsReps(let sets, let reps, let unit, let lastWeight):
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(sets)×\(reps)")
                    .font(.custom("JetBrainsMono-Medium", size: 13))
                    .foregroundStyle(Color.ink)
                    .monospacedDigit()
                Text(lastWeight.map { "\(formattedWeight($0)) \(unit)" } ?? "—")
                    .font(.custom("JetBrainsMono-Regular", size: 10))
                    .foregroundStyle(Color.ink3)
                    .monospacedDigit()
            }
            .frame(minWidth: 72, alignment: .trailing)

        case .sparkline(let points, let pr):
            HStack(spacing: 8) {
                if pr { PRPill() }
                SparklineView(points: points)
                    .frame(width: 80, height: 28)
            }

        case .controls(let onInfo, let onSwap):
            HStack(spacing: 2) {
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ink2)
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Info")

                Button(action: onSwap) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.ink2)
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap")
            }

        case .summary(let text, let rpe, let isPR):
            VStack(alignment: .trailing, spacing: 3) {
                if isPR { PRPill() }
                Text(text)
                    .font(.custom("JetBrainsMono-Regular", size: 11))
                    .foregroundStyle(Color.ink2)
                    .monospacedDigit()
                if let rpe {
                    Text(rpe)
                        .font(.custom("JetBrainsMono-Regular", size: 10))
                        .foregroundStyle(Color.ink3)
                }
            }
            .frame(minWidth: 88, alignment: .trailing)

        case .duration(let value):
            Text(value)
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .monospacedDigit()

        case .none:
            EmptyView()
        }
    }

    private func formattedWeight(_ w: Double) -> String {
        w == w.rounded() ? String(Int(w)) : String(format: "%.1f", w)
    }
}

// MARK: - PR pill

struct PRPill: View {
    var body: some View {
        Text("PR")
            .font(.custom("JetBrainsMono-SemiBold", size: 9))
            .tracking(0.14 * 9)
            .foregroundStyle(Color.accentInk)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Sparkline

private struct SparklineView: View {
    let points: [Double] // normalized 0..1

    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2 else { return }
            var path = Path()
            for (i, v) in points.enumerated() {
                let x = CGFloat(i) / CGFloat(points.count - 1) * size.width
                let y = size.height - CGFloat(v) * size.height
                if i == 0 { path.move(to: .init(x: x, y: y)) }
                else { path.addLine(to: .init(x: x, y: y)) }
            }
            ctx.stroke(
                path,
                with: .color(.accent),
                style: .init(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            )
            if let last = points.last {
                let lx = size.width
                let ly = size.height - CGFloat(last) * size.height
                let dot = Path(ellipseIn: CGRect(x: lx - 2, y: ly - 2, width: 4, height: 4))
                ctx.fill(dot, with: .color(.accent))
            }
        }
    }
}

// MARK: - TileList — grouped card container
//
// Wraps tiles in .flat mode and draws the card chrome (surface + 0.5px line +
// 12pt radius) once. Optional eyebrow row at the top (micro label left, mono
// count right). Children get auto inter-row 0.5px lineSoft separators
// (inset 14pt from the leading edge, matching the in-row gutter).
//
// Uses SwiftUI's underscored _VariadicView API to introspect children — the
// public ForEach(subviews:) variant is iOS 18+ and the deployment target
// here is iOS 17. Stable since iOS 13.

struct TileList<Content: View>: View {
    let label: String?
    let count: Int?
    @ViewBuilder var content: () -> Content

    init(label: String? = nil, count: Int? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.count = count
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                HStack {
                    Text(label)
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                    if let count {
                        Text("\(count)")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            _VariadicView.Tree(TileListRows()) {
                content()
            }
        }
        .background(Color.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct TileListRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let arr = Array(children)
        VStack(spacing: 0) {
            ForEach(Array(arr.enumerated()), id: \.offset) { i, child in
                child
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                if i < arr.count - 1 {
                    Rectangle()
                        .fill(Color.lineSoft)
                        .frame(height: 0.5)
                        .padding(.leading, 14)
                }
            }
        }
    }
}

// MARK: - Preview — anatomy artboard

#Preview("Anatomy") {
    ScrollView {
        VStack(alignment: .leading, spacing: 28) {

            // 01 · ANATOMY
            VStack(alignment: .leading, spacing: 6) {
                Text("01 · ANATOMY")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Text("The Exercise Tile")
                    .styled(.displayM)
                    .foregroundStyle(Color.ink)
                Text("One primitive, three slots. Every screen renders the same shape — the trailing slot is what changes per context.")
                    .styled(.body)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The tile + slot labels
            VStack(alignment: .leading, spacing: 10) {
                ExerciseTile(vm: .init(
                    leading: .thumb(urlString: nil),
                    title: "Barbell bench press",
                    meta: "Barbell · Intermediate · Compound",
                    trailing: .chevron
                ))
                HStack(alignment: .top, spacing: 12) {
                    slotLabel(title: "LEADING", body: "48pt slot — thumb · index · icon · handle", width: 120)
                    slotLabel(title: "CONTENT", body: "Title (Inter 14/500) over meta (JBMono 11/400)", width: nil)
                    slotLabel(title: "TRAILING", body: "Per-context behavior. Replaces 7 forks.", width: 130)
                }
            }

            // Densities
            VStack(alignment: .leading, spacing: 10) {
                Text("DENSITIES")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)

                ExerciseTile(
                    vm: .init(
                        leading: .index(3),
                        title: "Seated DB shoulder press",
                        meta: "3×10 · last 45 lb",
                        trailing: .setsReps(sets: 3, reps: 10, unit: "lb", lastWeight: 45)
                    ),
                    density: .compact
                )
                ExerciseTile(vm: .init(
                    leading: .thumb(urlString: nil),
                    title: "Incline dumbbell press",
                    meta: "Dumbbell · Intermediate · Compound",
                    trailing: .chevron
                ))
                ExerciseTile(vm: .init(
                    leading: .none,
                    title: "Barbell back squat",
                    meta: "Advanced · Compound · 245 lb PR",
                    trailing: .sparkline(points: [0.3, 0.4, 0.45, 0.55, 0.7, 0.85, 0.95], pr: true)
                ))

                HStack {
                    Text("COMPACT · 56pt").styled(.micro).foregroundStyle(Color.ink3)
                    Spacer()
                    Text("CATALOG · 76pt").styled(.micro).foregroundStyle(Color.ink3)
                    Spacer()
                    Text("CATALOG · 76pt").styled(.micro).foregroundStyle(Color.ink3)
                }
            }

            // Trailing slot library
            VStack(alignment: .leading, spacing: 10) {
                Text("02 · TRAILING SLOT LIBRARY")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Text("One tile, six behaviors")
                    .styled(.displayM)
                    .foregroundStyle(Color.ink)

                ExerciseTile(vm: .init(
                    leading: .index(1),
                    title: "Barbell bench press",
                    meta: "rest 180s · last 185 lb",
                    trailing: .setsReps(sets: 4, reps: 6, unit: "lb", lastWeight: 185)
                ))
                ExerciseTile(vm: .init(
                    leading: .index(1),
                    title: "Barbell bench press",
                    meta: "4×6 · rest 180s",
                    trailing: .controls(onInfo: {}, onSwap: {})
                ))
                ExerciseTile(vm: .init(
                    leading: .handle,
                    title: "Barbell bench press",
                    meta: "4×6 · rest 180s",
                    trailing: .duration("drag to reorder")
                ))
                ExerciseTile(vm: .init(
                    leading: .index(1),
                    title: "Barbell bench press",
                    meta: "4 sets · 4:32",
                    trailing: .summary(
                        text: "185×6 · 185×6 · 195×4 · 195×3",
                        rpe: "rpe 8.5",
                        isPR: true
                    )
                ))
                ExerciseTile(vm: .init(
                    leading: .icon(systemName: "figure.strengthtraining.traditional"),
                    title: "Push pull legs",
                    meta: "Custom routine · 7 exercises",
                    trailing: .chevron,
                    emphasis: .accent
                ))
            }

            // TileList grouped container
            VStack(alignment: .leading, spacing: 10) {
                Text("03 · TILELIST")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Text("Grouped card container")
                    .styled(.displayM)
                    .foregroundStyle(Color.ink)

                TileList(label: "TODAY'S EXERCISES", count: 3) {
                    ExerciseTile(
                        vm: .init(
                            leading: .index(1),
                            title: "Barbell bench press",
                            meta: "rest 180s · last 185 lb",
                            trailing: .setsReps(sets: 4, reps: 6, unit: "lb", lastWeight: 185)
                        ),
                        density: .flat
                    )
                    ExerciseTile(
                        vm: .init(
                            leading: .index(2),
                            title: "Incline DB press",
                            meta: "rest 120s · last 60 lb",
                            trailing: .setsReps(sets: 3, reps: 8, unit: "lb", lastWeight: 60)
                        ),
                        density: .flat
                    )
                    ExerciseTile(
                        vm: .init(
                            leading: .index(3),
                            title: "Tricep rope pushdown",
                            meta: "rest 60s · last 47.5 lb",
                            trailing: .setsReps(sets: 3, reps: 12, unit: "lb", lastWeight: 47.5)
                        ),
                        density: .flat
                    )
                }
            }
        }
        .padding(20)
    }
    .background(Color.bg.ignoresSafeArea())
    .preferredColorScheme(.dark)
}

// Small helper used only by the preview above.
private func slotLabel(title: String, body: String, width: CGFloat?) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .styled(.micro)
            .foregroundStyle(Color.accent)
        Text(body)
            .font(.custom("JetBrainsMono-Regular", size: 10))
            .foregroundStyle(Color.ink3)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
    .frame(width: width, alignment: .leading)
}
