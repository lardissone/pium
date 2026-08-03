import XCTest

/// Smoke coverage for the native shell.
///
/// These run locally only: XCUITest needs a real GUI session, and Pium
/// additionally needs a registered global hotkey and a floating panel. CI skips
/// this target on purpose.
final class LauncherSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Lands in NSArgumentDomain, so onboarding does not block the tests.
        app.launchArguments = ["-pium.hasCompletedOnboarding", "YES"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
    }

    func testMenubarItemExists() {
        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    }

    func testOpenPiumFromMenubarShowsAFocusedEmptySearchField() {
        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        statusItem.click()
        app.menuItems["Open Pium"].click()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        XCTAssertEqual(searchField.value as? String, "")
        XCTAssertTrue(searchField.hasKeyboardFocus)
    }

    func testEscapeDismissesTheLauncher() {
        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        statusItem.click()
        app.menuItems["Open Pium"].click()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))

        searchField.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(searchField.waitForNonExistence(timeout: 10))
    }
}

private extension XCUIElement {
    var hasKeyboardFocus: Bool {
        (value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }
}
