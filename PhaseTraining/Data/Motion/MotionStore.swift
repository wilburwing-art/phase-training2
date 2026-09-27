// MotionStore.swift — where labeled motion lives on the phone (PLAN-watch.md, step 3).
//
// `Application Support/Motion/<sessionId>/<exercise>-setN.ptmotion`, received
// from the watch by `WatchSyncCoordinator` through `WCSession.transferFile`.
// On device only: outside the backup export (which is a single file built
// from the stores, so this directory is never in it), never uploaded, not in
// the coach snapshot, so the App Store privacy label does not change.
//
// Cap (Wilbur, 2026-09-27): 12 months or 200 MB, whichever comes first,
// oldest dropped first. `prune()` runs after every file lands and on
// launch. "Erase all my data" removes the whole directory.

import Foundation
import OSLog

struct MotionStore {

    static let maxAge: TimeInterval = 365 * 86_400
    static let maxBytes: Int = 200 * 1_048_576

    let root: URL
    private static let log = Logger(subsystem: "com.phasetraining.app", category: "motion")

    static let shared = MotionStore(root: defaultRoot())

    static func defaultRoot() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Motion", isDirectory: true)
    }

    init(root: URL) {
        self.root = root
    }

    struct Entry: Equatable {
        let url: URL
        let sessionId: String
        let bytes: Int
        let modified: Date
    }

    /// Move a received file into place. The metadata names the session and
    /// the file; anything else is refused and left where WatchConnectivity
    /// put it (which the system deletes after the delegate returns).
    @discardableResult
    func store(fileAt url: URL, sessionId: String, fileName: String, now: Date = Date()) throws -> URL {
        guard fileName.hasSuffix(".ptmotion"), !fileName.contains("/"), !sessionId.contains("/") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let dir = root.appendingPathComponent(sessionId, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: url, to: destination)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: destination.path)
        prune(now: now)
        return destination
    }

    /// Every stored window, oldest first.
    func entries() -> [Entry] {
        let fm = FileManager.default
        guard let sessions = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [Entry] = []
        for session in sessions {
            guard let files = try? fm.contentsOfDirectory(at: session, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
            for file in files where file.pathExtension == "ptmotion" {
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                out.append(Entry(url: file, sessionId: session.lastPathComponent,
                                 bytes: values?.fileSize ?? 0,
                                 modified: values?.contentModificationDate ?? .distantPast))
            }
        }
        return out.sorted { $0.modified < $1.modified }
    }

    var totalBytes: Int { entries().reduce(0) { $0 + $1.bytes } }

    /// Drop windows older than `maxAge`, then the oldest until under `maxBytes`.
    func prune(now: Date = Date()) {
        let fm = FileManager.default
        var kept: [Entry] = []
        for entry in entries() {
            if now.timeIntervalSince(entry.modified) > Self.maxAge {
                try? fm.removeItem(at: entry.url)
            } else {
                kept.append(entry)
            }
        }
        var total = kept.reduce(0) { $0 + $1.bytes }
        for entry in kept where total > Self.maxBytes {
            try? fm.removeItem(at: entry.url)
            total -= entry.bytes
        }
        // Session directories left empty go too.
        if let sessions = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for session in sessions where (try? fm.contentsOfDirectory(atPath: session.path))?.isEmpty == true {
                try? fm.removeItem(at: session)
            }
        }
    }

    /// "Erase all my data".
    func wipe() {
        try? FileManager.default.removeItem(at: root)
    }

    /// For the DEBUG Signals sheet: windows, sessions, megabytes.
    func summary() -> (windows: Int, sessions: Int, megabytes: Double) {
        let all = entries()
        return (all.count, Set(all.map(\.sessionId)).count, Double(all.reduce(0) { $0 + $1.bytes }) / 1_048_576)
    }
}
