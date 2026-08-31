import Testing
import Foundation
@testable import Pium

/// The released build's names are what an installed copy already stores under,
/// so a change here is a silent data loss on every machine that updates:
/// settings, usage history and plugin secrets would all be looked for
/// somewhere new and found empty.
@Suite("AppIdentity")
struct AppIdentityTests {
    private let release = AppIdentity(bundleIdentifier: "com.lardissone.pium")
    private let development = AppIdentity(bundleIdentifier: "com.lardissone.pium.debug")

    @Test func theReleasedBuildKeepsTheNamesItAlreadyUses() {
        #expect(release.isRelease)
        #expect(release.folderName == "Pium")
        #expect(release.keychainService == "com.lardissone.pium.plugin-secrets")
        #expect(release.supportDirectory.lastPathComponent == "Pium")
        #expect(release.cacheDirectory.lastPathComponent == "Pium")
    }

    @Test func aDevelopmentBuildStoresSomewhereElseEntirely() {
        #expect(!development.isRelease)
        #expect(development.folderName == "Pium.debug")
        #expect(development.keychainService != release.keychainService)
        #expect(development.supportDirectory != release.supportDirectory)
        #expect(development.cacheDirectory != release.cacheDirectory)
    }

    /// The shortcut is the one piece of state macOS itself refuses to share:
    /// `RegisterEventHotKey` gives a combination to one process, so two copies
    /// that agreed on a default would leave whichever started second mute.
    @Test func theTwoBuildsDoNotStartOnTheSameShortcut() {
        #expect(HotkeyShortcut.optionSpace != HotkeyShortcut.controlOptionSpace)
        #expect(HotkeyShortcut.controlOptionSpace.isValid)
    }
}
