import Foundation

/// Turns one file's bytes into a manifest, or into the reason it is not one.
///
/// Two passes. The first walks the raw object rejecting keys no object declares,
/// because `Codable` cannot see a key no type mentions and silently accepting a
/// typo is how an author ends up with a command that never does what they wrote.
/// The second reads the known keys, applying the defaults the schema documents.
enum ManifestDecoder {
    static func decode(_ data: Data) -> Result<PluginManifest, PluginDiagnostic> {
        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.wrongType(
                    path: "", expected: String(localized: "plugin.type.object")
                ))
            }
            object = parsed
        } catch {
            return .failure(.malformedJSON(error.localizedDescription))
        }

        if let unknown = firstUnknownKey(in: object) { return .failure(unknown) }
        return build(from: object)
    }

    // MARK: - Unknown keys

    /// Walks the object against `ManifestKeys.byPath`, deepest path first so the
    /// message names the object the author has to look at.
    private static func firstUnknownKey(in object: [String: Any]) -> PluginDiagnostic? {
        if let diagnostic = unknownKey(in: object, at: "") { return diagnostic }

        for path in ["input", "command", "output"] {
            guard let nested = object[path] as? [String: Any] else { continue }
            if let diagnostic = unknownKey(in: nested, at: path) { return diagnostic }
        }

        for field in object["configuration"] as? [Any] ?? [] {
            guard let nested = field as? [String: Any] else { continue }
            if let diagnostic = unknownKey(in: nested, at: "configuration[]") {
                return diagnostic
            }
        }
        return nil
    }

    private static func unknownKey(
        in object: [String: Any],
        at path: String
    ) -> PluginDiagnostic? {
        guard let allowed = ManifestKeys.byPath[path] else { return nil }
        // Sorted so the same file always reports the same key first; an
        // unordered dictionary would make the diagnostic flap between runs.
        guard let key = object.keys.sorted().first(where: { !allowed.contains($0) }) else {
            return nil
        }
        return .unknownKey(path: path, key: key)
    }

    // MARK: - Building

    private static func build(
        from object: [String: Any]
    ) -> Result<PluginManifest, PluginDiagnostic> {
        for key in ManifestKeys.requiredAtRoot.sorted() where object[key] == nil {
            return .failure(.missingKey(key))
        }

        guard let version = object["schemaVersion"] as? Int else {
            return .failure(.wrongType(
                path: "schemaVersion", expected: String(localized: "plugin.type.integer")
            ))
        }
        guard version == PluginManifest.currentSchemaVersion else {
            return .failure(.unsupportedSchemaVersion(version))
        }

        guard let id = object["id"] as? String else {
            return .failure(.wrongType(path: "id", expected: String(localized: "plugin.type.string")))
        }
        guard let name = object["name"] as? String else {
            return .failure(.wrongType(path: "name", expected: String(localized: "plugin.type.string")))
        }

        let command: PluginCommand
        switch buildCommand(object["command"]) {
        case .success(let value): command = value
        case .failure(let diagnostic): return .failure(diagnostic)
        }

        let input: PluginInput
        switch buildInput(object["input"]) {
        case .success(let value): input = value
        case .failure(let diagnostic): return .failure(diagnostic)
        }

        let output: PluginOutput
        switch buildOutput(object["output"]) {
        case .success(let value): output = value
        case .failure(let diagnostic): return .failure(diagnostic)
        }

        let configuration: [PluginConfigurationField]
        switch buildConfiguration(object["configuration"]) {
        case .success(let value): configuration = value
        case .failure(let diagnostic): return .failure(diagnostic)
        }

        var timeout: Int?
        if let raw = object["timeoutSeconds"] {
            guard let seconds = raw as? Int else {
                return .failure(.wrongType(
                    path: "timeoutSeconds", expected: String(localized: "plugin.type.integer")
                ))
            }
            timeout = seconds
        }

        let optionalKeys: [PluginDiagnostic?] = [
            wrongType(object["description"], String.self, at: "description", expected: .text),
            wrongType(object["keywords"], [String].self, at: "keywords", expected: .array),
            wrongType(object["aliases"], [String].self, at: "aliases", expected: .array),
            wrongType(object["icon"], String.self, at: "icon", expected: .text),
            wrongType(
                object["confirmBeforeRun"], String.self, at: "confirmBeforeRun", expected: .text
            ),
        ]
        if let problem = optionalKeys.compactMap({ $0 }).first { return .failure(problem) }

        return .success(
            PluginManifest(
                schemaVersion: version,
                id: id,
                name: name,
                description: object["description"] as? String,
                keywords: object["keywords"] as? [String] ?? [],
                aliases: object["aliases"] as? [String] ?? [],
                icon: object["icon"] as? String,
                input: input,
                command: command,
                configuration: configuration,
                output: output,
                timeoutSeconds: timeout,
                confirmBeforeRun: object["confirmBeforeRun"] as? String
            )
        )
    }

    private static func buildCommand(_ raw: Any?) -> Result<PluginCommand, PluginDiagnostic> {
        guard let object = raw as? [String: Any] else {
            return .failure(.wrongType(
                path: "command", expected: String(localized: "plugin.type.object")
            ))
        }
        guard let executable = object["executable"] as? String else {
            return .failure(.missingKey("command.executable"))
        }
        if let problem = wrongType(
            object["arguments"], [String].self, at: "command.arguments", expected: .array
        ) {
            return .failure(problem)
        }
        if let problem = wrongType(
            object["workingDirectory"], String.self,
            at: "command.workingDirectory", expected: .text
        ) {
            return .failure(problem)
        }
        return .success(
            PluginCommand(
                executable: executable,
                arguments: object["arguments"] as? [String] ?? [],
                workingDirectory: object["workingDirectory"] as? String
            )
        )
    }

    /// Absent means `none`: a plugin that says nothing about input takes none.
    private static func buildInput(_ raw: Any?) -> Result<PluginInput, PluginDiagnostic> {
        guard let object = raw as? [String: Any] else {
            return .success(PluginInput(mode: .none, placeholder: nil))
        }
        guard
            let mode = enumValue(object["mode"], PluginInputMode.self, default: PluginInputMode.none)
        else {
            return .failure(.wrongType(
                path: "input.mode",
                expected: PluginInputMode.allCases.map(\.rawValue).joined(separator: ", ")
            ))
        }
        return .success(PluginInput(mode: mode, placeholder: object["placeholder"] as? String))
    }

    /// Absent means `silent`: a plugin that says nothing shows nothing.
    private static func buildOutput(_ raw: Any?) -> Result<PluginOutput, PluginDiagnostic> {
        guard let object = raw as? [String: Any] else {
            return .success(PluginOutput(mode: .silent))
        }
        guard let mode = enumValue(object["mode"], PluginOutputMode.self, default: .silent) else {
            return .failure(.wrongType(
                path: "output.mode",
                expected: PluginOutputMode.allCases.map(\.rawValue).joined(separator: ", ")
            ))
        }
        return .success(PluginOutput(mode: mode))
    }

    private static func buildConfiguration(
        _ raw: Any?
    ) -> Result<[PluginConfigurationField], PluginDiagnostic> {
        guard let array = raw as? [Any] else {
            return raw == nil
                ? .success([])
                : .failure(.wrongType(
                    path: "configuration", expected: String(localized: "plugin.type.array")
                ))
        }

        var fields: [PluginConfigurationField] = []
        for element in array {
            guard let object = element as? [String: Any] else {
                return .failure(.wrongType(
                    path: "configuration[]", expected: String(localized: "plugin.type.object")
                ))
            }
            guard let key = object["key"] as? String else {
                return .failure(.missingKey("configuration[].key"))
            }
            guard let label = object["label"] as? String else {
                return .failure(.missingKey("configuration[].label"))
            }
            guard let variable = object["environmentVariable"] as? String else {
                return .failure(.missingKey("configuration[].environmentVariable"))
            }
            guard
                let type = enumValue(object["type"], PluginConfigurationType.self, default: nil)
            else {
                return .failure(.wrongType(
                    path: "configuration[].type",
                    expected: PluginConfigurationType.allCases
                        .map(\.rawValue).joined(separator: ", ")
                ))
            }
            if let problem = wrongType(
                object["required"], Bool.self, at: "configuration[].required", expected: .boolean
            ) {
                return .failure(problem)
            }
            fields.append(
                PluginConfigurationField(
                    key: key,
                    label: label,
                    type: type,
                    required: object["required"] as? Bool ?? false,
                    environmentVariable: variable
                )
            )
        }
        return .success(fields)
    }

    /// What a key is allowed to hold, named so a diagnostic can say it in the
    /// author's language.
    private enum ExpectedType {
        case text, array, boolean

        var described: String {
            switch self {
            case .text: String(localized: "plugin.type.string")
            case .array: String(localized: "plugin.type.array")
            case .boolean: String(localized: "plugin.type.boolean")
            }
        }
    }

    /// `nil` when the key is absent or holds what it should.
    ///
    /// The same rule `enumValue` applies, extended to the optional keys that
    /// used to fall back silently: `"arguments": "--flag"` decoded to no
    /// arguments at all, which is exactly the command that never does what its
    /// author wrote.
    private static func wrongType<T>(
        _ raw: Any?,
        _ type: T.Type,
        at path: String,
        expected: ExpectedType
    ) -> PluginDiagnostic? {
        guard let raw, !(raw is T) else { return nil }
        return .wrongType(path: path, expected: expected.described)
    }

    /// Absent takes the default; present but unrecognised is an error, because
    /// falling back would run something other than what the author declared.
    private static func enumValue<T: RawRepresentable>(
        _ raw: Any?,
        _ type: T.Type,
        default fallback: T?
    ) -> T? where T.RawValue == String {
        guard let string = raw as? String else { return raw == nil ? fallback : nil }
        return T(rawValue: string)
    }
}
