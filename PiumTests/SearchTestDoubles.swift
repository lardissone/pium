import Foundation
@testable import Pium

/// A provider that yields a fixed sequence of batches, so ordering, merging,
/// and cancellation can be tested without real providers.
final class StubProvider: ResultProvider, @unchecked Sendable {
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

func stubResult(
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
