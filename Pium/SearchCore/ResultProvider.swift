import Foundation

/// A source of search results.
///
/// Providers return their own relevance signal in `SearchResult.textScore`;
/// ordering across providers is the coordinator's job, so a provider never
/// needs to know about the others.
protocol ResultProvider: Sendable {
    var kind: ResultKind { get }

    /// Batches of results for a query.
    ///
    /// A batch **replaces** this provider's previous contribution rather than
    /// adding to it: Spotlight reports a growing set rather than a delta.
    /// Providers that know their answer at once yield a single batch and
    /// finish. Ending the stream, or cancelling the task consuming it, must
    /// stop any work still running.
    ///
    /// Main-actor isolated because building the stream is synchronous now, and
    /// every provider reads main-actor state — an in-memory index, a
    /// preference, a live `NSMetadataQuery`. The work itself still happens off
    /// the caller's turn, inside the stream.
    @MainActor
    func results(for query: NormalizedQuery) -> AsyncStream<[SearchResult]>
}
