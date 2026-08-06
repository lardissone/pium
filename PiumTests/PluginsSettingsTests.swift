import Testing
import Foundation
@testable import Pium

@Suite("Plugins settings")
@MainActor
struct PluginsSettingsTests {
    private func record(id: String, name: String) -> PluginRecord {
        let manifest = PluginManifest(
            schemaVersion: 1,
            id: id,
            name: name,
            description: nil,
            keywords: [],
            aliases: [],
            icon: nil,
            input: PluginInput(mode: .none, placeholder: nil),
            command: PluginCommand(executable: "true", arguments: [], workingDirectory: nil),
            configuration: [],
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

    /// A disabled plugin leaves the result list but must stay in Preferences,
    /// which is the only way to switch it back on.
    @Test func adisabledPluginIsStillListed() {
        let plugin = record(id: "web.yt", name: "YouTube")
        let index = PluginIndex(
            root: URL(filePath: "/tmp/unused"),
            loader: { _ in [plugin] },
            watcher: NullSettingsWatcher()
        )
        index.refresh()

        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.disabledPluginIDs = ["web.yt"]

        #expect(index.records.count == 1)
        let state = PluginStatusResolver(
            configuration: PluginConfigurationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            secrets: InMemorySecretStore(),
            disabledIDs: preferences.disabledPluginIDs
        ).state(of: index.records[0])
        #expect(state == .disabled)
    }

    /// The toggle's write-through: enabling and disabling both round-trip
    /// into the injected `Preferences`, not the singleton.
    @Test func togglingWritesThroughToPreferences() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let view = PluginsSettingsView(
            index: PluginIndex(
                root: URL(filePath: "/tmp/unused"),
                loader: { _ in [] },
                watcher: NullSettingsWatcher()
            ),
            configuration: PluginConfigurationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            secrets: InMemorySecretStore(),
            preferences: preferences
        )

        let afterDisabling = view.setEnabled(false, pluginID: "web.yt", in: [])
        #expect(afterDisabling == ["web.yt"])
        #expect(preferences.disabledPluginIDs == ["web.yt"])

        let afterEnabling = view.setEnabled(true, pluginID: "web.yt", in: afterDisabling)
        #expect(afterEnabling.isEmpty)
        #expect(preferences.disabledPluginIDs.isEmpty)
    }

    /// The row's title for a file that never decoded: it has no name, so the
    /// filename is the only thing its author knows it by.
    @Test func anInvalidPluginIsTitledByItsFileName() {
        let broken = PluginRecord(
            fileURL: URL(filePath: "/tmp/broken.pium.json"),
            manifest: nil,
            diagnostic: .unreadableFile
        )
        #expect(PluginsSettingsView.title(for: broken) == "broken.pium.json")
    }

    @Test func avalidPluginIsTitledByItsName() {
        #expect(PluginsSettingsView.title(for: record(id: "web.yt", name: "YouTube")) == "YouTube")
    }

    /// Credentials whose plugin is no longer in the folder. They are listed,
    /// never deleted on their own: a file can vanish because of a branch
    /// checkout, and a hand-pasted token does not come back.
    @Test func orphanedSecretsAreThoseWithoutAplugin() {
        let orphans = PluginsSettingsView.orphanedPluginIDs(
            storedIDs: ["web.yt", "gone.plugin"],
            records: [record(id: "web.yt", name: "YouTube")]
        )
        #expect(orphans == ["gone.plugin"])
    }

    @Test func nothingIsOrphanedWhenEveryPluginIsPresent() {
        let orphans = PluginsSettingsView.orphanedPluginIDs(
            storedIDs: ["web.yt"],
            records: [record(id: "web.yt", name: "YouTube")]
        )
        #expect(orphans.isEmpty)
    }

    /// An invalid file still occupies its id as far as the folder is concerned,
    /// but it has no manifest, so its secrets would look orphaned. They are not.
    @Test func aninvalidPluginDoesNotOrphanItsOwnSecrets() {
        let broken = PluginRecord(
            fileURL: URL(filePath: "/tmp/web.yt.pium.json"),
            manifest: nil,
            diagnostic: .malformedJSON("x")
        )
        #expect(
            PluginsSettingsView.orphanedPluginIDs(storedIDs: ["web.yt"], records: [broken])
                == ["web.yt"]
        )
    }
}

@MainActor
private final class NullSettingsWatcher: PluginDirectoryWatching {
    func start(root: URL, onChange: @escaping @MainActor () -> Void) {}
    func stop() {}
}
