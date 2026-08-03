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
        let suiteName = "app.pium.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (Preferences(defaults: defaults), defaults, suiteName)
    }

    @Test func shortcutDefaultsToOptionSpace() {
        let (preferences, _, suite) = makeIsolatedPreferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(preferences.shortcut == .optionSpace)
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
        #expect(preferences.shortcut == .optionSpace)
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
}
