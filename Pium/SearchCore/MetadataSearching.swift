import Foundation

/// A source of file URLs matching a Spotlight predicate.
///
/// Exists so the file provider can be tested against a stub: what a machine has
/// indexed is not something a test may assume.
protocol MetadataSearching: Sendable {
    /// Batches of matching URLs. Each batch replaces the previous one, and the
    /// stream finishes when gathering completes or the query is stopped.
    @MainActor
    func search(predicate: NSPredicate, scope: FileSearchScope) -> AsyncStream<[URL]>
}

/// The live adapter over `NSMetadataQuery`.
///
/// Main-actor isolated because `NSMetadataQuery` has to be started on a thread
/// with a run loop and delivers its results through notifications.
@MainActor
final class SpotlightMetadataSearch: MetadataSearching {
    /// How many results to carry per batch. Spotlight will happily report tens
    /// of thousands; the list shows a couple of dozen.
    private static let batchLimit = 50

    func search(predicate: NSPredicate, scope: FileSearchScope) -> AsyncStream<[URL]> {
        let session = Session(predicate: predicate, scope: scope)
        let (urls, report) = AsyncStream<[URL]>.makeStream()

        session.onBatch = { batch in report.yield(batch) }
        session.onFinish = { report.finish() }

        report.onTermination = { _ in
            // Hops to the main actor because termination is delivered from
            // whichever task dropped the stream, and stopping a query has to
            // happen where its observers were registered.
            Task { @MainActor in session.stop() }
        }

        // A query that refuses to start reports nothing, so the stream has to
        // end or its consumer waits forever.
        guard session.start() else {
            report.finish()
            return urls
        }
        return urls
    }

    /// One running query and its observers.
    ///
    /// `NSMetadataQuery` is not `Sendable`, so it cannot be captured by the
    /// notification blocks directly. This holder is main-actor isolated and
    /// therefore is, which keeps the query itself from ever crossing an
    /// isolation boundary.
    @MainActor
    private final class Session {
        private let query = NSMetadataQuery()
        private var observers: [any NSObjectProtocol] = []

        var onBatch: (@MainActor ([URL]) -> Void)?
        var onFinish: (@MainActor () -> Void)?

        init(predicate: NSPredicate, scope: FileSearchScope) {
            query.predicate = predicate
            query.searchScopes = [scope.metadataScope]
            query.sortDescriptors = [
                NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)
            ]
            // Batching keeps the notification storm down on a broad query.
            query.notificationBatchingInterval = 0.2
        }

        func start() -> Bool {
            observe(.NSMetadataQueryGatheringProgress) { session in
                session.onBatch?(session.currentURLs())
            }
            observe(.NSMetadataQueryDidFinishGathering) { session in
                session.onBatch?(session.currentURLs())
                session.onFinish?()
            }
            return query.start()
        }

        func stop() {
            query.stop()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            onBatch = nil
            onFinish = nil
        }

        private func observe(
            _ name: Notification.Name,
            handler: @escaping @MainActor (Session) -> Void
        ) {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: query,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handler(self)
                }
            }
            observers.append(observer)
        }

        private func currentURLs() -> [URL] {
            query.disableUpdates()
            defer { query.enableUpdates() }

            var found: [URL] = []
            for index in 0..<query.resultCount {
                guard
                    let item = query.result(at: index) as? NSMetadataItem,
                    let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
                else {
                    continue
                }
                found.append(URL(filePath: path))
                if found.count >= SpotlightMetadataSearch.batchLimit { break }
            }
            return found
        }
    }
}
