// CoachContext+InjuryBlocks.swift
//
// Extracted from CoachContext.swift (Tier-3 god-object split). Injury + constraint context blocks.
// `snapshot(...)` in CoachContext.swift composes these section builders.

import Foundation

extension CoachContext {
    /// Cache slug → display name once per snapshot. CoachDatabase joins SQL
    /// per call, so calling listInjuries() in a tight loop is wasteful.
    static func injuryNameLookup() -> [String: String] {
        var out: [String: String] = [:]
        for inj in CoachDatabase.shared.listInjuries() {
            out[inj.slug] = inj.name
        }
        return out
    }

    /// Cache slug → full CommonInjury (for region + description + recovery).
    private static func injuryByLookup() -> [String: CommonInjury] {
        var out: [String: CommonInjury] = [:]
        for inj in CoachDatabase.shared.listInjuries() {
            out[inj.slug] = inj
        }
        return out
    }

    static func structuredInjuriesSection(memory: TrainingMemory, now: Date = Date()) -> String? {
        guard !memory.userInjuries.isEmpty else { return nil }
        let byLookup = injuryByLookup()
        let cal = Calendar.current
        var lines: [String] = []
        for inj in memory.userInjuries.sorted(by: { $0.slug < $1.slug }) {
            guard let common = byLookup[inj.slug] else { continue }
            var qualifiers: [String] = []
            if let region = common.bodyRegion, !region.isEmpty {
                qualifiers.append(region)
            }
            if let sev = inj.severity { qualifiers.append(sev.rawValue) }
            if let side = inj.side    { qualifiers.append(side.label.lowercased()) }
            if let onset = inj.onsetDate {
                let weeks = cal.dateComponents([.weekOfYear],
                                               from: cal.startOfDay(for: onset),
                                               to: cal.startOfDay(for: now)).weekOfYear ?? 0
                if weeks <= 0 {
                    qualifiers.append("onset this week")
                } else if weeks == 1 {
                    qualifiers.append("onset 1 week ago")
                } else {
                    qualifiers.append("onset \(weeks) weeks ago")
                }
            }
            let qualifierBlob = qualifiers.isEmpty ? "" : " (" + qualifiers.joined(separator: " · ") + ")"
            var line = "- \(common.name)\(qualifierBlob)"
            // Description + recovery time give the model a clinical anchor.
            // Both trimmed of trailing punctuation so we can compose cleanly.
            var detail: [String] = []
            if let desc = common.description, !desc.isEmpty {
                detail.append(desc.trimmingCharacters(in: CharacterSet(charactersIn: " .")))
            }
            // The listInjuries() projection doesn't include mechanism /
            // typical_recovery — they're columns on the table but not read by
            // CoachDatabase. Skipped here; can be promoted later if useful.
            if let notes = inj.notes, !notes.isEmpty {
                detail.append("user note: \(sanitizeFreeText(notes))")
            }
            if !detail.isEmpty {
                line += ". " + detail.joined(separator: ". ") + "."
            }
            lines.append(line)
        }
        guard !lines.isEmpty else { return nil }
        return "STRUCTURED INJURIES\n" + lines.joined(separator: "\n")
    }

    static func injuryFiltersSection(profile: DemographicProfile, memory: TrainingMemory) -> String? {
        guard !profile.excludedByInjury.isEmpty else { return nil }
        let names = injuryNameLookup()
        let db = CoachDatabase.shared
        var lines: [String] = []
        for entry in profile.excludedByInjury {
            let display = names[entry.slug] ?? entry.slug
            // Top 5 names, alphabetised; remainder rolled into "+N more".
            let sortedIds = Array(entry.exerciseIds)
            let resolved = sortedIds.compactMap { db.exercise(id: $0)?.name }
                .sorted()
            guard !resolved.isEmpty else { continue }
            let head = resolved.prefix(5).joined(separator: ", ")
            let rest = resolved.count - 5
            let trail = rest > 0 ? " (+ \(rest) more)" : ""
            lines.append("- \(display): \(head)\(trail)")
        }
        guard !lines.isEmpty else { return nil }
        return "INJURY FILTERS — exercises currently excluded\n" + lines.joined(separator: "\n")
    }
}
