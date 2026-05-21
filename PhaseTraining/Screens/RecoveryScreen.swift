// RecoveryScreen.swift — the "Body" tab.
//
// Top: a body silhouette (BodyAnatomyView) where each muscle is shaded by
// its freshness — red = needs recovery, gray = fresh. The user can flip
// between front/back via a corner button. Above the silhouette: two big
// stats (days since last workout / N fresh muscle groups).
//
// Bottom: a sectioned list of muscles ("MAIN" / "ACCESSORY") with a small
// 60pt body thumbnail per row (focused on just that muscle), label, and
// "X days" / "no recent exercises" subtitle.
//
// The freshness model + slug→intensity mapping live in MuscleFreshness;
// the silhouette renderer lives in BodyAnatomyView. This screen is the
// composition layer.

import SwiftUI

struct RecoveryScreen: View {
    @EnvironmentObject private var store: SessionStore

    /// Front / back toggle for the big body silhouette. Default to back —
    /// the screenshot reference + most lifting routines hammer posterior
    /// chain, so the back view is more interesting day-to-day.
    @State private var side: BodyAnatomyView.AnatomySide = .back

    /// Selected mode at the top — Recovery (default) or Results. Results is
    /// stubbed in this first pass: it points back to the Progress tab's
    /// muscle-balance card concept and reads the same volume rollup, but
    /// the heavy chart UI lives there. Keeping the toggle here so the
    /// shape matches the reference screenshot.
    @State private var mode: Mode = .recovery

    enum Mode: String, CaseIterable, Identifiable {
        case recovery = "Recovery"
        case results  = "Results"
        var id: String { rawValue }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        let rows = MuscleFreshness.rows(from: store.savedSessions)
        let highlights = recoveryHighlights(from: rows)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TabHeader(
                    eyebrow: "BODY",
                    eyebrowTrailing: nil,
                    title: "Recovery",
                    subtitle: nil
                )
                .padding(.horizontal, -20)

                modeToggle
                topStats(rows: rows)
                bodySilhouette(highlights: highlights)
                muscleSections(rows: rows)

