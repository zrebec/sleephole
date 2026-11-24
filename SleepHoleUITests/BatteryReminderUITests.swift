import XCTest

/// The battery reminder (13l): during the setup of a night the phone at 30 % or less and unplugged gets a calm note; a plugged
/// phone gets none; it is gone when the setup ends. `-fakeBattery` works in the simulator only.
final class BatteryReminderUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The app is not reinstalled between tests: a night left in the store would be resumed by the next test class
    /// (13l: `GuideLanguageUITests` then found a running night instead of Settings). Leave an empty store behind.
    override func tearDown() {
        let app = XCUIApplication()
        app.launchArguments = ["-clearNights", "-screenshot", "-mute"]
        app.launch()
        app.terminate()
    }

    private func launch(_ battery: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-clearNights", "-startTestNight", "-testNightGrace", "30", "-testNightMinutes", "40",
                                "-fakeBattery", battery, "-screenshot", "-mute", "-lang", "en"]
        app.launch()
        return app
    }

    private func note(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'The battery is at'")).firstMatch
    }

    func testTheNoteShowsInTheSetupAndIsGoneAfterIt() {
        let app = launch("0.24")
        let n = note(app)
        XCTAssertTrue(n.waitForExistence(timeout: 30), "no battery note in the setup")
        XCTAssertTrue(n.label.contains("24%"), "label: \(n.label)")
        XCTAssertTrue(n.label.contains("Put the phone on the charger"), "label: \(n.label)")
        XCTAssertTrue(app.buttons["Cancel night"].isHittable, "'Cancel night' is not reachable")
        XCTAssertTrue(n.waitForNonExistence(timeout: 90), "the note stayed after the setup")
    }

    func testNoNoteWhenCharging() {
        let app = launch("0.24,charging")
        XCTAssertTrue(app.buttons["Cancel night"].waitForExistence(timeout: 30))
        XCTAssertFalse(note(app).exists, "a charging phone got the note")
    }
}
