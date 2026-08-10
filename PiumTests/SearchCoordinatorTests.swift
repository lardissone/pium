import Testing
import Foundation
@testable import Pium

/// A provider that yields a fixed sequence of batches, so ordering, merging,
/// and cancellation can be tested without real providers.
private final class StubProvider: ResultProvider, @unchecked Sendable {
    let kind: ResultKind
    private let batches: [[SearchResult]]
    private let delay: Duration

    convenience init(kind: ResultKind, results: [SearchResult], delay: Duration = .zero) {
        self.init(kind: kind, batches: [results], delay: delay)
    }

    init(kind: ResultKind, batches: [[SearchResult]], delay: Duration = .zero) {
        self.kind = kind
        self.batches = batches
        self.delay = delay
    }

    @MainActor
    func results(for query: NormalizedQuery) -> AsyncStream<[SearchResult]> {
        AsyncStream { continuation in
            Task { [batches, delay] in
                for batch in batches {
                    if delay > .zero { try? await Task.sleep(for: delay) }
                    continuation.yield(batch)
                }
                continuation.finish()
            }
        }
    }
}

private func stubResult(
    _ title: String,
    kind: ResultKind,
    score: Double
) -> SearchResult {
    SearchResult(
        id: "\(kind.rawValue):\(title)",
        kind: kind,
        title: title,
        subtitle: nil,
        iconSource: .systemSymbol("app"),
        searchableTerms: [title],
        textScore: score,
        actions: []
    )
}

private func collect(_ stream: AsyncStream<[SearchResult]>) async -> [[SearchResult]] {
    var all: [[SearchResult]] = []
    for await batch in stream { all.append(batch) }
    return all
}

@Suite("Search coordinator")
@MainActor
struct SearchCoordinatorTests {
    @Test func resultsAreOrderedByDescendingScore() async {
        let coordinator = SearchCoordinator(providers: [
            StubProvider(kind: .application, results: [
                stubResult("Low", kind: .application, score: 0.4),
                stubResult("High", kind: .application, score: 0.9),
            ])
        ])
        let results = await collect(coordinator.search("x")).last ?? []
        #expect(results.map(\.title) == ["High", "Low"])
    }

    /// The PRD fixes the tie-break as plugin, application, file.
    @Test func equalScoresBreakTowardPluginThenApplicationThenFile() async {
        let coordinator = SearchCoordinator(providers: [
            StubProvider(kind: .file, results: [stubResult("F", kind: .file, score: 0.5)]),
            StubProvider(kind: .application, results: [stubResult("A", kind: .application, score: 0.5)]),
            StubProvider(kind: .plugin, results: [stubResult("P", kind: .plugin, score: 0.5)]),
        ])
        let results = await collect(coordinator.search("x")).last ?? []
        #expect(results.map(\.title) == ["P", "A", "F"])
    }

    @Test func anEmptyQueryReturnsNothingWithoutConsultingProviders() async {
        let coordinator = SearchCoordinator(providers: [
            StubProvider(kind: .application, results: [
                stubResult("Safari", kind: .application, score: 1)
            ])
        ])
        #expect(await collect(coordinator.search("")).last?.isEmpty == true)
        #expect(await collect(coordinator.search("   ")).last?.isEmpty == true)
    }

    /// A superseded query must stop publishing rather than overwrite fresher
    /// results. This is the bug that makes a launcher feel broken while typing.
    @Test func aStaleQueryStopsPublishing() async {
        let slow = StubProvider(
            kind: .application,
            results: [stubResult("Stale", kind: .application, score: 1)],
            delay: .milliseconds(200)
        )
        let coordinator = SearchCoordinator(providers: [slow])

        async let first = collect(coordinator.search("old"))
        try? await Task.sleep(for: .milliseconds(20))
        let second = await collect(coordinator.search("new"))

        #expect(await first.flatMap(\.self).isEmpty, "The superseded query must publish nothing")
        #expect(second.last?.map(\.title) == ["Stale"])
    }

    @Test func eachSearchAdvancesTheGeneration() async {
        let coordinator = SearchCoordinator(providers: [])
        let before = coordinator.currentGeneration
        _ = await collect(coordinator.search("a"))
        #expect(coordinator.currentGeneration > before)
    }

