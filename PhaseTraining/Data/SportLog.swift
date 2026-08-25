// SportLog.swift — retrospective logging for sport-day sessions.
//
// Sport days schedule "go climbing" or "go ski touring" on the plan, but
// until now there was no in-app way to record that the session actually
// happened. The "Log it after." copy on TodayScreen promised a feature that
// didn't exist; this is that feature.
//
// Intentionally a separate type from SavedSession (which is lift-shaped:
// exercises × sets × reps). A SportLogEntry stores the minimum useful
// outcome: how long, how hard, and a freeform note. The coach + future
// progress surfaces can read this list to reason about non-lift load.
//
// Persisted as JSON under `pt_sport_logs` in UserDefaults, same pattern as
// the early days of PlanStore — fine while the row count stays in the
// hundreds. If sport-log queries ever get hot enough to need indexed
// access we can promote this to UserDatabase like SessionStore did.

import Foundation
import Combine

struct SportLogEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// Start-of-day for the session date — the day the user actually went
    /// out. Normalized by the store before insert so dedupe-per-day queries
    /// don't have to do calendar math.
    var date: Date
    /// Sport played. Stored as a slug via Sport's singleValueContainer codec.
    var sport: Sport
    /// Session duration in minutes. Clamped 1...600 in the sheet — long
    /// enough for an all-day tour, short enough to reject typos.
    var durationMinutes: Int
    /// Subjective intensity. Reuses EventIntensity so the planner and the
    /// log share the same vocabulary; if we ever swap one we update both.
    var intensity: EventIntensity
    /// Optional free-text note ("indoor V4s, felt strong"). Trimmed +
    /// nil'd when empty so blank notes don't show up as empty lines.
    var note: String?
    /// When the entry was logged. Audit trail — never user-edited from the
    /// sheet. Used as the tiebreaker when multiple entries share a date.
    var loggedAt: Date
}

final class SportLogStore: ObservableObject {
    private static let key = "pt_sport_logs"

    @Published private(set) var entries: [SportLogEntry] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? Self.decoder().decode([SportLogEntry].self, from: data) {
            self.entries = decoded
        }
    }

    // MARK: - Queries

    /// Most recent entry whose `date` falls on the same calendar day as
    /// `date`. nil if nothing's been logged that day. Used by TodayScreen
    /// to decide between "Log session" CTA and the "already logged" recap.
    func entry(on date: Date) -> SportLogEntry? {
        let cal = Calendar.current
        return entries
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .max(by: { $0.loggedAt < $1.loggedAt })
    }

    // MARK: - Mutations

    /// Append a new entry. `date` is normalized to start-of-day so the
    /// `entry(on:)` dedupe stays correct regardless of when the user
    /// taps Save.
    func log(sport: Sport,
             on date: Date,
             durationMinutes: Int,
             intensity: EventIntensity,
             note: String? = nil,
             now: Date = Date()) {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = SportLogEntry(
            date: Calendar.current.startOfDay(for: date),
            sport: sport,
            durationMinutes: durationMinutes,
            intensity: intensity,
            note: (trimmed?.isEmpty == false) ? trimmed : nil,
            loggedAt: now
        )
        entries.append(entry)
        persist()
    }

    /// Replace an existing entry in place (matched by id). Used when the
    /// user re-opens the sheet to fix a typo.
    func update(_ entry: SportLogEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var fixed = entry
        fixed.date = Calendar.current.startOfDay(for: entry.date)
        let trimmed = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        fixed.note = (trimmed?.isEmpty == false) ? trimmed : nil
        entries[idx] = fixed
        persist()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Persistence

    /// Drop the live cache after a wipe. `MemoryStore.wipeAllUserData()` removes
    /// `pt_sport_logs` from UserDefaults, but this store is an app-lifetime
    /// @StateObject: without this, `entries` survives the wipe and the next
    /// `persist()` writes the whole pre-erase history straight back.
    func reset() {
        entries = []
        defaults.removeObject(forKey: Self.key)
    }

    private func persist() {
        guard let data = try? Self.encoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
