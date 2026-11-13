import XCTest

/// The wake code (13n): the digits typed on the night screen survive the swap to the alarm screen (B42) – the digits live in `AppModel`, so the black rest screen of 13k keeps them too – and the alarm screen's field can be focused by a tap on the smallest phone at a large text size (B43).
final class WakeCodeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The app is not reinstalled between tests: leave an empty store behind.
    override func tearDown() {
        let app = XCUIApplication()
        app.launchArguments = ["-clearNights", "-screenshot", "-mute"]
        app.launch()
        app.terminate()
    }

    private func launch(minutes: Int, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-clearNights", "-startTestNight", "-testNightGrace", "5", "-testNightMinutes", "\(minutes)",
                                "-mute", "-screenshot", "-lang", "en"] + extra
        app.launch()
        return app
    }

    private func value(_ field: XCUIElement) -> String { (field.value as? String) ?? "?" }

    /// B42: "12" typed just before the wake time is still there on the alarm screen, with the keyboard up.
    func testTheTypedCodeSurvivesTheAlarm() {
        let app = launch(minutes: 1)
        let field = app.textFields["Code"]
        XCTAssertTrue(field.waitForExistence(timeout: 60), "no code field on the night screen")
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "no keyboard after the tap")
        field.typeText("12")
        XCTAssertEqual(value(field), "12")
        XCTAssertTrue(app.staticTexts["Good morning ☀️"].waitForExistence(timeout: 90), "the alarm screen did not come")
        let f2 = app.textFields["Code"]
        XCTAssertTrue(f2.waitForExistence(timeout: 10))
        XCTAssertEqual(value(f2), "12", "the typed digits were lost at the swap")
        XCTAssertTrue(app.keyboards.count > 0, "the keyboard went away at the swap")
        f2.typeText("34")                                   // fails when the field has no focus
        XCTAssertEqual(value(f2), "1234")
    }

    /// B43: on the iPhone SE at accessibility-medium a tap on the alarm's field raises the keyboard and the field takes the digits.
    func testTheAlarmFieldTakesFocusAtALargeText() {
        let app = launch(minutes: 1, extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"])
        XCTAssertTrue(app.staticTexts["Good morning ☀️"].waitForExistence(timeout: 120), "the alarm screen did not come")
        let field = app.textFields["Code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "no keyboard after the tap")
        field.typeText("12")
        XCTAssertEqual(value(app.textFields["Code"]), "12")
    }
}
