import XCTest

/// The running app's accessibility tree – what VoiceOver reads (13e4). English UI, a seeded town, no first-run guide.
final class AccessibilityUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-lang", "en", "-seedNights", "12", "-openTab", tab, "-screenshot"]
        app.launch()
        return app
    }

    func testTownBuildingsAreAccessibilityElementsAndTappable() throws {
        let app = launch(tab: "town")
        let summary = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Your town:'")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 20), "no town summary element")

        let digits = summary.label.filter(\.isNumber)
        let count = try XCTUnwrap(Int(digits), "no number in '\(summary.label)'")
        XCTAssertGreaterThan(count, 0)

        // the SKView's children: buttons on screen that are not tab bar buttons (labels are read once, up front)
        let screen = app.windows.firstMatch.frame
        let tabLabels = Set(app.tabBars.buttons.allElementsBoundByIndex.map { $0.label })
        // the header above the town (name, counts, coins) is made of buttons too
        let header = ["Town name:", "Complete buildings:", "Residents"]
        let labels: [String] = app.buttons.allElementsBoundByIndex.compactMap { b in
            guard b.exists, !b.label.isEmpty, !tabLabels.contains(b.label), !header.contains(where: b.label.hasPrefix),
                  !b.label.contains("🪙"), b.frame.width > 10, b.frame.height > 10,
                  screen.contains(CGPoint(x: b.frame.midX, y: b.frame.midY)) else { return nil }
            return b.label
        }
        XCTAssertGreaterThanOrEqual(labels.count, 1, "no building elements on screen")
        XCTAssertEqual(labels.count, count, "building elements differ from the summary's \(count): \(labels)")

        // a tap at an element's frame centre must hit that building and open its sheet
        var opened: String?
        for label in labels {
            let button = app.buttons[label].firstMatch
            guard button.exists else { continue }
            let name = label.components(separatedBy: ", ").first ?? label
            // 13y2: the whole card is the label (one sentence), nothing in the value
            XCTAssertTrue(label.hasPrefix(name) && label.contains("Night of") && label.contains("Level"), "no card in the label '\(label)'")
            button.tap()
            let night = app.descendants(matching: .any)["buildingSheetSummary"]
            if night.waitForExistence(timeout: 3) {
                let sentence = night.label
                XCTAssertTrue(sentence.hasPrefix(name) && sentence.contains("Night of") && sentence.contains("Level"), "the sheet block: '\(sentence)'")
                XCTAssertEqual(sentence, label, "the sheet and the town element differ")
                XCTAssertFalse(app.staticTexts[name].exists, "a separate name element is left in the sheet")
                opened = name
                // a tap on the dimmed area above the sheet dismisses it
                app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
                XCTAssertTrue(night.waitForNonExistence(timeout: 5), "sheet did not close")
                break
            }
        }
        XCTAssertNotNil(opened, "no building element opened the building sheet")
    }

    func testStatsCalendarDaysAndTilesAreSingleElements() {
        let app = launch(tab: "stats")
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'best streak'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "no 'best streak' tile")

        let day = app.buttons.matching(NSPredicate(
            format: "label MATCHES '.*[0-9]{4}.*, (complete|unfinished|ruins|excused).*'")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 10), "no calendar day with a full date and an outcome")
    }

    func testTodayBadgesAreSingleElements() {
        let app = launch(tab: "today")
        let coins = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Coins:'")).firstMatch
        XCTAssertTrue(coins.waitForExistence(timeout: 20), "no coin badge element")
        let streak = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS 'nights in a row' OR label CONTAINS 'streak starts today'")).firstMatch
        XCTAssertTrue(streak.waitForExistence(timeout: 10), "no streak badge element")
        XCTAssertTrue(streak.label.contains("keep it going") || streak.label.contains("first good night"),
                      "the streak badge is not one combined element: '\(streak.label)'")
    }
}
