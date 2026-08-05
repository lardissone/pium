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
        #expect(index.records.count == 1)
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
}

@MainActor
private final class NullSettingsWatcher: PluginDirectoryWatching {
    func start(root: URL, onChange: @escaping @MainActor () -> Void) {}
    func stop() {}
}
