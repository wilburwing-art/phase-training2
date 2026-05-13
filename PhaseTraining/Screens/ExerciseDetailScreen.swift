// ExerciseDetailScreen.swift — Info card for a single exercise from coach.db.
// Reference: design handoff exercise-detail.jsx (variation A).
// History-bar tab is omitted: this slice has no logged history per exercise yet.
// "Add to workout" is shown only when reached via the picker in :add mode.

import SwiftUI

struct ExerciseDetailScreen: View {
    let exercise: Exercise
    let canAdd: Bool

    let onBack: () -> Void
    let onAdd: (() -> Void)?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        heroPlaceholder
                            .padding(.horizontal, 20)
                            .padding(.top, 18)

                        meta
                            .padding(.horizontal, 20)
                            .padding(.top, 18)

                        titleBlock
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        metaPills
                            .padding(.horizontal, 20)
                            .padding(.top, 14)

                        statRow
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                        if !exercise.cues.isEmpty {
                            formCues
                                .padding(.horizontal, 20)
                                .padding(.top, 28)
                        }

                        if let desc = exercise.description, !desc.isEmpty {
                            descriptionBlock(desc)
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                        }

                        if let prog = exercise.progression, !prog.isEmpty {
                            progressionBlock
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                        }

                        Spacer().frame(height: canAdd ? 140 : 60)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if canAdd {
                addButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
        .foregroundStyle(Color.ink)
        .preferredColorScheme(.dark)
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                        Text("Back")
                            .font(.custom("SpaceGrotesk-Medium", size: 15))
                    }
                    .foregroundStyle(Color.ink)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(exercise.modalityLabel.uppercased())
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Rectangle().fill(Color.line).frame(height: 0.5)
        }
    }

    // MARK: - Hero placeholder (no video assets bundled yet)

    private var heroPlaceholder: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.surface)
                .overlay(stripes)
                .overlay(
                    RoundedRectangle(cornerRadius: 20).stroke(Color.line, lineWidth: 0.5)
                )

            HStack {
                Text("DEMO · PLACEHOLDER")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
            }
            .padding(16)
        }
        .frame(height: 180)
    }

    private var stripes: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let stride: CGFloat = 12
                var x: CGFloat = -size.height
                while x < size.width {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    p.addLine(to: CGPoint(x: x + size.height + 4, y: size.height))
                    p.addLine(to: CGPoint(x: x + 4, y: 0))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(Color.white.opacity(0.04)))
                    x += stride
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Meta eyebrow

    private var meta: some View {
        let label = [exercise.isCompound ? "COMPOUND" : "ISOLATION",
                     exercise.isUnilateral ? "UNILATERAL" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
        return Text(label)
            .styled(.micro)
            .foregroundStyle(Color.ink3)
    }

    private var titleBlock: some View {
        Text(exercise.name)
            .font(.custom("SpaceGrotesk-SemiBold", size: 38))
            .tracking(-0.025 * 38)
            .foregroundStyle(Color.ink)
            .lineSpacing(-2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Meta pills

    private var metaPills: some View {
        HStack(spacing: 8) {
            if let env = exercise.environment {
                pill(env.capitalized)
            }
            pill(exercise.modalityLabel)
            pill(exercise.difficultyLabel)
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.custom("JetBrainsMono-Medium", size: 10))
            .tracking(0.06 * 10)
            .foregroundStyle(Color.ink2)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .overlay(
                Capsule().stroke(Color.line, lineWidth: 0.5)
            )
    }

    // MARK: - Stat row

    private var statRow: some View {
        HStack(spacing: 8) {
            statCard(key: "SETS",
                     value: exercise.defaultSets.map(String.init) ?? "—",
                     sub: "default")
            statCard(key: "REPS",
                     value: exercise.defaultReps ?? "—",
                     sub: "default")
            statCard(key: "REST",
                     value: exercise.defaultRest ?? "—",
                     sub: "default")
        }
    }

    private func statCard(key: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .tracking(0.06 * 10)
                .foregroundStyle(Color.ink3)
            Text(value)
                .font(.custom("SpaceGrotesk-SemiBold", size: 22))
                .tracking(-0.02 * 22)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 2)
            Text(sub)
                .font(.custom("JetBrainsMono-Regular", size: 10))
                .tracking(0.04 * 10)
                .foregroundStyle(Color.ink3)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Form cues

    private var formCues: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FORM CUES")
                    .styled(.micro)
                    .foregroundStyle(Color.ink2)
                Spacer()
            }
            .padding(.bottom, 8)

            ForEach(Array(exercise.cues.enumerated()), id: \.offset) { idx, cue in
                HStack(alignment: .top, spacing: 14) {
                    Text(String(format: "%02d", idx + 1))
                        .font(.custom("JetBrainsMono-Medium", size: 11))
                        .foregroundStyle(Color.accent)
                        .frame(width: 22, alignment: .leading)
                    Text(cue)
                        .font(.custom("Inter-Regular", size: 14))
                        .foregroundStyle(Color.ink)
                        .lineSpacing(2)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                if idx < exercise.cues.count - 1 {
                    Rectangle().fill(Color.line).frame(height: 0.5)
                }
            }
        }
    }

    // MARK: - Description / progression

    private func descriptionBlock(_ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DESCRIPTION")
                .styled(.micro)
                .foregroundStyle(Color.ink2)
            Text(desc)
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(Color.ink2)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROGRESSION")
                .styled(.micro)
                .foregroundStyle(Color.ink2)
            if let prog = exercise.progression {
                Text(prog)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink2)
                    .lineSpacing(2)
            }
            if let reg = exercise.regression {
                Text("REGRESSION")
                    .styled(.micro)
                    .foregroundStyle(Color.ink2)
                    .padding(.top, 8)
                Text(reg)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink2)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Add CTA

    private var addButton: some View {
        Button(action: { onAdd?() }) {
            HStack(spacing: 6) {
                Text("Add to workout")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
