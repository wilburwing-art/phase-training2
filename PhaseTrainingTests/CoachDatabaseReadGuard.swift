import SQLite3
import XCTest
@testable import PhaseTraining

/// setUp guard for suites that plan from the bundled catalog (11e 1.10).
/// When coach.db stops reading, every planner call returns empty and a grid
/// suite reports thousands of "empty session" failures in two seconds. This
/// throws one failure per case that names the SQLite code instead.
enum CoachDatabaseReadGuard {
    /// Below these the bundle is broken. The shipped catalog holds hundreds of
    /// exercises and over a hundred routines.
    static let minExercises: Int64 = 100
    static let minRoutines: Int64 = 1

    /// `SQLITE_IOERR | (27 << 8)` from Apple's sqlite3.h. Swift does not
    /// import the shifted macro.
    static let sqliteIOErrVnode: Int32 = 6922

    struct Unreadable: LocalizedError, CustomStringConvertible {
        let description: String
        var errorDescription: String? { description }
    }

    static func requireReadable() throws {
        let check = CoachDatabase.shared.readCheck()
        if check.code == SQLITE_OK,
           check.exerciseCount >= minExercises,
           check.routineCount >= minRoutines { return }
        throw Unreadable(description: message(for: check))
    }

    static func message(for check: CoachDatabase.ReadCheck) -> String {
        var text = "coach.db unreadable: code \(check.code) (\(check.message)), "
            + "\(check.exerciseCount) exercises, \(check.routineCount) routines."
        if check.code == sqliteIOErrVnode {
            text += " SQLITE_IOERR_VNODE: the bundled coach.db was replaced while the test host"
                + " held it open. Another session likely reinstalled the app on this simulator."
                + " Re-run with the simulator to yourself."
        }
        return text
    }
}

final class CoachDatabaseReadGuardTests: XCTestCase {
    func test_bundledCatalogPassesTheGuard() throws {
        let check = CoachDatabase.shared.readCheck()
        XCTAssertEqual(check.code, SQLITE_OK, check.message)
        XCTAssertGreaterThanOrEqual(check.exerciseCount, CoachDatabaseReadGuard.minExercises)
        XCTAssertGreaterThanOrEqual(check.routineCount, CoachDatabaseReadGuard.minRoutines)
        XCTAssertNoThrow(try CoachDatabaseReadGuard.requireReadable())
    }

    func test_vnodeErrorIsNamedInTheFailure() {
        let check = CoachDatabase.ReadCheck(exerciseCount: 0, routineCount: 0,
                                            code: CoachDatabaseReadGuard.sqliteIOErrVnode,
                                            message: "exercises: disk I/O error")
        let text = CoachDatabaseReadGuard.message(for: check)
        XCTAssertTrue(text.contains("code 6922"), text)
        XCTAssertTrue(text.contains("SQLITE_IOERR_VNODE"), text)
    }

    func test_otherErrorsDoNotBlameAReinstall() {
        let check = CoachDatabase.ReadCheck(exerciseCount: 0, routineCount: 0,
                                            code: SQLITE_CANTOPEN, message: "coach.db did not open")
        XCTAssertFalse(CoachDatabaseReadGuard.message(for: check).contains("SQLITE_IOERR_VNODE"))
    }
}
