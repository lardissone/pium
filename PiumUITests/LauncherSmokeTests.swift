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
        app.launchArguments = [
            // Lands in NSArgumentDomain, so onboarding does not block the tests.
            "-pium.hasCompletedOnboarding", "YES",
            // The menu titles below are English. Without this the suite fails
            // whenever the developer has left Pium set to another language.
            "-AppleLanguages", "(en)",
        ]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
    }

    func testMenubarItemExists() {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    }

    func testOpenPiumFromMenubarShowsAFocusedEmptySearchField() {
        openLauncherFromMenubar()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        XCTAssertEqual(searchField.value as? String, "")
        XCTAssertTrue(searchField.hasKeyboardFocus)
    }

    func testEscapeDismissesTheLauncher() {
        openLauncherFromMenubar()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))

        searchField.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(searchField.waitForNonExistence(timeout: 10))
    }

    /// The panel is hidden with `orderOut` rather than destroyed, so the SwiftUI
    /// view stays mounted between openings. Without an explicit per-opening
    /// reset, only the first opening is cleared and focused — and an unfocused
    /// field never receives the Escape key either.
    func testSecondOpeningIsAlsoEmptyAndFocused() {
        openLauncherFromMenubar()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText("leftover")
        XCTAssertEqual(searchField.value as? String, "leftover")

        searchField.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(searchField.waitForNonExistence(timeout: 10))

        openLauncherFromMenubar()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        XCTAssertEqual(
            searchField.value as? String, "",
            "Every opening must start with an empty query"
        )
        XCTAssertTrue(
            searchField.hasKeyboardFocus,
            "Every opening must start with the input focused"
        )
    }

    func testTypingFindsAnApplication() {
        openLauncherFromMenubar()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText("safari")

        // Safari ships with macOS, so it is a safe target on any machine.
        XCTAssertTrue(
            app.staticTexts["Safari"].waitForExistence(timeout: 10),
            "Typing a known application name must show it in the results"
        )
    }

    func testArrowKeysMoveTheSelection() {
        openLauncherFromMenubar()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText("a")
        XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 10))

        let before = selectedRowTitle()
        searchField.typeKey(.downArrow, modifierFlags: [])
        XCTAssertNotEqual(before, selectedRowTitle(), "Down must move the selection")
    }

    /// A combined row exposes its title as the element's value, not its label.
    private func selectedRowTitle() -> String? {
        app.descendants(matching: .any)
            .matching(identifier: "result.row")
            .matching(NSPredicate(format: "selected == true"))
            .firstMatch
            .value as? String
    }

    private var statusItem: XCUIElement {
        app.menuBars.statusItems.firstMatch
    }

    private func openLauncherFromMenubar() {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        statusItem.click()
        let openItem = app.menuItems["Open Pium"]
        XCTAssertTrue(openItem.waitForExistence(timeout: 10))
        openItem.click()
    }
}

private extension XCUIElement {
    var hasKeyboardFocus: Bool {
        (value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }
}
