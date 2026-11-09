import XCTest

/// 13z: "Try the rise" shows a progress line; its percent grows; the stop button hides it.
final class RisePreviewUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testTheProgressLineAppearsGrowsAndStops() {
        let app = XCUIApplication()
        app.launchArguments += ["-lang", "en", "-seedNights", "12", "-openTab", "settings", "-scrollTo", "alarmRise",
                                "-riseSeconds", "120", "-screenshot", "-mute"]
        app.launch()
        let line = app.descendants(matching: .any).matching(identifier: "risePreviewLine").firstMatch
        XCTAssertFalse(line.exists)
        let try_ = app.buttons["Try the rise"]
        XCTAssertTrue(try_.waitForExistence(timeout: 20))
        try_.tap()
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertTrue(line.label.hasPrefix("Now "), line.label)
        XCTAssertTrue(line.label.contains("/ 120s"), line.label)
        Thread.sleep(forTimeInterval: 10)
        let digits = line.label.dropFirst(4).prefix { $0.isNumber }
        XCTAssertGreaterThan(Int(digits) ?? 0, 30, line.label)
        app.buttons["riseStop"].tap()
        XCTAssertTrue(NSPredicate(format: "exists == false").evaluate(with: line) || {
            let e = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: line)
            return XCTWaiter().wait(for: [e], timeout: 3) == .completed
        }())
    }
}
