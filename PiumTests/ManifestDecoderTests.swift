import Testing
import Foundation
@testable import Pium

@Suite("Manifest decoding")
struct ManifestDecoderTests {
    private let minimal = """
    {
      "schemaVersion": 1,
      "id": "web.youtube",
      "name": "YouTube",
      "command": { "executable": "open", "arguments": ["https://youtube.com"] }
    }
    """

    private func decode(_ json: String) -> Result<PluginManifest, PluginDiagnostic> {
        ManifestDecoder.decode(Data(json.utf8))
    }

    private func manifest(_ json: String) throws -> PluginManifest {
        try decode(json).get()
    }

    private func diagnostic(_ json: String) throws -> PluginDiagnostic {
        guard case .failure(let diagnostic) = decode(json) else {
            Issue.record("Expected this manifest to be rejected")
            throw PluginDiagnostic.unreadableFile
        }
        return diagnostic
    }

    @Test func aMinimalManifestDecodes() throws {
        let manifest = try manifest(minimal)
        #expect(manifest.id == "web.youtube")
        #expect(manifest.name == "YouTube")
        #expect(manifest.command.executable == "open")
        #expect(manifest.command.arguments == ["https://youtube.com"])
    }

    /// Absent optional objects have documented defaults, so the smallest useful
    /// manifest stays small.
    @Test func absentSectionsTakeTheirDocumentedDefaults() throws {
        let manifest = try manifest(minimal)
        #expect(manifest.input.mode == .none)
        #expect(manifest.output.mode == .silent)
        #expect(manifest.keywords.isEmpty)
        #expect(manifest.aliases.isEmpty)
        #expect(manifest.configuration.isEmpty)
        #expect(manifest.timeoutSeconds == nil)
        #expect(manifest.confirmBeforeRun == nil)
    }

    @Test func everySectionDecodes() throws {
        let manifest = try manifest("""
        {
          "schemaVersion": 1,
          "id": "ha.toggle",
          "name": "Toggle light",
          "description": "Toggles the office light",
          "keywords": ["light", "luz"],
          "aliases": ["ha"],
          "icon": "lightbulb.fill",
          "input": { "mode": "optional", "placeholder": "Room" },
          "command": {
            "executable": "curl",
            "arguments": ["-X", "POST", "{{input|url_encode}}"],
            "workingDirectory": "."
          },
          "configuration": [
            {
              "key": "token",
              "label": "Access token",
              "type": "secret",
              "required": true,
              "environmentVariable": "PIUM_SECRET_TOKEN"
            }
          ],
          "output": { "mode": "toast" },
          "timeoutSeconds": 30,
          "confirmBeforeRun": "This will toggle the light."
        }
        """)

        #expect(manifest.input.mode == .optional)
        #expect(manifest.input.placeholder == "Room")
        #expect(manifest.icon == "lightbulb.fill")
        #expect(manifest.aliases == ["ha"])
        #expect(manifest.output.mode == .toast)
        #expect(manifest.timeoutSeconds == 30)
        #expect(manifest.configuration.first?.type == .secret)
        #expect(manifest.configuration.first?.required == true)
        #expect(manifest.command.workingDirectory == ".")
    }

    /// `required` defaults to false, matching the schema.
    @Test func aConfigurationFieldIsOptionalUnlessItSaysOtherwise() throws {
        let manifest = try manifest("""
        {
          "schemaVersion": 1, "id": "a.b", "name": "A",
          "command": { "executable": "true" },
          "configuration": [
            { "key": "url", "label": "URL", "type": "string",
              "environmentVariable": "PIUM_CONFIG_URL" }
          ]
        }
        """)
        #expect(manifest.configuration.first?.required == false)
    }

    /// The rule `Codable` cannot express, and the one that catches typos.
    @Test func anUnknownRootKeyIsRejectedByName() throws {
        let diagnostic = try diagnostic("""
        {
          "schemaVersion": 1, "id": "a.b", "name": "A",
          "command": { "executable": "true" },
          "timout": 5
        }
        """)
        #expect(diagnostic == .unknownKey(path: "", key: "timout"))
    }

    @Test func anUnknownNestedKeyNamesItsObject() throws {
        let diagnostic = try diagnostic("""
        {
          "schemaVersion": 1, "id": "a.b", "name": "A",
          "command": { "executable": "true", "shel": true }
        }
        """)
        #expect(diagnostic == .unknownKey(path: "command", key: "shel"))
    }

    @Test func anUnknownKeyInsideConfigurationIsRejected() throws {
        let diagnostic = try diagnostic("""
        {
          "schemaVersion": 1, "id": "a.b", "name": "A",
          "command": { "executable": "true" },
          "configuration": [
            { "key": "k", "label": "L", "type": "string",
              "environmentVariable": "PIUM_CONFIG_K", "defualt": "x" }
          ]
        }
        """)
        #expect(diagnostic == .unknownKey(path: "configuration[]", key: "defualt"))
    }

    @Test func aMissingRequiredKeyIsNamed() throws {
        #expect(
            try diagnostic("""
            { "schemaVersion": 1, "name": "A", "command": { "executable": "true" } }
            """) == .missingKey("id")
        )
    }

    @Test func aMissingExecutableIsNamed() throws {
        #expect(
            try diagnostic("""
            { "schemaVersion": 1, "id": "a.b", "name": "A", "command": {} }
            """) == .missingKey("command.executable")
        )
    }

    @Test func malformedJSONIsReportedAsSuch() throws {
        guard case .malformedJSON = try diagnostic("{ not json") else {
            Issue.record("Malformed JSON must be reported as malformed JSON")
            return
        }
    }

    @Test func aFutureSchemaVersionIsRejected() throws {
        #expect(
            try diagnostic("""
            { "schemaVersion": 99, "id": "a.b", "name": "A",
              "command": { "executable": "true" } }
            """) == .unsupportedSchemaVersion(99)
        )
    }

    @Test func aWrongTypeNamesTheKeyAndTheExpectedType() throws {
        guard case .wrongType(let path, _) = try diagnostic("""
        { "schemaVersion": 1, "id": "a.b", "name": "A",
          "command": { "executable": "true" }, "timeoutSeconds": "thirty" }
        """) else {
            Issue.record("A wrong type must be reported as a wrong type")
            return
        }
        #expect(path == "timeoutSeconds")
    }

    @Test func anUnknownInputModeIsRejected() throws {
        guard case .wrongType = try diagnostic("""
        { "schemaVersion": 1, "id": "a.b", "name": "A",
          "command": { "executable": "true" }, "input": { "mode": "sometimes" } }
        """) else {
            Issue.record("An unknown input mode must be rejected")
            return
        }
    }
}
