// ProfileScreen+RowSummaries.swift — read-only value summaries for the
// Profile tab's SettingsRows.
//
// Pure extraction from ProfileScreen.swift (architecture item 11): every
// property here is a derived, side-effect-free string (plus the
// `currentTier` helper the equipment summary reads). No presentation state.

import SwiftUI

extension ProfileScreen {

    // MARK: - Row summaries

    var sportsSummary: String {
        let sports = store.memory.sports
        guard !sports.isEmpty else { return "None" }
        let primary = store.memory.primarySport ?? sports.first
        let primaryName = primary?.name ?? sports.first?.name ?? ""
        let othersCount = max(0, sports.count - 1)
        if othersCount == 0 { return primaryName }
        return "\(primaryName) +\(othersCount)"
    }

    var seasonsSummary: String {
        if store.memory.sports.isEmpty {
            return store.memory.defaultSeason.label
        }
        // If every sport's season matches the default, show just the default.
        // Otherwise show "Mixed".
        let perSport = store.memory.sports.map { store.memory.seasonsBySport[$0] ?? store.memory.defaultSeason }
        let unique = Set(perSport)
        if unique.count == 1, let only = unique.first {
            return only.label
        }
        return "Mixed"
    }

    var liftDaysSummary: String {
        let n = store.memory.liftDaysPerWeek
        return "\(n) " + (n == 1 ? "day" : "days") + " / week"
    }

    var supportSummary: String {
        guard let p = store.memory.supportPattern, !p.isEmpty else { return "Off" }
        let n = p.days.count
        return "Climbing · \(n) " + (n == 1 ? "day" : "days")
    }

    var equipmentSummary: String {
        let tier = currentTier
        if tier == .custom {
            let count = store.memory.equipment.count
            return "Custom (\(count))"
        }
        return tier.label
    }

    var experienceSummary: String {
        store.memory.experience.label
    }

    var aboutSummary: String {
        var parts: [String] = []
        if let age = store.memory.age { parts.append("\(age)") }
        if let gender = store.memory.gender { parts.append(gender.label) }
        if parts.isEmpty { return "Not set" }
        return parts.joined(separator: " · ")
    }

    var bodyWeightSummary: String {
        let logCount = store.memory.bodyWeightLog.count
        let imperial = store.memory.usesImperial
        // Prefer the log's newest entry, fall back to the scalar — so a
        // populated log never shows "—" just because the mirror lagged.
        let kg = store.memory.latestBodyWeightEntry?.weightKg ?? store.memory.weightKg
        guard let kg else {
            return logCount == 0 ? "Not set" : "—"
        }
        let weight = BodyMetrics.formatWeight(kg: kg, imperial: imperial)
        if logCount <= 1 { return weight }
        return "\(weight) · \(logCount) entries"
    }

    var bodyCompositionSummary: String {
        let log = store.memory.bodyCompositionLog.sorted { $0.date > $1.date }
        guard let latest = log.first else { return "Not set" }
        var parts: [String] = []
        if let bf = latest.bodyFatPercent {
            parts.append(String(format: "%.1f%%", bf))
        }
        if let lean = latest.leanMassKg {
            let imperial = store.memory.usesImperial
            let display = imperial ? BodyMetrics.kgToLb(lean) : lean
            parts.append(String(format: "%.0f %@ LBM", display, imperial ? "lb" : "kg"))
        }
        if parts.isEmpty { return "Not set" }
        return parts.joined(separator: " · ")
    }

    var dislikesSummary: String {
        let count = store.memory.dislikes.count
        if count == 0 { return "None" }
        if count == 1 { return store.memory.dislikes[0] }
        return "\(count) items"
    }

    /// Trailing summary for the Subscription row. Shows "Pro" when the
    /// entitlement is active, otherwise prompts the user to upgrade.
    var subscriptionRowValue: String {
        subStore.isPro ? "Pro" : "Upgrade"
    }

    var injuriesSummary: String {
        // Build 87: prefer the typed userInjuries store; free-text constraints
        // that aren't recognised injury slugs still surface (legacy notes).
        let known = Set(CoachDatabase.shared.listInjuries().map(\.slug))
        let structuredCount = store.memory.userInjuries.count
        let legacy = store.memory.constraints.filter { !known.contains($0) }
        let total = structuredCount + legacy.count
        if total == 0 { return "None" }
        if total == 1 {
            if let only = store.memory.userInjuries.first,
               let name = CoachDatabase.shared.listInjuries().first(where: { $0.slug == only.slug })?.name {
                return name
            }
            return legacy.first ?? "1 item"
        }
        return "\(total) items"
    }

    var remindersSummary: String {
        WeeklyReminderScheduler.isEnabled ? "On" : "Off"
    }

    var currentTier: EquipmentTier {
        let eq = store.memory.equipment
        if eq == [.bodyweight] { return .bodyweight }
        if eq == [.dumbbells]  { return .dumbbells  }
        if eq == [.fullGym]    { return .fullGym    }
        return .custom
    }
}
