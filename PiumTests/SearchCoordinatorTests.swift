import Testing
import Foundation
@testable import Pium

/// A provider that returns fixed results after an optional delay, so ordering
/// and cancellation can be tested without real providers.
private final class StubProvider: ResultProvider, @unchecked Sendable {
    let kind: ResultKind
    private let results: [SearchResult]
    private let delay: Duration

    init(kind: ResultKind, results: [SearchResult], delay: Duration = .zero) {
        self.kind = kind
        self.results = results
        self.delay = delay
    }

    func results(for query: NormalizedQuery) async -> [SearchResult] {
        if delay > .zero { try? await Task.sleep(for: delay) }
        return results
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
        let results = await coordinator.search("x")
        #expect(results.map(\.title) == ["High", "Low"])
    }

    /// The PRD fixes the tie-break as plugin, application, file.
    @Test func equalScoresBreakTowardPluginThenApplicationThenFile() async {
        let coordinator = SearchCoordinator(providers: [
            StubProvider(kind: .file, results: [stubResult("F", kind: .file, score: 0.5)]),
            StubProvider(kind: .application, results: [stubResult("A", kind: .application, score: 0.5)]),
            StubProvider(kind: .plugin, results: [stubResult("P", kind: .plugin, score: 0.5)]),
        ])
        let results = await coordinator.search("x")
        #expect(results.map(\.title) == ["P", "A", "F"])
    }

    @Test func anEmptyQueryReturnsNothingWithoutConsultingProviders() async {
        let coordinator = SearchCoordinator(providers: [
            StubProvider(kind: .application, results: [
                stubResult("Safari", kind: .application, score: 1)
            ])
        ])
        #expect(await coordinator.search("").isEmpty)
        #expect(await coordinator.search("   ").isEmpty)
    }

    /// A slow provider's results must not overwrite a newer query's. This is
    /// the bug that makes a launcher feel broken while typing fast.
    @Test func aStaleQueryIsDiscarded() async {
        let slow = StubProvider(
            kind: .application,
            results: [stubResult("Stale", kind: .application, score: 1)],
            delay: .milliseconds(200)
        )
        let coordinator = SearchCoordinator(providers: [slow])

        async let first = coordinator.search("old")
        try? await Task.sleep(for: .milliseconds(20))
        let second = await coordinator.search("new")

        #expect(await first.isEmpty, "The superseded query must yield nothing")
        #expect(second.map(\.title) == ["Stale"])
    }

    @Test func eachSearchAdvancesTheGeneration() async {
        let coordinator = SearchCoordinator(providers: [])
        let before = coordinator.currentGeneration
        _ = await coordinator.search("a")
        #expect(coordinator.currentGeneration > before)
    }
}
