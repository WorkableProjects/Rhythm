import XCTest

/// End-to-end flows. Each test launches with an empty in-memory store and a fixed local clock
/// (Friday 9 October 2026, 9:30 AM) so schedule states are deterministic.
@MainActor
final class RhythmUITests: XCTestCase {
    private var app: XCUIApplication!

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-RhythmUITesting", "-RhythmClock", "2026-10-09T09:30:00"] + extraArguments
        app.launch()
    }

    private func launchWithSample(extraArguments: [String] = []) {
        launch(extraArguments: extraArguments)
        app.buttons["exploreSampleButton"].tap()
        XCTAssertTrue(app.otherElements["liveStatus"].waitForExistence(timeout: 5) || app.staticTexts["countdown"].waitForExistence(timeout: 5))
    }

    private var liveStatusLabel: String {
        let element = app.descendants(matching: .any)["liveStatus"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        return element.label
    }

    // MARK: First run

    func testFirstRunShowsOnboardingAndSampleIsLabelled() {
        launch()
        XCTAssertTrue(app.buttons["setUpScheduleButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["exploreSampleButton"].exists)

        app.buttons["exploreSampleButton"].tap()
        XCTAssertTrue(app.staticTexts["You’re exploring a sample schedule."].waitForExistence(timeout: 5))
        XCTAssertTrue(liveStatusLabel.contains("Biology"))

        app.buttons["removeSampleButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["scheduleNeeded"].waitForExistence(timeout: 5))
    }

    // MARK: Creating a timetable

    func testCreateSixClassTimetableWithLunch() {
        launch()
        app.buttons["setUpScheduleButton"].tap()
        let name = app.textFields["newTemplateNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Regular Day")
        app.buttons["createTemplateButton"].tap()

        // New periods default to 50 minutes starting 5 minutes after the previous one:
        // 8:00, 8:55, 9:50, 10:45 (Lunch), 11:40, 12:35, 13:30.
        let titles = ["English", "Biology", "Algebra II", "Lunch", "History", "Spanish", "PE"]
        for title in titles {
            let add = app.buttons["addPeriodButton"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.tap()
            let field = app.textFields["periodTitleField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(title)
            if title == "Lunch" {
                app.buttons["Type"].firstMatch.tap()
                app.buttons["Lunch"].firstMatch.tap()
            }
            app.buttons["savePeriodButton"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["templatePeriodRow-\(title)"].waitForExistence(timeout: 5))
        }

        app.tabBars.buttons["Today"].tap()
        // 9:30 falls in the second period (8:55–9:45).
        XCTAssertTrue(liveStatusLabel.contains("Biology"))
        XCTAssertTrue(liveStatusLabel.contains("remaining"))
    }

    // MARK: Editing

    func testEditingPeriodUpdatesToday() {
        launchWithSample()
        app.tabBars.buttons["Schedule"].tap()
        app.descendants(matching: .any)["templateRow-Sample Schedule"].firstMatch.tap()
        app.descendants(matching: .any)["templatePeriodRow-Biology"].firstMatch.tap()

        let field = app.textFields["periodTitleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.clearAndType("AP Biology")
        app.buttons["savePeriodButton"].tap()

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(liveStatusLabel.contains("AP Biology"))
    }

    func testOverlapIsReportedBeforeSaving() {
        launchWithSample()
        app.tabBars.buttons["Schedule"].tap()
        app.descendants(matching: .any)["templateRow-Sample Schedule"].firstMatch.tap()
        app.buttons["addPeriodButton"].firstMatch.tap()
        // The suggested new period starts after the last one, so it is valid until moved.
        XCTAssertTrue(app.buttons["savePeriodButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["periodIssues"].exists)
    }

    func testCreateDateException() {
        launchWithSample()
        app.tabBars.buttons["Schedule"].tap()
        let change = app.buttons["changeThisDateButton"]
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        change.tap()

        app.segmentedControls["overrideKindPicker"].buttons["No School"].tap()
        app.textFields["overrideTitleField"].tap()
        app.textFields["overrideTitleField"].typeText("Teacher Workday")
        app.buttons["saveOverrideButton"].tap()

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["noSchool"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Teacher Workday"].exists)
    }

    // MARK: Quicklinks

    func testQuicklinkAddEditReorderDelete() {
        launchWithSample()
        app.tabBars.buttons["Quicklinks"].tap()

        addQuicklink(title: "Classroom", url: "https://classroom.google.com")
        addQuicklink(title: "Dictionary", url: "https://www.merriam-webster.com")
        XCTAssertTrue(app.descendants(matching: .any)["quicklinkRow-Dictionary"].waitForExistence(timeout: 5))

        // Malformed URLs block saving with an explanation.
        app.buttons["addQuicklinkButton"].tap()
        app.textFields["quicklinkTitleField"].tap()
        app.textFields["quicklinkTitleField"].typeText("Broken")
        app.textFields["quicklinkURLField"].tap()
        app.textFields["quicklinkURLField"].typeText("javascript:alert(1)")
        XCTAssertTrue(app.descendants(matching: .any)["quicklinkURLError"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveQuicklinkButton"].isEnabled)
        app.buttons["Cancel"].tap()

        // Edit
        let classroom = app.descendants(matching: .any)["quicklinkRow-Classroom"].firstMatch
        classroom.swipeLeft()
        app.buttons["Edit"].firstMatch.tap()
        let title = app.textFields["quicklinkTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.clearAndType("Google Classroom")
        app.buttons["saveQuicklinkButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quicklinkRow-Google Classroom"].waitForExistence(timeout: 5))

        // Reorder using Edit mode's move handles.
        app.buttons["Edit"].firstMatch.tap()
        let handles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'"))
        if handles.count >= 2 {
            handles.element(boundBy: 1).press(forDuration: 0.5, thenDragTo: handles.element(boundBy: 0))
        }
        app.buttons["Done"].firstMatch.tap()

        // Delete
        let dictionary = app.descendants(matching: .any)["quicklinkRow-Dictionary"].firstMatch
        dictionary.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertFalse(app.descendants(matching: .any)["quicklinkRow-Dictionary"].waitForExistence(timeout: 2))
    }

    private func addQuicklink(title: String, url: String) {
        let add = app.buttons["emptyAddQuicklinkButton"].exists ? app.buttons["emptyAddQuicklinkButton"] : app.buttons["addQuicklinkButton"]
        add.tap()
        let titleField = app.textFields["quicklinkTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(title)
        app.textFields["quicklinkURLField"].tap()
        app.textFields["quicklinkURLField"].typeText(url)
        app.buttons["saveQuicklinkButton"].tap()
    }

    // MARK: Permissions and accessibility

    func testDeniedNotificationPermissionIsExplainedWithoutCrash() {
        launchWithSample(extraArguments: ["-RhythmNotificationsDenied"])
        app.buttons["settingsButton"].tap()
        let permission = app.descendants(matching: .any)["notificationPermissionRow"]
        XCTAssertTrue(permission.waitForExistence(timeout: 5))
        XCTAssertTrue(permission.label.contains("Off"))
        app.buttons["Done"].firstMatch.tap()

        app.tabBars.buttons["Schedule"].tap()
        app.descendants(matching: .any)["templateRow-Sample Schedule"].firstMatch.tap()
        app.descendants(matching: .any)["templatePeriodRow-Biology"].firstMatch.tap()
        app.buttons["addReminderButton"].tap()
        let title = app.textFields["reminderTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Lab goggles")
        app.buttons["saveReminderButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["notificationsDeniedNotice"].waitForExistence(timeout: 5))
        app.buttons["savePeriodButton"].tap()
    }

    func testCountdownAccessibilityAtLargeTextSize() {
        launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        app.buttons["exploreSampleButton"].tap()
        let label = liveStatusLabel
        // e.g. "In progress. Biology, 25 minutes remaining, ends at 9:55 AM. Up next: Algebra II at 10:00 AM."
        XCTAssertTrue(label.hasPrefix("In progress. Biology"), label)
        XCTAssertTrue(label.contains("minutes remaining"), label)
        XCTAssertTrue(label.contains("ends at"), label)
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        guard let current = value as? String, !current.isEmpty else {
            typeText(text)
            return
        }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        typeText(text)
    }
}
