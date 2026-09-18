import XCTest

/// Screenshots of the screens that hold the exercise images, for eyeballing
/// the screen-width scale on any simulator: Today (composite rows), a Library
/// muscle list (catalog rows with the line-art flip), and a detail sheet (the
/// hero). Since 2026-09-15 the thumbnail, the tile paddings and the hero
/// height take `ScreenScale.factor` like the type does, so a Pro Max draws a
/// 94pt thumbnail and a 17e an 80pt one. The assertions are existence only;
/// the attachments are the check. Run it against two devices and compare:
///
///     xcodebuild test -only-testing:PhaseTrainingUITests/ImageSlotScalingUITests \
///         -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
///
/// Runs without the Mac's display being awake, which the click-through
/// verification (`cliclick`) does not.
final class ImageSlotScalingUITests: XCTestCase {

    func test_imageSlotsOnTodayLibraryAndDetail() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-plan-demo"]
        app.launch()

        let today = app.tabBars.buttons["Today"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        attach(app, "today-rows")

        let library = app.tabBars.buttons["Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        // Core holds ab wheel rollout, plank and hanging knee raise, all with
        // generated line art, at the top of the alphabetical list.
        let core = app.buttons["library-tile-core"]
        XCTAssertTrue(core.waitForExistence(timeout: 5), "Core tile should exist on the Library tab")
        core.tap()
        let rollout = app.staticTexts["Ab Wheel Rollout"].firstMatch
        XCTAssertTrue(rollout.waitForExistence(timeout: 5), "Core list should render its rows")
        attach(app, "library-core-rows")

        rollout.tap()
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "detail sheet should open")
        // Two shots a hold apart so both frames of the hero crossfade land
        // in the attachments (LineArtHero holds each position 1.6 s).
        attach(app, "detail-hero-a")
        Thread.sleep(forTimeInterval: 1.7)
        attach(app, "detail-hero-b")
        done.tap()

        // A row still on a photo (the drills are the last to be drawn), so
        // the page's non-art layout is in the attachments too.
        let skip = app.staticTexts["A-Skip Running Drill"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5), "photo exercise's detail sheet should open")
        attach(app, "detail-photo")
        done.tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
