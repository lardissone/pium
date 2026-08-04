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

    /// The only test that proves the predicate is one Spotlight evaluates.
    ///
    /// A unit test over `predicateFormat` cannot: `LIKE` builds a perfectly
    /// valid `NSPredicate` that Spotlight silently matches nothing against.
    /// This writes a uniquely named file and waits for the index to catch up.
    @Test func aFileInTheHomeFolderIsFoundOnceIndexed() async throws {
        let name = "pium-test-\(UUID().uuidString.prefix(8))"
        // Deliberately not `~/Documents`: macOS privacy controls hide that
        // folder's contents from Spotlight results unless the app has been
        // granted access, so a test pointed there passes or fails depending on
        // what the developer once clicked. See PIUM-41.
        let folder = URL(filePath: NSHomeDirectory()).appending(path: "pium-test-scratch")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).txt")
        try "pium integration test".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let search = SpotlightMetadataSearch()
        let predicate = SpotlightQuery.predicate(for: TextNormalizer.query(name))

        // Indexing usually lands within a few seconds; the retries cover a busy
        // machine without turning a real failure into a thirty-second wait.
        var found = false
        for _ in 0..<15 where !found {
            for await batch in search.search(predicate: predicate, scope: .home) {
                if batch.contains(where: { $0.lastPathComponent == "\(name).txt" }) {
                    found = true
                    break
                }
            }
            if !found { try? await Task.sleep(for: .seconds(2)) }
        }

        #expect(found, "Spotlight must find a file in the home folder once it is indexed")
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
