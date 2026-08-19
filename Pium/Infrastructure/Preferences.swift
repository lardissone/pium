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
        static let disabledPluginIDs = "pium.disabledPluginIDs"
        static let hudAnchor = "pium.hudAnchor"
        static let requestedFolderAccess = "pium.requestedFolderAccess"
        static let debugLoggingExpiry = "pium.debugLoggingExpiry"
        static let additionalSearchPaths = "pium.additionalSearchPaths"
        static let excludedSearchFolders = "pium.excludedSearchFolders"
        static let bookmarks = "pium.bookmarks"
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

    /// Plugins the user switched off. Disabled means absent from search; the
    /// Plugins section of Preferences is the way back, so a disabled plugin is
    /// never hidden there.
    var disabledPluginIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.disabledPluginIDs) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Key.disabledPluginIDs) }
    }

    /// Where HUD panels appear on screen.
    var hudAnchor: HUDAnchor {
        get {
            defaults.string(forKey: Key.hudAnchor).flatMap(HUDAnchor.init(rawValue:)) ?? .topRight
        }
        set { defaults.set(newValue.rawValue, forKey: Key.hudAnchor) }
    }

    /// When the current debug logging session ends; `nil` when there is none.
    ///
    /// A deadline rather than a switch: see `DebugLogging`.
    var debugLoggingExpiry: Date? {
        get { defaults.object(forKey: Key.debugLoggingExpiry) as? Date }
        set { defaults.set(newValue, forKey: Key.debugLoggingExpiry) }
    }

    /// Directories added to the controlled `PATH`, searched after the defaults.
    var additionalSearchPaths: [String] {
        get { defaults.stringArray(forKey: Key.additionalSearchPaths) ?? [] }
        set { defaults.set(newValue, forKey: Key.additionalSearchPaths) }
    }

    /// What the user never wants to see among file results, kept in the order
    /// they were added. See `FolderExclusion` for what an entry can be.
    var excludedSearchFolders: [String] {
        get { defaults.stringArray(forKey: Key.excludedSearchFolders) ?? [] }
        set { defaults.set(newValue, forKey: Key.excludedSearchFolders) }
    }

    /// The bookmarks the user made, as JSON.
    ///
    /// In preferences rather than in a watched folder like the plugins:
    /// Settings is the only thing that writes these, there is no author
    /// editing them in a text editor, and there are dozens of them rather
    /// than hundreds.
    ///
    /// Stored data that cannot be read reads as none. It means somebody's hand
    /// edit or a format that no longer exists, and losing the bookmarks is bad
    /// where refusing to launch is worse.
    var bookmarks: [Bookmark] {
        get {
            guard
                let data = defaults.data(forKey: Key.bookmarks),
                let decoded = try? JSONDecoder().decode([Bookmark].self, from: data)
            else {
                return []
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.bookmarks)
        }
    }

    /// Which protected folders Pium has already asked macOS about.
    ///
    /// Remembered rather than looked up because there is nothing to look it up
    /// in: macOS exposes no way to read TCC's answer, and the only way to find
    /// out is to ask, which is the thing this exists to avoid doing twice.
    var requestedFolderAccess: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.requestedFolderAccess) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Key.requestedFolderAccess) }
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
