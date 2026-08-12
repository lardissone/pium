import Testing
import Foundation
@testable import Pium

/// Guards the two project settings whose loss is silent: without `LSUIElement`
/// a Dock icon appears, and a bundle identifier change breaks the logging
/// subsystem, the Keychain service name, and the Sparkle feed at once.
///
/// `Bundle.main` is the app bundle rather than the test bundle because
/// `PiumTests` sets `TEST_HOST` to the app.
@Suite("Project configuration")
struct ProjectConfigurationTests {
    @Test func appIsAUserInterfaceElement() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
    }

    @Test func bundleIdentifierIsStable() {
        #expect(Bundle.main.bundleIdentifier == "com.lardissone.pium")
    }
}
