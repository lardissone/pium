import Foundation

/// Which copy of Pium this is, and the names everything it stores hangs off.
///
/// The Debug configuration builds with a bundle identifier of its own, so a
/// copy running from Xcode and an installed one can be open at the same time
/// without either rewriting the other's state: the identifier already gives
/// them separate user defaults, and these derive the rest — the Application
/// Support folder, the icon cache, the Keychain service.
///
/// The variant is appended rather than substituted, so the released build's
/// names are the ones it has always had and nothing needs migrating.
///
/// Plugins are deliberately not split. They live in `~/.config/pium/plugins`
/// and belong to the user rather than to Pium; a development build is meant
/// to see the same ones.
struct AppIdentity: Sendable {
    /// What the released application is called. Every build's identifier
    /// starts with it.
    static let releaseBundleIdentifier = "com.lardissone.pium"

    /// The build that is running.
    static let current = AppIdentity(
        bundleIdentifier: Bundle.main.bundleIdentifier ?? releaseBundleIdentifier
    )

    let bundleIdentifier: String

    /// Whether this is the build people install.
    var isRelease: Bool { bundleIdentifier == Self.releaseBundleIdentifier }

    /// Empty for the released build, `.debug` for a development one.
    var variant: String {
        guard bundleIdentifier.hasPrefix(Self.releaseBundleIdentifier) else { return "" }
        return String(bundleIdentifier.dropFirst(Self.releaseBundleIdentifier.count))
    }

    /// The folder name Pium uses wherever macOS expects one: `Pium`, or
    /// `Pium.debug` for a development build.
    var folderName: String { "Pium" + variant }

    /// `~/Library/Application Support/Pium`.
    var supportDirectory: URL {
        URL.applicationSupportDirectory.appending(path: folderName)
    }

    /// `~/Library/Caches/Pium`. Everything here can be fetched again.
    var cacheDirectory: URL {
        URL.cachesDirectory.appending(path: folderName)
    }

    /// The Keychain service plugin secrets are stored under.
    var keychainService: String { bundleIdentifier + ".plugin-secrets" }
}
