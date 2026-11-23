// CloudBackupTests.swift — the weekly iCloud Drive backup write. Every
// defaults suite, database and container here is private to the test.

import XCTest
@testable import PhaseTraining

final class CloudBackupTests: XCTestCase {

    private var suites: [String] = []
    private var tempDirs: [URL] = []

    override func tearDown() {
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        for d in tempDirs { try? FileManager.default.removeItem(at: d) }
        suites = []; tempDirs = []
        super.tearDown()
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "cloud-backup-\(UUID().uuidString)"
        suites.append(suite)
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func tempContainer() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempDirs.append(url)
        return url
    }

    private func backupFile(in root: URL) -> URL {
        root.appendingPathComponent("Documents").appendingPathComponent(CloudBackup.fileName)
    }

    private func modificationDate(_ url: URL) throws -> Date {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attrs[.modificationDate] as? Date)
    }

    // MARK: - isDue

    func test_isDue_nilLastWrite() {
        XCTAssertTrue(CloudBackup.isDue(lastWrite: nil, now: Date()))
    }

    func test_isDue_sixDaysIsNotDue() {
        let now = Date()
        XCTAssertFalse(CloudBackup.isDue(lastWrite: now.addingTimeInterval(-6 * 86_400), now: now))
    }

    func test_isDue_sevenDaysIsDue() {
        let now = Date()
        XCTAssertTrue(CloudBackup.isDue(lastWrite: now.addingTimeInterval(-7 * 86_400), now: now))
    }

    // MARK: - write

    func test_write_producesDecodableFileAndStamps() throws {
        let defaults = freshDefaults()
        let root = try tempContainer()
        let now = Date()
        let envelope = BackupManager.snapshot(defaults: defaults, userDB: UserDatabase(path: ":memory:"))

        try CloudBackup.write(envelope: envelope, to: root, now: now, defaults: defaults)

        let data = try Data(contentsOf: backupFile(in: root))
        XCTAssertNoThrow(try BackupManager.decode(data))
        let stamp = try XCTUnwrap(CloudBackup.lastWrite(defaults: defaults))
        XCTAssertEqual(stamp.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
    }

    func test_write_unwritablePathThrowsAndDoesNotStamp() {
        let defaults = freshDefaults()
        let envelope = BackupManager.snapshot(defaults: defaults, userDB: UserDatabase(path: ":memory:"))

        XCTAssertThrowsError(try CloudBackup.write(
            envelope: envelope, to: URL(fileURLWithPath: "/dev/null/container"),
            now: Date(), defaults: defaults))
        XCTAssertNil(CloudBackup.lastWrite(defaults: defaults))
        XCTAssertNil(defaults.object(forKey: CloudBackup.lastWriteKey))
    }

    // MARK: - runIfDue

    func test_runIfDue_nilContainerWritesNothing() async throws {
        let defaults = freshDefaults()
        await CloudBackup.runIfDue(defaults: defaults, userDB: UserDatabase(path: ":memory:"),
                                   now: Date(), containerURL: { nil })
        XCTAssertNil(defaults.object(forKey: CloudBackup.lastWriteKey))
    }

    func test_runIfDue_writesAndStamps() async throws {
        let defaults = freshDefaults()
        let root = try tempContainer()
        await CloudBackup.runIfDue(defaults: defaults, userDB: UserDatabase(path: ":memory:"),
                                   now: Date(), containerURL: { root })
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupFile(in: root).path))
        XCTAssertNotNil(CloudBackup.lastWrite(defaults: defaults))
    }

    func test_runIfDue_secondRunDoesNotRewrite() async throws {
        let defaults = freshDefaults()
        let db = UserDatabase(path: ":memory:")
        let root = try tempContainer()
        let now = Date()
        await CloudBackup.runIfDue(defaults: defaults, userDB: db, now: now, containerURL: { root })
        let first = try modificationDate(backupFile(in: root))

        try await Task.sleep(nanoseconds: 1_100_000_000)
        await CloudBackup.runIfDue(defaults: defaults, userDB: db, now: now.addingTimeInterval(60),
                                   containerURL: { root })
        XCTAssertEqual(try modificationDate(backupFile(in: root)), first)
    }

    func test_isSignedIn_followsTheIdentityToken() {
        XCTAssertFalse(CloudBackup.isSignedIn(token: { nil }))
        XCTAssertTrue(CloudBackup.isSignedIn(token: { "token" as NSString }))
    }
}
