import Testing
import Foundation
@testable import Pium

/// The whole path a plugin takes: a file on disk, through the index and the
/// provider, into the ranked list the launcher renders.
///
/// The unit suites above each prove one link. This proves they are connected,
/// which is what the UI test asserts and what no unit test would catch on its
/// own.
@Suite("Plugin search integration")
@MainActor
struct PluginSearchIntegrationTests {
    private func makeRoot() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// The manifest the UI test writes, verbatim in shape.
    private func writeManifest(named name: String, in root: URL) throws {
        try """
        { "schemaVersion": 1, "id": "uitest.\(name)", "name": "\(name)",
          "command": { "executable": "true" } }
        """.write(to: root.appending(path: "\(name).pium.json"), atomically: true, encoding: .utf8)
    }

    private func results(from coordinator: SearchCoordinator, _ query: String) async -> [SearchResult] {
        var last: [SearchResult] = []
        for await batch in coordinator.search(query) { last = batch }
        return last
    }

    @Test func amanifestOnDiskBecomesArankedResult() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "pium-uitest-476c28"
        try writeManifest(named: name, in: root)

        let index = PluginIndex(root: root, watcher: SilentWatcher())
        index.refresh()
        #expect(index.records.count == 1, "The manifest must load")

        let coordinator = SearchCoordinator(
            providers: [PluginProvider(index: index, reveal: { _ in })],
            frecency: FrecencyStore(fileURL: root.appending(path: "frecency.json"))
        )

        let titles = await results(from: coordinator, name).map(\.title)
        #expect(titles == [name], "The plugin must survive ranking and reach the list")
    }

    /// The index driven by the real watcher, which is what the app runs and
    /// what "appears without restarting" means. The two halves are proven
    /// separately above; only together do they reload anything.
    @Test func theIndexReloadsWhenTheFolderChanges() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let index = PluginIndex(
            root: root,
            watcher: FileSystemEventWatcher(debounce: .milliseconds(50))
        )
        index.refresh()
        #expect(index.records.isEmpty)

        index.startObserving()
        defer { index.stopObserving() }
        try writeManifest(named: "pium-uitest-476c28", in: root)

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while index.records.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(index.records.count == 1, "A manifest written to the folder must load itself")
    }
}

/// The index is driven by hand here; the watcher's own behaviour is proven in
/// `FileSystemEventWatcherTests`.
@MainActor
private final class SilentWatcher: PluginDirectoryWatching {
    func start(root: URL, onChange: @escaping @MainActor () -> Void) {}
    func stop() {}
}
