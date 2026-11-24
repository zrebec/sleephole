import XCTest

/// The volume reminder (13r): a running night with a low media volume shows a calm line under the alarm time.
/// `-fakeVolume` works in the simulator only.
final class VolumeReminderUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    override func tearDown() {
        let app = XCUIApplication()
        app.launchArguments = ["-clearNights", "-screenshot", "-mute"]
        app.launch()
        app.terminate()
    }

    private func launch(_ volume: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-clearNights", "-startTestNight", "-testNightGrace", "30", "-testNightMinutes", "40",
                                "-fakeVolume", volume, "-screenshot", "-mute", "-lang", "en"]
        app.launch()
        return app
    }

    private func note(_ app: XCUIApplication, _ word: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", word)).firstMatch
    }

    func testLowShowsTheTurnedDownLine() {
        let app = launch("0.12")
        XCTAssertTrue(note(app, "The sound is turned down").waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Cancel night"].isHittable)
    }

    func testZeroShowsTheOffLine() {
        let app = launch("0")
        XCTAssertTrue(note(app, "The sound is off").waitForExistence(timeout: 30))
    }

    func testNormalVolumeShowsNothing() {
        let app = launch("0.6")
        XCTAssertTrue(app.buttons["Cancel night"].waitForExistence(timeout: 30))
        XCTAssertFalse(note(app, "The sound is").exists)
    }

    /// B54a (13ad): the alarm screen says why it is silent, and the code field is still there to reach.
    func testTheAlarmScreenShowsTheOffLine() {
        let app = XCUIApplication()
        app.launchArguments += ["-clearNights", "-startTestNight", "-testNightGrace", "5", "-testNightMinutes", "1",
                                "-fakeVolume", "0", "-screenshot", "-mute", "-lang", "en"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Good morning ☀️"].waitForExistence(timeout: 120), "the alarm screen did not come")
        XCTAssertTrue(note(app, "The sound is off").waitForExistence(timeout: 10), "no volume line on the alarm screen")
        XCTAssertTrue(app.textFields["Code"].exists)
    }

    func testTheAlarmScreenKeepsTheCodeFieldReachableAtTheLargestText() {
        let app = XCUIApplication()
        app.launchArguments += ["-clearNights", "-startTestNight", "-testNightGrace", "5", "-testNightMinutes", "1",
                                "-fakeVolume", "0", "-screenshot", "-mute", "-lang", "en",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Good morning ☀️"].waitForExistence(timeout: 120), "the alarm screen did not come")
        XCTAssertTrue(note(app, "The sound is off").waitForExistence(timeout: 10))
        let field = app.textFields["Code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        // At AX5 the panel's own texts already fill the first screen (the same without the volume line – 13ad screenshots
        // on the 16 Pro and the 17e): the screen scrolls. The line sits BELOW the panel, so it never pushes the field down.
        XCTAssertLessThan(field.frame.minY, note(app, "The sound is off").frame.minY, "the line is above the code field")
        if !field.isHittable { app.swipeUp() }
        XCTAssertTrue(field.isHittable, "the code field is out of reach")
    }
}
