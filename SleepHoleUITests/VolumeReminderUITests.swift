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
}
