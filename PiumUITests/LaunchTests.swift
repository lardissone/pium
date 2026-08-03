import XCTest

/// XCUITest needs a real GUI session, and Pium additionally needs a registered
/// global hotkey and a floating panel, so this target is skipped on CI and run
/// locally. This case exists to prove the target is wired up; the launcher
/// smoke tests arrive with the launcher itself.
final class LaunchTests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
    }
}
