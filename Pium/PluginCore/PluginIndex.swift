import Foundation
import OSLog

/// An in-memory snapshot of the plugin folder.
///
/// Queries read `records` synchronously, so parsing never happens on the query
/// path — plugins share the 50 ms budget with applications. Refreshed on
/// filesystem events, never on a timer, because the PRD budgets approximately
/// zero idle CPU.
@MainActor
final class PluginIndex {
    private let logger = Logger(subsystem: Signposts.subsystem, category: "Plugins")
    private let root: URL
    private let loader: @Sendable (URL) -> [PluginRecord]
    private let watcher: any PluginDirectoryWatching

    private(set) var records: [PluginRecord] = []

    init(
        root: URL = PluginLoader.defaultRoot,
        loader: @escaping @Sendable (URL) -> [PluginRecord] = { PluginLoader.load(from: $0) },
        watcher: any PluginDirectoryWatching = UnwatchedDirectory()
    ) {
        self.root = root
        self.loader = loader
        self.watcher = watcher
    }

    func refresh() {
        records = resolvingConflicts(in: loader(root))
        logger.notice("Loaded \(self.records.count, privacy: .public) plugins")
    }

    func startObserving() {
        watcher.start(root: root) { [weak self] in self?.refresh() }
    }

    func stopObserving() {
        watcher.stop()
    }

    /// Two plugins cannot share an id or an alias. The earlier file by path
    /// wins, so the outcome is the same on every launch, and the loser is
    /// invalidated with a diagnostic naming what it collided with — no plugin
    /// silently steals a trigger (PRD §10.3).
    private func resolvingConflicts(in records: [PluginRecord]) -> [PluginRecord] {
        var identifiers: Set<String> = []
        var aliases: Set<String> = []

        return records.map { record in
            guard let manifest = record.manifest else { return record }

            guard identifiers.insert(manifest.id).inserted else {
                return record.invalidated(by: .duplicateIdentifier(manifest.id))
            }

            for alias in manifest.aliases {
                let folded = TextNormalizer.fold(alias)
                guard aliases.insert(folded).inserted else {
                    return record.invalidated(by: .conflictingAlias(folded))
                }
            }
            return record
        }
    }
}

/// Replaced by `FileSystemEventWatcher` in Task 7.
@MainActor
final class UnwatchedDirectory: PluginDirectoryWatching {
    func start(root: URL, onChange: @escaping @MainActor () -> Void) {}
    func stop() {}
}
