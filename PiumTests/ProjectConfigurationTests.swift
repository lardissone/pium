import Testing
import Foundation
@testable import Pium

/// Guards the project settings whose loss is silent: without `LSUIElement`
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

    /// Sparkle reads both of these from the bundle and there is no code path
    /// that can supply them instead. A missing public key does not fail the
    /// build; it fails every update, at the point where a signature is
    /// checked, on a user's machine.
    @Test func theBundleCarriesSparkleConfiguration() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        #expect(feed?.hasPrefix("https://") == true)

        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        #expect(key?.isEmpty == false)
    }

    /// The key that keeps discovery and installation separate (PRD §13).
    /// Sparkle only refuses to download automatically while it reads `false`
    /// from the bundle; absent, it infers permission from
    /// `automaticallyChecksForUpdates` — true — and offers "download and
    /// install automatically" again. A merge that drops it, or an
    /// `INFOPLIST_FILE` setting that stops being applied, breaks the headline
    /// product rule with the build green.
    @Test func automaticInstallationIsNotOffered() {
        let allows = Bundle.main.object(forInfoDictionaryKey: "SUAllowsAutomaticUpdates") as? Bool
        #expect(allows == false)
    }

    /// PRD §13: every six hours.
    @Test func updatesAreCheckedEverySixHours() {
        let interval = Bundle.main.object(forInfoDictionaryKey: "SUScheduledCheckInterval") as? Int
        #expect(interval == 21600)
    }
}
