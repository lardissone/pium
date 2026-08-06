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
            "LANG": Locale.current.identifier + ".UTF-8",
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
}
