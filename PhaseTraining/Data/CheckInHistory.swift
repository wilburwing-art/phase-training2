import Foundation

struct CheckInHistoryRow: Hashable, Identifiable {
    let id: UUID
    let weekStart: Date
    let intent: String?
    let rating: String?
    let notes: String?
}

enum CheckInHistory {
    /// Newest weekStart first. Ties keep the later-appended record first.
    static func rows(_ checkIns: [WeeklyCheckIn]) -> [CheckInHistoryRow] {
        checkIns.enumerated()
            .sorted { a, b in
                if a.element.weekStart != b.element.weekStart {
                    return a.element.weekStart > b.element.weekStart
                }
                return a.offset > b.offset
            }
            .map { _, c in
                CheckInHistoryRow(
                    id: c.id,
                    weekStart: c.weekStart,
                    intent: nonBlank(c.intent),
                    rating: (c.lastWeekRating?.isEmpty ?? true) ? nil : c.lastWeekRating,
                    notes: nonBlank(c.notes)
                )
            }
    }

    /// Spoken rating: "too easy", "about right", "too hard", nil for unknown or nil.
    static func spokenRating(_ raw: String?) -> String? {
        switch raw {
        case "too_easy": return "too easy"
        case "right": return "about right"
        case "too_hard": return "too hard"
        default: return nil
        }
    }

    /// One VoiceOver sentence per row. Parts that are nil are skipped.
    static func spoken(_ row: CheckInHistoryRow, dateText: (Date) -> String) -> String {
        var parts = ["Week of \(dateText(row.weekStart))."]
        if let r = spokenRating(row.rating) { parts.append("Last week \(r).") }
        if let i = row.intent { parts.append("Intent: \(i).") }
        if let n = row.notes { parts.append("Notes: \(n).") }
        return parts.joined(separator: " ")
    }

    private static func nonBlank(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
}
