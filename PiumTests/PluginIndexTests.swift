import Testing
import Foundation
@testable import Pium

@Suite("Plugin index")
@MainActor
struct PluginIndexTests {
    private func record(
        id: String,
        aliases: [String] = [],
        path: String? = nil
    ) -> PluginRecord {
        let manifest = PluginManifest(
            schemaVersion: 1,
            id: id,
            name: id,
            description: nil,
            keywords: [],
            aliases: aliases,
            icon: nil,
            input: PluginInput(mode: .none, placeholder: nil),
            command: PluginCommand(executable: "true", arguments: [], workingDirectory: nil),
            configuration: [],
            output: PluginOutput(mode: .silent),
            timeoutSeconds: nil,
            confirmBeforeRun: nil
        )
        return PluginRecord(
            fileURL: URL(filePath: path ?? "/tmp/\(id).pium.json"),
            manifest: manifest,
            diagnostic: nil
        )
    }

    private func index(loading records: [PluginRecord]) -> PluginIndex {
        PluginIndex(
            root: URL(filePath: "/tmp/unused"),
            loader: { _ in records },
            watcher: NullWatcher()
        )
    }

    @Test func refreshingLoadsTheRecords() {
        let index = index(loading: [record(id: "a.one"), record(id: "b.two")])
        index.refresh()
        #expect(index.records.count == 2)
    }

    /// The first file wins by path order, so the same pair of duplicates always
    /// resolves the same way. Silently dropping one would leave the author
    /// wondering which of the two Pium chose.
    @Test func aduplicateIdentifierInvalidatesTheLaterFile() {
        let index = index(loading: [
            record(id: "a.one", path: "/tmp/1.pium.json"),
            record(id: "a.one", path: "/tmp/2.pium.json"),
        ])
        index.refresh()

        #expect(index.records.count == 2)
        #expect(index.records.first?.isValid == true)
        #expect(index.records.last?.diagnostic == .duplicateIdentifier("a.one"))
    }

    @Test func aconflictingAliasInvalidatesTheLaterFile() {
        let index = index(loading: [
            record(id: "a.one", aliases: ["yt"], path: "/tmp/1.pium.json"),
            record(id: "b.two", aliases: ["yt"], path: "/tmp/2.pium.json"),
        ])
        index.refresh()

        #expect(index.records.first?.isValid == true)
        #expect(index.records.last?.diagnostic == .conflictingAlias("yt"))
    }

    /// Aliases are compared folded, or "YT" and "yt" would both claim the
    /// trigger and neither author would understand why.
    @Test func aliasConflictsAreDetectedRegardlessOfCase() {
        let index = index(loading: [
            record(id: "a.one", aliases: ["YT"], path: "/tmp/1.pium.json"),
            record(id: "b.two", aliases: ["yt"], path: "/tmp/2.pium.json"),
        ])
        index.refresh()
        #expect(index.records.last?.diagnostic == .conflictingAlias("yt"))
    }

    @Test func distinctPluginsBothStayValid() {
        let index = index(loading: [
            record(id: "a.one", aliases: ["one"]),
            record(id: "b.two", aliases: ["two"]),
        ])
        index.refresh()
        #expect(index.records.allSatisfy { $0.isValid })
    }

    /// An already-invalid record keeps the diagnostic it arrived with; conflict
    /// detection must not overwrite the reason the author actually needs.
    @Test func analreadyInvalidRecordKeepsItsOwnDiagnostic() {
        let broken = PluginRecord(
            fileURL: URL(filePath: "/tmp/broken.pium.json"),
            manifest: nil,
            diagnostic: .malformedJSON("unexpected end of input")
        )
        let index = index(loading: [broken])
        index.refresh()
        #expect(index.records.first?.diagnostic == .malformedJSON("unexpected end of input"))
    }

    @Test func observingRefreshesWhenTheWatcherFires() {
        let watcher = NullWatcher()
        // Built before the closure: the loader is `@Sendable` and nonisolated,
        // so it cannot reach a main-actor helper.
        let loaded = record(id: "a.one")
        let index = PluginIndex(
            root: URL(filePath: "/tmp/unused"),
            loader: { _ in [loaded] },
            watcher: watcher
        )
        index.startObserving()
        #expect(index.records.isEmpty)

        watcher.fire()
        #expect(index.records.count == 1)
    }
}

/// A watcher a test drives by hand, so the index's behaviour is tested without
/// FSEvents, a real directory, or waiting.
@MainActor
private final class NullWatcher: PluginDirectoryWatching {
    private var onChange: (@MainActor () -> Void)?

    func start(root: URL, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func stop() { onChange = nil }

    func fire() { onChange?() }
}
