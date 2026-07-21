//
//  RepelicanPhaseCard.swift
//  PhaseTraining
//
//  "Physique tracks your phase" — the Today-surface home of the mascot. The
//  Repelican's build reflects the user's current SeasonPhase (see MASCOT.md):
//  off-season bulks up week over week, in-season / event-prep trend lean,
//  endurance-primary athletes stay leaner throughout. Reads only values
//  already on TrainingMemory; no new persistence.
//

import SwiftUI

/// A Today-row card: the Repelican at its phase-driven `bulk` plus a one-line
/// read on what the current block is building. Bulk morphs when the phase
/// changes (SeasonsEditorSheet re-stamps the phase and this re-renders).
struct RepelicanPhaseCard: View {
    @EnvironmentObject private var memory: MemoryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: SeasonPhase { memory.memory.seasonForPlanner }
    private var isEndurance: Bool { RepelicanPhysique.isEndurance(memory.memory.primarySport) }

    private var bulk: Double {
        RepelicanPhysique.bulk(
            phase: phase,
            weekInPhase: memory.memory.weeksInCurrentPhase,
            primaryIsEndurance: isEndurance
        )
    }

    /// What the mascot's build says about the phase — light, human, and
    /// endurance-aware (never implies "bigger = better" for a runner).
    private var blurb: String {
        switch phase {
        case .offSeason:
            return isEndurance
                ? "Base-building — banking the volume with you."
                : "Off-season bulk — filling out week by week."
        case .preSeason:
            return "Sharpening up for the season."
        case .inSeason:
            return isEndurance
                ? "Lean and race-sharp."
                : "In-season — holding strength, recovering hard."
        case .eventPrep:
            return "Tapering lean toward peak day."
        case .maintenance:
            return "Staying strong, year-round."
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            RepelicanView(bulk: bulk)
                .frame(width: 64, height: 72)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: bulk)
                .repelicanIdle()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR REPELICAN")
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
                Text(blurb)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your Repelican. \(blurb)")
    }
}

#Preview("Off-season vs event prep") {
    let offSeason = MemoryStore(defaults: UserDefaults(suiteName: "RepelicanPhaseCard.off")!)
    offSeason.update { mem in
        mem.defaultSeason = .offSeason
        mem.phaseStartedAt = Calendar.current.date(byAdding: .day, value: -28, to: Date())
    }
    let eventPrep = MemoryStore(defaults: UserDefaults(suiteName: "RepelicanPhaseCard.prep")!)
    eventPrep.update { mem in
        mem.defaultSeason = .eventPrep
        mem.peakDate = Calendar.current.date(byAdding: .day, value: 14, to: Date())
    }
    return VStack(spacing: 12) {
        RepelicanPhaseCard().environmentObject(offSeason)
        RepelicanPhaseCard().environmentObject(eventPrep)
    }
    .padding()
    .background(Color.bg)
    .preferredColorScheme(.dark)
}
