import Darwin
import Foundation

/// Builds the environment a plugin's command runs in.
///
/// An explicit allowlist rather than an inherited environment: what Pium itself
/// carries depends on whether it was opened from the Finder or a terminal, and a
/// plugin whose behaviour follows from that is a bug that cannot be reproduced.
/// A command needing more than these five names declares it in its manifest.
///
/// This is the first place in Pium that reads a secret. The value enters the
/// returned dictionary and goes nowhere else — not to a log, not to a
/// diagnostic, not into an error.
@MainActor
struct ChildEnvironment {
    private let configuration: any PluginConfigurationStoring
    private let secrets: any PluginSecretStoring
    private let searchPaths: [String]

    init(
        configuration: any PluginConfigurationStoring,
        secrets: any PluginSecretStoring,
        searchPaths: [String] = ControlledPath.default
    ) {
        self.configuration = configuration
        self.secrets = secrets
        self.searchPaths = searchPaths
    }

    func build(for manifest: PluginManifest) -> Result<[String: String], ExecutionFailure> {
        var environment: [String: String] = [
            "PATH": searchPaths.joined(separator: ":"),
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "LANG": Self.languageValue(for: Locale.current.identifier),
            "TMPDIR": NSTemporaryDirectory(),
        ]

        for field in manifest.configuration {
            let value: String?
            switch field.type {
            case .string:
                value = configuration.value(pluginID: manifest.id, key: field.key)
            case .secret:
                // `secret(pluginID:key:)` throws: a Keychain that refuses is not
                // a field the user never filled, and reporting it as empty would
                // send them to retype a token that is already stored.
                //
                // This stops the run even for an *optional* field, which is not
                // an oversight. Optional means the plugin works without the
                // value, not that any answer will do: a stored secret that
                // cannot be read is a machine in a state the user did not
                // choose, and running anyway means authenticating as nobody —
                // hitting a live endpoint unauthenticated, or writing as the
                // wrong identity. Better to say which field the Keychain
                // refused and let the user decide.
                do {
                    value = try secrets.secret(pluginID: manifest.id, key: field.key)
                } catch {
                    return .failure(.secretUnavailable(field: field.key))
                }
            }

            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                guard field.required else { continue }
                return .failure(.missingConfiguration(field: field.key))
            }
            environment[field.environmentVariable] = value
        }
        return .success(environment)
    }

    /// The locale a child gets when the system has none for the identifier
    /// asked about. Present on every macOS install.
    static let fallbackLanguage = "en_US.UTF-8"

    /// The `LANG` a child gets for a locale identifier: that identifier's
    /// UTF-8 locale where the system has one, and `fallbackLanguage` where it
    /// does not.
    ///
    /// `Locale.current.identifier` follows the user's Region setting, and not
    /// every combination it produces names a locale that exists — an English
    /// language with an Argentine region gives `en_AR`, which no macOS install
    /// carries. A child handing that to `setlocale` prints "Setting locale
    /// failed" on its stderr before falling back to `C`, which is noise on the
    /// very stream a plugin's own message arrives on. Falling back here keeps
    /// the child's environment as this file describes it: fixed, valid, and
    /// not a function of how the machine is configured.
    ///
    /// `newlocale` is the existence check because it is the same lookup the
    /// child's own C library performs, so nothing is assumed about where
    /// locale definitions live or what names they answer to. Its mask is
    /// spelled out one category at a time because `LC_ALL_MASK` is a compound
    /// macro Swift does not import; these six are what it is defined as.
    static func languageValue(for identifier: String) -> String {
        let candidate = identifier + ".UTF-8"
        let allCategories =
            LC_COLLATE_MASK | LC_CTYPE_MASK | LC_MESSAGES_MASK
            | LC_MONETARY_MASK | LC_NUMERIC_MASK | LC_TIME_MASK
        guard let locale = newlocale(allCategories, candidate, nil) else {
            return fallbackLanguage
        }
        freelocale(locale)
        return candidate
    }
}
