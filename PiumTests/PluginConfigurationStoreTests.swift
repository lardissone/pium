import Testing
import Foundation
@testable import Pium

@Suite("Plugin configuration store")
@MainActor
struct PluginConfigurationStoreTests {
    /// A private suite per test, so one test's values can never be another's.
    private func makeStore() -> PluginConfigurationStore {
        PluginConfigurationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    @Test func anAbsentValueIsNil() {
        #expect(makeStore().value(pluginID: "web.yt", key: "baseURL") == nil)
    }

    @Test func avalueSurvivesAroundTrip() {
        let store = makeStore()
        store.setValue("https://example.com", pluginID: "web.yt", key: "baseURL")
        #expect(store.value(pluginID: "web.yt", key: "baseURL") == "https://example.com")
    }

    /// Two plugins declaring the same field key must not share a value.
    @Test func valuesAreScopedToTheirPlugin() {
        let store = makeStore()
        store.setValue("one", pluginID: "a.one", key: "url")
        store.setValue("two", pluginID: "b.two", key: "url")
        #expect(store.value(pluginID: "a.one", key: "url") == "one")
        #expect(store.value(pluginID: "b.two", key: "url") == "two")
    }

    @Test func nilRemovesTheValue() {
        let store = makeStore()
        store.setValue("x", pluginID: "a.one", key: "url")
        store.setValue(nil, pluginID: "a.one", key: "url")
        #expect(store.value(pluginID: "a.one", key: "url") == nil)
    }

    /// An empty string is a value the user cleared, not a value they set. Both
    /// the form and the required-field check treat it as absent.
    @Test func anEmptyValueIsTreatedAsAbsent() {
        let store = makeStore()
        store.setValue("   ", pluginID: "a.one", key: "url")
        #expect(store.value(pluginID: "a.one", key: "url") == nil)
    }
}
