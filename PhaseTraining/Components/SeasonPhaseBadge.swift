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

    var body: some View {
        Button { presentingEditor = true } label: {
            switch style {
            case .compact: compactBody
            case .full:    fullBody
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("season-phase-badge")
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
                .stroke(Color.accentBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Compact pill (Week tab header)

    private var compactBody: some View {
        HStack(spacing: 4) {
            Image(systemName: phaseIcon)
                .font(.system(size: 10, weight: .medium))
            Text(compactLabel)
                .font(.monoXS)
        }
        .foregroundStyle(Color.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentWash)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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

    /// Compact text — "Pre-season · wk 3" or "Pre-season".
    private var compactLabel: String {
        if let weeks = memory.memory.weeksInCurrentPhase {
            return "\(phase.label) · wk \(weeks)"
        }
        return phase.label
    }

    /// Multi-line meta. For .eventPrep we prefer a peak countdown; for
    /// everything else we show the week counter + phase subtitle.
    private var metaLine: String {
        if phase == .eventPrep, let days = memory.memory.daysUntilPeak {
            if days > 0 {
                return "T-\(days)d to peak. \(phase.subtitle)"
            } else if days == 0 {
                return "Peak day. \(phase.subtitle)"
            } else {
                return "Peak passed \(-days)d ago. \(phase.subtitle)"
            }
        }
        if let weeks = memory.memory.weeksInCurrentPhase {
            return "Week \(weeks) · \(phase.subtitle)"
        }
        return phase.subtitle
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
        if let weeks = memory.memory.weeksInCurrentPhase {
            return "\(phase.label), week \(weeks). Tap to edit."
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
