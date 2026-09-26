// ExploreSession.swift — A3 of PLAN-predictive-recommendations.md.
//
// The "Looked" tier: what the user searched and browsed, and whether it led
// anywhere. Before this every search box and preview was `@State` and died
// with its view.
//
// The unit of record is one visit to one browse surface, not a keystroke or a
// tap. A raw look carries almost no signal; a look that CONVERTED (swapped in,
// added, started) carries a lot, and a search that dead-ended (zero or partial
// results, left without acting) is both a preference miss and a catalog-gap
// report. So a session holds its latest query, what was opened, and what
// converted, each open and conversion stamped with the query in force then.
//
// On device only, in UserDatabase (`explore_sessions`, migration v2), pruned
// to 90 days, cleared by wipeAll(), not in backups. Nothing reads it yet (A4).

import Foundation

enum ExploreSurface: String, Codable, CaseIterable {
    case exercisePicker
    case library
    case libraryMuscle
    case workoutCategory
    case overrideToday
}

enum ExploreItemKind: String, Codable {
    case exercise
    /// Bundled coach.db routine (int id).
    case routine
    /// User-built routine (string id).
    case customRoutine
}

enum ExploreConversionKind: String, Codable, CaseIterable {
    /// Picked in a "Replace X" picker.
    case swapIn
    /// Picked in the live session's "Add exercise" picker.
    case addToSession
    /// Picked while building or editing a routine.
    case addToRoutine
    /// Started a routine as a live session.
    case startRoutine
    /// Put a workout on today in place of the planned one.
    case switchToday
}

struct ExploreOpen: Codable, Hashable {
    var kind: ExploreItemKind
    var id: String
    var name: String
    var query: String?
    var at: Date
}

struct ExploreConversion: Codable, Hashable {
    var kind: ExploreConversionKind
    var itemKind: ExploreItemKind
    var id: String
    var name: String
    var query: String?
    var at: Date
}

struct ExploreSession: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var surface: ExploreSurface
    var startedAt: Date
    var endedAt: Date
    /// Latest non-empty query of the visit, normalised (see `normalise`).
    var query: String?
    var resultCount: Int?
    /// `CoachDatabase.SearchTier` raw value at `query`; nil for surfaces that
    /// filter in memory rather than through the tiered search.
    var tier: Int?
    var broadened: Bool = false
    var opens: [ExploreOpen] = []
    var conversions: [ExploreConversion] = []

    var converted: Bool { !conversions.isEmpty }

    /// Trim, lowercase, collapse inner whitespace, cap at 60 characters.
    static func normalise(_ raw: String) -> String? {
        let words = raw.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        return String(words.joined(separator: " ").prefix(60))
    }
}

/// Where a finished session goes. `UserDatabase` in production; an array in
/// tests and previews.
protocol ExploreSink: AnyObject {
    func recordExploreSession(_ session: ExploreSession)
}

/// Owned by one surface for its lifetime (`@State`), flushed on disappear.
/// Keeps only the latest query state; `opened` and `converted` snapshot it.
final class ExploreRecorder {
    let surface: ExploreSurface
    private weak var sink: ExploreSink?
    private let now: () -> Date
    private var session: ExploreSession
    private var currentQuery: String?

    init(surface: ExploreSurface, sink: ExploreSink? = ExploreRecorder.defaultSink(),
         now: @escaping () -> Date = Date.init) {
        self.surface = surface
        self.sink = sink
        self.now = now
        let t = now()
        self.session = ExploreSession(surface: surface, startedAt: t, endedAt: t)
    }

    /// Production sink: the real database, except under XCTest and SwiftUI
    /// Previews, where it is nil so neither ever writes the user's file.
    static func defaultSink() -> ExploreSink? {
        let env = ProcessInfo.processInfo.environment
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || env["XCTestConfigurationFilePath"] != nil {
            return nil
        }
        return UserDatabase.shared
    }

    /// Call whenever the surface's result list reloads. An empty query clears
    /// the current one but keeps the last non-empty query on the session.
    func query(_ raw: String, results: Int, tier: Int? = nil, broadened: Bool = false) {
        currentQuery = ExploreSession.normalise(raw)
        guard let q = currentQuery else { return }
        session.query = q
        session.resultCount = results
        session.tier = tier
        session.broadened = broadened
    }

    func opened(_ kind: ExploreItemKind, id: String, name: String) {
        session.opens.append(ExploreOpen(kind: kind, id: id, name: name,
                                         query: currentQuery, at: now()))
    }

    func converted(_ kind: ExploreConversionKind, itemKind: ExploreItemKind,
                   id: String, name: String) {
        session.conversions.append(ExploreConversion(kind: kind, itemKind: itemKind, id: id,
                                                     name: name, query: currentQuery, at: now()))
    }

    /// Write the visit if it showed intent, then start a fresh session so a
    /// surface that reappears (a tab switched back to) records a new visit.
    func flush() {
        defer {
            let t = now()
            session = ExploreSession(surface: surface, startedAt: t, endedAt: t)
            currentQuery = nil
        }
        let showedIntent = session.query != nil || !session.opens.isEmpty || session.converted
        guard showedIntent else { return }
        session.endedAt = now()
        sink?.recordExploreSession(session)
    }
}
