// SportLogStoreTests.swift — pins the persistence + per-day-dedupe
// contract that TodayScreen depends on.

import XCTest
@testable import PhaseTraining

final class SportLogStoreTests: XCTestCase {

    // MARK: - Fixtures

    private func freshDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private var climbing: Sport {
        Sport.catalog.first { $0.slug == "climbing" }!
    }

    // MARK: - log

    func test_log_appendsEntry_andNormalizesDateToStartOfDay() {
        let defaults = freshDefaults("SportLogStoreTests.log_appends")
        let store = SportLogStore(defaults: defaults)
        let cal = Calendar.current
        // Pick a moment well into the afternoon so normalization is observable.
        let now = cal.date(bySettingHour: 17, minute: 32, second: 0, of: Date())!

        store.log(sport: climbing, on: now,
                  durationMinutes: 75, intensity: .hard,
                  note: "  bouldering, V4 felt good  ",
                  now: now)

        XCTAssertEqual(store.entries.count, 1)
        let entry = store.entries[0]
        XCTAssertEqual(entry.sport.slug, "climbing")
        XCTAssertEqual(entry.durationMinutes, 75)
        XCTAssertEqual(entry.intensity, .hard)
        XCTAssertEqual(entry.note, "bouldering, V4 felt good",
                       "Note must be trimmed before persist")
        XCTAssertEqual(entry.date, cal.startOfDay(for: now),
                       "Date must be normalized to start-of-day")
    }

    func test_log_emptyNote_persistsAsNil() {
        let defaults = freshDefaults("SportLogStoreTests.empty_note")
        let store = SportLogStore(defaults: defaults)

        store.log(sport: climbing, on: Date(),
                  durationMinutes: 30, intensity: .light, note: "   ")

        XCTAssertNil(store.entries[0].note,
                     "Whitespace-only note must collapse to nil so the UI doesn't render an empty line")
    }

    // MARK: - entry(on:)

    func test_entryOn_returnsMostRecentLogForThatDay() {
        let defaults = freshDefaults("SportLogStoreTests.entry_on_recent")
        let store = SportLogStore(defaults: defaults)
        let day = Calendar.current.startOfDay(for: Date())
        // Two logs same day — second one wins (most recent loggedAt).
        store.log(sport: climbing, on: day,
                  durationMinutes: 45, intensity: .moderate, note: "first",
                  now: day.addingTimeInterval(60))
        store.log(sport: climbing, on: day,
                  durationMinutes: 90, intensity: .hard, note: "fixed it",
                  now: day.addingTimeInterval(3600))

        let resolved = store.entry(on: day)
        XCTAssertEqual(resolved?.durationMinutes, 90)
        XCTAssertEqual(resolved?.note, "fixed it")
    }

    func test_entryOn_nilWhenNothingLoggedThatDay() {
        let defaults = freshDefaults("SportLogStoreTests.entry_on_nil")
        let store = SportLogStore(defaults: defaults)
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        store.log(sport: climbing, on: yesterday,
                  durationMinutes: 60, intensity: .moderate, note: nil)

        XCTAssertNil(store.entry(on: today),
                     "Yesterday's log must not satisfy today's query")
    }

    // MARK: - Persistence round-trip

    func test_entriesPersistAcrossInstances() {
        let defaults = freshDefaults("SportLogStoreTests.roundtrip")
        let a = SportLogStore(defaults: defaults)
        a.log(sport: climbing, on: Date(),
              durationMinutes: 50, intensity: .light, note: "easy day")

        let b = SportLogStore(defaults: defaults)
        XCTAssertEqual(b.entries.count, 1)
        XCTAssertEqual(b.entries[0].durationMinutes, 50)
        XCTAssertEqual(b.entries[0].sport.slug, "climbing")
    }

    // MARK: - update / delete

    func test_update_replacesEntryInPlace_andRetrimsNote() {
        let defaults = freshDefaults("SportLogStoreTests.update")
        let store = SportLogStore(defaults: defaults)
        store.log(sport: climbing, on: Date(),
                  durationMinutes: 60, intensity: .moderate, note: "initial")

        var entry = store.entries[0]
        entry.durationMinutes = 90
        entry.intensity = .hard
        entry.note = "  updated  "
        store.update(entry)

        XCTAssertEqual(store.entries.count, 1, "Update must not duplicate")
        XCTAssertEqual(store.entries[0].durationMinutes, 90)
        XCTAssertEqual(store.entries[0].intensity, .hard)
        XCTAssertEqual(store.entries[0].note, "updated")
    }

    func test_delete_removesById() {
        let defaults = freshDefaults("SportLogStoreTests.delete")
        let store = SportLogStore(defaults: defaults)
        store.log(sport: climbing, on: Date(),
                  durationMinutes: 60, intensity: .moderate, note: nil)
        let id = store.entries[0].id

        store.delete(id: id)

        XCTAssertEqual(store.entries.count, 0)

        // And the deletion persists.
        let reloaded = SportLogStore(defaults: defaults)
        XCTAssertEqual(reloaded.entries.count, 0)
    }
}
