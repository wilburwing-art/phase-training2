// ProgressRecoverySection.swift — full recovery view, embedded on Progress.
//
// Lives alongside the existing muscleBalanceCard / strengthRatiosCard /
// prFeedCard on ProgressScreen. The full body silhouette + per-muscle
// freshness list lived in RecoveryScreen (a separate Body tab) before the
// IA rework; consolidated here so muscle data has one home.

import SwiftUI

struct ProgressRecoverySection: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var memoryStore: MemoryStore

    /// Front / back toggle for the big body silhouette. Back default —
    /// most lifting hammers posterior chain, so back is more interesting
    /// day-to-day.
    @State private var side: BodyAnatomyView.AnatomySide = .back

    var body: some View {
        let rows = MuscleFreshness.rows(from: store.savedSessions)
        let highlights = recoveryHighlights(from: rows)
        VStack(alignment: .leading, spacing: 12) {
            Text("RECOVERY")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            topStats(rows: rows)
            bodySilhouette(highlights: highlights)
            muscleSections(rows: rows)
        }
    }

    // MARK: - Top stats

    private func topStats(rows: [MuscleFreshness.Row]) -> some View {
        let daysSince = Self.daysSinceLastWorkout(sessions: store.savedSessions)
        let freshCount = Self.freshMainMuscleCount(rows: rows)
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
                BodyAnatomyView(highlights: highlights, side: side,
                                bodyGender: memoryStore.memory.gender ?? .male)
                    .frame(height: 320)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
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
        // Show only main muscle groups — accessory groups were noisy without
        // adding useful per-session decisions. Wilbur audit 2026-05-25.
        let main = rows.filter { Self.mainSlugs.contains($0.slug) }
            .sorted { $0.freshness < $1.freshness }

        return VStack(alignment: .leading, spacing: 16) {
            if !main.isEmpty {
                muscleSection(title: "MUSCLE GROUPS", rows: main)
            }
        }
    }

    private func muscleSection(title: String, rows: [MuscleFreshness.Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .padding(.top, 8)
            VStack(spacing: 6) {
                ForEach(rows, id: \.slug) { row in
                    muscleRow(row: row)
                }
            }
        }
    }

    private func muscleRow(row: MuscleFreshness.Row) -> some View {
        HStack(spacing: 12) {
            // Each thumbnail shows the side its OWN muscle is on, not the
            // screen-wide toggle. With the shared toggle (defaulting to .back)
            // every anterior row — Quadriceps, Chest, Anterior Delt, Rectus
            // Abdominis, Biceps — rendered a back silhouette with nothing
            // highlighted, i.e. a blank body beside most of the list, and
            // flipping the toggle just blanked the posterior rows instead.
            BodyAnatomyView(
                highlights: [row.slug: .primary],
                side: Self.side(forSlug: row.slug) ?? side,
                bodyGender: memoryStore.memory.gender ?? .male
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
        Self.subtitle(for: row)
    }

    private func freshnessColor(_ f: Double) -> Color {
        if f >= 1.0 { return Color.ok }
        if f < 0.33 { return Color.danger }
        if f < 0.66 { return Color(red: 0.95, green: 0.61, blue: 0.07) }
        return Color(red: 0.95, green: 0.77, blue: 0.06)
    }

    // MARK: - Helpers

    private func recoveryHighlights(
        from rows: [MuscleFreshness.Row]
    ) -> [String: BodyAnatomyView.HighlightIntensity] {
        Self.highlights(from: rows)
    }

    // MARK: - Pure section math
    //
    // Statics, not instance methods, so ProgressRecoverySectionTests can
    // reach them — the section had no coverage at all, including the
    // freshMainMuscleCount filter that fixed a headline reading 70+.

    /// The "FRESH MUSCLE GROUPS" headline.
    ///
    /// Counts the SAME rows the list below renders. It once counted all 80
    /// muscle_groups rows — including muscles never trained, which default to
    /// freshness 1.0 — while the list was filtered to `mainSlugs`. The
    /// headline routinely read 70+ and was unrelated to what it labelled.
    static func freshMainMuscleCount(rows: [MuscleFreshness.Row]) -> Int {
        rows.filter { mainSlugs.contains($0.slug) && $0.freshness >= 1.0 }.count
    }

    /// Silhouette highlight map. Fresh muscles (`.none`) are omitted rather
    /// than passed through, so the body renders unpainted where there's
    /// nothing to warn about.
    static func highlights(
        from rows: [MuscleFreshness.Row]
    ) -> [String: BodyAnatomyView.HighlightIntensity] {
        var out: [String: BodyAnatomyView.HighlightIntensity] = [:]
        for row in rows where row.intensity != .none {
            out[row.slug] = row.intensity
        }
        return out
    }

    /// Whole calendar days since the most recent session STARTED. Nil with no
    /// history. Clamped at 0 so a future-dated session (an import, or a clock
    /// change) reads "0 days" rather than a negative headline.
    static func daysSinceLastWorkout(sessions: [SavedSession],
                                     now: Date = Date(),
                                     calendar: Calendar = .current) -> Int? {
        guard let last = sessions.map(\.startTime).max() else { return nil }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: last),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, days)
    }

    /// Per-muscle row subtitle.
    static func subtitle(for row: MuscleFreshness.Row) -> String {
        guard let days = row.daysSinceLastWorked else {
            return "No recent exercises"
        }
        if days == 0 { return "Trained today" }
        if days == 1 { return "1 day ago" }
        return "\(days) days ago"
    }

    /// Which silhouette actually shows a given muscle. nil = visible from
    /// either side (or not worth forcing), so the caller's toggle stands.
    /// Covers exactly `mainSlugs`, the only rows the list renders.
    static func side(forSlug slug: String) -> BodyAnatomyView.AnatomySide? {
        switch slug {
        case "chest", "pec-major-clav", "pec-major-sternal",
             "delt-anterior", "biceps",
             "rectus-abdominis", "external-obliques", "internal-obliques",
             "quadriceps":
            return .front
        case "lats", "rhomboids", "erector-thoracic", "erector-lumbar",
             "delt-posterior", "triceps", "hamstrings", "glutes":
            return .back
        default:
            return nil   // shoulders / delt-lateral read on both
        }
    }

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

#Preview("Progress recovery section") {
    ScrollView {
        ProgressRecoverySection()
            .padding(20)
    }
    .background(Color.bg)
    .environmentObject(SessionStore(defaults: UserDefaults(suiteName: "ProgressRecoverySection.preview")!))
    .preferredColorScheme(.dark)
}
