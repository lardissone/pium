import Foundation

/// Runs a query across every provider and merges their batches as they arrive.
///
/// Each search takes a generation number. When a newer search starts, older
/// ones stop publishing rather than overwrite fresher results — the behaviour
/// that keeps the list sane while the user types quickly.
@MainActor
final class SearchCoordinator {
    private let providers: [any ResultProvider]
    private let frecency: any FrecencyStoring
    /// Injected so a test can freeze the clock the decay is measured against.
    private let now: @Sendable () -> Date
    private(set) var currentGeneration = 0

    init(
        providers: [any ResultProvider],
        frecency: any FrecencyStoring = FrecencyStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.providers = providers
        self.frecency = frecency
        self.now = now
    }

    func search(_ text: String) -> AsyncStream<[SearchResult]> {
        currentGeneration += 1
        let generation = currentGeneration
        let query = TextNormalizer.query(text)

        // Built with `makeStream` rather than the closure initialiser so the
        // tasks below are created here, in a main-actor context they inherit.
        // Annotating a `Task` with `@MainActor` inside the stream's `@Sendable`
        // closure defeats the region-based isolation checker and fails to
        // compile.
        let (published, publish) = AsyncStream<[SearchResult]>.makeStream()

        // No results, recent items, or favourites for an empty query.
        guard !query.isEmpty else {
            publish.yield([])
            publish.finish()
            return published
        }

        // Taken once, so every batch of one search ranks against the same
        // history even if the user picks something while it is still running.
        let usage = frecency.snapshot()

        let signpost = Signposts.search.beginInterval("query")
        let (batches, reportBatch) = AsyncStream<(ResultKind, [SearchResult])>.makeStream()

        // One drain per provider rather than a task group: an `addTask` closure
        // does not inherit isolation, and annotating it `@MainActor` runs into
        // the same isolation-checker limitation. Asking each provider for its
        // stream happens here, synchronously, where the main actor is already
        // held.
        let drains = providers.map { provider in
            let kind = provider.kind
            let stream = provider.results(for: query)
            return Task {
                for await batch in stream { reportBatch.yield((kind, batch)) }
            }
        }

        let producers = Task {
            for drain in drains { await drain.value }
            reportBatch.finish()
        }

        // Exactly one task folds the batches together, so the accumulated
        // contributions are never touched from two places at once. That is what
        // keeps this free of actors and locks under strict concurrency.
        let consumer = Task {
            var contributions: [ResultKind: [SearchResult]] = [:]
            for await (kind, batch) in batches {
                // A newer query started while this one was running.
                guard generation == currentGeneration else { break }
                contributions[kind] = batch
                publish.yield(
                    ResultRanker.rank(
                        contributions.values.flatMap(\.self),
                        for: query,
                        usage: usage,
                        now: now()
                    )
                )
            }
            Signposts.search.endInterval("query", signpost)
            publish.finish()
        }

        publish.onTermination = { _ in
            for drain in drains { drain.cancel() }
            producers.cancel()
            consumer.cancel()
        }

        return published
    }
}
