import Foundation
import OSLog

/// Where debug logging puts what it records.
///
/// Files of Pium's own rather than the unified log, and deliberately: what
/// this records is text the user typed and output their commands produced,
/// and the unified log is not Pium's — the system writes it, any
/// `sysdiagnose` collects it, and neither Pium nor the user can delete it. A
/// mode whose promise is "turn it on, reproduce, send it to me, delete it"
/// cannot write where deletion is impossible.
///
/// An actor, so writes serialise without a lock and without blocking the main
/// actor behind file I/O.
actor DebugLogStore {
    /// PRD §14: twenty megabytes or seven days, whichever comes first.
    static let totalSizeLimit = 20 * 1024 * 1024
    static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    /// Five segments fit under the total, so evicting one drops a fifth of the
    /// history rather than all of it.
    static let segmentSizeLimit = 4 * 1024 * 1024

    static let defaultDirectory = URL.applicationSupportDirectory
        .appending(path: "Pium")
        .appending(path: "DebugLogs")

    private static let fileExtension = "log"

    private let directory: URL
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: Signposts.subsystem, category: "DebugLog")
    /// The segment being appended to, and how much is in it. Held so the size
    /// is not read back from disk on every line.
    private var current: (url: URL, size: Int)?
    /// Whether a failure has already been reported. Logging must not turn one
    /// unwritable directory into a line per event forever.
    private var hasReportedFailure = false

    init(
        directory: URL = DebugLogStore.defaultDirectory,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directory = directory
        self.now = now
    }

    func write(_ event: DebugEvent) {
        let moment = now()
        let line = Data((event.line(at: moment) + "\n").utf8)
        guard let segment = segment(for: line.count, at: moment) else { return }
        do {
            let handle = try FileHandle(forWritingTo: segment.url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            current = (segment.url, segment.size + line.count)
        } catch {
            report(error)
        }
    }

    /// Every segment, oldest first. Names carry their timestamp, so sorting
    /// them sorts the history.
    func export() throws -> Data {
        try segments().reduce(into: Data()) { combined, url in
            combined.append(try Data(contentsOf: url))
        }
    }

    func deleteAll() {
        for url in (try? segments()) ?? [] {
            try? FileManager.default.removeItem(at: url)
        }
        current = nil
    }

    /// The segment the next line belongs in, opening one when there is none or
    /// when the one in hand has no room left.
    private func segment(for length: Int, at moment: Date) -> (url: URL, size: Int)? {
        if let current, current.size + length <= Self.segmentSizeLimit {
            return current
        }
        do {
            try createDirectoryIfNeeded()
            // Rotation runs when a segment opens rather than on every line:
            // eviction reads the whole directory, and doing that per event
            // would put a directory scan inside a 50 ms budget.
            evict(at: moment)
            let name = "pium-\(Self.stamp.string(from: moment)).\(Self.fileExtension)"
            let url = directory.appending(path: name)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            current = (url, size(of: url))
            return current
        } catch {
            report(error)
            return nil
        }
    }

    private func createDirectoryIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func evict(at moment: Date) {
        var remaining = (try? segments()) ?? []

        // Age first: a quiet week is exactly the case the size limit never
        // catches.
        remaining.removeAll { url in
            guard
                let modified = (try? FileManager.default
                    .attributesOfItem(atPath: url.path)[.modificationDate]) as? Date,
                moment.timeIntervalSince(modified) > Self.maximumAge
            else { return false }
            try? FileManager.default.removeItem(at: url)
            return true
        }

        // Room is kept for the segment about to be opened, not just for what
        // is already there. Evicting down to the ceiling and *then* growing a
        // fresh segment against it would leave the directory over the limit
        // for as long as that segment took to fill — which is most of the
        // time, since eviction only runs when the next one opens.
        var total = remaining.reduce(Self.segmentSizeLimit) { $0 + size(of: $1) }
        while total > Self.totalSizeLimit, let oldest = remaining.first {
            total -= size(of: oldest)
            try? FileManager.default.removeItem(at: oldest)
            remaining.removeFirst()
        }
    }

    private func size(of url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int) ?? 0
    }

    private func segments() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == Self.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Reported once, and through the unified log, which is safe: this line
    /// carries a file system error and never a user's content.
    private func report(_ error: Error) {
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        logger.error("Could not write the debug log: \(error.localizedDescription, privacy: .public)")
    }

    /// Sorts lexically and chronologically at once, which is what lets
    /// `segments()` order the history by name alone.
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()
}
