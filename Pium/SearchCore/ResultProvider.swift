import Foundation

/// A source of search results.
///
/// Providers return their own relevance signal in `SearchResult.textScore`;
/// ordering across providers is the coordinator's job, so a provider never
/// needs to know about the others.
protocol ResultProvider: Sendable {
    var kind: ResultKind { get }

    /// Results for a query. Implementations must support cancellation through
    /// Swift Concurrency so a stale query stops doing work.
    func results(for query: NormalizedQuery) async -> [SearchResult]
}
