import Testing
import ServiceManagement
@testable import Pium

@Suite("LoginItemController")
@MainActor
struct LoginItemControllerTests {
    /// The product ships with launch at login off. This describes a fresh
    /// install: it only holds while the service has never been registered on
    /// the machine running the tests.
    @Test func launchAtLoginIsOffByDefault() {
        let controller = LoginItemController()
        #expect(controller.isEnabled == false)
    }

    /// `isEnabled` must report what macOS actually thinks, not a cached flag
    /// the app set for itself, or the Settings toggle drifts from reality.
    @Test func enabledStateMirrorsTheSystemService() {
        let controller = LoginItemController()
        #expect(controller.isEnabled == (SMAppService.mainApp.status == .enabled))
    }
}
