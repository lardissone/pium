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
