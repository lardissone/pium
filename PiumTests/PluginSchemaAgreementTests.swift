import Testing
import Foundation
@testable import Pium

/// The shipped schema is documentation an agent writes manifests from, so a
/// schema that disagrees with the code is a lie with a user-visible cost. These
/// tests read the file that actually ships.
@Suite("Plugin schema agreement")
struct PluginSchemaAgreementTests {
    private func schema() throws -> [String: Any] {
        let url = try #require(
            Bundle(for: BundleMarker.self).url(
                forResource: "PluginManifest.schema", withExtension: "json"
            ) ?? Bundle.main.url(forResource: "PluginManifest.schema", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        return try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    /// Walks to a nested `properties` object by path.
    private func object(_ schema: [String: Any], at path: [String]) throws -> [String: Any] {
        var current = schema
        for step in path {
            let properties = try #require(current["properties"] as? [String: Any])
            current = try #require(properties[step] as? [String: Any])
            // Arrays describe their element shape under `items`.
            if let items = current["items"] as? [String: Any] { current = items }
        }
        return current
    }

    private func declaredKeys(_ schema: [String: Any], at path: [String]) throws -> Set<String> {
        let node = try object(schema, at: path)
        let properties = try #require(node["properties"] as? [String: Any])
        return Set(properties.keys)
    }

    private func enumValues(_ schema: [String: Any], at path: [String]) throws -> Set<String> {
        let node = try object(schema, at: path)
        return Set(try #require(node["enum"] as? [String]))
    }

    @Test func theSchemaDeclaresTheKeysSwiftAccepts() throws {
        let schema = try schema()
        #expect(try declaredKeys(schema, at: []) == ManifestKeys.byPath[""])
        #expect(try declaredKeys(schema, at: ["command"]) == ManifestKeys.byPath["command"])
        #expect(try declaredKeys(schema, at: ["input"]) == ManifestKeys.byPath["input"])
        #expect(try declaredKeys(schema, at: ["output"]) == ManifestKeys.byPath["output"])
        #expect(
            try declaredKeys(schema, at: ["configuration"])
                == ManifestKeys.byPath["configuration[]"]
        )
    }

    /// Every enum the code switches on must offer exactly the values the schema
    /// advertises, or a manifest the schema calls valid fails to decode.
    @Test func theSchemaDeclaresTheEnumeratedValuesSwiftAccepts() throws {
        let schema = try schema()
        #expect(
            try enumValues(schema, at: ["input", "mode"])
                == Set(PluginInputMode.allCases.map(\.rawValue))
        )
        #expect(
            try enumValues(schema, at: ["output", "mode"])
                == Set(PluginOutputMode.allCases.map(\.rawValue))
        )
        #expect(
            try enumValues(schema, at: ["configuration", "type"])
                == Set(PluginConfigurationType.allCases.map(\.rawValue))
        )
    }

    /// Strictness is the whole point: a schema that tolerates extra keys would
    /// tell an author their typo is fine while Pium rejects the file.
    @Test func everyObjectForbidsUnknownKeys() throws {
        let schema = try schema()
        for path in [[], ["command"], ["input"], ["output"], ["configuration"]] {
            let node = try object(schema, at: path)
            #expect(
                node["additionalProperties"] as? Bool == false,
                "additionalProperties must be false at \(path)"
            )
        }
    }

    @Test func theSchemaVersionMatchesTheCode() throws {
        let node = try object(try schema(), at: ["schemaVersion"])
        #expect(node["const"] as? Int == PluginManifest.currentSchemaVersion)
    }

    /// A key set alone does not catch a schema whose `pattern` is looser or
    /// stricter than what `ManifestValidator` accepts — an author's editor
    /// would call such a file valid while Pium rejects it, or the reverse.
    /// Checked by running the same candidates through both: the schema's
    /// regex, and `ManifestValidator` on a manifest built with that key.
    @Test func theConfigurationKeyPatternAgreesWithTheValidator() throws {
        let node = try object(try schema(), at: ["configuration"])
        let properties = try #require(node["properties"] as? [String: Any])
        let keyNode = try #require(properties["key"] as? [String: Any])
        let pattern = try #require(keyNode["pattern"] as? String)
        let regex = try NSRegularExpression(pattern: pattern)

        let candidates = [
            "baseURL", "token", "api_key", "apiKey2", "base-url",
            "", "Token Key", "base.url", "2fa", "clé",
            // Reserved: it is the name of the plugin's own input in a template.
            "input",
        ]
        for candidate in candidates {
            let range = NSRange(candidate.startIndex..., in: candidate)
            let schemaAccepts = regex.firstMatch(in: candidate, range: range)?.range == range
            let validatorAccepts = ManifestValidator.validate(
                manifestWithConfigurationKey(candidate)
            ) == nil
            #expect(
                schemaAccepts == validatorAccepts,
                "\(candidate.debugDescription): schema accepts \(schemaAccepts), validator accepts \(validatorAccepts)"
            )
        }
    }

    private func manifestWithConfigurationKey(_ key: String) -> PluginManifest {
        PluginManifest(
            schemaVersion: 1,
            id: "web.youtube",
            name: "YouTube",
            description: nil,
            keywords: [],
            aliases: [],
            icon: nil,
            input: PluginInput(mode: .optional, placeholder: nil),
            command: PluginCommand(executable: "open", arguments: [], workingDirectory: nil),
            configuration: [
                PluginConfigurationField(
                    key: key,
                    label: "Label",
                    type: .string,
                    required: true,
                    environmentVariable: "PIUM_KEY"
                ),
            ],
            output: PluginOutput(mode: .silent),
            timeoutSeconds: nil,
            confirmBeforeRun: nil
        )
    }
}

/// Locates the bundle the resource ships in. `Bundle.main` is the app because
/// PiumTests sets TEST_HOST, but naming a type keeps this working if that
/// changes.
final class BundleMarker {}
