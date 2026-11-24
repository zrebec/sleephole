import XCTest

/// B40 (13h): the replayed guide (Settings → Guide) must stay open when its language picker switches the language.
final class GuideLanguageUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testReplayedGuideSurvivesALanguageSwitch() {
        let app = XCUIApplication()
        app.launchArguments += ["-lang", "cs", "-openTab", "settings", "-scrollTo", "schedule", "-screenshot"]
        app.launch()

        // Settings in Czech: the "Průvodce" button (maybe below the fold)
        let open = app.buttons["Průvodce"]
        var swipes = 0
        _ = open.waitForExistence(timeout: 20)
        while !(open.exists && open.isHittable) && swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(open.exists, "no 'Průvodce' button in Settings")
        open.tap()

        // page 0 of the guide holds the language picker
        let slovak = app.buttons["Slovenčina"]
        XCTAssertTrue(slovak.waitForExistence(timeout: 10), "the replayed guide did not open")
        shot(app, "guide-cs")
        slovak.tap()
        sleep(3)
        shot(app, "guide-after-sk")
        XCTAssertTrue(app.buttons["Slovenčina"].exists, "the guide closed after switching to Slovak")
        XCTAssertTrue(app.buttons["English"].exists)
        XCTAssertTrue(app.buttons["Ďalej"].exists, "the guide is not in Slovak")

        app.buttons["English"].tap()
        sleep(3)
        shot(app, "guide-after-en")
        XCTAssertTrue(app.buttons["English"].exists, "the guide closed after switching to English")
        XCTAssertTrue(app.buttons["Next"].exists, "the guide is not in English")

        // Close is on the last page
        var taps = 0
        while !app.buttons["Close"].exists && taps < 12 {
            app.buttons["Next"].tap(); taps += 1
        }
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["English"].waitForNonExistence(timeout: 5), "Close did not close the guide")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let dir = "/Users/zrebec/Projects/sleephole/build/13h/shots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
}
