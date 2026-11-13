import XCTest

/// L5 (13o): an unsaved schedule draft survives a language switch on the same screen (Settings is rebuilt by `.id(lang)`).
final class SettingsDraftUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testTheScheduleDraftSurvivesALanguageSwitch() {
        let app = XCUIApplication()
        app.launchArguments += ["-lang", "en", "-openTab", "settings", "-scrollTo", "schedule", "-screenshot"]
        app.launch()

        // change the reminder (allowed even when the times are locked) without saving
        let stepper = app.steppers.matching(NSPredicate(format: "label BEGINSWITH 'Reminder'")).firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 20), "no reminder stepper")
        stepper.buttons.element(boundBy: 1).tap()                        // increment
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the draft did not show Save")

        // the language picker is at the top of Settings
        let slovak = app.buttons["Slovenčina"]
        var swipes = 0
        while !(slovak.exists && slovak.isHittable) && swipes < 12 { app.swipeDown(); swipes += 1 }
        XCTAssertTrue(slovak.isHittable, "no language picker")
        slovak.tap()
        sleep(3)                                                         // Settings is rebuilt in Slovak

        // back down to the schedule: the draft is still there (the button now reads "Uložiť")
        let ulozit = app.buttons["Uložiť"]
        swipes = 0
        while !(ulozit.exists && ulozit.isHittable) && swipes < 12 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(ulozit.exists, "the unsaved schedule draft was lost by the language switch")
    }
}
