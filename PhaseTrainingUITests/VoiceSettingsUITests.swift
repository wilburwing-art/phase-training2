import XCTest

/// Profile > Voice (voice 2.1): the sheet opens from the APP group, cues
/// start off, turning them on shows the cue levels, and the choice sticks on
/// the row after Done.
final class VoiceSettingsUITests: XCTestCase {

    func test_turnCuesOnAndPickFullLevel() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset"]
        app.launch()

        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()

        let row = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Voice")).firstMatch
        var swipes = 0
        while !(row.exists && row.isHittable) && swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Voice row should exist")
        XCTAssertTrue(row.label.contains("Cues off"), row.label)
        row.tap()

        let cues = app.switches["voice.cues"]
        XCTAssertTrue(cues.waitForExistence(timeout: 5))
        XCTAssertEqual(cues.value as? String, "0")
        XCTAssertFalse(app.buttons["voice.level.full"].exists, "levels stay hidden while cues are off")
        XCTAssertTrue(app.buttons["voice.pick.automatic"].exists)
        XCTAssertTrue(app.buttons["voice.sample"].exists)

        cues.switches.firstMatch.tap()
        XCTAssertEqual(cues.value as? String, "1")
        let full = app.buttons["voice.level.full"]
        XCTAssertTrue(full.waitForExistence(timeout: 5))
        full.tap()
        XCTAssertTrue(full.isSelected)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "voice-settings-sheet"
        add(shot)

        app.buttons["Done"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Cues on"), row.label)
    }
}
