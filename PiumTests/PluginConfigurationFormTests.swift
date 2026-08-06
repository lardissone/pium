import Testing
import Foundation
@testable import Pium

@Suite("Plugin configuration form")
@MainActor
struct PluginConfigurationFormTests {
    private let field = PluginConfigurationField(
        key: "token",
        label: "Access token",
        type: .secret,
        required: true,
        environmentVariable: "PIUM_SECRET_TOKEN"
    )

    /// Saving a secret writes it and leaves nothing in preferences, which is
    /// the rule the whole design rests on.
    @Test func savingAsecretWritesOnlyToTheSecretStore() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let configuration = PluginConfigurationStore(defaults: defaults)
        let secrets = InMemorySecretStore()

        try PluginConfigurationForm.save(
            "hunter2",
            field: field,
            pluginID: "web.yt",
            configuration: configuration,
            secrets: secrets
        )

        #expect(secrets.hasSecret(pluginID: "web.yt", key: "token"))
        #expect(configuration.value(pluginID: "web.yt", key: "token") == nil)
    }

    @Test func savingAregularValueWritesOnlyToPreferences() throws {
        let configuration = PluginConfigurationStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        let secrets = InMemorySecretStore()
        let url = PluginConfigurationField(
            key: "baseURL",
            label: "Server URL",
            type: .string,
            required: true,
            environmentVariable: "PIUM_CONFIG_BASE_URL"
        )

        try PluginConfigurationForm.save(
            "https://example.com",
            field: url,
            pluginID: "web.yt",
            configuration: configuration,
            secrets: secrets
        )

        #expect(configuration.value(pluginID: "web.yt", key: "baseURL") == "https://example.com")
        #expect(!secrets.hasSecret(pluginID: "web.yt", key: "baseURL"))
    }

    @Test func clearingAsecretRemovesIt() throws {
        let secrets = InMemorySecretStore(secrets: ["web.yt/token": "hunter2"])
        try PluginConfigurationForm.save(
            "",
            field: field,
            pluginID: "web.yt",
            configuration: PluginConfigurationStore(
                defaults: UserDefaults(suiteName: UUID().uuidString)!
            ),
            secrets: secrets
        )
        #expect(!secrets.hasSecret(pluginID: "web.yt", key: "token"))
    }
}
