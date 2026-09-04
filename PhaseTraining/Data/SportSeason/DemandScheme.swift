// DemandScheme.swift — the prescription band per Demand.
//
// Demand-driven, not goal-driven: the slot a movement fills (its Demand) sets
// the rep/rest/RPE/tempo *character*; the phase's ProgressionMode then modulates
// volume + intensity (`SetScheme.modulated`). Kept as a hand-tuned Swift table
// next to PhaseRule — editing a band and re-running SeasonFidelityTest is the
// inner loop, no DB rebuild. Replaces the old path where ski/climb reps/rest/
// tempo came from each movement's GENERIC catalog default (the same numbers a
// general-fitness user got), which ignored the slot's demand entirely.

import Foundation

enum DemandScheme {

    /// Base prescription for one slot of a given demand, pre-progression.
    /// Felt-sense starting bands; tune per demand and re-run SeasonFidelityTest.
    static let base: [Demand: SetScheme] = [
        // shared
        .maxStrength: SetScheme(
            setsLow: 3, setsHigh: 5, repsLow: 3, repsHigh: 5,
            intensityRPELow: 7, intensityRPEHigh: 8, restSeconds: 180, fatigueCost: 4),
        .power: SetScheme(
            setsLow: 3, setsHigh: 5, repsLow: 2, repsHigh: 3,
            intensityRPELow: 6, intensityRPEHigh: 7,
            explosiveConcentric: true, restSeconds: 180, fatigueCost: 3),
        .core: SetScheme(
            setsLow: 2, setsHigh: 3, repsLow: 10, repsHigh: 15,
            intensityRPELow: 6, intensityRPEHigh: 7, restSeconds: 60, fatigueCost: 2),
        .prehab: SetScheme(
            setsLow: 2, setsHigh: 3, repsLow: 10, repsHigh: 15,
            intensityRPELow: 5, intensityRPEHigh: 6, restSeconds: 45, fatigueCost: 1),
        .upperStrength: SetScheme(
            setsLow: 3, setsHigh: 5, repsLow: 4, repsHigh: 6,
            intensityRPELow: 7, intensityRPEHigh: 8, restSeconds: 120, fatigueCost: 3),
        .aerobicUphill: SetScheme(
            setsLow: 3, setsHigh: 4, holdSeconds: 60,
            intensityRPELow: 6, intensityRPEHigh: 7, restSeconds: 60, fatigueCost: 3),

        // skiing
        .eccentricLeg: SetScheme(
            setsLow: 3, setsHigh: 4, repsLow: 4, repsHigh: 6,
            intensityRPELow: 7, intensityRPEHigh: 7,
            eccentricTempoSeconds: 4, restSeconds: 150, fatigueCost: 4),
        .legEndurance: SetScheme(
            setsLow: 2, setsHigh: 3, repsLow: 12, repsHigh: 20,
            intensityRPELow: 7, intensityRPEHigh: 8, restSeconds: 60, fatigueCost: 3),
        .kneeStability: SetScheme(
            setsLow: 2, setsHigh: 3, repsLow: 8, repsHigh: 12,
            intensityRPELow: 6, intensityRPEHigh: 7, restSeconds: 60, fatigueCost: 2),
        .hipLateral: SetScheme(
            setsLow: 2, setsHigh: 3, repsLow: 10, repsHigh: 15,
            intensityRPELow: 6, intensityRPEHigh: 6, restSeconds: 45, fatigueCost: 2),

        // climbing
        .fingerStrength: SetScheme(
            setsLow: 4, setsHigh: 6, holdSeconds: 8,
            intensityRPELow: 7, intensityRPEHigh: 7, restSeconds: 120, fatigueCost: 4),
        .pullStrength: SetScheme(
            setsLow: 3, setsHigh: 5, repsLow: 4, repsHigh: 6,
            intensityRPELow: 7, intensityRPEHigh: 8, restSeconds: 150, fatigueCost: 4),
        .contactStrength: SetScheme(
            setsLow: 4, setsHigh: 6, repsLow: 2, repsHigh: 3,
            intensityRPELow: 7, intensityRPEHigh: 7,
            explosiveConcentric: true, restSeconds: 120, fatigueCost: 4),
        .bodyTension: SetScheme(
            setsLow: 3, setsHigh: 4, repsLow: 6, repsHigh: 10,
            intensityRPELow: 7, intensityRPEHigh: 7, restSeconds: 90, fatigueCost: 3),
        .pullEndurance: SetScheme(
            setsLow: 3, setsHigh: 4, repsLow: 12, repsHigh: 20,
            intensityRPELow: 7, intensityRPEHigh: 8, restSeconds: 60, fatigueCost: 3),
        .antagonist: SetScheme(
            setsLow: 2, setsHigh: 3, repsLow: 10, repsHigh: 15,
            intensityRPELow: 6, intensityRPEHigh: 7, restSeconds: 60, fatigueCost: 2),
    ]

    /// Safe default for any demand without an explicit band — keeps the
    /// generator whole if a new `Demand` case lands before its scheme is authored.
    static let fallback = SetScheme(
        setsLow: 3, setsHigh: 3, repsLow: 8, repsHigh: 12,
        intensityRPELow: 7, intensityRPEHigh: 7, restSeconds: 90, fatigueCost: 2)

    /// The prescription for a demand under a phase's progression.
    static func scheme(for demand: Demand, progression: ProgressionMode) -> SetScheme {
        (base[demand] ?? fallback).modulated(by: progression)
    }
}
