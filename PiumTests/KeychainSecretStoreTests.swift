import Testing
import Foundation
@testable import Pium

@Suite("Keychain secret store")
@MainActor
struct KeychainSecretStoreTests {
    /// A service name unique per test, and every item removed at the end.
    /// Items left behind from a previous run would be owned by a differently
    /// signed binary, which is what makes macOS show a Keychain prompt — an
    /// invisible dialog on a headless machine (PIUM-62).
    private func makeStore() -> KeychainSecretStore {
        KeychainSecretStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            service: "app.pium.Pium.tests.\(UUID().uuidString)"
        )
    }

    @Test func anAbsentSecretIsNotStored() {
        #expect(!makeStore().hasSecret(pluginID: "web.yt", key: "token"))
    }

    @Test func asecretSurvivesAroundTrip() throws {
        let store = makeStore()
        defer { try? store.removeSecrets(pluginID: "web.yt") }

        try store.setSecret("hunter2", pluginID: "web.yt", key: "token")
        #expect(store.hasSecret(pluginID: "web.yt", key: "token"))
        #expect(try store.secret(pluginID: "web.yt", key: "token") == "hunter2")
    }

    @Test func writingTwiceReplacesRatherThanDuplicates() throws {
        let store = makeStore()
        defer { try? store.removeSecrets(pluginID: "web.yt") }

        try store.setSecret("first", pluginID: "web.yt", key: "token")
        try store.setSecret("second", pluginID: "web.yt", key: "token")
        #expect(try store.secret(pluginID: "web.yt", key: "token") == "second")
    }

    @Test func nilRemovesTheSecret() throws {
        let store = makeStore()
        try store.setSecret("hunter2", pluginID: "web.yt", key: "token")
        try store.setSecret(nil, pluginID: "web.yt", key: "token")

        #expect(!store.hasSecret(pluginID: "web.yt", key: "token"))
        #expect(try store.secret(pluginID: "web.yt", key: "token") == nil)
    }

    @Test func anEmptyStringRemovesTheSecret() throws {
        let store = makeStore()
        try store.setSecret("hunter2", pluginID: "web.yt", key: "token")
        try store.setSecret("", pluginID: "web.yt", key: "token")

        #expect(!store.hasSecret(pluginID: "web.yt", key: "token"))
        #expect(try store.secret(pluginID: "web.yt", key: "token") == nil)
    }

    /// What Preferences lists as orphaned credentials.
    @Test func storedPluginIDsReportsEveryPluginWithASecret() throws {
        let store = makeStore()
        defer {
            try? store.removeSecrets(pluginID: "a.one")
            try? store.removeSecrets(pluginID: "b.two")
        }

        try store.setSecret("x", pluginID: "a.one", key: "token")
        try store.setSecret("y", pluginID: "b.two", key: "token")
        #expect(store.storedPluginIDs() == ["a.one", "b.two"])
    }

    @Test func removingAPluginsSecretsRemovesEveryField() throws {
        let store = makeStore()
        try store.setSecret("x", pluginID: "a.one", key: "token")
        try store.setSecret("y", pluginID: "a.one", key: "other")

        try store.removeSecrets(pluginID: "a.one")
        #expect(!store.hasSecret(pluginID: "a.one", key: "token"))
        #expect(!store.hasSecret(pluginID: "a.one", key: "other"))
        #expect(store.storedPluginIDs().isEmpty)
    }

    /// The presence index can drift if someone deletes an item in Keychain
    /// Access. Reconciling is what the Plugins section does when it appears.
    @Test func reconcileRebuildsTheIndexFromTheKeychain() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = "app.pium.Pium.tests.\(UUID().uuidString)"
        let store = KeychainSecretStore(defaults: defaults, service: service)
        defer { try? store.removeSecrets(pluginID: "a.one") }

        try store.setSecret("x", pluginID: "a.one", key: "token")
        // A stale entry the Keychain knows nothing about.
        defaults.set(["a.one/token", "ghost.plugin/token"], forKey: "pium.plugin.storedSecrets")

        store.reconcile()
        #expect(store.hasSecret(pluginID: "a.one", key: "token"))
        #expect(!store.hasSecret(pluginID: "ghost.plugin", key: "token"))
    }
}

@Suite("In-memory secret store")
@MainActor
struct InMemorySecretStoreTests {
    /// Every other unit's tests rely on this double matching
    /// `KeychainSecretStore`'s empty-string-removes-secret behavior.
    @Test func anEmptyStringRemovesTheSecret() throws {
        let store = InMemorySecretStore()
        try store.setSecret("hunter2", pluginID: "web.yt", key: "token")
        try store.setSecret("", pluginID: "web.yt", key: "token")

        #expect(!store.hasSecret(pluginID: "web.yt", key: "token"))
        #expect(try store.secret(pluginID: "web.yt", key: "token") == nil)
    }
}
