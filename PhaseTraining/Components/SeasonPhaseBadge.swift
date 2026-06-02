// SeasonPhaseBadge.swift — the missing namesake-on-screen.
//
// SeasonPhase drives the planner (TrainingMemory.seasonForPlanner) and is the
// pitch of the entire app, but before build 103 the user only saw it inside
// the Profile editor and weekly check-in. Today / Progress / Week now render
// this badge so "you're in Pre-Season, week 3" is visible wherever the
// user lands.
//
// The badge is tap-to-edit: a tap pops the existing SeasonsEditorSheet.
// Variants tune density per surface — `.compact` for inline header strips,
// `.full` for the row-style placement Today + Progress use.
//
// No new data: reads everything off TrainingMemory.seasonForPlanner plus the
// build-103 phaseStartedAt + peakDate fields. When peak is set and the phase
// is .eventPrep, the meta string becomes a countdown ("T-21d to peak")
// instead of the week counter.

import SwiftUI

struct SeasonPhaseBadge: View {
    enum Style {
        /// Inline 1-line pill for header strips (Week tab).
        case compact
        /// Full row with phase + meta + chevron for Today/Progress.
        case full
    }

    @EnvironmentObject private var memory: MemoryStore
    @State private var presentingEditor = false

    var style: Style = .full
    /// Surface the badge is placed on ("today" / "progress" / "week"). Keeps
    /// the accessibility identifier unique per instance so a UI test (or a
    /// layout that ever stacks two badges) can't get an ambiguous match.
    var surface: String = "today"

