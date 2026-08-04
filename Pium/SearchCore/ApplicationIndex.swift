import Foundation
import OSLog

/// An in-memory snapshot of installed applications.
///
/// Queries read `applications` synchronously, so scanning never happens on the
/// query path. The snapshot is refreshed when the application directories
/// change — never on a timer, because the PRD budgets approximately zero idle
/// CPU.
@MainActor
final class ApplicationIndex {
    private let logger = Logger(subsystem: Signposts.subsystem, category: "ApplicationIndex")
    private let roots: [URL]
    private let scanner: @Sendable ([URL]) -> [InstalledApplication]

    private var sources: [DispatchSourceFileSystemObject] = []
    private var pendingRefresh: Task<Void, Never>?

    private(set) var applications: [InstalledApplication] = []

    /// Filesystem events arrive in bursts while an installer writes; this waits
    /// for the burst to settle before rescanning.
    private static let refreshDebounce = Duration.milliseconds(500)

    init(
        roots: [URL] = ApplicationScanner.searchRoots,
        scanner: @escaping @Sendable ([URL]) -> [InstalledApplication] = {
            ApplicationScanner.scan(roots: $0)
        }
    ) {
        self.roots = roots
        self.scanner = scanner
    }

    func refresh() {
        applications = scanner(roots)
        logger.debug("Indexed \(self.applications.count, privacy: .public) applications")
    }

    func startObserving() {
        stopObserving()
        for root in roots {
            let descriptor = open(root.path, O_EVTONLY)
            // A missing directory is normal; there is simply nothing to watch.
            guard descriptor >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
    }

    func stopObserving() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        for source in sources { source.cancel() }
        sources.removeAll()
    }

    /// Coalesces a burst of filesystem events into one rescan.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: Self.refreshDebounce)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
