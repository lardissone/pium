import Testing
import Foundation
@testable import Pium

@Suite("Frecency store")
@MainActor
struct FrecencyStoreTests {
    /// Each test gets its own file so runs cannot see each other's writes or
    /// the developer's real history.
    private func makeStore() -> (FrecencyStore, URL) {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        return (FrecencyStore(fileURL: url), url)
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func aNewStoreIsEmpty() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(store.snapshot().isEmpty)
    }

    @Test func recordingASelectionMakesItVisible() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.record(resultID: "safari", query: TextNormalizer.query("saf"), at: now)

        let entries = store.snapshot().entries(forResultID: "safari")
        #expect(entries.count == 1)
        #expect(entries.first?.selectionCount == 1)
        #expect(entries.first?.query == "saf")
    }

    /// Selecting the same thing for the same query again is a stronger signal,
    /// not a second record.
    @Test func recordingTheSamePairAgainIncrementsTheCount() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.record(resultID: "safari", query: TextNormalizer.query("saf"), at: now)
        store.record(
            resultID: "safari",
            query: TextNormalizer.query("saf"),
            at: now.addingTimeInterval(60)
        )

        let entries = store.snapshot().entries(forResultID: "safari")
        #expect(entries.count == 1)
        #expect(entries.first?.selectionCount == 2)
        #expect(entries.first?.lastSelected == now.addingTimeInterval(60))
    }

    /// Reaching the same result by a different query is a separate association,
    /// which is what makes the query-specific boost possible.
    @Test func adifferentQueryForTheSameResultIsASeparateEntry() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.record(resultID: "safari", query: TextNormalizer.query("saf"), at: now)
        store.record(resultID: "safari", query: TextNormalizer.query("browser"), at: now)

        #expect(store.snapshot().entries(forResultID: "safari").count == 2)
    }

    /// The query is stored folded, so case and accents never reach the file.
    @Test func theStoredQueryIsFolded() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.record(resultID: "codigo", query: TextNormalizer.query("  CÓDIGO  "), at: now)
        #expect(store.snapshot().entries(forResultID: "codigo").first?.query == "codigo")
    }

    @Test func historySurvivesAReload() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.record(resultID: "safari", query: TextNormalizer.query("saf"), at: now)

        let reloaded = FrecencyStore(fileURL: url)
        #expect(reloaded.snapshot().entries(forResultID: "safari").count == 1)
    }

    /// "Erase all usage history" has to actually erase it, on disk as well as in
    /// memory.
    @Test func clearingRemovesEverythingIncludingTheFile() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.record(resultID: "safari", query: TextNormalizer.query("saf"), at: now)
        store.clear()

        #expect(store.snapshot().isEmpty)
        #expect(FrecencyStore(fileURL: url).snapshot().isEmpty)
    }

    /// A corrupt file must not wedge the launcher: history is disposable, the
    /// launcher is not.
    @Test func acorruptFileStartsEmptyRatherThanFailing() throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)

        #expect(FrecencyStore(fileURL: url).snapshot().isEmpty)
    }

    /// An empty query cannot be an association, and recording one would make
    /// the boost fire for everything.
    @Test func anEmptyQueryIsNotRecorded() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.record(resultID: "safari", query: TextNormalizer.query("   "), at: now)
        #expect(store.snapshot().isEmpty)
    }
}
