// BodyMetrics.swift — pure unit-conversion helpers for height + weight.
//
// TrainingMemory stores metric (cm + kg) so the underlying number is
// stable; this module renders + parses the user's preferred unit system.
//
// Why a dedicated module: conversion is value math, used by the onboarding
// editor, the profile editor, and the Progress strength-ratio card. Keeping
// it stateless makes it trivially unit-testable.

import Foundation

enum BodyMetrics {

    // MARK: - Weight

    /// 1 kg ≈ 2.20462262 lb. Source: NIST.
    static let kgPerLb: Double = 0.45359237

    static func kgToLb(_ kg: Double) -> Double {
        kg / kgPerLb
    }

    static func lbToKg(_ lb: Double) -> Double {
        lb * kgPerLb
    }

    /// Format a weight (stored in kg) for display in the user's unit system.
    /// Returns "—" when nil so empty UI states are predictable.
    static func formatWeight(kg: Double?, imperial: Bool) -> String {
        guard let kg else { return "—" }
        if imperial {
            let lb = kgToLb(kg)
            return String(format: "%.1f lb", lb)
        } else {
            return String(format: "%.1f kg", kg)
        }
    }

    // MARK: - Height

    /// 1 inch = 2.54 cm exactly.
    static let cmPerInch: Double = 2.54

    /// Convert whole-cm height to (feet, inches) — inches rounded to nearest.
    static func cmToFeetInches(_ cm: Int) -> (feet: Int, inches: Int) {
        let totalInches = Int((Double(cm) / cmPerInch).rounded())
        return (totalInches / 12, totalInches % 12)
    }

    /// Convert (feet, inches) → cm, rounded to whole cm. Negative inputs
    /// are clamped to 0 so the field never produces nonsense.
    static func feetInchesToCm(feet: Int, inches: Int) -> Int {
        let totalInches = max(feet, 0) * 12 + max(inches, 0)
        return Int((Double(totalInches) * cmPerInch).rounded())
    }

    /// Format a height (stored in cm) for display in the user's unit system.
    static func formatHeight(cm: Int?, imperial: Bool) -> String {
        guard let cm else { return "—" }
        if imperial {
            let (f, i) = cmToFeetInches(cm)
            return "\(f)′ \(i)″"
        } else {
            return "\(cm) cm"
        }
    }
}
