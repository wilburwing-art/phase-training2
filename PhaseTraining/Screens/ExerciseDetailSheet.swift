// ExerciseDetailSheet.swift — read-only detail view for a single Exercise.
//
// Surfaces every field on `Exercise` that the rest of the app currently
// discards: description, instructions, cues, default sets/reps/rest,
// regression / progression text, and the compound / unilateral flags.
//
// Reachable from SubstituteExerciseSheet, CoachRequestScreen preview rows,
// LibraryScreen, and CustomRoutineEditSheet. Pure UI + DB reads — no
// mutations leave this view.
//
// The "Difficulty chain" section walks adjacent exercises by movement
// pattern + difficulty tier (CoachDatabase.adjacentByDifficulty). The chain
// is rendered as NavigationLinks so users can keep stepping easier/harder
// and back without losing place.

import SwiftUI

struct ExerciseDetailSheet: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ExerciseDetailContent(exercise: exercise)
            }
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationBackground(Color.bg)
    }
}

/// Inner content view — extracted so chain-navigation NavigationLinks can
/// push a new copy of the same UI without nesting NavigationStacks.
private struct ExerciseDetailContent: View {
    let exercise: Exercise

    /// Pre-curated substitutes from `exercise_substitutions`, loaded once
    /// per pushed instance. Ranked by similarity score. The DB query takes
    /// a recursive lock; per-render evaluation would be wasted churn.
    @State private var substitutes: [ExerciseSubstitute] = []

    /// Adjacent easier/harder peers by movement pattern + difficulty tier
    /// (CoachDatabase.adjacentByDifficulty). Cached once per pushed instance
    /// for the same reason as `substitutes` — see comment above.
    @State private var adjacency: (easier: Exercise?, harder: Exercise?) = (nil, nil)

    /// `(slug, role, label)` muscle relations feeding the anatomy
    /// silhouettes. Cached once per pushed instance alongside `substitutes`
    /// and `adjacency` — see comment above.
    @State private var muscles: [(slug: String, role: String, label: String)] = []

