import Foundation

/// The rules about meaning, which decoding cannot express.
///
/// Returns `nil` for a sound manifest. One diagnostic rather than a list: the
/// author fixes the first problem and re-saves, and the file reloads by itself.
enum ManifestValidator {
    private static let minimumTimeout = 1
    private static let maximumTimeout = 3600

    static func validate(_ manifest: PluginManifest) -> PluginDiagnostic? {
        guard isValidIdentifier(manifest.id) else {
            return .invalidIdentifier(manifest.id)
        }

        if let problem = firstConfigurationKeyProblem(in: manifest.configuration) {
            return problem
        }

        if let seconds = manifest.timeoutSeconds,
           !(minimumTimeout...maximumTimeout).contains(seconds) {
            return .invalidTimeout(seconds)
        }

        if let message = manifest.confirmBeforeRun,
           message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .wrongType(
                path: "confirmBeforeRun",
                expected: String(localized: "plugin.type.nonEmptyText")
            )
        }

        return firstArgumentProblem(in: manifest)
    }

    /// A key becomes part of a `UserDefaults` key and a Keychain account, and
    /// is what a configuration row's `ForEach` uses for identity, so it needs
    /// a grammar that keeps storage and identity sound — plus uniqueness: two
    /// fields sharing a key read and write the same storage slot, so the
    /// second silently shadows the first.
    private static func firstConfigurationKeyProblem(
        in fields: [PluginConfigurationField]
    ) -> PluginDiagnostic? {
        var seen = Set<String>()
        for field in fields {
            guard isValidConfigurationKey(field.key) else {
                return .invalidConfigurationKey(field.key)
            }
            guard !PluginTemplate.reservedVariableNames.contains(field.key) else {
                return .reservedConfigurationKey(field.key)
            }
            guard seen.insert(field.key).inserted else {
                return .duplicateConfigurationKey(field.key)
            }
        }
        return nil
    }

    /// Every argument must parse, and none may interpolate a secret.
    ///
    /// The secret rule is checked against parsed tokens rather than the text,
    /// because `{{token}}`, `{{ token }}`, and `{{token|url_encode}}` are the
    /// same interpolation and only the parser knows that. PRD §10.4: a secret
    /// reaches a child process as an environment variable or not at all, and an
    /// argument array is visible in the process table.
    private static func firstArgumentProblem(in manifest: PluginManifest) -> PluginDiagnostic? {
        let secrets = Set(manifest.configuration.filter { $0.type == .secret }.map(\.key))
        let declared = Set(manifest.configuration.map(\.key))

        for argument in manifest.command.arguments {
            let tokens: [PluginTemplateToken]
            switch PluginTemplate.parseAllowingConfiguration(
                argument, configurationKeys: declared
            ) {
            case .success(let parsed): tokens = parsed
            case .failure(let diagnostic): return diagnostic
            }

            for case .configuration(let key, _) in tokens where secrets.contains(key) {
                return .secretInArguments(key: key)
            }
        }
        return nil
    }

    /// Lowercase letters, digits, dots, and hyphens, starting and ending
    /// alphanumeric. The id keys usage history, so two ids that look alike
    /// must not be two different plugins.
    private static func isValidIdentifier(_ identifier: String) -> Bool {
        guard let first = identifier.first, let last = identifier.last else { return false }
        guard first.isASCIILowercaseOrDigit, last.isASCIILowercaseOrDigit else { return false }
        return identifier.allSatisfy { $0.isASCIILowercaseOrDigit || $0 == "." || $0 == "-" }
    }

    /// A field name, not a plugin id: it starts with an ASCII letter, and
    /// after that allows ASCII letters, digits, underscores, and hyphens —
    /// `baseURL`, `api_key`, and `base-url` are all sound field names.
    ///
    /// Dots are rejected even though they would otherwise be a safe
    /// character. `PluginConfigurationStore` assembles the stored key as
    /// `pium.plugin.<pluginID>.config.<field>`; a dot inside the field could
    /// reproduce that `.config.` boundary and land on a different plugin
    /// id/field pair's storage slot. Excluding dots removes that class of
    /// collision entirely.
    private static func isValidConfigurationKey(_ key: String) -> Bool {
        guard let first = key.first, first.isASCIILetter else { return false }
        return key.allSatisfy { $0.isASCIILetterOrDigit || $0 == "_" || $0 == "-" }
    }
}

private extension Character {
    var isASCIILowercaseOrDigit: Bool {
        ("a"..."z").contains(self) || ("0"..."9").contains(self)
    }

    var isASCIILetter: Bool {
        ("a"..."z").contains(self) || ("A"..."Z").contains(self)
    }

    var isASCIILetterOrDigit: Bool {
        isASCIILetter || ("0"..."9").contains(self)
    }
}
