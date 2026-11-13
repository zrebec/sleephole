import XCTest

/// The black rest screen (13k): after the setup, 15 s without a touch (`-restAfter 15`) the night screen turns black; a tap brings it back, the first tap only wakes (the control under it is not pressed), and it comes again after the wait.
final class RestScreenUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The app is not reinstalled between tests: a night left in the store would be resumed by the next test class
    /// (13l: `GuideLanguageUITests` then found a running night instead of Settings). Leave an empty store behind.
    override func tearDown() {
        let app = XCUIApplication()
        app.launchArguments = ["-clearNights", "-screenshot", "-mute"]
        app.launch()
        app.terminate()
    }

    func testTheNightScreenRestsAfterTheSetupAndWakesOnATap() {
        // `-clearNights`: the app is not reinstalled between runs, and a night left by an earlier run (40 min long) would
        // be resumed – or already at its alarm – instead of a fresh one.
        // `-restAfter 15` (not 4): XCUITest's own wait for the app to go idle takes several seconds after a tap, and with a
        // 4 s gap the rest came back before the checks after the wake looked.
        let app = XCUIApplication()
        app.launchArguments += ["-clearNights", "-startTestNight", "-testNightGrace", "5", "-testNightMinutes", "40", "-restAfter", "15",
                                "-mute", "-screenshot", "-lang", "en"]
        app.launch()

        let cancel = app.buttons["Cancel night"]
        let rest = app.descendants(matching: .any)["restScreen"]
        // the launch can take longer than the 5 s setup + 15 s, so the night screen may already be black when we look
        let up = NSPredicate { _, _ in cancel.exists || rest.exists }
        wait(for: [XCTNSPredicateExpectation(predicate: up, object: nil)], timeout: 30)

        // 5 s of setup + 15 s without a touch
        XCTAssertTrue(rest.waitForExistence(timeout: 60), "the night screen did not rest")
        XCTAssertFalse(cancel.exists && cancel.isHittable, "'Cancel night' is still reachable under the rest screen")
        XCTAssertTrue(rest.label.contains("Lock the phone"), "label: \(rest.label)")

        // a tap on the spot where 'Cancel night' was: it only wakes, it opens nothing
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.878)).tap()
        XCTAssertTrue(rest.waitForNonExistence(timeout: 5), "a tap did not end the rest")
        XCTAssertTrue(cancel.isHittable, "the night screen did not come back")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'End tonight early'")).firstMatch.exists,
                       "the first tap pressed 'Cancel night'")

        // untouched again → rests again
        XCTAssertTrue(rest.waitForExistence(timeout: 60), "the night screen did not rest a second time")
    }

    /// B51 (13ad): a nap rests like a night – the setup of a nap is 2 min, then 15 s without a touch (`-restAfter 15`).
    func testTheNapScreenRestsToo() {
        let app = XCUIApplication()
        app.launchArguments += ["-clearNights", "-startNap", "-restAfter", "15", "-mute", "-screenshot", "-lang", "en"]
        app.launch()
        let rest = app.descendants(matching: .any)["restScreen"]
        XCTAssertTrue(rest.waitForExistence(timeout: 240), "the nap screen did not rest")
        XCTAssertTrue(rest.label.contains("Lock the phone"), "label: \(rest.label)")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(rest.waitForNonExistence(timeout: 5), "a tap did not end the nap's rest")
    }
}
