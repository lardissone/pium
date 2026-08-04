import Testing
import Foundation
@testable import Pium

@Suite("Frecency records")
struct FrecencyEntryTests {
    private func entry(
        _ resultID: String,
        query: String,
        count: Int = 1,
        at date: Date = Date(timeIntervalSince1970: 0)
    ) -> FrecencyEntry {
        FrecencyEntry(resultID: resultID, query: query, selectionCount: count, lastSelected: date)
    }

    /// The file has to survive a Pium update, so the shape is part of the
    /// contract rather than an implementation detail.
    @Test func anEntrySurvivesARoundTrip() throws {
        let original = entry("app:/Applications/Safari.app", query: "saf", count: 3)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FrecencyEntry.self, from: data)
        #expect(decoded == original)
    }

    @Test func aSnapshotFindsEveryEntryForAResult() {
        let snapshot = UsageSnapshot(entries: [
            entry("safari", query: "saf"),
            entry("safari", query: "browser"),
            entry("mail", query: "ma"),
        ])
        #expect(snapshot.entries(forResultID: "safari").count == 2)
        #expect(snapshot.entries(forResultID: "mail").count == 1)
        #expect(snapshot.entries(forResultID: "unknown").isEmpty)
    }

    @Test func anEmptySnapshotReportsItself() {
        #expect(UsageSnapshot(entries: []).isEmpty)
        #expect(!UsageSnapshot(entries: [entry("safari", query: "saf")]).isEmpty)
    }
}
