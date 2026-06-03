// MesocycleProgression.swift — week-of-cycle math for the SeasonPhaseBadge.
//
// Build 103. The badge already shows phase + week-counter; this layer
// decides whether the current week (or the next one) is a deload, so the
// user gets early warning instead of finding out when the volume drops
// mid-session.
//
// Standard 4-week mesocycle: weeks 1-3 build, week 4 deload, reset on
// week 5. Tunable per-phase because in-season blocks deload less often
// and event-prep is governed by the peak date (taper window).
//
// Pure value math. No I/O, no DB. Tests cover the boundary weeks +
// each phase's cycle length.

import Foundation

enum MesocycleProgression {

    enum DeloadState: Equatable {
        case build              // normal training week
        case deloadNextWeek     // deload one cycle away — surface the warning
        case deload             // this IS the deload week
        case taper              // event-prep taper (T-7 to T-0)
        case peak               // event-prep peak (day 0)
        case offCycle           // maintenance / no programmed deload cycle
    }

    struct Status: Equatable {
        let state: DeloadState
        /// 1-indexed week inside the current cycle. Mesocycle length depends
        /// on phase (see `cycleLength(for:)`). nil when offCycle.
        let weekOfCycle: Int?
        /// Short pill label: "DELOAD", "BUILD W3", etc. Empty when offCycle.
        let badge: String
        /// One-liner the badge meta line can use.
        let detail: String
    }

    /// Cycle length per phase. Pre-season and off-season run the
    /// canonical 4-week meso; in-season stretches to 6 (less frequent
    /// deloads — the sport itself is the volume); event-prep is special
    /// (driven by peak date, not cycle count); maintenance is undulating
    /// and doesn't have a programmed deload — the planner already varies
    /// volume week to week.
    static func cycleLength(for phase: SeasonPhase) -> Int {
        switch phase {
        case .offSeason:   return 4
        case .preSeason:   return 4
        case .inSeason:    return 6
        case .eventPrep:   return 4
        case .maintenance: return 0  // sentinel: no fixed cycle
        }
    }

    /// Compute status from the absolute weeks-into-phase counter + the
    /// phase + (optional) days-to-peak. weeksInPhase is 1-indexed (week 1 =
    /// first 7 days since phaseStartedAt). nil weeksInPhase → offCycle.
    static func status(
        phase: SeasonPhase,
        weeksInPhase: Int?,
        daysUntilPeak: Int?
    ) -> Status {
        // Event-prep: peak date wins. We only fall back to cycle math when
        // there's no peak set — defensive, since the SeasonsEditorSheet
        // requires a peak for .eventPrep but legacy saves might be missing.
        if phase == .eventPrep, let days = daysUntilPeak {
            if days <= 0 {
                return Status(
                    state: .peak,
                    weekOfCycle: nil,
                    badge: "PEAK",
                    detail: days == 0 ? "Today is the peak." : "Peak passed \(-days)d ago."
                )
            }
            if days <= 7 {
                return Status(
                    state: .taper,
                    weekOfCycle: nil,
                    badge: "TAPER",
                    detail: "T-\(days)d taper — volume drops, intensity holds."
                )
            }
            if days <= 14 {
                return Status(
                    state: .deloadNextWeek,
                    weekOfCycle: nil,
                    badge: "TAPER NEXT",
                    detail: "T-\(days)d. Taper starts in one week."
                )
            }
            // Far from peak — fall through to cycle math below.
        }

        let cycle = cycleLength(for: phase)
        if cycle == 0 {
            return Status(state: .offCycle, weekOfCycle: nil, badge: "", detail: phase.subtitle)
        }
        guard let weeks = weeksInPhase else {
            return Status(state: .offCycle, weekOfCycle: nil, badge: "", detail: phase.subtitle)
        }
        // Map absolute week → 1-indexed week-of-cycle.
        let weekOfCycle = ((weeks - 1) % cycle) + 1
        if weekOfCycle == cycle {
            return Status(
                state: .deload,
                weekOfCycle: weekOfCycle,
                badge: "DELOAD WK",
                detail: "Deload — volume −30%, intensity holds. Earn the recovery."
            )
        }
        if weekOfCycle == cycle - 1 {
            return Status(
                state: .deloadNextWeek,
                weekOfCycle: weekOfCycle,
                badge: "DELOAD NEXT",
                detail: "Week \(weekOfCycle) of \(cycle). Deload starts in one week — push the top sets."
            )
        }
        return Status(
            state: .build,
            weekOfCycle: weekOfCycle,
            badge: "BUILD W\(weekOfCycle)",
            detail: "Week \(weekOfCycle) of \(cycle). \(phase.subtitle)"
        )
    }
}