    var body: some View {
        let adj = adjacency
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metaBadges
                anatomySection
                heroImage
                if let desc = exercise.description, !desc.isEmpty {
                    section(title: "Overview") {
                        Text(desc)
                            .styled(.body)
                            .foregroundStyle(Color.ink2)
                    }
                }
                if let inst = exercise.instructions, !inst.isEmpty {
                    section(title: "How to") {
                        Text(inst)
                            .styled(.body)
                            .foregroundStyle(Color.ink2)
                    }
                }
                if !exercise.cues.isEmpty {
                    section(title: "Cues") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(exercise.cues, id: \.self) { cue in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("·")
                                        .font(.monoS)
                                        .foregroundStyle(Color.ink3)
                                    Text(cue)
                                        .styled(.body)
                                        .foregroundStyle(Color.ink2)
                                }
                            }
                        }
                    }
                }
                if hasDefaults {
                    section(title: "Defaults") {
                        defaultsGrid
                    }
                }
                watchDemoButton
                if hasFreeTextChain {
                    section(title: "Coach notes") {
                        freeTextChainRows
                    }
                }
                if !substitutes.isEmpty {
                    section(title: "Swaps") {
                        VStack(spacing: 8) {
                            ForEach(substitutes) { sub in
                                substituteLink(sub)
                            }
                        }
                    }
                }
                if adj.easier != nil || adj.harder != nil {
                    section(title: "Difficulty chain") {
                        VStack(spacing: 8) {
                            if let e = adj.easier {
                                chainLink(direction: .easier, peer: e)
                            }
                            if let h = adj.harder {
                                chainLink(direction: .harder, peer: h)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .onAppear {
            if substitutes.isEmpty {
                substitutes = CoachDatabase.shared.substitutes(forExerciseId: exercise.id)
            }
            if adjacency.easier == nil && adjacency.harder == nil {
                adjacency = CoachDatabase.shared.adjacentByDifficulty(forExerciseId: exercise.id)
            }
            if muscles.isEmpty {
                muscles = CoachDatabase.shared.musclesForExercise(exercise.id)
            }
        }
    }

    // MARK: - Anatomy

    /// Pair of front/back silhouettes with this exercise's primary /
    /// secondary / stabilizer muscles shaded. Sits below the meta-badge row
    /// and above the hero image; this is supplementary to (not a replacement
    /// for) the textual cue / instruction sections below. Hidden when the
    /// exercise has no muscle relations on file (mostly cardio / mobility).
    @ViewBuilder
    private var anatomySection: some View {
        if !muscles.isEmpty {
            let highlights = anatomyHighlights(from: muscles)
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 16) {
                    BodyAnatomyView(highlights: highlights, side: .front)
                        .frame(width: 120, height: 220)
                    BodyAnatomyView(highlights: highlights, side: .back)
                        .frame(width: 120, height: 220)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                anatomyLegend
            }
            .padding(.vertical, 4)
        }
    }

    private var anatomyLegend: some View {
        HStack(spacing: 14) {
            legendDot(color: BodyAnatomyView.HighlightIntensity.primary.color, label: "Primary")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func legendDot(color: Color?, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color ?? Color.ink3)
                .frame(width: 8, height: 8)
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
        }
    }

    /// Collapse the `(slug, role, label)` rows from CoachDatabase into the
    /// slug → intensity dict BodyAnatomyView consumes. Highest role wins
    /// when a single slug appears under multiple roles (shouldn't happen
    /// given the PK, but defensive).
    private func anatomyHighlights(
        from muscles: [(slug: String, role: String, label: String)]
    ) -> [String: BodyAnatomyView.HighlightIntensity] {
        var map: [String: BodyAnatomyView.HighlightIntensity] = [:]
        for row in muscles {
            // Only show primary muscles. Secondary + stabilizer were
            // accessory-group noise that Wilbur audited out 2026-05-25.
            guard row.role == "primary" else { continue }
            map[row.slug] = .primary
        }
        return map
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .styled(.displayM)
                .foregroundStyle(Color.ink)
            Text(metaLine)
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if exercise.modalityLabel != "—" { parts.append(exercise.modalityLabel) }
        if exercise.difficultyLabel != "—" { parts.append(exercise.difficultyLabel) }
        if let env = exercise.environment, !env.isEmpty {
            parts.append(env.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        return parts.joined(separator: " · ")
    }

    private var metaBadges: some View {
        WrappingFlow(spacing: 6) {
            if exercise.isCompound { badge("Compound") }
            if exercise.isUnilateral { badge("Unilateral") }
        }
    }

    @ViewBuilder
    private var watchDemoButton: some View {
        if let urlString = exercise.videoURL, let url = URL(string: urlString) {
            VStack(alignment: .leading, spacing: 6) {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Watch demo")
                            .font(.custom("SpaceGrotesk-SemiBold", size: 14))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.accentInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if let attr = exercise.sourceVideoAttribution, !attr.isEmpty {
                    Text(attr)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
    }

    @ViewBuilder
    private var heroImage: some View {
        if let urlString = exercise.imageURL, let url = URL(string: urlString) {
            VStack(alignment: .leading, spacing: 6) {
                CachedAsyncImage(
                    url: url,
                    loaded: { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                    },
                    placeholder: {
                        ZStack {
                            Color.elevated
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color.ink3)
                        }
                    },
                    failure: {
                        ZStack {
                            Color.elevated
                            VStack(spacing: 6) {
                                Image(systemName: "photo")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.ink3)
                                Text("Image unavailable")
                                    .font(.monoXS)
                                    .foregroundStyle(Color.ink3)
                            }
                        }
                    }
                )
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
                Text("Image: free-exercise-db")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
        }
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .styled(.micro)
            .foregroundStyle(Color.ink3)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            content()
        }
    }

    private var hasDefaults: Bool {
        exercise.defaultSets != nil
            || (exercise.defaultReps?.isEmpty == false)
            || (exercise.defaultRest?.isEmpty == false)
            || (exercise.defaultDuration?.isEmpty == false)
    }

    private var defaultsGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = exercise.defaultSets { defaultRow("Sets", "\(s)") }
            if let r = exercise.defaultReps, !r.isEmpty { defaultRow("Reps", r) }
            if let rest = exercise.defaultRest, !rest.isEmpty { defaultRow("Rest", rest) }
            if let d = exercise.defaultDuration, !d.isEmpty { defaultRow("Duration", d) }
        }
    }

    private func defaultRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Spacer()
            Text(value)
                .font(.monoS)
                .foregroundStyle(Color.ink)
        }
    }

    private var hasFreeTextChain: Bool {
        (exercise.regression?.isEmpty == false) || (exercise.progression?.isEmpty == false)
    }

    private var freeTextChainRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reg = exercise.regression, !reg.isEmpty {
                freeTextRow(arrow: "arrow.down", label: "Easier", value: reg)
            }
            if let prog = exercise.progression, !prog.isEmpty {
                freeTextRow(arrow: "arrow.up", label: "Harder", value: prog)
            }
        }
    }

    private func freeTextRow(arrow: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: arrow)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.ink3)
            Text(label.uppercased())
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Spacer(minLength: 6)
            Text(value)
                .styled(.body)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    private enum ChainDirection {
        case easier, harder
        var symbol: String { self == .easier ? "arrow.down" : "arrow.up" }
        var label: String { self == .easier ? String(localized: "EASIER", comment: "Substitute difficulty") : String(localized: "HARDER", comment: "Substitute difficulty") }
    }

    /// Mirrors `chainLink`'s NavigationLink-into-the-same-content pattern so
    /// substitutes are tappable and step into a fresh `ExerciseDetailContent`
    /// — same as the difficulty chain, no nested NavigationStack.
    private func substituteLink(_ sub: ExerciseSubstitute) -> some View {
        NavigationLink {
            ExerciseDetailContent(exercise: sub.exercise)
                .navigationTitle("Exercise")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(sub.exercise.name)
                            .styled(.body)
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Text("\(sub.matchPercent)%")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                    if !sub.contextLabels.isEmpty {
                        WrappingFlow(spacing: 4) {
                            ForEach(sub.contextLabels, id: \.self) { label in
                                Text(label)
                                    .font(.monoXS)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.bg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.line, lineWidth: 0.5)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(Color.ink3)
                            }
                        }
                    }
                    if let notes = sub.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink3)
                    .padding(.top, 2)
            }
            .padding(14)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exercise-substitute-\(sub.exercise.id)")
    }

    private func chainLink(direction: ChainDirection, peer: Exercise) -> some View {
        NavigationLink {
            ExerciseDetailContent(exercise: peer)
                .navigationTitle("Exercise")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: direction.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(direction.label)
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                    Text(peer.name)
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    Text(peer.difficultyLabel)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink3)
            }
            .padding(14)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
