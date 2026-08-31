import Foundation
import OSLog

/// Records what the user picked, and hands out immutable snapshots of it.
protocol FrecencyStoring: Sendable {
    @MainActor func snapshot() -> UsageSnapshot
    @MainActor func record(resultID: String, query: NormalizedQuery, at date: Date)
    @MainActor func clear()
}

/// Usage history, kept in one small JSON file.
///
/// ADR-5: not SQLite. One entry per query-and-result pair, read once at launch
/// and written on selection — a launcher records a handful of these a day. The
/// protocol above is what makes swapping in a database later a one-file change
/// if that ever stops being true.
@MainActor
final class FrecencyStore: FrecencyStoring {
    private let logger = Logger(subsystem: Signposts.subsystem, category: "Frecency")
    private let fileURL: URL
    private var entries: [FrecencyEntry]

    /// `~/Library/Application Support/Pium/frecency.json`.
    static var defaultFileURL: URL {
        let base = AppIdentity.current.supportDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: "frecency.json")
    }

    init(fileURL: URL = FrecencyStore.defaultFileURL) {
        self.fileURL = fileURL
        self.entries = Self.load(from: fileURL)
    }

    func snapshot() -> UsageSnapshot {
        UsageSnapshot(entries: entries)
    }

    func record(resultID: String, query: NormalizedQuery, at date: Date = Date()) {
        // An empty query is not an association; recording one would make the
        // query-specific boost fire for every search.
        guard !query.isEmpty else { return }

        if let index = entries.firstIndex(where: {
            $0.resultID == resultID && $0.query == query.folded
        }) {
            entries[index].selectionCount += 1
            entries[index].lastSelected = date
        } else {
            entries.append(
                FrecencyEntry(
                    resultID: resultID,
                    query: query.folded,
                    selectionCount: 1,
                    lastSelected: date
                )
            )
        }
        save()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func load(from url: URL) -> [FrecencyEntry] {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([FrecencyEntry].self, from: data)
        else {
            // Missing is normal on a first run, and corrupt is recoverable:
            // history is disposable, the launcher is not.
            return []
        }
        return decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            // Atomic, so a crash mid-write leaves the previous history rather
            // than a truncated file.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not write usage history: \(error)")
        }
    }
}
