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
}

/// Locates the bundle the resource ships in. `Bundle.main` is the app because
/// PiumTests sets TEST_HOST, but naming a type keeps this working if that
/// changes.
final class BundleMarker {}
