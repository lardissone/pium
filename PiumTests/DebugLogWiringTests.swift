import Testing
import Foundation
@testable import Pium

@Suite("Debug log wiring")
@MainActor
struct DebugLogWiringTests {
    private func makeDirectory() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Points the facade at a directory of this test's own, with a session
    /// that is live, and puts the shared seams back afterwards.
    private func withRecording(
        into directory: URL,
        _ body: () async throws -> Void
    ) async rethrows {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.debugLoggingExpiry = Date().addingTimeInterval(60)
        let previousStore = DebugLog.store
        let previousPreferences = DebugLog.preferences
        DebugLog.store = DebugLogStore(directory: directory, now: { Date() })
        DebugLog.preferences = preferences
        defer {
            DebugLog.store = previousStore
            DebugLog.preferences = previousPreferences
        }
        try await body()
    }

    /// A ranking bug — "this should have been first" — is the one most often
    /// reported and the one a log without the query cannot explain.
    @Test func asearchRecordsWhatWasTypedAndHowManyCameBack() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await withRecording(into: directory) {
            let coordinator = SearchCoordinator(
                providers: [
                    StubProvider(
                        kind: .application,
                        results: [
                            stubResult("Firefox", kind: .application, score: 0.9),
                            stubResult("Fireworks", kind: .application, score: 0.8),
                        ]
                    )
                ],
                frecency: FrecencyStore(
                    fileURL: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
                )
            )
            for await _ in coordinator.search("fire") {}
            try await Task.sleep(for: .milliseconds(200))

            let exported = String(decoding: try await DebugLog.store.export(), as: UTF8.self)
            #expect(exported.contains("search"))
            #expect(exported.contains("\"fire\""), "the query is what makes a ranking bug legible")
            #expect(exported.contains("2 results"))
        }
    }
}