    var body: some View {
        Button { presentingEditor = true } label: {
            switch style {
            case .compact: compactBody
            case .full:    fullBody
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("season-phase-badge-\(surface)")
        .accessibilityLabel(accessibilityLabel)
        .sheet(isPresented: $presentingEditor) {
            SeasonsEditorSheet().environmentObject(memory)
        }
    }

    // MARK: - Full row (Today / Progress)

    private var fullBody: some View {
        HStack(spacing: 12) {
            phaseGlyph
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(phaseLabel.uppercased())
                        .styled(.micro)
                        .foregroundStyle(Color.accent)
                    if let sportLabel {
                        Text("·")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        Text(sportLabel.uppercased())
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                            .lineLimit(1)
                    }
                    if !mesoStatus.badge.isEmpty {
                        Spacer(minLength: 4)
                        Text(mesoStatus.badge)
                            .styled(.micro)
                            .foregroundStyle(deloadTint(mesoStatus.state, fg: true))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(deloadTint(mesoStatus.state, fg: false))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(metaLine)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.ink3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderTintForDeload, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Bump the border to the warning tint when we're inside a deload-
    /// adjacent week so the user sees it from across the screen, not just
    /// when reading the meta text.
    private var borderTintForDeload: Color {
        switch mesoStatus.state {
        case .deload, .taper, .peak: return Color.danger.opacity(0.4)
        case .deloadNextWeek:        return Color.accentBorder
        default:                     return Color.accentBorder
        }
    }

    private func deloadTint(_ state: MesocycleProgression.DeloadState, fg: Bool) -> Color {
        switch state {
        case .deload, .taper, .peak:
            return fg ? Color.accentInk : Color.danger.opacity(0.85)
        case .deloadNextWeek:
            return fg ? Color.accentInk : Color.accent
        default:
            return fg ? Color.ink3 : Color.elevated
        }
    }

    // MARK: - Compact pill (Week tab header)

    private var compactBody: some View {
        HStack(spacing: 4) {
            Image(systemName: phaseIcon)
                .font(.system(size: 10, weight: .medium))
            Text(compactLabel)
                .font(.monoXS)
        }
        .foregroundStyle(compactTint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(compactBg)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(compactBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Compact-pill tint matrix — same warning gradient as the full row.
    /// Deload-adjacent weeks bump foreground to danger and background to a
    /// matching wash so the Week tab header reads "this is the deload" at
    /// a glance.
    private var compactTint: Color {
        switch mesoStatus.state {
        case .deload, .taper, .peak: return Color.danger
        default:                     return Color.accent
        }
    }

    private var compactBg: Color {
        switch mesoStatus.state {
        case .deload, .taper, .peak: return Color.danger.opacity(0.08)
        default:                     return Color.accentWash
        }
    }

    private var compactBorder: Color {
        switch mesoStatus.state {
        case .deload, .taper, .peak: return Color.danger.opacity(0.35)
        default:                     return Color.accentBorder
        }
    }

    // MARK: - Glyph

    private var phaseGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentWash)
            Image(systemName: phaseIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accent)
        }
    }

    // MARK: - Derived strings

    private var phase: SeasonPhase { memory.memory.seasonForPlanner }

    private var phaseLabel: String { phase.label }

    /// Primary sport name when the phase is per-sport, nil otherwise. We
    /// only show this when there's a primary sport AND an explicit per-
    /// sport entry that's different from the default — otherwise we'd
    /// repeat the default with no extra signal.
    private var sportLabel: String? {
        guard let s = memory.memory.primarySport,
              memory.memory.seasonsBySport[s] != nil else { return nil }
        return s.name
    }

    /// Mesocycle state — drives the deload/taper warning treatment.
    private var mesoStatus: MesocycleProgression.Status {
        MesocycleProgression.status(
            phase: phase,
            weeksInPhase: memory.memory.weeksInCurrentPhase,
            daysUntilPeak: memory.memory.daysUntilPeak
        )
    }

    /// Compact text — "Pre-season · DELOAD NEXT" or "Pre-season · wk 3".
    /// The deload-adjacent variants win the trailing segment so the user
    /// sees the warning even in the tightest pill placement.
    ///
    /// The "wk N" number is the CYCLE-relative week (mesoStatus.weekOfCycle),
    /// matching the full-row meta's "Week N of M" — so the same badge never
    /// shows two different week numbers across surfaces. Falls back to the
    /// absolute weeks-in-phase only for off-cycle phases (maintenance), where
    /// there's no cycle week and the meta shows no number either.
    private var compactLabel: String {
        switch mesoStatus.state {
        case .deload:           return "\(phase.label) · DELOAD"
        case .deloadNextWeek:   return "\(phase.label) · deload next"
        case .taper:            return "\(phase.label) · TAPER"
        case .peak:             return "\(phase.label) · PEAK"
        default:
            if let week = badgeWeekNumber {
                return "\(phase.label) · wk \(week)"
            }
            return phase.label
        }
    }

    /// Single source for the week number shown anywhere on the badge: the
    /// cycle-relative week when a cycle is running, else the absolute
    /// weeks-in-phase (off-cycle phases only).
    private var badgeWeekNumber: Int? {
        mesoStatus.weekOfCycle ?? memory.memory.weeksInCurrentPhase
    }

    /// Multi-line meta. MesocycleProgression owns the copy so the rule and
    /// the message stay in lockstep — change the cycle length there once
    /// and every surface re-reads consistently.
    private var metaLine: String {
        mesoStatus.detail
    }

    private var phaseIcon: String {
        switch phase {
        case .offSeason:   return "snowflake"
        case .preSeason:   return "leaf"
        case .inSeason:    return "flame"
        case .eventPrep:   return "flag.checkered"
        case .maintenance: return "infinity"
        }
    }

    private var accessibilityLabel: String {
        // Use the same cycle-relative week the visible text shows so VoiceOver
        // and the pill never disagree.
        if let week = badgeWeekNumber {
            return "\(phase.label), week \(week). Tap to edit."
        }
        return "\(phase.label). Tap to edit."
    }
}

#Preview("Full · maintenance") {
    let defaults = UserDefaults(suiteName: "SeasonPhaseBadge.preview.full")!
    let store = MemoryStore(defaults: defaults)
    store.update { mem in
        mem.defaultSeason = .maintenance
        mem.phaseStartedAt = Calendar.current.date(byAdding: .day, value: -14, to: Date())
    }
    return SeasonPhaseBadge(style: .full)
        .environmentObject(store)
        .padding()
        .background(Color.bg)
        .preferredColorScheme(.dark)
}

#Preview("Full · event prep") {
    let defaults = UserDefaults(suiteName: "SeasonPhaseBadge.preview.eventPrep")!
    let store = MemoryStore(defaults: defaults)
    store.update { mem in
        mem.defaultSeason = .eventPrep
        mem.peakDate = Calendar.current.date(byAdding: .day, value: 21, to: Date())
        mem.phaseStartedAt = Calendar.current.date(byAdding: .day, value: -7, to: Date())
    }
    return SeasonPhaseBadge(style: .full)
        .environmentObject(store)
        .padding()
        .background(Color.bg)
        .preferredColorScheme(.dark)
}

#Preview("Compact") {
    let defaults = UserDefaults(suiteName: "SeasonPhaseBadge.preview.compact")!
    let store = MemoryStore(defaults: defaults)
    store.update { mem in
        mem.defaultSeason = .preSeason
        mem.phaseStartedAt = Calendar.current.date(byAdding: .day, value: -21, to: Date())
    }
    return SeasonPhaseBadge(style: .compact)
        .environmentObject(store)
        .padding()
        .background(Color.bg)
        .preferredColorScheme(.dark)
}
