import Testing
import Darwin
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

    /// An identifier the system has no locale for is not passed through: a
    /// child handing one to `setlocale` prints "Setting locale failed" on the
    /// stream a plugin's own message arrives on.
    @Test func anIdentifierWithNoLocaleBehindItFallsBack() {
        #expect(ChildEnvironment.languageValue(for: "qq_QQ") == ChildEnvironment.fallbackLanguage)
    }

    /// A region setting produces identifiers with keywords attached, which name
    /// no locale either.
    @Test func anIdentifierCarryingKeywordsFallsBack() {
        #expect(
            ChildEnvironment.languageValue(for: "en_US@rg=arzzzz")
                == ChildEnvironment.fallbackLanguage
        )
    }

    @Test func anIdentifierTheSystemHasIsTheOneTheChildGets() {
        #expect(ChildEnvironment.languageValue(for: "en_US") == "en_US.UTF-8")
    }

    /// Whatever this machine's Region setting happens to be, the `LANG` a
    /// plugin runs under names a locale its C library can actually load.
    @Test func thelanguageTheChildGetsNamesALocaleThisSystemHas() throws {
        let built = try environment().build(for: manifest([])).get()
        let language = try #require(built["LANG"])
        // `LC_ALL_MASK` is a compound macro Swift does not import; these six
        // categories are what it is defined as.
        let allCategories =
            LC_COLLATE_MASK | LC_CTYPE_MASK | LC_MESSAGES_MASK
            | LC_MONETARY_MASK | LC_NUMERIC_MASK | LC_TIME_MASK
        let locale = newlocale(allCategories, language, nil)
        #expect(locale != nil, "LANG names a locale this system does not have: \(language)")
        if let locale { freelocale(locale) }
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