                Spacer().frame(height: 60)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Mode toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach(Mode.allCases) { m in
                Button {
                    mode = m
                } label: {
                    Text(m.rawValue.uppercased())
                        .styled(.micro)
                        .foregroundStyle(m == mode ? Color.accentInk : Color.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(m == mode ? Color.accent : Color.surface)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Top stats

    private func topStats(rows: [MuscleFreshness.Row]) -> some View {
        let daysSince = daysSinceLastWorkout()
        let freshCount = rows.filter { $0.freshness >= 1.0 }.count
        return HStack(spacing: 8) {
            statBlock(
                value: daysSince.map { "\($0)" } ?? "—",
                unit: daysSince == 1 ? "DAY" : "DAYS",
                label: "SINCE LAST WORKOUT"
            )
            statBlock(
                value: "\(freshCount)",
                unit: nil,
                label: "FRESH MUSCLE GROUPS"
            )
        }
    }

    private func statBlock(value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.custom("SpaceGrotesk-SemiBold", size: 32))
                    .tracking(-0.025 * 32)
                    .foregroundStyle(Color.ink)
                if let unit {
                    Text(unit)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Body silhouette

    private func bodySilhouette(
        highlights: [String: BodyAnatomyView.HighlightIntensity]
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack {
                BodyAnatomyView(highlights: highlights, side: side)
                    .frame(height: 360)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                side = (side == .front) ? .back : .front
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .padding(10)
                    .background(Color.elevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel(side == .front ? "Show back view" : "Show front view")
        }
    }

    // MARK: - Sections

    private func muscleSections(rows: [MuscleFreshness.Row]) -> some View {
        let main = rows.filter { Self.mainSlugs.contains($0.slug) }
            .sorted { $0.freshness < $1.freshness }
        let accessory = rows.filter { !Self.mainSlugs.contains($0.slug) }
            .sorted { $0.freshness < $1.freshness }

        return VStack(alignment: .leading, spacing: 24) {
            if !main.isEmpty {
                muscleSection(title: "MAIN MUSCLE GROUPS", rows: main)
            }
            if !accessory.isEmpty {
                muscleSection(title: "ACCESSORY MUSCLE GROUPS", rows: accessory)
            }
        }
    }

    private func muscleSection(title: String, rows: [MuscleFreshness.Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .padding(.bottom, 4)
            VStack(spacing: 6) {
                ForEach(rows, id: \.slug) { row in
                    muscleRow(row: row)
                }
            }
        }
    }

    private func muscleRow(row: MuscleFreshness.Row) -> some View {
        HStack(spacing: 12) {
            // Tiny silhouette focused on just this muscle. Render whichever
            // side is currently selected — keeps the row in sync with the
            // big silhouette above.
            BodyAnatomyView(
                highlights: [row.slug: .primary],
                side: side
            )
            .frame(width: 36, height: 64)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                Text(subtitleFor(row: row))
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }

            Spacer()

            Text("\(Int((row.freshness * 100).rounded()))%")
                .font(.monoXS)
                .foregroundStyle(freshnessColor(row.freshness))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func subtitleFor(row: MuscleFreshness.Row) -> String {
        guard let days = row.daysSinceLastWorked else {
            return "No recent exercises"
        }
        if days == 0 { return "Trained today" }
        if days == 1 { return "1 day ago" }
        return "\(days) days ago"
    }

    private func freshnessColor(_ f: Double) -> Color {
        if f >= 1.0 { return Color.ok }
        if f < 0.33 { return Color.danger }
        if f < 0.66 { return Color(red: 0.95, green: 0.61, blue: 0.07) }   // #F39C12
        return Color(red: 0.95, green: 0.77, blue: 0.06)                    // #F1C40F
    }

    // MARK: - Helpers

    private func recoveryHighlights(
        from rows: [MuscleFreshness.Row]
    ) -> [String: BodyAnatomyView.HighlightIntensity] {
        if mode == .recovery {
            var out: [String: BodyAnatomyView.HighlightIntensity] = [:]
            for row in rows where row.intensity != .none {
                out[row.slug] = row.intensity
            }
            return out
        } else {
            // Results mode (stub): highlight the muscles that have been
            // trained at all in the last 14 days — same volume-rollup
            // intent as the Progress muscle-balance card, in the
            // body-silhouette format.
            let volumes = MuscleVolume.rows(from: store.savedSessions, weeks: 2, limit: 20)
            guard let max = volumes.first?.volume, max > 0 else { return [:] }
            var out: [String: BodyAnatomyView.HighlightIntensity] = [:]
            for row in volumes {
                let frac = row.volume / max
                if frac > 0.66 { out[row.slug] = .primary }
                else if frac > 0.33 { out[row.slug] = .secondary }
                else if frac > 0 { out[row.slug] = .tertiary }
            }
            return out
        }
    }

    private func daysSinceLastWorkout() -> Int? {
        guard let last = store.savedSessions.map(\.startTime).max() else { return nil }
        let seconds = Date().timeIntervalSince(last)
        return max(0, Int((seconds / 86_400).rounded(.down)))
    }

    // MARK: - Section taxonomy

    /// "Main" muscle groups the average lifter cares about day-to-day —
    /// these get top billing. Everything else falls to "Accessory" (calves,
    /// forearms, grip, neck, rotator-cuff, etc.) Order here mirrors the
    /// screenshot reference: chest, back, shoulders, arms, core, lower body.
    static let mainSlugs: Set<String> = [
        "chest", "pec-major-clav", "pec-major-sternal",
        "lats", "rhomboids", "erector-thoracic",
        "shoulders", "delt-anterior", "delt-lateral", "delt-posterior",
        "biceps", "triceps",
        "rectus-abdominis", "external-obliques", "internal-obliques",
        "quadriceps", "hamstrings", "glutes",
        "erector-lumbar",
    ]
}

// MARK: - Preview

#Preview("Recovery") {
    RecoveryScreen()
        .environmentObject(SessionStore(defaults: UserDefaults(suiteName: "RecoveryScreen.preview")!))
}
