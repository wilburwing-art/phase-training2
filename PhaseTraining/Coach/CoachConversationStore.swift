// CoachConversationStore.swift — per-day chat persistence + drawer state.
//
// One conversation per calendar day. Today's lives at `pt_coach_today`. On
// startup (or on a midnight rollover while foregrounded), if the stored
// "last seen day" doesn't match today we archive the current bucket to
// `pt_coach_archive_<yyyy-MM-dd>` and reset.
//
// Drawer presentation + prefill state lives here too so InsightCard and
// CoachBubble share one surface.

import Foundation
import Combine

struct CoachMessage: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var role: String       // "user" or "assistant"
    var text: String
    var date: Date = Date()
    /// Plan-level proposal (Phase 13c). MiniPlanDiffCard renders this.
    var proposal: CoachProposal? = nil
    /// Workout-level proposal (Phase 13d). MiniWorkoutDiffCard renders this.
    var workoutProposal: CoachWorkoutProposal? = nil
    /// Memory-update proposal (Phase 13f). MiniMemoryDiffCard renders this.
    var memoryProposal: CoachMemoryProposal? = nil

    var isUser: Bool { role == "user" }
}

final class CoachConversationStore: ObservableObject {
    private static let todayKey       = "pt_coach_today"
    private static let lastSeenDayKey = "pt_coach_last_seen_day"
    private static let archivePrefix  = "pt_coach_archive_"
    private static let turnsKey       = "pt_coach_turns_today"

    @Published var messages: [CoachMessage] = []
    @Published var presented: Bool = false
    @Published var prefill: String = ""
    /// User-initiated sends so far today. Persisted separately from the
    /// transcript so clearing the chat doesn't reset the daily cost guard;
    /// reset on calendar-day rollover. Drives the soft/hard turn caps.
    @Published private(set) var turnsToday: Int = 0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        if let stored = Self.load(defaults: defaults, key: Self.todayKey) {
            self.messages = stored
        }
        rolloverIfNeeded(now: now)
        self.turnsToday = defaults.integer(forKey: Self.turnsKey)
    }

    // MARK: - Public

    func append(_ message: CoachMessage) {
        messages.append(message)
        save()
    }

    /// Append to an in-flight assistant message; used while streaming deltas.
    func appendDelta(to id: UUID, _ delta: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text += delta
    }

    /// Persist whatever's currently in messages. Call once at end-of-stream
    /// rather than on every delta to avoid hammering UserDefaults.
    func flush() {
        save()
    }

    /// Attach a fresh proposal to an assistant message.
    func setProposal(on id: UUID, _ proposal: CoachProposal) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].proposal = proposal
        save()
    }

    /// Update an existing proposal's status (applied or rejected).
    func setProposalStatus(messageId: UUID, _ status: CoachProposal.Status) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              messages[idx].proposal != nil else { return }
        messages[idx].proposal?.status = status
        save()
    }

    /// Attach a workout-level proposal to an assistant message.
    func setWorkoutProposal(on id: UUID, _ proposal: CoachWorkoutProposal) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].workoutProposal = proposal
        save()
    }

    func setWorkoutProposalStatus(messageId: UUID, _ status: CoachWorkoutProposal.Status) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              messages[idx].workoutProposal != nil else { return }
        messages[idx].workoutProposal?.status = status
        save()
    }

    func setMemoryProposal(on id: UUID, _ proposal: CoachMemoryProposal) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].memoryProposal = proposal
        save()
    }

    func setMemoryProposalStatus(messageId: UUID, _ status: CoachMemoryProposal.Status) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              messages[idx].memoryProposal != nil else { return }
        messages[idx].memoryProposal?.status = status
        save()
    }

    func present(withPrefill text: String = "") {
        prefill = text
        presented = true
    }

    // MARK: - Turn caps (cost guard)

    /// Count a user-initiated send against today's cap. Persisted under a
    /// dedicated key so `clearToday()` does NOT reset it.
    func recordTurn(now: Date = Date()) {
        // Roll over first so a session held open across midnight counts the new
        // day's first turn against a fresh counter, not yesterday's bucket.
        rolloverIfNeeded(now: now)
        turnsToday += 1
        defaults.set(turnsToday, forKey: Self.turnsKey)
    }

    /// At/above the soft cap: still sends, but the drawer shows a slow-down note.
    var atSoftCap: Bool { turnsToday >= CoachConfig.softTurnCap }

    /// At/above the hard cap: the drawer blocks further sends until rollover.
    var atHardCap: Bool { turnsToday >= CoachConfig.hardTurnCap }

    /// Conversation history in the wire format CoachClient.stream expects.
    /// Drops empty placeholder bubbles (in-flight assistant turn before any
    /// deltas arrive).
    func wireHistory() -> [CoachClient.Turn] {
        messages
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { .init(role: $0.role, text: $0.text) }
    }

    /// Manual reset — clears today's slot without archiving.
    func clearToday() {
        messages = []
        defaults.removeObject(forKey: Self.todayKey)
    }

    // MARK: - Rollover

    /// If today's date differs from the last-seen day, archive the current
    /// `pt_coach_today` bucket under `pt_coach_archive_<yyyy-MM-dd>` and reset.
    func rolloverIfNeeded(now: Date = Date()) {
        let today = Self.dayString(for: now)
        let lastSeen = defaults.string(forKey: Self.lastSeenDayKey)

        if lastSeen != today {
            if let lastSeen,
               let stale = Self.load(defaults: defaults, key: Self.todayKey),
               !stale.isEmpty,
               let data = try? Self.encoder().encode(stale) {
                defaults.set(data, forKey: Self.archivePrefix + lastSeen)
            }
            messages = []
            defaults.removeObject(forKey: Self.todayKey)
            defaults.set(today, forKey: Self.lastSeenDayKey)
            turnsToday = 0
            defaults.removeObject(forKey: Self.turnsKey)
        }
    }

    // MARK: - Persistence

    /// Snapshot messages on the main thread, then encode + write on a
    /// background queue. The drawer fires save() on every status change
    /// (apply/reject of a proposal); with a long chat + diff cards, the
    /// synchronous encode added ms to a hot UI path. Build 60 hit the iOS
    /// watchdog from a long apply cascade where this was a contributor.
    private func save() {
        let snapshot = messages
        let store = defaults
        Task.detached(priority: .utility) {
            if let data = try? Self.encoder().encode(snapshot) {
                store.set(data, forKey: Self.todayKey)
            }
        }
    }

    private static func load(defaults: UserDefaults, key: String) -> [CoachMessage]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder().decode([CoachMessage].self, from: data)
    }

    private static func dayString(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
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
