import Testing
import Foundation
@testable import Pium

/// A stand-in for Spotlight that yields fixed batches, so the provider can be
/// tested without a live index.
private final class StubMetadataSearch: MetadataSearching, @unchecked Sendable {
    private let batches: [[URL]]
    private(set) var searchCount = 0

    init(batches: [[URL]]) {
        self.batches = batches
    }

    @MainActor
    func search(predicate: NSPredicate, scope: FileSearchScope) -> AsyncStream<[URL]> {
        searchCount += 1
        return AsyncStream { continuation in
            for batch in batches { continuation.yield(batch) }
            continuation.finish()
        }
    }
}

@Suite("Spotlight file provider")
@MainActor
struct SpotlightFileProviderTests {
    private func makeProvider(
        _ paths: [String],
        enabled: Bool = true,
        search: StubMetadataSearch? = nil
    ) -> (SpotlightFileProvider, StubMetadataSearch) {
        let stub = search ?? StubMetadataSearch(batches: [paths.map { URL(filePath: $0) }])
        let provider = SpotlightFileProvider(
            search: stub,
            isEnabled: { enabled },
            scope: { .home },
            debounce: .zero,
            open: { _ in },
            reveal: { _ in }
        )
        return (provider, stub)
    }

    private func results(
        _ provider: SpotlightFileProvider,
        _ text: String
    ) async -> [SearchResult] {
        var last: [SearchResult] = []
        for await batch in provider.results(for: TextNormalizer.query(text)) { last = batch }
        return last
    }

    @Test func matchingFilesBecomeResults() async {
        let (provider, _) = makeProvider(["/Users/someone/Documents/report.pdf"])
        let found = await results(provider, "report")
        #expect(found.map(\.title) == ["report.pdf"])
        #expect(found.first?.kind == .file)
    }

    /// The subtitle is what tells two same-named files apart.
    @Test func resultsCarryTheirLocationAsASubtitle() async {
        let (provider, _) = makeProvider(["\(NSHomeDirectory())/Documents/report.pdf"])
        let found = await results(provider, "report")
        #expect(found.first?.subtitle == "~/Documents")
    }

    /// Identity is the path, so selection survives the list reordering as more
    /// batches arrive.
    @Test func identityIsThePath() async {
        let (provider, _) = makeProvider(["/Users/someone/Documents/report.pdf"])
        let found = await results(provider, "report")
        #expect(found.first?.id == "/Users/someone/Documents/report.pdf")
    }

    @Test func resultsCarryOpenThenRevealActions() async {
        let (provider, _) = makeProvider(["/Users/someone/Documents/report.pdf"])
        let found = await results(provider, "report")
        #expect(found.first?.actions.map(\.id) == ["open", "reveal"])
        #expect(found.first?.actions.first?.shortcut == .returnKey)
        #expect(found.first?.actions.last?.shortcut == .commandReturn)
    }

    /// Technical noise never reaches the list.
    @Test func excludedPathsAreDropped() async {
        let (provider, _) = makeProvider([
            "/Users/someone/Documents/report.pdf",
            "/Users/someone/Library/Caches/report.pdf",
        ])
        let found = await results(provider, "report")
        #expect(found.map(\.id) == ["/Users/someone/Documents/report.pdf"])
    }

    /// One character matches most of the disk, so Spotlight is never asked.
    @Test func aQueryShorterThanTwoCharactersIssuesNoSearch() async {
        let (provider, stub) = makeProvider(["/Users/someone/Documents/report.pdf"])
        #expect(await results(provider, "r").isEmpty)
        #expect(stub.searchCount == 0)
    }

    @Test func anEmptyQueryIssuesNoSearch() async {
        let (provider, stub) = makeProvider(["/Users/someone/Documents/report.pdf"])
        #expect(await results(provider, "").isEmpty)
        #expect(stub.searchCount == 0)
    }

    /// Turning file search off must stop the query being issued at all, not
    /// discard its results afterwards.
    @Test func disabledFileSearchIssuesNoSearch() async {
        let (provider, stub) = makeProvider(
            ["/Users/someone/Documents/report.pdf"], enabled: false
        )
        #expect(await results(provider, "report").isEmpty)
        #expect(stub.searchCount == 0)
    }

    /// The stubs above prove the mapping; this proves the whole provider works
    /// against the real index, which is where the wiring bugs live.
    @Test func aRealFileIsFoundThroughTheLiveAdapter() async throws {
        let name = "pium-provider-\(UUID().uuidString.prefix(8))"
        // Deliberately not `~/Documents`: macOS privacy controls hide that
        // folder's contents from Spotlight results unless the app has been
        // granted access, so a test pointed there passes or fails depending on
        // what the developer once clicked. See PIUM-41.
        let folder = URL(filePath: NSHomeDirectory()).appending(path: "pium-test-scratch")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).txt")
        try "pium integration test".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = SpotlightFileProvider(
            isEnabled: { true },
            scope: { .home },
            debounce: .zero,
            open: { _ in },
            reveal: { _ in }
        )

        var found = false
        for _ in 0..<15 where !found {
            let batch = await results(provider, name)
            found = batch.contains { $0.title == "\(name).txt" }
            if !found { try? await Task.sleep(for: .seconds(2)) }
        }

        #expect(found, "The provider must surface a real indexed file")
    }

    /// Exactly how `AppDelegate` builds it: real debounce, preferences-backed
    /// flags, live adapter. This is the delta between the passing tests above
    /// and the app.
    @Test func theProviderAsTheAppBuildsItFindsARealFile() async throws {
        let name = "pium-default-\(UUID().uuidString.prefix(8))"
        // Deliberately not `~/Documents`: macOS privacy controls hide that
        // folder's contents from Spotlight results unless the app has been
        // granted access, so a test pointed there passes or fails depending on
        // what the developer once clicked. See PIUM-41.
        let folder = URL(filePath: NSHomeDirectory()).appending(path: "pium-test-scratch")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).txt")
        try "pium integration test".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = SpotlightFileProvider()

        var found = false
        for _ in 0..<15 where !found {
            let batch = await results(provider, name)
            found = batch.contains { $0.title == "\(name).txt" }
            if !found { try? await Task.sleep(for: .seconds(2)) }
        }

        #expect(found, "The provider as the app builds it must surface a real file")
    }

    /// Progressive batches reach the coordinator as they arrive.
    @Test func everyBatchIsPublished() async {
        let stub = StubMetadataSearch(batches: [
            [URL(filePath: "/Users/someone/ab.txt")],
            [URL(filePath: "/Users/someone/ab.txt"), URL(filePath: "/Users/someone/abc.txt")],
        ])
        let (provider, _) = makeProvider([], search: stub)

        var counts: [Int] = []
        for await batch in provider.results(for: TextNormalizer.query("ab")) {
            counts.append(batch.count)
        }
        #expect(counts == [1, 2])
    }
}
