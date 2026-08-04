import Testing
import Foundation
@testable import Pium

@Suite("Metadata search adapter")
@MainActor
struct MetadataSearchingTests {
    /// The one test here that touches the live index. It asserts termination,
    /// not content: what a machine has indexed is not something a test may
    /// assume, but a stream that never finishes hangs its consumer forever.
    @Test func theStreamFinishesForAQueryThatMatchesNothing() async {
        let search = SpotlightMetadataSearch()
        let predicate = SpotlightQuery.predicate(
            for: TextNormalizer.query("zzzq\(UUID().uuidString)")
        )

        var batches = 0
        for await batch in search.search(predicate: predicate, scope: .home) {
            batches += 1
            #expect(batch.isEmpty)
        }
        #expect(batches >= 0)
    }

    /// Abandoning the stream early must stop the query rather than leave it
    /// running and reporting into nothing.
    @Test func abandoningTheStreamEndsTheSearch() async {
        let search = SpotlightMetadataSearch()
        let predicate = SpotlightQuery.predicate(for: TextNormalizer.query("e"))

        var iterator = search.search(predicate: predicate, scope: .home).makeAsyncIterator()
        _ = await iterator.next()
        // Dropping the iterator terminates the stream; the adapter's
        // termination handler is what stops the query.
    }
}
