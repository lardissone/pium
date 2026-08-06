import Testing
import Foundation
@testable import Pium

@Suite("Child environment")
@MainActor
struct ChildEnvironmentTests {
    private func field(
        _ key: String,
        type: PluginConfigurationType,
        required: Bool = true,
        variable: String
    ) -> PluginConfigurationField {
        PluginConfigurationField(
            key: key, label: key, type: type, required: required, environmentVariable: variable
        )
    }

    private func manifest(_ configuration: [PluginConfigurationField]) -> PluginManifest {
        PluginManifest(
            schemaVersion: 1,
            id: "home.assistant",
            name: "Home Assistant",
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
    }

    private func environment(
        values: [String: String] = [:],
        secrets: [String: String] = [:]
    ) -> ChildEnvironment {
        let store = PluginConfigurationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        for (key, value) in values {
            let parts = key.split(separator: "/")
            store.setValue(value, pluginID: String(parts[0]), key: String(parts[1]))
        }
        return ChildEnvironment(
            configuration: store,
            secrets: InMemorySecretStore(secrets: secrets),
            searchPaths: ["/usr/bin", "/bin"]
        )
    }

    @Test func theAllowlistIsPresentAndNothingElseIs() throws {
        let built = try environment().build(for: manifest([])).get()
        #expect(built["PATH"] == "/usr/bin:/bin")
        #expect(built["HOME"] == NSHomeDirectory())
        #expect(built["USER"] == NSUserName())
        #expect(built["LANG"] != nil)
        #expect(built["TMPDIR"] != nil)
        #expect(Set(built.keys) == ["PATH", "HOME", "USER", "LANG", "TMPDIR"])
    }

    /// The launching environment is not inherited, so a variable Pium happens
    /// to carry cannot leak into a plugin.
    @Test func nothingIsInheritedFromTheLaunchingEnvironment() throws {
        setenv("PIUM_TEST_LEAK", "visible", 1)
        defer { unsetenv("PIUM_TEST_LEAK") }
        let built = try environment().build(for: manifest([])).get()
        #expect(built["PIUM_TEST_LEAK"] == nil)
    }

    @Test func aregularValueReachesItsDeclaredVariable() throws {
        let built = try environment(values: ["home.assistant/baseURL": "https://home.local"])
            .build(for: manifest([
                field("baseURL", type: .string, variable: "PIUM_CONFIG_BASE_URL"),
            ]))
            .get()
        #expect(built["PIUM_CONFIG_BASE_URL"] == "https://home.local")
    }

    @Test func asecretReachesItsDeclaredVariable() throws {
        let built = try environment(secrets: ["home.assistant/token": "hunter2"])
            .build(for: manifest([
                field("token", type: .secret, variable: "PIUM_SECRET_TOKEN"),
            ]))
            .get()
        #expect(built["PIUM_SECRET_TOKEN"] == "hunter2")
    }

    @Test func amissingRequiredValueStopsTheRun() {
        guard case .failure(let failure) = environment().build(for: manifest([
            field("baseURL", type: .string, variable: "PIUM_CONFIG_BASE_URL"),
        ])) else {
            Issue.record("A missing required value must stop the run")
            return
        }
        #expect(failure == .missingConfiguration(field: "baseURL"))
    }

    /// An optional field nobody filled is simply absent, not empty: a command
    /// reading it can tell "unset" from "set to nothing".
    @Test func amissingOptionalValueIsAbsentRatherThanEmpty() throws {
        let built = try environment().build(for: manifest([
            field("region", type: .string, required: false, variable: "PIUM_CONFIG_REGION"),
        ])).get()
        #expect(built["PIUM_CONFIG_REGION"] == nil)
    }

    /// A locked or refusing Keychain reports itself rather than masquerading as
    /// a field the user forgot to fill.
    @Test func arefusingKeychainIsReportedAsSuch() {
        let environment = ChildEnvironment(
            configuration: PluginConfigurationStore(
                defaults: UserDefaults(suiteName: UUID().uuidString)!
            ),
            secrets: RefusingSecretStore(),
            searchPaths: ["/usr/bin", "/bin"]
        )
        guard case .failure(let failure) = environment.build(for: manifest([
            field("token", type: .secret, variable: "PIUM_SECRET_TOKEN"),
        ])) else {
            Issue.record("A Keychain failure must stop the run")
            return
        }
        #expect(failure == .secretUnavailable(field: "token"))
    }
}

/// A store whose reads always fail, which `InMemorySecretStore` cannot do.
private struct RefusingSecretStore: PluginSecretStoring {
    func hasSecret(pluginID: String, key: String) -> Bool { true }
    func setSecret(_ value: String?, pluginID: String, key: String) throws {}
    func secret(pluginID: String, key: String) throws -> String? {
        throw SecretStoreError.keychain(errSecInteractionNotAllowed)
    }
    func storedPluginIDs() -> Set<String> { [] }
    func removeSecrets(pluginID: String) throws {}
    func reconcile() {}
}
