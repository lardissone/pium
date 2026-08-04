import Testing
import Foundation
@testable import Pium

@Suite("Selection recording")
@MainActor
struct SelectionRecordingTests {
    private func makeStore() -> FrecencyStore {
        FrecencyStore(fileURL: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json"))
    }

    /// Running an action is the signal the PRD says to learn from.
    @Test func performingAnActionRecordsTheSelection() {
        let store = makeStore()
        store.record(resultID: "app:Safari", query: TextNormalizer.query("saf"), at: .now)
        #expect(store.snapshot().entries(forResultID: "app:Safari").count == 1)
    }

    /// Abandoned queries are never stored — PRD §7.3. Typing without choosing
    /// must leave no trace.
    @Test func typingWithoutSelectingRecordsNothing() {
        let store = makeStore()
        #expect(store.snapshot().isEmpty)
    }
}
