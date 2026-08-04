import Foundation

/// Typed access to Pium's settings.
///
/// Every key carries a `pium.` prefix so a future migration can find and
/// rewrite Pium's own keys without touching system keys stored in the same
/// domain. Values that macOS itself reads, such as `AppleLanguages`, keep
/// their system names.
@MainActor
final class Preferences {
    static let shared = Preferences(defaults: .standard)

    private enum Key {
        static let shortcut = "pium.shortcut"
        static let hasCompletedOnboarding = "pium.hasCompletedOnboarding"
        static let preferredLanguage = "pium.preferredLanguage"
        static let isFileSearchEnabled = "pium.isFileSearchEnabled"
        static let fileSearchScope = "pium.fileSearchScope"
        /// Read by macOS at launch to pick the application's language.
        static let appleLanguages = "AppleLanguages"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The combination that summons the launcher.
    var shortcut: HotkeyShortcut {
        get {
            guard
                let data = defaults.data(forKey: Key.shortcut),
                let decoded = try? JSONDecoder().decode(HotkeyShortcut.self, from: data)
            else {
                // Missing or unreadable: the product default takes over rather
                // than leaving the user with no way to open the launcher.
                return .optionSpace
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.shortcut)
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    /// Whether Spotlight is consulted at all. Off means no query is issued,
    /// rather than results discarded after the fact, so this is also how a user
    /// opts out of Spotlight traffic entirely.
    var isFileSearchEnabled: Bool {
        get {
            // `bool(forKey:)` reports false for a missing key and the product
            // default is on, so the absence has to be checked explicitly.
            guard defaults.object(forKey: Key.isFileSearchEnabled) != nil else { return true }
            return defaults.bool(forKey: Key.isFileSearchEnabled)
        }
        set { defaults.set(newValue, forKey: Key.isFileSearchEnabled) }
    }

    /// Where file search looks. The PRD defaults this to the home directory;
    /// every indexed volume is opt-in.
    var fileSearchScope: FileSearchScope {
        get {
            guard
                let raw = defaults.string(forKey: Key.fileSearchScope),
                let scope = FileSearchScope(rawValue: raw)
            else {
                return .home
            }
            return scope
        }
        set { defaults.set(newValue.rawValue, forKey: Key.fileSearchScope) }
    }

    /// Language override for Pium's own interface. Takes effect on next launch.
    var preferredLanguage: PreferredLanguage {
        get {
            guard
                let raw = defaults.string(forKey: Key.preferredLanguage),
                let language = PreferredLanguage(rawValue: raw)
            else {
                return .system
            }
            return language
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.preferredLanguage)
            if let code = newValue.languageCode {
                defaults.set([code], forKey: Key.appleLanguages)
            } else {
                defaults.removeObject(forKey: Key.appleLanguages)
            }
        }
    }
}

/// Which language Pium's interface uses, independent of the system setting.
enum PreferredLanguage: String, CaseIterable, Sendable {
    case system
    case english
    case spanish

    /// BCP 47 code written to `AppleLanguages`; `nil` means defer to the system.
    var languageCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .spanish: "es"
        }
    }
}