    /// The point of the whole change: a later batch must reach the list without
    /// waiting for every provider to finish.
    @Test func eachProviderBatchIsPublishedAsItArrives() async {
        let coordinator = SearchCoordinator(providers: [
            StubProvider(kind: .file, batches: [
                [stubResult("One", kind: .file, score: 0.5)],
                [
                    stubResult("One", kind: .file, score: 0.5),
                    stubResult("Two", kind: .file, score: 0.4),
                ],
            ])
        ])
        let published = await collect(coordinator.search("x"))
        #expect(published.map(\.count) == [1, 2])
    }

    /// A batch replaces that provider's previous contribution. Spotlight
    /// reports a growing set, not a delta, so appending would duplicate.
    @Test func aNewBatchReplacesThatProvidersPreviousResults() async {
        let coordinator = SearchCoordinator(providers: [
            StubProvider(kind: .file, batches: [
                [stubResult("Old", kind: .file, score: 0.5)],
                [stubResult("New", kind: .file, score: 0.5)],
            ])
        ])
        let published = await collect(coordinator.search("x"))
        #expect(published.last?.map(\.title) == ["New"])
    }

    /// The stubs above prove the merge; this proves a slow real provider's
    /// batch actually reaches a consumer through the coordinator.
    ///
    /// PIUM-50: skipped on CI. A fresh GitHub Actions macOS VM has no
    /// Spotlight index at all, and there is no cheap way to build one inside
    /// a job that tears the VM down when it finishes. This coverage still
    /// runs, and matters, on a developer's machine, where the index already
    /// exists.
    @Test(
        .disabled(
            if: isRunningOnCI,
            "PIUM-50: needs a live Spotlight index, which a fresh CI VM has no way to provide"
        )
    )
    func aRealFileProviderBatchReachesTheConsumer() async throws {
        let name = "pium-coord-\(UUID().uuidString.prefix(8))"
        // Deliberately not `~/Documents`: macOS privacy controls hide that
        // folder's contents from Spotlight results unless the app has been
        // granted access, so a test pointed there passes or fails depending on
        // what the developer once clicked. See PIUM-41.
        let folder = URL(filePath: NSHomeDirectory()).appending(path: "pium-test-scratch")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).txt")
        try "pium integration test".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let coordinator = SearchCoordinator(providers: [
            SpotlightFileProvider(
                isEnabled: { true },
                scope: { .home },
                debounce: .zero,
                open: { _ in },
                reveal: { _ in }
            )
        ])

        var found = false
        for _ in 0..<15 where !found {
            for await batch in coordinator.search(name) {
                if batch.contains(where: { $0.title == "\(name).txt" }) {
                    found = true
                    break
                }
            }
            if !found { try? await Task.sleep(for: .seconds(2)) }
        }

        #expect(found, "A real file must reach the consumer through the coordinator")
    }

    /// Ordering is the ranker's job now, so the coordinator has to be handing
    /// it the usage history rather than sorting by text score alone.
    @Test func theCoordinatorAppliesUsageHistory() async {
        let store = FrecencyStore(
            fileURL: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        )
        store.record(resultID: "application:Used", query: TextNormalizer.query("x"), at: .now)

        let coordinator = SearchCoordinator(
            providers: [
                StubProvider(kind: .application, results: [
                    stubResult("Fresh", kind: .application, score: 0.5),
                    stubResult("Used", kind: .application, score: 0.5),
                ])
            ],
            frecency: store
        )

        let ranked = await collect(coordinator.search("x")).last ?? []
        #expect(ranked.map(\.title) == ["Used", "Fresh"])
    }

    /// One provider's results must not wait behind another's.
    @Test func aFastProviderIsPublishedBeforeASlowOne() async {
        let coordinator = SearchCoordinator(providers: [
            StubProvider(
                kind: .file,
                results: [stubResult("Slow", kind: .file, score: 0.9)],
                delay: .milliseconds(150)
            ),
            StubProvider(kind: .application, results: [
                stubResult("Fast", kind: .application, score: 0.5)
            ]),
        ])
        let published = await collect(coordinator.search("x"))
        #expect(published.first?.map(\.title) == ["Fast"])
        #expect(published.last?.map(\.title) == ["Slow", "Fast"])
    }
}
