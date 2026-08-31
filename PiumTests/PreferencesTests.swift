import Testing
import Foundation
import AppKit
import Carbon.HIToolbox
@testable import Pium

@Suite("Preferences")
@MainActor
struct PreferencesTests {
    /// Each test gets an isolated defaults domain so runs cannot see each
    /// other's writes or the developer's real settings.
    private func makeIsolatedPreferences() -> (Preferences, UserDefaults, String) {
        let suiteName = "com.lardissone.pium.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (Preferences(defaults: defaults), defaults, suiteName)
    }

    /// Nothing is excluded until the user says so: the hardcoded exclusions in
    /// `SpotlightQuery` are the only ones a fresh install has.
    @Test func noFoldersAreExcludedFromFileSearchByDefault() {
        let (preferences, _, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(preferences.excludedSearchFolders.isEmpty)
    }

    @Test func excludedFoldersSurviveAWriteAndReload() {
        let (preferences, defaults, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        preferences.excludedSearchFolders = ["node_modules", "/Users/someone/archive"]

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.excludedSearchFolders == ["node_modules", "/Users/someone/archive"])
    }

    /// Which combination that is depends on the build, so the expectation is
    /// written against the same source the app reads.
    @Test func shortcutDefaultsToTheProductDefault() {
        let (preferences, _, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(preferences.shortcut == .productDefault)
    }

    @Test func shortcutSurvivesAWriteAndReload() {
        let (preferences, defaults, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let custom = HotkeyShortcut(
            keyCode: UInt16(kVK_ANSI_P),
            modifiers: [.command, .shift],
            keyLabel: "P"
        )
        preferences.shortcut = custom

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.shortcut == custom)
    }

    /// A corrupt or older-format value must not crash or wedge the app, or the
    /// user is left with no way to open the launcher.
    @Test func corruptShortcutDataFallsBackToTheDefault() {
        let (_, defaults, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        defaults.set(Data("not json".utf8), forKey: "pium.shortcut")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.shortcut == .productDefault)
    }

    @Test func onboardingStartsIncomplete() {
        let (preferences, _, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(preferences.hasCompletedOnboarding == false)
        preferences.hasCompletedOnboarding = true
        #expect(preferences.hasCompletedOnboarding == true)
    }

    @Test func preferredLanguageDefaultsToSystem() {
        let (preferences, _, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(preferences.preferredLanguage == .system)
    }

    /// File search is a headline feature, so it is on out of the box.
    @Test func fileSearchIsOnByDefault() {
        let (preferences, _, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(preferences.isFileSearchEnabled)
    }

    /// The default being `true` is the reason this cannot lean on
    /// `bool(forKey:)`, which reports false for a key that was never written.
    @Test func fileSearchCanBeTurnedOffAndSurvivesAReload() {
        let (preferences, defaults, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        preferences.isFileSearchEnabled = false
        #expect(Preferences(defaults: defaults).isFileSearchEnabled == false)
    }

    /// The PRD defaults the scope to the user's home directory; searching every
    /// indexed volume is opt-in.
    @Test func scopeDefaultsToTheHomeDirectory() {
        let (preferences, _, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(preferences.fileSearchScope == .home)
    }

    @Test func scopeSurvivesAWriteAndReload() {
        let (preferences, defaults, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        preferences.fileSearchScope = .allIndexedLocal
        #expect(Preferences(defaults: defaults).fileSearchScope == .allIndexedLocal)
    }

    /// An unreadable value must not wedge search; the default takes over.
    @Test func anUnknownScopeFallsBackToTheDefault() {
        let (_, defaults, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        defaults.set("nonsense", forKey: "pium.fileSearchScope")
        #expect(Preferences(defaults: defaults).fileSearchScope == .home)
    }

    @Test func eachScopeMapsToASpotlightScope() {
        #expect(FileSearchScope.home.metadataScope == NSMetadataQueryUserHomeScope)
        #expect(FileSearchScope.allIndexedLocal.metadataScope == NSMetadataQueryLocalComputerScope)
    }

    /// Choosing a language writes `AppleLanguages` into Pium's own domain,
    /// which is how macOS overrides language for a single application.
    ///
    /// The suite's persistent domain is read directly rather than through
    /// `defaults.stringArray(for:)`, because a `UserDefaults` search list also
    /// covers `NSGlobalDomain` — where `AppleLanguages` always has a value.
    /// Reading through the search list would see the system's language and
    /// never observe the clear.
    @Test func choosingALanguageWritesAppleLanguagesIntoPiumsDomain() {
        let (preferences, _, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        preferences.preferredLanguage = .spanish
        let afterSet = UserDefaults.standard.persistentDomain(forName: suite)
        #expect(afterSet?["AppleLanguages"] as? [String] == ["es"])

        preferences.preferredLanguage = .system
        let afterClear = UserDefaults.standard.persistentDomain(forName: suite)
        #expect(afterClear?["AppleLanguages"] == nil)
    }

    @Test func noPluginIsDisabledByDefault() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(preferences.disabledPluginIDs.isEmpty)
    }

    @Test func disabledPluginsSurviveAroundTrip() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.disabledPluginIDs = ["web.yt", "demo.hello"]
        #expect(preferences.disabledPluginIDs == ["web.yt", "demo.hello"])
    }
}
