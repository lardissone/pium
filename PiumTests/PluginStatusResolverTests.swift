import Testing
import Foundation
@testable import Pium

@Suite("Plugin status")
@MainActor
struct PluginStatusResolverTests {
    private func field(
        _ key: String,
        label: String,
        type: PluginConfigurationType,
        required: Bool
    ) -> PluginConfigurationField {
        PluginConfigurationField(
            key: key,
            label: label,
            type: type,
            required: required,
            environmentVariable: "PIUM_\(key.uppercased())"
        )
    }

    private func record(
        id: String = "web.yt",
        configuration: [PluginConfigurationField] = []
    ) -> PluginRecord {
        let manifest = PluginManifest(
            schemaVersion: 1,
            id: id,
            name: "YouTube",
            description: nil,
            keywords: [],
            aliases: [],
            icon: nil,
            input: PluginInput(mode: .none, placeholder: nil),
            command: PluginCommand(executable: "true", arguments: [], workingDirectory: nil),
            configuration: configuration,
            output: PluginOutput(mode: .silent),
            timeoutSeconds: nil,
            confirmBeforeRun: nil
        )
        return PluginRecord(
            fileURL: URL(filePath: "/tmp/\(id).pium.json"),
            manifest: manifest,
            diagnostic: nil
        )
    }

    private func resolver(
        values: [String: String] = [:],
        secrets: [String: String] = [:],
        disabled: Set<String> = []
    ) -> PluginStatusResolver {
        let configuration = PluginConfigurationStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        for (key, value) in values {
            let parts = key.split(separator: "/")
            configuration.setValue(value, pluginID: String(parts[0]), key: String(parts[1]))
        }
        return PluginStatusResolver(
            configuration: configuration,
            secrets: InMemorySecretStore(secrets: secrets),
            disabledIDs: disabled
        )
    }

    @Test func aplainValidPluginIsReady() {
        #expect(resolver().state(of: record()) == .ready)
    }

    @Test func abrokenManifestIsInvalid() {
        let broken = PluginRecord(
            fileURL: URL(filePath: "/tmp/broken.pium.json"),
            manifest: nil,
            diagnostic: .malformedJSON("unexpected end of input")
        )
        #expect(
            resolver().state(of: broken) == .invalid(.malformedJSON("unexpected end of input"))
        )
    }

    /// Disabled wins over a missing value: it is not going to run either way,
    /// and the switch the user threw is the more useful thing to report.
    @Test func adisabledPluginReportsDisabledEvenWhenUnconfigured() {
        let record = record(
            configuration: [field("token", label: "Token", type: .secret, required: true)]
        )
        #expect(resolver(disabled: ["web.yt"]).state(of: record) == .disabled)
    }

    @Test func amissingRequiredValueIsReported() {
        let record = record(
            configuration: [field("baseURL", label: "Server URL", type: .string, required: true)]
        )
        #expect(resolver().state(of: record) == .missingConfiguration(["Server URL"]))
    }

    @Test func afilledRequiredValueIsReady() {
        let record = record(
            configuration: [field("baseURL", label: "Server URL", type: .string, required: true)]
        )
        #expect(
            resolver(values: ["web.yt/baseURL": "https://example.com"]).state(of: record) == .ready
        )
    }

    @Test func amissingRequiredSecretIsReported() {
        let record = record(
            configuration: [field("token", label: "Access token", type: .secret, required: true)]
        )
        #expect(resolver().state(of: record) == .missingConfiguration(["Access token"]))
    }

    @Test func astoredSecretSatisfiesItsField() {
        let record = record(
            configuration: [field("token", label: "Access token", type: .secret, required: true)]
        )
        #expect(resolver(secrets: ["web.yt/token": "hunter2"]).state(of: record) == .ready)
    }

    /// Optional fields never block anything.
    @Test func anEmptyOptionalFieldIsReady() {
        let record = record(
            configuration: [field("note", label: "Note", type: .string, required: false)]
        )
        #expect(resolver().state(of: record) == .ready)
    }

    /// Every missing field is named, in manifest order, so the message does not
    /// change between runs.
    @Test func everyMissingFieldIsNamedInOrder() {
        let record = record(
            configuration: [
                field("baseURL", label: "Server URL", type: .string, required: true),
                field("token", label: "Access token", type: .secret, required: true),
            ]
        )
        #expect(
            resolver().state(of: record) == .missingConfiguration(["Server URL", "Access token"])
        )
    }
}
